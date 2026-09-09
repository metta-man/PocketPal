import Foundation
import SwiftData
import UniformTypeIdentifiers

// Optional JSON metadata is additive: legacy receipts and their original evidence remain intact.
enum FinanceTreatment: String, Codable, CaseIterable, Identifiable {
    case regular = "一般收支", expenseRefund = "支出退款", salesRefund = "退回客戶款項"
    case transfer = "戶口轉帳", capital = "老闆注資／提取", loan = "借款／還本金", reimbursement = "歸還墊支"
    var id: String { rawValue }
    var excluded: Bool { [.transfer, .capital, .loan, .reimbursement].contains(self) }
}
struct FinanceEvidence: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var type: String
}
struct FinancePayment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var amount: Decimal
    var reference: String
}
struct FinanceAudit: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date = .now
    var actor: String
    var action: String
}
struct FinancePayroll: Codable, Equatable {
    var employee: String
    var month: String
    var gross: Decimal
    var employerCost: Decimal
    var deductions: Decimal
}
struct FinanceMetadata: Codable, Equatable {
    var treatment: FinanceTreatment = .regular
    var account = ""
    var client = ""
    var project = ""
    var paidBy = ""
    var dueDate: Date?
    var tracksPayments = false
    var payments: [FinancePayment] = []
    var evidence: [FinanceEvidence] = []
    var audit: [FinanceAudit] = []
    var submittedBy = ""
    var approval = "未提交"
    var payroll: FinancePayroll?
    var hours: Decimal?
    var isTemplate = false
    var recurrence: String?
    var nextDue: Date?
    var anchorDay: Int?
    var recurrenceSource: String?
    var sourceKey: String?
    var matchedRecord: UUID?
    var requiredDocuments: [String] = []
}
extension Receipt {
    var finance: FinanceMetadata {
        get {
            guard let data = financeMetadataJSON?.data(using: .utf8),
                  let value = try? JSONDecoder().decode(FinanceMetadata.self, from: data) else { return FinanceMetadata() }
            return value
        }
        set { financeMetadataJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }
    var faceAmount: Decimal { totalAmount.flatMap { $0.isFinite ? Decimal(string: String($0)) : nil } ?? 0 }
    var paidAmount: Decimal { finance.tracksPayments ? finance.payments.reduce(0) { $0 + $1.amount } : faceAmount }
    var outstanding: Decimal { finance.tracksPayments ? max(0, faceAmount - paidAmount) : 0 }
    var cashIncome: Decimal {
        guard !finance.isTemplate, finance.matchedRecord == nil, !finance.treatment.excluded else { return 0 }
        if finance.treatment == .salesRefund { return -paidAmount }
        if finance.treatment == .expenseRefund { return 0 }
        return transactionKind == .income ? paidAmount : 0
    }
    var cashExpense: Decimal {
        guard !finance.isTemplate, finance.matchedRecord == nil, !finance.treatment.excluded else { return 0 }
        if finance.treatment == .expenseRefund { return -paidAmount }
        if finance.treatment == .salesRefund { return 0 }
        return transactionKind == .expense ? paidAmount : 0
    }
    var isOverdue: Bool { outstanding > 0 && (finance.dueDate.map { ReceiptDeliveryPackage.calendar.startOfDay(for: $0) < ReceiptDeliveryPackage.calendar.startOfDay(for: .now) } ?? false) }
    var financeSearchText: String {
        [searchText, merchantName ?? "", category ?? "", notes ?? "", String(describing: faceAmount), finance.client,
         finance.project, finance.account, finance.paidBy, finance.submittedBy, finance.payroll?.employee ?? ""].joined(separator: " ")
    }
    var allEvidence: [FinanceEvidence] {
        let primary = asset.map { FinanceEvidence(id: $0.id, name: $0.originalFilename, path: $0.storageRelativePath, type: $0.contentTypeIdentifier) }
        return (primary.map { [$0] } ?? []) + finance.evidence
    }
}
enum FinanceWorkflowError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
@MainActor
enum FinanceWorkflow {
    static func update(_ receipt: Receipt, actor: String, action: String, context: ModelContext,
                       change: (inout FinanceMetadata) throws -> Void) throws {
        let previous = receipt.financeMetadataJSON
        let oldUpdated = receipt.updatedAt
        let original = receipt.finance
        var value = original
        try change(&value)
        if original.approval == "已批准" && value.approval == "已批准" && value != original { value.approval = "待審批" }
        value.audit.append(FinanceAudit(actor: actor.isEmpty ? "本機使用者" : actor, action: action))
        receipt.finance = value
        receipt.touch()
        do { try context.save() } catch {
            receipt.financeMetadataJSON = previous
            receipt.updatedAt = oldUpdated
            throw error
        }
    }
    static func pay(_ receipt: Receipt, amount: Decimal, date: Date, reference: String, actor: String, context: ModelContext) throws {
        guard receipt.finance.tracksPayments, amount > 0, amount <= receipt.outstanding, date <= .now else {
            throw FinanceWorkflowError.invalid("付款須大於零、不超過未付款餘額，而且不能記為未來付款。")
        }
        try update(receipt, actor: actor, action: "記錄付款 \(amount)；\(reference)", context: context) {
            $0.payments.append(FinancePayment(date: date, amount: amount, reference: reference))
        }
    }
    static func duplicates(of receipt: Receipt, in records: [Receipt]) -> [Receipt] {
        records.filter {
            $0.id != receipt.id && !$0.finance.isTemplate && $0.expenseType == receipt.expenseType &&
            $0.transactionKind == receipt.transactionKind && $0.totalAmount != nil && receipt.totalAmount != nil &&
            $0.faceAmount == receipt.faceAmount && $0.resolvedCurrency == receipt.resolvedCurrency &&
            $0.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == receipt.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
            $0.transactionDate != nil && receipt.transactionDate != nil && ReceiptDeliveryPackage.calendar.isDate($0.transactionDate!, inSameDayAs: receipt.transactionDate!)
        }
    }
    static func occurrences(_ template: Receipt, through: Date) -> [Date] {
        guard template.finance.isTemplate, let first = template.finance.nextDue, let interval = template.finance.recurrence else { return [] }
        var result: [Date] = []
        var date = first
        for _ in 0..<120 where date <= through {
            result.append(date)
            date = next(date, interval: interval, anchor: template.finance.anchorDay ?? ReceiptDeliveryPackage.calendar.component(.day, from: first))
        }
        return result
    }
    static func next(_ date: Date, interval: String, anchor: Int) -> Date {
        let calendar = ReceiptDeliveryPackage.calendar
        if interval == "每週" { return calendar.date(byAdding: .day, value: 7, to: date)! }
        let months = interval == "每年" ? 12 : interval == "每季" ? 3 : 1
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let target = calendar.date(byAdding: .month, value: months, to: first)!
        let days = calendar.range(of: .day, in: .month, for: target)!.count
        return calendar.date(byAdding: .day, value: min(anchor, days) - 1, to: target)!
    }
    static func generate(_ templates: [Receipt], records: [Receipt], through: Date, context: ModelContext) throws -> Int {
        var inserted: [Receipt] = []
        var keys = Set(records.compactMap { $0.finance.recurrenceSource })
        var originals: [(Receipt, String?)] = []
        do {
            for template in templates {
                let dates = occurrences(template, through: through)
                guard !dates.isEmpty else { continue }
                originals.append((template, template.financeMetadataJSON))
                var metadata = template.finance
                for date in dates {
                    let key = template.id.uuidString + ":" + String(date.timeIntervalSince1970)
                    if keys.insert(key).inserted {
                        let receipt = Receipt(importSource: .manual, transactionKind: template.transactionKind, processingState: .ready,
                            merchantName: template.merchantName, transactionDate: date, totalAmount: template.totalAmount,
                            currencyCode: template.currencyCode, category: template.category, notes: template.notes,
                            expenseType: template.expenseType, taxCategory: template.taxCategory)
                        var draft = metadata
                        draft.isTemplate = false; draft.recurrence = nil; draft.nextDue = nil
                        draft.tracksPayments = true; draft.payments = []; draft.dueDate = date
                        draft.evidence = []; draft.payroll?.month = date.formatted(.dateTime.year().month()); draft.recurrenceSource = key; draft.audit = [FinanceAudit(actor: "本機", action: "由定期項目建立待確認紀錄")]
                        receipt.finance = draft
                        receipt.rebuildSearchText()
                        context.insert(receipt); inserted.append(receipt)
                    }
                    metadata.nextDue = next(date, interval: metadata.recurrence ?? "每月", anchor: metadata.anchorDay ?? 1)
                }
                template.finance = metadata
            }
            try context.save()
            return inserted.count
        } catch {
            for receipt in inserted { context.delete(receipt) }
            for (receipt, json) in originals { receipt.financeMetadataJSON = json }
            throw error
        }
    }
}

struct FinanceCashEntry {
    var date: Date?
    var income: Decimal
    var expense: Decimal
}
extension Receipt {
    func cashEntries(start: Date? = nil, end: Date? = nil) -> [FinanceCashEntry] {
        guard !finance.isTemplate, finance.matchedRecord == nil, !finance.treatment.excluded, totalAmount?.isFinite == true else { return [] }
        let events: [(Date?, Decimal)] = finance.tracksPayments ? finance.payments.map { ($0.date, $0.amount) } : [(transactionDate, faceAmount)]
        return events.compactMap { date, amount in
            if let start, let date, date < ReceiptDeliveryPackage.calendar.startOfDay(for: start) { return nil }
            if let end, let date, date >= ReceiptDeliveryPackage.calendar.date(byAdding: .day, value: 1, to: ReceiptDeliveryPackage.calendar.startOfDay(for: end))! { return nil }
            var income: Decimal = 0, expense: Decimal = 0
            switch finance.treatment {
            case .expenseRefund: expense = -amount
            case .salesRefund: income = -amount
            default: if transactionKind == .income { income = amount } else { expense = amount }
            }
            return FinanceCashEntry(date: date, income: income, expense: expense)
        }
    }
    var cashIncomeHKD: Double { ExchangeRateTable.convertToHKD(amount: NSDecimalNumber(decimal: cashIncome).doubleValue, from: resolvedCurrency) }
    var cashExpenseHKD: Double { ExchangeRateTable.convertToHKD(amount: NSDecimalNumber(decimal: cashExpense).doubleValue, from: resolvedCurrency) }
}

extension FinanceWorkflow {
    static func updatePayroll(_ receipt: Receipt, gross: Decimal, employerCost: Decimal, deductions: Decimal,
                              actor: String, context: ModelContext) throws {
        guard gross > 0, employerCost >= 0, deductions >= 0, deductions <= gross,
              gross + employerCost >= receipt.paidAmount || !receipt.finance.tracksPayments else {
            throw FinanceWorkflowError.invalid("請核對人工金額、扣款及已付總額。")
        }
        let oldAmount = receipt.totalAmount
        let total = NSDecimalNumber(decimal: gross + employerCost).doubleValue
        guard total.isFinite else { throw FinanceWorkflowError.invalid("金額超出可處理範圍。") }
        receipt.totalAmount = total
        do {
            try update(receipt, actor: actor, action: "修訂人工：應發 \(gross)，扣款 \(deductions)，僱主成本 \(employerCost)", context: context) {
                $0.payroll = FinancePayroll(employee: receipt.merchantName ?? "", month: (receipt.transactionDate ?? .now).formatted(.dateTime.year().month()), gross: gross, employerCost: employerCost, deductions: deductions)
                if $0.approval == "已批准" { $0.approval = "待審批" }
            }
        } catch { receipt.totalAmount = oldAmount; throw error }
    }
}
