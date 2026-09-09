import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FinanceImportDraft: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var date: Date
    var amount: Double
    var kind: TransactionKind
    var category: String
    var metadata: FinanceMetadata
    var notes: String? = nil
}
@MainActor
enum FinanceImporter {
    static func insert(_ drafts: [FinanceImportDraft], existing: [Receipt], ledger: ReceiptLedger, context: ModelContext) throws -> Int {
        var keys = Set(existing.compactMap { $0.finance.sourceKey })
        var created: [Receipt] = []
        do {
            for draft in drafts where keys.insert(draft.key).inserted {
                guard draft.amount.isFinite, draft.amount >= 0 else { throw FinanceWorkflowError.invalid("匯入包含無效金額。") }
                let receipt = Receipt(importSource: .files, transactionKind: draft.kind, processingState: .ready, merchantName: draft.name,
                    transactionDate: draft.date, totalAmount: draft.amount, currencyCode: "HKD", category: draft.category, notes: draft.notes, expenseType: ledger.expenseType)
                var metadata = draft.metadata
                metadata.sourceKey = draft.key
                metadata.audit.append(FinanceAudit(actor: "本機", action: "經預覽確認匯入 \(draft.key)"))
                receipt.finance = metadata; receipt.rebuildSearchText()
                context.insert(receipt); created.append(receipt)
            }
            try context.save(); return created.count
        } catch { created.forEach { context.delete($0) }; throw error }
    }
    static func legacy(context: ModelContext) throws -> [FinanceImportDraft] {
        var result: [FinanceImportDraft] = []
        for row in try context.fetch(FetchDescriptor<InvoiceRecord>()) {
            var data = FinanceMetadata(); data.client = row.clientName; data.project = row.projectName ?? ""; data.dueDate = row.dueDate; data.tracksPayments = true
            if row.status == .paid { data.payments = [.init(date: row.paidAt ?? row.issueDate, amount: Decimal(string: String(row.amountHKD)) ?? 0, reference: "既有已付款紀錄")] }
            result.append(.init(key: "invoice:" + row.id.uuidString, name: row.clientName + " / " + row.invoiceNumber, date: row.issueDate,
                amount: row.amountHKD, kind: .income, category: "客戶發票", metadata: data, notes: row.notes))
        }
        for row in try context.fetch(FetchDescriptor<BillRecord>()) {
            var data = FinanceMetadata(); data.dueDate = row.dueDate; data.tracksPayments = true
            if row.status == .paid { data.payments = [.init(date: row.paidAt ?? row.dueDate, amount: Decimal(string: String(row.amountHKD)) ?? 0, reference: "既有已付款紀錄")] }
            result.append(.init(key: "bill:" + row.id.uuidString, name: row.vendorName, date: row.dueDate, amount: row.amountHKD, kind: .expense, category: row.category, metadata: data, notes: row.notes))
        }
        for row in try context.fetch(FetchDescriptor<PayrollRunRecord>()) {
            var data = FinanceMetadata(); data.dueDate = row.payDate; data.tracksPayments = true
            data.requiredDocuments = ["核對員工扣款（舊資料沒有此欄位，暫列 0）"]
            if row.status == .paid { data.payments = [.init(date: row.payDate, amount: Decimal(string: String(row.grossPayHKD + row.employerCostHKD)) ?? 0, reference: "既有人工付款紀錄")] }
            data.payroll = FinancePayroll(employee: row.employeeName, month: row.payDate.formatted(.dateTime.year().month()), gross: Decimal(string: String(row.grossPayHKD)) ?? 0, employerCost: Decimal(string: String(row.employerCostHKD)) ?? 0, deductions: 0)
            result.append(.init(key: "payroll:" + row.id.uuidString, name: row.employeeName, date: row.payDate, amount: row.grossPayHKD + row.employerCostHKD, kind: .expense, category: "人工及僱主成本", metadata: data, notes: row.notes))
        }
        for row in try context.fetch(FetchDescriptor<RecurringRuleRecord>()) {
            var data = FinanceMetadata(); data.isTemplate = true; data.nextDue = row.isEnabled ? row.nextRunAt : nil
            data.recurrence = [.weekly: "每週", .monthly: "每月", .quarterly: "每季", .yearly: "每年"][row.interval]
            data.anchorDay = ReceiptDeliveryPackage.calendar.component(.day, from: row.nextRunAt)
            result.append(.init(key: "recurring:" + row.id.uuidString, name: row.title, date: row.nextRunAt, amount: row.amountHKD, kind: row.transactionKind, category: row.category, metadata: data))
        }
        return result
    }
}
struct FinanceImportView: View {
    let ledger: ReceiptLedger
    @Environment(\.modelContext) private var context
    @Query private var records: [Receipt]
    @State private var account = ""
    @State private var showingFile = false
    @State private var drafts: [FinanceImportDraft] = []
    @State private var selected: Set<String> = []
    @State private var matched: [String: UUID] = [:]
    @State private var message: String?
    @State private var confirm = false
    @State private var busy = false
    @State private var skipped = 0
    private var existingKeys: Set<String> { Set(records.compactMap { $0.finance.sourceKey }) }
    var body: some View {
        Form {
            Section("銀行 CSV") {
                TextField("銀行戶口名稱（用於分開去重）", text: $account)
                Text("只匯入以 HKD 記錄的 CSV。先核對日期、正負方向和金額；同日同額可能是不同交易，重複提示須自行確認。") .font(.caption)
                Button("選擇 CSV") { showingFile = true }.disabled(account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            if ledger == .business {
                Section("已有會計紀錄") {
                    Button("預覽已有發票、帳單、人工及定期項目") {
                        do {
                            let container = try PocketPalModelContainer.makeExperiments()
                            drafts = try FinanceImporter.legacy(context: ModelContext(container))
                            selected = Set(drafts.filter { !existingKeys.contains($0.key) }.map(\.key))
                            matched = [:]; skipped = 0
                        } catch { message = error.localizedDescription }
                    }
                    Text("原會計資料保留；匯入後以收支管理作日常操作。銀行紀錄如已對應這些收支，請選擇匹配，避免再計一次。") .font(.caption)
                }
            }
            Section("預覽（\(drafts.count) 筆；無法解析 \(skipped) 行）") {
                ForEach(drafts) { draft in
                    VStack(alignment: .leading) {
                        Toggle(isOn: Binding(get: { selected.contains(draft.key) }, set: { if $0 { selected.insert(draft.key) } else { selected.remove(draft.key) } })) {
                            Text("\(draft.name) · \(draft.kind == .income ? "收入" : "支出") HKD \(draft.amount.formatted())\n\(draft.date.formatted(date: .abbreviated, time: .omitted))")
                        }.disabled(existingKeys.contains(draft.key))
                        if existingKeys.contains(draft.key) {
                            Text("疑似已匯入，預設略過").font(.caption)
                            if draft.key.hasPrefix("bank:") {
                                Button("這是另一筆交易，另行匯入") {
                                    guard let index = drafts.firstIndex(where: { $0.key == draft.key }) else { return }
                                    drafts[index].key += ":manual:" + UUID().uuidString
                                    selected.insert(drafts[index].key)
                                }.font(.caption)
                            }
                        }
                        let candidates = matchingCandidates(draft)
                        if !candidates.isEmpty {
                            Picker("匹配已有紀錄", selection: Binding(get: { matched[draft.key] }, set: { matched[draft.key] = $0 })) {
                                Text("建立獨立待確認紀錄").tag(nil as UUID?)
                                ForEach(candidates) { receipt in Text(receipt.displayMerchantName).tag(Optional(receipt.id)) }
                            }
                            Text("匹配行只作對帳證據，不再計入收支；原紀錄的付款仍需核對。") .font(.caption)
                        }
                    }
                }
                Button("匯入所選 \(selected.count) 筆") { confirm = true }.disabled(selected.isEmpty || busy)
            }
        }
        .formStyle(.grouped)
            .navigationTitle("匯入及對帳")
        .fileImporter(isPresented: $showingFile, allowedContentTypes: [.commaSeparatedText]) { result in
            do {
                let url = try result.get()
                busy = true
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        let result = try await BankStatementImportService().parseStatement(at: url, accountName: account)
                        var occurrence: [String: Int] = [:]
                        drafts = result.transactions.map { row in
                            let key = "bank:" + ledger.rawValue + ":" + account + ":" + row.duplicateKey
                            let index = occurrence[key, default: 0]; occurrence[key] = index + 1
                            var data = FinanceMetadata(); data.account = account
                            return FinanceImportDraft(key: key + ":" + String(index), name: row.descriptionText, date: row.postedAt,
                                amount: abs(row.amountHKD), kind: row.amountHKD < 0 ? .expense : .income, category: row.suggestedCategory ?? "未分類", metadata: data)
                        }
                        selected = Set(drafts.filter { !existingKeys.contains($0.key) }.map(\.key)); matched = [:]; skipped = result.skippedRowCount
                    } catch { message = error.localizedDescription }
                }
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("確認匯入 \(selected.count) 筆？", isPresented: $confirm, titleVisibility: .visible) {
            Button("確認匯入") {
                do {
                    let chosen = drafts.filter { selected.contains($0.key) }.map { draft in
                        var value = draft; value.metadata.matchedRecord = matched[draft.key]; return value
                    }
                    let count = try FinanceImporter.insert(chosen, existing: records, ledger: ledger, context: context)
                    drafts = []; selected = []; message = "已匯入 \(count) 筆，請核對。"
                } catch { message = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("匯入結果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好", role: .cancel) {} } message: { Text(message ?? "") }
    }
    private func matchingCandidates(_ draft: FinanceImportDraft) -> [Receipt] {
        guard draft.key.hasPrefix("bank:") else { return [] }
        return records.filter {
            ledger.includes($0) && $0.finance.matchedRecord == nil && $0.finance.sourceKey?.hasPrefix("bank:") != true &&
            $0.resolvedCurrency == .hkd && $0.transactionKind == draft.kind && abs(($0.totalAmount ?? -1) - draft.amount) < 0.005
        }
    }
}

struct FinanceApplicationView: View {
    let ledger: ReceiptLedger
    @Query private var all: [Receipt]
    @State private var project = ""
    @State private var start = ReceiptDeliveryPackage.calendar.date(byAdding: .month, value: -6, to: .now) ?? .now
    @State private var end = Date.now
    private var records: [Receipt] {
        ReceiptDeliveryPackage.select(all, ledger: ledger, start: start, end: end, includeUndated: false, confirmedOnly: false)
            .filter { project.isEmpty || $0.finance.project.localizedCaseInsensitiveContains(project) }
    }
    var body: some View {
        Form {
            Section("準備指定期間資料") {
                DatePicker("由", selection: $start, displayedComponents: .date)
                DatePicker("至", selection: $end, displayedComponents: .date)
                TextField("項目（可選）", text: $project)
                Text("\(records.count) 筆紀錄；已記工時 \(records.reduce(Decimal.zero) { $0 + ($1.finance.hours ?? 0) }.description) 小時")
                Text("無工時紀錄不等於零工時。工時按交易日期分組；請將工作日期填為交易日期。") .font(.caption)
            }
            Section("文件準備提示") {
                Text("入息紀錄及證明、相關支出證明、付款紀錄；按實際計劃補充住戶、資產、工時或項目文件。")
                Text("在每筆紀錄填上所需文件名稱及工時，再附上圖片／PDF；匯出包會包含清單供逐項核對。")
                Link("職津官方申請文件要求", destination: URL(string: "https://www.1823.gov.hk/tc/faq/how-to-apply-for-the-working-family-allowance-scheme-what-documentary-proof-needs-to-be-submitted-with-the-application")!)
                Link("BUD 官方資料", destination: URL(string: "https://www.bud.hkpc.org/")!)
                Text("此頁不判斷資助資格；正式表格、申領期及證明要求以相關計劃最新指引為準。") .font(.caption)
            }
            ForEach(records.filter { !$0.finance.requiredDocuments.isEmpty }) { receipt in
                Section(receipt.displayMerchantName) {
                    ForEach(receipt.finance.requiredDocuments, id: \.self) { Text("待核對：" + $0) }
                    NavigationLink("檢查附件及紀錄") { FinanceRecordView(receipt: receipt) }
                }
            }
        }.formStyle(.grouped).navigationTitle("文件及工時")
    }
}
