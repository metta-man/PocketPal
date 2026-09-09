import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FinanceWorkspaceView: View {
    var ledger: ReceiptLedger
    @Environment(\.modelContext) private var context
    @Environment(\.serviceContainer) private var services
    @Query(sort: \Receipt.importedAt, order: .reverse) private var all: [Receipt]
    @State private var search = ""
    @State private var filter = "全部"
    @State private var start = ReceiptDeliveryPackage.calendar.date(from: ReceiptDeliveryPackage.calendar.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var end = Date.now
    @State private var limitDates = false
    @State private var creating = false
    @State private var error: String?
    @AppStorage("finance.autoGenerateRecurring") private var autoRecurring = false
    @State private var generationConfirmation = false
    @State private var generationTemplates: [Receipt] = []
    private var records: [Receipt] { all.filter { ledger.includes($0) } }
    private var templates: [Receipt] { all.filter { $0.finance.isTemplate && (ledger == .personal ? $0.expenseType == .personal : $0.expenseType != .personal) } }
    private var filtered: [Receipt] {
        records.filter { receipt in
            (search.isEmpty || receipt.financeSearchText.localizedCaseInsensitiveContains(search)) &&
            (!limitDates || ReceiptDeliveryPackage.select([receipt], ledger: ledger, start: start, end: end, includeUndated: false, confirmedOnly: false).count == 1) &&
            (filter == "全部" || filter == "未收" && receipt.transactionKind == .income && receipt.outstanding > 0 ||
             filter == "未付" && receipt.transactionKind == .expense && receipt.outstanding > 0 ||
             filter == "逾期" && receipt.isOverdue || filter == "待對帳" && receipt.finance.sourceKey?.hasPrefix("bank:") == true && receipt.finance.matchedRecord == nil || filter == "待審批" && receipt.finance.approval == "待審批" ||
             filter == "疑似重複" && !FinanceWorkflow.duplicates(of: receipt, in: records).isEmpty ||
             filter == "欠資料" && !ReceiptDeliveryPackage.issues(for: receipt, fileURL: { services.fileStorageService.fileURL(forRelativePath: $0) }).isEmpty)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("\(ledger.title)收支") {
                    Text("已收、已付按付款日期計算；未收未付為所選紀錄目前餘額。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(summary, id: \.self) { Text($0) }
                    Picker("顯示", selection: $filter) {
                        ForEach(["全部", "未收", "未付", "逾期", "待對帳", "待審批", "疑似重複", "欠資料"], id: \.self) { Text($0) }
                    }
                    Toggle("指定期間", isOn: $limitDates)
                    if limitDates {
                        DatePicker("由", selection: $start, displayedComponents: .date)
                        DatePicker("至", selection: $end, displayedComponents: .date)
                        Text("按交易日期篩選；無日期紀錄請到明細補填。") .font(.caption)
                    }
                }
                Section("紀錄（\(filtered.count)）") {
                    ForEach(filtered) { receipt in
                        NavigationLink { FinanceRecordView(receipt: receipt) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(receipt.displayMerchantName)
                                Text("\(receipt.resolvedCurrency.rawValue) \(receipt.faceAmount.description) · \(receipt.category ?? "未分類")")
                                    .font(.subheadline)
                                if receipt.outstanding > 0 {
                                    Text("\(receipt.isOverdue ? "逾期 · " : "")未\(receipt.transactionKind == .income ? "收" : "付") \(receipt.outstanding.description)")
                                        .foregroundStyle(receipt.isOverdue ? .red : .secondary)
                                }
                                if !receipt.finance.project.isEmpty { Text(receipt.finance.project).font(.caption) }
                            }
                        }
                    }
                    if filtered.isEmpty { Text("未有符合條件的紀錄。") .foregroundStyle(.secondary) }
                }
                Section("定期收支") {
                    Toggle("開啟收支管理時自動建立到期紀錄", isOn: $autoRecurring)
                    Text("只在開啟本頁時執行，每個項目每次最多補建 120 期；不會自動標記付款。") .font(.caption)
                    Text("到期後產生待確認、未付款紀錄，確認實際收付款後才計入現金收支。") .font(.caption)
                    ForEach(templates) { receipt in
                        NavigationLink { FinanceRecordView(receipt: receipt) } label: {
                            Text("\(receipt.displayMerchantName) · \(receipt.finance.recurrence ?? "") · \(receipt.finance.nextDue?.formatted(date: .abbreviated, time: .omitted) ?? "已暫停")")
                        }
                    }
                    Button("建立到期待確認紀錄") {
                        generationTemplates = templates.filter { !FinanceWorkflow.occurrences($0, through: .now).isEmpty }
                        generationConfirmation = true
                    }.disabled(templates.isEmpty)
                }
                Section("交付與資料") {
                    NavigationLink("备份、還原及員工交接") { FinanceArchiveView(ledger: ledger) }
                    NavigationLink("匯入銀行 CSV／會計紀錄") { FinanceImportView(ledger: ledger) }
                    NavigationLink("申請文件及工時清單") { FinanceApplicationView(ledger: ledger) }
                    Text("完整紀錄包可於設定匯出。") .font(.caption)
                }
            }
            .environment(\.timeZone, ReceiptDeliveryPackage.calendar.timeZone)
            .navigationTitle("收支管理")
            .task { generateIfEnabled() }
            .onChange(of: autoRecurring) { _, _ in generateIfEnabled() }
            .searchable(text: $search, prompt: "金額、客戶、項目、員工或備註")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("新增", systemImage: "plus") { creating = true } } }
            .sheet(isPresented: $creating) { FinanceCreateView(ledger: ledger) }
            .confirmationDialog("建立 \(generationTemplates.reduce(0) { $0 + FinanceWorkflow.occurrences($1, through: .now).count }) 筆到期紀錄？", isPresented: $generationConfirmation, titleVisibility: .visible) {
                Button("建立待確認紀錄") {
                    do { _ = try FinanceWorkflow.generate(generationTemplates, records: all, through: .now, context: context) }
                    catch { self.error = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("未能完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func generateIfEnabled() {
        guard autoRecurring else { return }
        do { _ = try FinanceWorkflow.generate(templates, records: all, through: .now, context: context) }
        catch { self.error = error.localizedDescription }
    }
    private var summary: [String] {
        let groups = Dictionary(grouping: filtered, by: { $0.resolvedCurrency.rawValue })
        return groups.keys.sorted().map { code in
            let list = groups[code] ?? []
            let entries = list.flatMap { $0.cashEntries(start: limitDates ? start : nil, end: limitDates ? end : nil) }
            let income = entries.reduce(Decimal.zero) { $0 + $1.income }
            let expense = entries.reduce(Decimal.zero) { $0 + $1.expense }
            let dueIn = list.filter { $0.transactionKind == .income }.reduce(Decimal.zero) { $0 + $1.outstanding }
            let dueOut = list.filter { $0.transactionKind == .expense }.reduce(Decimal.zero) { $0 + $1.outstanding }
            return "\(code) 已收 \(income) · 已付 \(expense)\n淨收支 \(income - expense) · 未收 \(dueIn) · 未付 \(dueOut)"
        }
    }
}

struct FinanceCreateView: View {
    let ledger: ReceiptLedger
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var amount = ""
    @State private var kind = TransactionKind.expense
    @State private var currency = Currency.hkd
    @State private var category = "其他"
    @State private var date = Date.now
    @State private var metadata = FinanceMetadata()
    @State private var recurring = false
    @State private var interval = "每月"
    @State private var payroll = false
    @State private var employerCost = "0"
    @State private var deductions = "0"
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("記一筆") {
                    TextField("商戶、客戶或員工", text: $title)
                    Picker("方向", selection: $kind) { Text("支出").tag(TransactionKind.expense); Text("收入").tag(TransactionKind.income) }
                    TextField(payroll ? "應發人工" : "金額", text: $amount)
                    Picker("貨幣", selection: $currency) { ForEach(Currency.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("交易日期", selection: $date, displayedComponents: .date)
                    TextField("分類：租金、水電、外判、材料等", text: $category)
                    Picker("款項性質", selection: $metadata.treatment) { ForEach(FinanceTreatment.allCases) { Text($0.rawValue).tag($0) } }
                    if metadata.treatment.excluded { Text("此類資金往來不計入營業收入／支出。利息請另記一般支出。") .font(.caption) }
                    Toggle("尚未收款／付款", isOn: $metadata.tracksPayments)
                    if metadata.tracksPayments { DatePicker("到期日", selection: Binding(get: { metadata.dueDate ?? date }, set: { metadata.dueDate = $0 }), displayedComponents: .date) }
                }
                Section("客戶及項目") {
                    TextField("客戶（可選）", text: $metadata.client)
                    TextField("項目（可選）", text: $metadata.project)
                    TextField("戶口／付款方式", text: $metadata.account)
                    TextField("代墊人（可選）", text: $metadata.paidBy)
                    TextField("備註", text: $notes, axis: .vertical)
                }
                if ledger == .business {
                    Section("人工") {
                        Toggle("人工紀錄", isOn: $payroll)
                        if payroll {
                            TextField("額外僱主成本（例如僱主供款）", text: $employerCost)
                            TextField("員工扣款（已包含在應發人工）", text: $deductions)
                            Text("請填入已核實金額。總成本＝應發人工＋僱主成本；員工扣款不重複加為成本。付款可分次記錄，分別註明員工實收和代繳供款。") .font(.caption)
                        }
                    }
                }
                Section("重複") {
                    Toggle("建立定期項目", isOn: $recurring)
                    if recurring { Picker("頻率", selection: $interval) { ForEach(["每週", "每月", "每季", "每年"], id: \.self) { Text($0) } } }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("新增收支")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("儲存") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || AmountParser.parse(amount) == nil) }
            }
            .alert("未能儲存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            guard let parsed = AmountParser.parse(amount), parsed > 0, parsed.isFinite else { throw FinanceWorkflowError.invalid("請填正數金額。") }
            var data = metadata
            var total = Decimal(string: String(parsed))!
            if payroll {
                guard kind == .expense, metadata.treatment == .regular,
                      let cost = Decimal(string: employerCost), let deduction = Decimal(string: deductions),
                      cost >= 0, deduction >= 0, deduction <= total else { throw FinanceWorkflowError.invalid("請核對人工及扣款；人工須為一般支出。") }
                data.payroll = FinancePayroll(employee: title, month: date.formatted(.dateTime.year().month()), gross: total, employerCost: cost, deductions: deduction)
                total += cost
            }
            if data.treatment == .expenseRefund { kind = .income }
            if data.treatment == .salesRefund { kind = .expense }
            if data.tracksPayments { data.dueDate = data.dueDate ?? date }
            if recurring {
                data.isTemplate = true; data.recurrence = interval; data.nextDue = date
                data.anchorDay = ReceiptDeliveryPackage.calendar.component(.day, from: date)
            }
            data.audit = [FinanceAudit(actor: "本機使用者", action: recurring ? "建立定期項目" : "建立收支紀錄")]
            let receipt = Receipt(importSource: .manual, transactionKind: kind, processingState: .ready, merchantName: title,
                transactionDate: date, totalAmount: NSDecimalNumber(decimal: total).doubleValue, currencyCode: currency.rawValue,
                category: payroll ? "人工及僱主成本" : category, notes: notes, expenseType: ledger.expenseType)
            receipt.finance = data; receipt.rebuildSearchText(); context.insert(receipt)
            do { try context.save() } catch { context.delete(receipt); throw error }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct FinanceRecordView: View {
    let receipt: Receipt
    @Environment(\.modelContext) private var context
    @Environment(\.serviceContainer) private var services
    @Query private var all: [Receipt]
    @AppStorage("finance.actor") private var actor = ""
    @State private var data = FinanceMetadata()
    @State private var amount = ""
    @State private var paymentDate = Date.now
    @State private var reference = ""
    @State private var showFiles = false
    @State private var error: String?
    @State private var confirmPayment = false
    @State private var correctingPayment: FinancePayment?
    @State private var correcting = false
    @State private var savedMessage = false
    @State private var payrollGross = ""
    @State private var payrollCost = ""
    @State private var payrollDeductions = ""
    @State private var hours = ""
    @State private var documents = ""
    @State private var previewURL: URL?
    var body: some View {
        Form {
            Section("紀錄") {
                Text("\(receipt.resolvedCurrency.rawValue) \(receipt.faceAmount.description)")
                NavigationLink("編輯金額、日期及原始資料") { ReceiptDetailView(receipt: receipt) }
                if !FinanceWorkflow.duplicates(of: receipt, in: all).isEmpty {
                    Text("發現 \(FinanceWorkflow.duplicates(of: receipt, in: all).count) 筆疑似重複；請核對，系統不會自動刪除。") .foregroundStyle(.orange)
                }
                if let payroll = receipt.finance.payroll {
                    Text("\(payroll.employee) · \(payroll.month)\n應發 \(payroll.gross) · 扣款 \(payroll.deductions) · 僱主成本 \(payroll.employerCost)\n員工實收參考 \(payroll.gross - payroll.deductions)")
                }
            }
            if receipt.finance.payroll != nil {
                Section("修訂人工") {
                    TextField("應發人工", text: $payrollGross)
                    TextField("僱主成本", text: $payrollCost)
                    TextField("員工扣款", text: $payrollDeductions)
                    Button("儲存人工金額") {
                        perform {
                            guard let gross = Decimal(string: payrollGross), let cost = Decimal(string: payrollCost), let deductions = Decimal(string: payrollDeductions) else { throw FinanceWorkflowError.invalid("請填有效人工金額。") }
                            try FinanceWorkflow.updatePayroll(receipt, gross: gross, employerCost: cost, deductions: deductions, actor: actor, context: context)
                        }
                    }
                }
            }
            Section("分類及追蹤") {
                Picker("款項性質", selection: $data.treatment) { ForEach(FinanceTreatment.allCases) { Text($0.rawValue).tag($0) } }
                TextField("客戶", text: $data.client)
                TextField("項目", text: $data.project)
                TextField("戶口／付款方式", text: $data.account)
                TextField("代墊人", text: $data.paidBy)
                if receipt.finance.sourceKey?.hasPrefix("bank:") == true {
                    Picker("對應已有收支", selection: $data.matchedRecord) {
                        Text("未匹配（獨立計入收支）").tag(nil as UUID?)
                        ForEach(all.filter { $0.id != receipt.id && $0.finance.matchedRecord == nil && $0.finance.sourceKey?.hasPrefix("bank:") != true && $0.expenseType == receipt.expenseType && $0.transactionKind == receipt.transactionKind && $0.resolvedCurrency == receipt.resolvedCurrency }) { candidate in
                            Text("\(candidate.displayMerchantName) · \(candidate.faceAmount)").tag(Optional(candidate.id))
                        }
                    }
                    Text("匹配後此銀行行只作證據，請在對應紀錄核對付款，避免重複計算。") .font(.caption)
                }
                Toggle("追蹤未收／未付", isOn: $data.tracksPayments).disabled(!data.payments.isEmpty)
                if data.tracksPayments {
                    DatePicker("到期日", selection: Binding(get: { data.dueDate ?? .now }, set: { data.dueDate = $0 }), displayedComponents: .date)
                    Text("啟用後，以付款紀錄計算已收已付；請補錄過往付款。") .font(.caption)
                }
                TextField("工時（可選）", text: $hours)
                TextField("所需文件（每行一项）", text: $documents, axis: .vertical)
                TextField("操作人姓名（供交接紀錄）", text: $actor)
                Button("儲存分類及追蹤資料") { saveMetadata() }
            }
            if receipt.finance.isTemplate {
                Section("定期項目") {
                    Button(receipt.finance.nextDue == nil ? "恢復（由今日開始）" : "暫停產生新紀錄") {
                        perform { try FinanceWorkflow.update(receipt, actor: actor, action: "切換定期項目", context: context) { $0.nextDue = $0.nextDue == nil ? .now : nil } }
                    }
                }
            } else if receipt.finance.tracksPayments {
                Section("付款") {
                    Text("已\(receipt.transactionKind == .income ? "收" : "付") \(receipt.paidAmount.description) · 尚欠 \(receipt.outstanding.description)")
                    ForEach(receipt.finance.payments) { payment in
                        VStack(alignment: .leading) {
                            Text("\(payment.date.formatted(date: .abbreviated, time: .omitted)) · \(payment.amount) · \(payment.reference)")
                            Button("撤回這筆錯誤付款") { correctingPayment = payment; correcting = true }.font(.caption)
                        }
                    }
                    if receipt.outstanding > 0 {
                        TextField("本次金額", text: $amount)
                        DatePicker("實際付款日期", selection: $paymentDate, in: ...Date.now, displayedComponents: .date)
                        TextField("付款參考／對方名稱", text: $reference)
                        Button("記錄這次付款") { confirmPayment = true }
                    }
                }
            }
            Section("證明（\(receipt.allEvidence.count)）") {
                ForEach(receipt.allEvidence) { file in
                    Button(file.name) { previewURL = services.fileStorageService.fileURL(forRelativePath: file.path) }
                }
                Button("加入圖片或 PDF（可多選）") { showFiles = true }
                ForEach(receipt.finance.requiredDocuments, id: \.self) { name in
                    Button("確認已備齊：" + name) {
                        perform { try FinanceWorkflow.update(receipt, actor: actor, action: "確認已備齊文件：" + name, context: context) { $0.requiredDocuments.removeAll { $0 == name } } }
                    }
                }
            }
            Section("提交及審批") {
                Text("狀態：\(receipt.finance.approval)")
                Text("本機／檔案交接紀錄；姓名並非登入身份。批准前請核對原始證明。") .font(.caption)
                Button("提交給老闆核對") { approve("待審批") }
                Button("核對並批准") { approve("已批准") }
                Button("退回補資料") { approve("需補資料") }
            }
            Section("修改紀錄") {
                ForEach(receipt.finance.audit.reversed()) { entry in
                    Text("\(entry.date.formatted()) · \(entry.actor)\n\(entry.action)").font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(receipt.displayMerchantName)
        .onAppear { load() }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            perform { try addEvidence(result.get()) }
        }
        .sheet(item: Binding(get: { previewURL.map { FinancePreviewURL(url: $0) } }, set: { previewURL = $0?.url })) { item in
            NavigationStack { FinanceEvidencePreview(url: item.url) }
        }
        .confirmationDialog("撤回錯誤付款？原內容會保留於修改紀錄。", isPresented: $correcting, titleVisibility: .visible) {
            Button("確認撤回", role: .destructive) {
                guard let payment = correctingPayment else { return }
                perform { try FinanceWorkflow.update(receipt, actor: actor, action: "撤回付款 \(payment.amount)，日期 \(payment.date.formatted())，參考 \(payment.reference)", context: context) { $0.payments.removeAll { $0.id == payment.id } } }
                correctingPayment = nil
            }
            Button("取消", role: .cancel) { correctingPayment = nil }
        }
        .confirmationDialog("確認記錄付款？", isPresented: $confirmPayment, titleVisibility: .visible) {
            Button("確認 \(amount)") {
                perform {
                    guard let value = Decimal(string: amount) else { throw FinanceWorkflowError.invalid("請輸入有效金額。") }
                    try FinanceWorkflow.pay(receipt, amount: value, date: paymentDate, reference: reference, actor: actor, context: context)
                    amount = ""; reference = ""
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("未能完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) {} } message: { Text(error ?? "") }
        .alert("已儲存", isPresented: $savedMessage) { Button("好", role: .cancel) {} }
    }
    private func load() {
        data = receipt.finance; hours = data.hours?.description ?? ""; documents = data.requiredDocuments.joined(separator: "\n")
        payrollGross = data.payroll?.gross.description ?? ""; payrollCost = data.payroll?.employerCost.description ?? ""
        payrollDeductions = data.payroll?.deductions.description ?? ""
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); load() } catch { self.error = error.localizedDescription }
    }
    private func saveMetadata() {
        perform {
            if !hours.isEmpty && (Decimal(string: hours) == nil || Decimal(string: hours)! < 0) { throw FinanceWorkflowError.invalid("工時須為非負數。") }
            if data.treatment == .expenseRefund && receipt.transactionKind != .income || data.treatment == .salesRefund && receipt.transactionKind != .expense {
                throw FinanceWorkflowError.invalid("支出退款須為收入方向，退回客戶款項須為支出方向，請先編輯原始資料。")
            }
            try FinanceWorkflow.update(receipt, actor: actor, action: "更新分類 \(data.treatment.rawValue)、客戶 \(data.client)、項目 \(data.project)、戶口 \(data.account)、代墊人 \(data.paidBy)、工時 \(hours)、付款追蹤 \(data.tracksPayments)", context: context) { current in
                current.treatment = data.treatment; current.client = data.client; current.project = data.project
                current.account = data.account; current.paidBy = data.paidBy; current.tracksPayments = data.tracksPayments
                current.matchedRecord = data.matchedRecord
                current.dueDate = data.dueDate; current.hours = Decimal(string: hours)
                current.requiredDocuments = Array(Set(documents.components(separatedBy: .newlines).filter { !$0.isEmpty })).sorted()
            }
            savedMessage = true
        }
    }
    private func approve(_ status: String) {
        perform {
            guard !actor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FinanceWorkflowError.invalid("請先填寫操作人姓名。") }
            if status == "已批准" && (receipt.totalAmount == nil || receipt.transactionDate == nil || receipt.faceAmount <= 0) {
                throw FinanceWorkflowError.invalid("請先補齊日期及有效金額。")
            }
            try FinanceWorkflow.update(receipt, actor: actor, action: status, context: context) {
                $0.approval = status
                if status == "待審批" { $0.submittedBy = actor }
            }
        }
    }
    private func addEvidence(_ urls: [URL]) throws {
        var evidence: [FinanceEvidence] = []
        var created: [URL] = []
        do {
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let stored = try services.fileStorageService.storeImportedFile(from: url, receiptID: UUID())
                created.append(services.fileStorageService.fileURL(forRelativePath: stored.relativePath))
                if let thumbnail = stored.thumbnailRelativePath { created.append(services.fileStorageService.fileURL(forRelativePath: thumbnail)) }
                evidence.append(FinanceEvidence(name: stored.originalFilename, path: stored.relativePath, type: stored.contentType.identifier))
            }
            try FinanceWorkflow.update(receipt, actor: actor, action: "加入 \(evidence.count) 份證明", context: context) { $0.evidence.append(contentsOf: evidence) }
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

}
struct FinancePreviewURL: Identifiable { let url: URL; var id: URL { url } }
struct FinanceEvidencePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            if url.pathExtension.lowercased() == "pdf" { PDFPreviewView(url: url) }
            else {
                #if os(macOS)
                if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit() }
                else { Text("無法讀取附件") }
                #else
                if let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit() }
                else { Text("無法讀取附件") }
                #endif
            }
        }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("關閉") { dismiss() } } }
    }
}
