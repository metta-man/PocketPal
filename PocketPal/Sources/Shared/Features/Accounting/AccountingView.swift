import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AccountingModule: String, CaseIterable, Identifiable {
    case overview
    case banking
    case sales
    case bills
    case projects
    case books
    case automation
    case operations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Accounting"
        case .banking:
            return "Banking"
        case .sales:
            return "Sales"
        case .bills:
            return "Bills"
        case .projects:
            return "Projects"
        case .books:
            return "Accounts & Journals"
        case .automation:
            return "Rules"
        case .operations:
            return "Payroll & Inventory"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "Run the business layer from one calm workspace."
        case .banking:
            return "Import and classify bank activity inside the quarantined accounting store."
        case .sales:
            return "Track clients, invoices, due dates, and paid status."
        case .bills:
            return "Keep vendor bills visible until they are paid."
        case .projects:
            return "Manage client work, billable time, mileage, and reimbursements."
        case .books:
            return "Maintain accounts and manual journal adjustments."
        case .automation:
            return "Apply rules and recurring entries to reduce repeated work."
        case .operations:
            return "Keep lightweight payroll and inventory records in view."
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "building.columns"
        case .banking:
            return "creditcard"
        case .sales:
            return "doc.text"
        case .bills:
            return "tray.and.arrow.down"
        case .projects:
            return "clock.badge.checkmark"
        case .books:
            return "books.vertical"
        case .automation:
            return "wand.and.stars"
        case .operations:
            return "shippingbox"
        }
    }
}

private enum AccountingQuickAdd: String, Identifiable {
    case client = "Client"
    case project = "Project"
    case invoice = "Invoice"
    case bill = "Bill"
    case bankTransaction = "Bank Transaction"
    case timeEntry = "Time Entry"
    case mileageTrip = "Mileage Trip"
    case recurringRule = "Recurring Rule"
    case accountingRule = "Rule"
    case journalEntry = "Journal Entry"
    case account = "Account"
    case payrollRun = "Payroll Run"
    case inventoryItem = "Inventory Item"

    var id: String { rawValue }
}

struct AccountingView: View {
    var body: some View {
        NavigationStack {
            AccountingModuleView(module: .overview)
        }
    }
}

struct AccountingModuleView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\AccountingAccount.code)])
    private var accounts: [AccountingAccount]

    @Query(sort: [SortDescriptor(\BankTransaction.postedAt, order: .reverse)])
    private var bankTransactions: [BankTransaction]

    @Query(sort: [SortDescriptor(\ClientRecord.name)])
    private var clients: [ClientRecord]

    @Query(sort: [SortDescriptor(\ProjectRecord.createdAt, order: .reverse)])
    private var projects: [ProjectRecord]

    @Query(sort: [SortDescriptor(\InvoiceRecord.dueDate)])
    private var invoices: [InvoiceRecord]

    @Query(sort: [SortDescriptor(\BillRecord.dueDate)])
    private var bills: [BillRecord]

    @Query(sort: [SortDescriptor(\TimeEntryRecord.workDate, order: .reverse)])
    private var timeEntries: [TimeEntryRecord]

    @Query(sort: [SortDescriptor(\MileageTripRecord.tripDate, order: .reverse)])
    private var mileageTrips: [MileageTripRecord]

    @Query(sort: [SortDescriptor(\RecurringRuleRecord.nextRunAt)])
    private var recurringRules: [RecurringRuleRecord]

    @Query(sort: [SortDescriptor(\AccountingRuleRecord.merchantContains)])
    private var accountingRules: [AccountingRuleRecord]

    @Query(sort: [SortDescriptor(\JournalEntryRecord.entryDate, order: .reverse)])
    private var journalEntries: [JournalEntryRecord]

    @Query(sort: [SortDescriptor(\PayrollRunRecord.payDate, order: .reverse)])
    private var payrollRuns: [PayrollRunRecord]

    @Query(sort: [SortDescriptor(\InventoryItemRecord.name)])
    private var inventoryItems: [InventoryItemRecord]

    @State private var quickAdd: AccountingQuickAdd?
    @State private var errorMessage: String?
    @State private var importMessage: String?
    @State private var isShowingStatementImporter = false
    @State private var isImportingStatement = false

    let module: AccountingModule
    private let bankStatementImportService = BankStatementImportService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                moduleHeader
                moduleContent
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color.receiptGroupedBackground)
        .navigationTitle(module.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
        .toolbar {
            accountingToolbar
        }
        .sheet(item: $quickAdd) { mode in
            NavigationStack {
                AccountingQuickAddView(mode: mode)
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $isShowingStatementImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text, .pdf],
            allowsMultipleSelection: true,
            onCompletion: handleStatementImport
        )
        .alert("Accounting Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Statement Import", isPresented: Binding(
            get: { importMessage != nil },
            set: { newValue in
                if !newValue {
                    importMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var openInvoiceTotal: Double {
        invoices.filter { $0.status != .paid }.map(\.amountHKD).reduce(0, +)
    }

    private var openBillTotal: Double {
        bills.filter { $0.status != .paid }.map(\.amountHKD).reduce(0, +)
    }

    private var unreconciledCount: Int {
        bankTransactions.filter { $0.status != .reconciled }.count
    }

    private var billableTotal: Double {
        timeEntries.filter { !$0.isBilled }.map(\.billableAmountHKD).reduce(0, +)
            + mileageTrips.filter { !$0.isReimbursed }.map(\.reimbursableHKD).reduce(0, +)
    }

    @ToolbarContentBuilder
    private var accountingToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch module {
            case .overview:
                EmptyView()
            case .banking:
                Button("Add Tx") { quickAdd = .bankTransaction }
                Button("Import Statement") { isShowingStatementImporter = true }
                Button("Sample Import") { importSampleBankFeed() }
                Button("Apply Rules") { applyAccountingRules() }
                    .disabled(accountingRules.isEmpty || bankTransactions.isEmpty)
            case .sales:
                Button("Client") { quickAdd = .client }
                Button("Invoice") { quickAdd = .invoice }
            case .bills:
                Button("Bill") { quickAdd = .bill }
            case .projects:
                Button("Project") { quickAdd = .project }
                Button("Time") { quickAdd = .timeEntry }
                Button("Mileage") { quickAdd = .mileageTrip }
            case .books:
                Button("Account") { quickAdd = .account }
                Button("Journal") { quickAdd = .journalEntry }
                Button("Seed Accounts") { seedDefaultAccounts() }
                    .disabled(!accounts.isEmpty)
            case .automation:
                Button("Rule") { quickAdd = .accountingRule }
                Button("Recurring") { quickAdd = .recurringRule }
                Button("Apply Rules") { applyAccountingRules() }
                    .disabled(accountingRules.isEmpty)
                Button("Post Due") { postDueRecurringEntries() }
                    .disabled(recurringRules.allSatisfy { !$0.isEnabled || $0.nextRunAt > .now })
            case .operations:
                Button("Payroll") { quickAdd = .payrollRun }
                Button("Inventory") { quickAdd = .inventoryItem }
            }
        }
    }

    private var moduleHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: module.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(module.title)
                    .font(.title2.weight(.semibold))
                Text(module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch module {
        case .overview:
            heroCard
            bankingCard
            salesCard
            billsCard
            projectsCard
            booksCard
            automationCard
            operationsCard
        case .banking:
            bankingCard
        case .sales:
            salesCard
        case .bills:
            billsCard
        case .projects:
            projectsCard
        case .books:
            booksCard
        case .automation:
            automationCard
        case .operations:
            operationsCard
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                metricChip(Currency.amountString(openInvoiceTotal, currencyCode: Currency.hkd.rawValue), "Open invoices")
                metricChip(Currency.amountString(openBillTotal, currencyCode: Currency.hkd.rawValue), "Open bills")
                metricChip("\(unreconciledCount)", "Unreconciled")
                metricChip(Currency.amountString(billableTotal, currencyCode: Currency.hkd.rawValue), "Billable")
                metricChip(Currency.amountString(inventoryValue, currencyCode: Currency.hkd.rawValue), "Inventory")
            }
        }
        .padding(18)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var bankingCard: some View {
        card {
            actionHeader(title: "Bank feeds", subtitle: "\(bankTransactions.count) transactions, \(unreconciledCount) need review", systemImage: "creditcard.fill") {
                Button("Add Tx") { quickAdd = .bankTransaction }
                Button("Import Statement") { isShowingStatementImporter = true }
                Button("Sample Import") { importSampleBankFeed() }
                Button("Apply Rules") { applyAccountingRules() }
                    .disabled(accountingRules.isEmpty || bankTransactions.isEmpty)
            }

            if isImportingStatement {
                Label("Importing statement...", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(bankTransactions.prefix(4)) { transaction in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(transaction.descriptionText)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text("\(transaction.accountName) • \(transaction.status.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Currency.amountString(transaction.amountHKD, currencyCode: Currency.hkd.rawValue))
                        .font(.headline)
                }
            }

            if bankTransactions.isEmpty {
                emptyLine("Import or enter bank activity to classify without touching the receipt ledger.")
            }
        }
    }

    private var salesCard: some View {
        card {
            actionHeader(title: "Invoices & clients", subtitle: "\(clients.count) clients, \(invoices.count) invoices", systemImage: "doc.text.fill") {
                Button("Client") { quickAdd = .client }
                Button("Invoice") { quickAdd = .invoice }
            }

            ForEach(invoices.prefix(4)) { invoice in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(invoice.invoiceNumber)
                            .font(.body.weight(.semibold))
                        Text("\(invoice.clientName) • Due \(invoice.dueDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(invoice.status == .paid ? "Paid" : "Mark Paid") {
                        markInvoicePaid(invoice)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if invoices.isEmpty {
                emptyLine("Create invoices, track overdue payments, and mark paid when money lands.")
            }
        }
    }

    private var billsCard: some View {
        card {
            actionHeader(title: "Bills", subtitle: "\(bills.count) vendor bills tracked", systemImage: "tray.and.arrow.down.fill") {
                Button("Bill") { quickAdd = .bill }
            }

            ForEach(bills.prefix(4)) { bill in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bill.vendorName)
                            .font(.body.weight(.semibold))
                        Text("\(bill.category) • Due \(bill.dueDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(bill.status == .paid ? "Paid" : "Mark Paid") {
                        markBillPaid(bill)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if bills.isEmpty {
                emptyLine("Track unpaid supplier bills, due dates, categories, and payment status.")
            }
        }
    }

    private var projectsCard: some View {
        card {
            actionHeader(title: "Clients, projects, time & mileage", subtitle: "\(projects.count) projects, \(timeEntries.count) time entries, \(mileageTrips.count) trips", systemImage: "clock.badge.checkmark.fill") {
                Button("Project") { quickAdd = .project }
                Button("Time") { quickAdd = .timeEntry }
                Button("Mileage") { quickAdd = .mileageTrip }
            }

            ForEach(projects.prefix(3)) { project in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.body.weight(.semibold))
                        Text("\(project.clientName) • Budget \(Currency.amountString(project.budgetHKD, currencyCode: Currency.hkd.rawValue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusPill(project.isActive ? "Active" : "Closed")
                }
            }

            if projects.isEmpty {
                emptyLine("Track jobs, billable time, mileage, and reimbursement amounts.")
            }
        }
    }

    private var booksCard: some View {
        card {
            actionHeader(title: "Chart of accounts & journals", subtitle: "\(accounts.count) accounts, \(journalEntries.count) entries", systemImage: "books.vertical.fill") {
                Button("Account") { quickAdd = .account }
                Button("Journal") { quickAdd = .journalEntry }
                Button("Seed Accounts") { seedDefaultAccounts() }
            }

            ForEach(accounts.prefix(5)) { account in
                dividerRow {
                    Text("\(account.code) \(account.name)")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(account.accountType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if accounts.isEmpty {
                emptyLine("Add accounts for basic double-entry reports and manual journal adjustments.")
            }
        }
    }

    private var automationCard: some View {
        card {
            actionHeader(title: "Rules & recurring entries", subtitle: "\(accountingRules.count) rules, \(recurringRules.count) recurring schedules", systemImage: "wand.and.stars") {
                Button("Rule") { quickAdd = .accountingRule }
                Button("Recurring") { quickAdd = .recurringRule }
                Button("Apply Rules") { applyAccountingRules() }
                Button("Post Due") { postDueRecurringEntries() }
            }

            ForEach(recurringRules.prefix(3)) { recurringRule in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recurringRule.title)
                            .font(.body.weight(.semibold))
                        Text("\(recurringRule.interval.displayName) • Next \(recurringRule.nextRunAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusPill(recurringRule.isEnabled ? "On" : "Off")
                }
            }

            if recurringRules.isEmpty && accountingRules.isEmpty {
                emptyLine("Create merchant rules and recurring entries to reduce manual categorization.")
            }
        }
    }

    private var operationsCard: some View {
        card {
            actionHeader(title: "Payroll & inventory", subtitle: "\(payrollRuns.count) payroll runs, \(inventoryItems.count) items", systemImage: "shippingbox.and.arrow.backward.fill") {
                Button("Payroll") { quickAdd = .payrollRun }
                Button("Inventory") { quickAdd = .inventoryItem }
            }

            ForEach(payrollRuns.prefix(2)) { payrollRun in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(payrollRun.employeeName)
                            .font(.body.weight(.semibold))
                        Text("Pay date \(payrollRun.payDate, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Currency.amountString(payrollRun.grossPayHKD, currencyCode: Currency.hkd.rawValue))
                        .font(.headline)
                }
            }

            ForEach(inventoryItems.prefix(3)) { item in
                dividerRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                        Text("\(item.sku) • \(item.quantityOnHand.formatted()) on hand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusPill(item.needsReorder ? "Reorder" : "Stocked")
                }
            }

            if payrollRuns.isEmpty && inventoryItems.isEmpty {
                emptyLine("Track payroll runs and lightweight inventory values for reporting.")
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(18)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionHeader<MenuContent: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.receiptAccentBlue)
                .frame(width: 34, height: 34)
                .background(Color.receiptAccentBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                menu()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func metricChip(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func dividerRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 10) {
                content()
            }
        }
    }

    private func statusPill(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.receiptElevatedBackground, in: Capsule())
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func seedDefaultAccounts() {
        guard accounts.isEmpty else { return }

        [
            AccountingAccount(code: "1000", name: "Cash and Bank", accountType: .asset),
            AccountingAccount(code: "1100", name: "Accounts Receivable", accountType: .asset),
            AccountingAccount(code: "2000", name: "Accounts Payable", accountType: .liability),
            AccountingAccount(code: "3000", name: "Owner Equity", accountType: .equity),
            AccountingAccount(code: "4000", name: "Sales", accountType: .income),
            AccountingAccount(code: "5000", name: "Business Expenses", accountType: .expense)
        ].forEach(modelContext.insert)

        saveChanges()
    }

    private func importSampleBankFeed() {
        let samples = [
            BankTransaction(accountName: "Cash and Bank", postedAt: .now.addingTimeInterval(-86_400), descriptionText: "Cafe North", amountHKD: -145),
            BankTransaction(accountName: "Cash and Bank", postedAt: .now.addingTimeInterval(-172_800), descriptionText: "North Star Studio payment", amountHKD: 8_000),
            BankTransaction(accountName: "Cash and Bank", postedAt: .now, descriptionText: "Office rent", amountHKD: -12_000, suggestedCategory: "Rent")
        ]
        samples.forEach(modelContext.insert)
        saveChanges()
    }

    private func handleStatementImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importStatementFiles(urls)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importStatementFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImportingStatement = true
        defer { isImportingStatement = false }

        var insertedCount = 0
        var duplicateCount = 0
        var skippedCount = 0
        let existingKeys = Set(bankTransactions.map(Self.duplicateKey(for:)))
        var importedKeys = existingKeys

        do {
            for url in urls {
                let result = try await bankStatementImportService.parseStatement(at: url)
                skippedCount += result.skippedRowCount

                for draft in result.transactions {
                    guard !importedKeys.contains(draft.duplicateKey) else {
                        duplicateCount += 1
                        continue
                    }

                    importedKeys.insert(draft.duplicateKey)
                    modelContext.insert(BankTransaction(
                        accountName: draft.accountName,
                        postedAt: draft.postedAt,
                        descriptionText: draft.descriptionText,
                        amountHKD: draft.amountHKD,
                        suggestedCategory: draft.suggestedCategory
                    ))
                    insertedCount += 1
                }
            }

            try modelContext.save()
            applyAccountingRules()
            importMessage = "Imported \(insertedCount) transactions. Skipped \(skippedCount) rows and \(duplicateCount) duplicates."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func duplicateKey(for transaction: BankTransaction) -> String {
        BankStatementTransactionDraft(
            accountName: transaction.accountName,
            postedAt: transaction.postedAt,
            descriptionText: transaction.descriptionText,
            amountHKD: transaction.amountHKD,
            suggestedCategory: transaction.suggestedCategory
        )
        .duplicateKey
    }

    private func markInvoicePaid(_ invoice: InvoiceRecord) {
        invoice.status = .paid
        invoice.paidAt = invoice.paidAt ?? .now
        saveChanges()
    }

    private func markBillPaid(_ bill: BillRecord) {
        bill.status = .paid
        bill.paidAt = bill.paidAt ?? .now
        saveChanges()
    }

    private func applyAccountingRules() {
        var appliedCount = 0

        for rule in accountingRules where rule.isEnabled {
            for transaction in bankTransactions where transaction.descriptionText.localizedCaseInsensitiveContains(rule.merchantContains) {
                transaction.suggestedCategory = rule.category
                appliedCount += 1
            }
        }

        saveChanges()
        importMessage = appliedCount == 1
            ? "Applied rules to 1 transaction."
            : "Applied rules to \(appliedCount) transactions."
    }

    private func postDueRecurringEntries() {
        for rule in recurringRules where rule.isEnabled && rule.nextRunAt <= .now {
            let signedAmount = rule.transactionKind == .expense ? -rule.amountHKD : rule.amountHKD
            modelContext.insert(BankTransaction(
                accountName: "Cash and Bank",
                postedAt: rule.nextRunAt,
                descriptionText: rule.title,
                amountHKD: signedAmount,
                suggestedCategory: rule.category
            ))
            modelContext.insert(JournalEntryRecord(
                entryDate: rule.nextRunAt,
                memo: rule.title,
                debitAccountName: rule.transactionKind == .expense ? rule.category : "Cash and Bank",
                creditAccountName: rule.transactionKind == .expense ? "Cash and Bank" : rule.category,
                amountHKD: rule.amountHKD
            ))
            rule.nextRunAt = nextDate(after: rule.nextRunAt, interval: rule.interval)
        }

        saveChanges()
    }

    private func nextDate(after date: Date, interval: RecurringInterval) -> Date {
        let calendar = Calendar.current
        switch interval {
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var inventoryValue: Double {
        inventoryItems.map(\.inventoryValueHKD).reduce(0, +)
    }
}

private struct AccountingQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let mode: AccountingQuickAdd

    @State private var title = ""
    @State private var secondary = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var accountType = AccountType.expense
    @State private var transactionKind = TransactionKind.expense
    @State private var recurringInterval = RecurringInterval.monthly
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(mode.rawValue) {
                TextField(primaryPlaceholder, text: $title)
                if showsSecondaryField {
                    TextField(secondaryPlaceholder, text: $secondary)
                }
                if showsAmountField {
                    TextField(amountPlaceholder, text: $amount)
                        .receiptAccountingNumericField()
                }
                if showsDateField {
                    DatePicker(dateLabel, selection: $date, displayedComponents: .date)
                }
                if mode == .account {
                    Picker("Type", selection: $accountType) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                if mode == .recurringRule {
                    Picker("Entry Type", selection: $transactionKind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    Picker("Interval", selection: $recurringInterval) {
                        ForEach(RecurringInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add \(mode.rawValue)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var primaryPlaceholder: String {
        switch mode {
        case .client: return "Client name"
        case .project: return "Project name"
        case .invoice: return "Invoice number"
        case .bill: return "Vendor"
        case .bankTransaction: return "Description"
        case .timeEntry: return "Project"
        case .mileageTrip: return "Purpose"
        case .recurringRule: return "Rule title"
        case .accountingRule: return "Merchant contains"
        case .journalEntry: return "Memo"
        case .account: return "Account name"
        case .payrollRun: return "Employee name"
        case .inventoryItem: return "Item name"
        }
    }

    private var secondaryPlaceholder: String {
        switch mode {
        case .client: return "Email"
        case .project: return "Client name"
        case .invoice: return "Client name"
        case .bill: return "Category"
        case .bankTransaction: return "Bank account"
        case .timeEntry: return "Notes"
        case .mileageTrip: return "Project"
        case .recurringRule: return "Category"
        case .accountingRule: return "Category"
        case .journalEntry: return "Debit account / Credit account"
        case .account: return "Account code"
        case .payrollRun: return "Notes"
        case .inventoryItem: return "SKU"
        }
    }

    private var amountPlaceholder: String {
        switch mode {
        case .timeEntry: return "Hours"
        case .mileageTrip: return "Distance KM"
        case .inventoryItem: return "Quantity on hand"
        default: return "Amount HKD"
        }
    }

    private var dateLabel: String {
        switch mode {
        case .invoice, .bill: return "Due Date"
        case .recurringRule: return "Next Date"
        default: return "Date"
        }
    }

    private var showsSecondaryField: Bool {
        mode != .account || true
    }

    private var showsAmountField: Bool {
        switch mode {
        case .client, .accountingRule:
            return false
        default:
            return true
        }
    }

    private var showsDateField: Bool {
        switch mode {
        case .client, .project, .account, .accountingRule, .inventoryItem:
            return false
        default:
            return true
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecondary = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAmount = AmountParser.parse(amount) ?? 0

        switch mode {
        case .client:
            modelContext.insert(ClientRecord(name: cleanTitle, email: cleanSecondary.nilIfEmpty))
        case .project:
            modelContext.insert(ProjectRecord(name: cleanTitle, clientName: cleanSecondary.nilIfEmpty ?? "Unassigned", budgetHKD: parsedAmount))
        case .invoice:
            modelContext.insert(InvoiceRecord(invoiceNumber: cleanTitle, clientName: cleanSecondary.nilIfEmpty ?? "Client", dueDate: date, amountHKD: parsedAmount))
        case .bill:
            modelContext.insert(BillRecord(vendorName: cleanTitle, dueDate: date, amountHKD: parsedAmount, category: cleanSecondary.nilIfEmpty ?? "Uncategorized"))
        case .bankTransaction:
            modelContext.insert(BankTransaction(accountName: cleanSecondary.nilIfEmpty ?? "Cash and Bank", postedAt: date, descriptionText: cleanTitle, amountHKD: parsedAmount))
        case .timeEntry:
            modelContext.insert(TimeEntryRecord(projectName: cleanTitle, workDate: date, hours: parsedAmount, hourlyRateHKD: 650, notes: cleanSecondary.nilIfEmpty))
        case .mileageTrip:
            modelContext.insert(MileageTripRecord(projectName: cleanSecondary.nilIfEmpty, tripDate: date, distanceKM: parsedAmount, purpose: cleanTitle))
        case .recurringRule:
            modelContext.insert(RecurringRuleRecord(title: cleanTitle, transactionKind: transactionKind, amountHKD: parsedAmount, category: cleanSecondary.nilIfEmpty ?? "Recurring", interval: recurringInterval, nextRunAt: date))
        case .accountingRule:
            modelContext.insert(AccountingRuleRecord(merchantContains: cleanTitle, category: cleanSecondary.nilIfEmpty ?? "Business", expenseType: .business, taxCategory: .deductible))
        case .journalEntry:
            let accountNames = cleanSecondary.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            modelContext.insert(JournalEntryRecord(memo: cleanTitle, debitAccountName: accountNames.first ?? "Business Expenses", creditAccountName: accountNames.dropFirst().first ?? "Cash and Bank", amountHKD: parsedAmount))
        case .account:
            modelContext.insert(AccountingAccount(code: cleanSecondary.nilIfEmpty ?? "9999", name: cleanTitle, accountType: accountType, openingBalanceHKD: parsedAmount))
        case .payrollRun:
            modelContext.insert(PayrollRunRecord(payDate: date, employeeName: cleanTitle, grossPayHKD: parsedAmount, notes: cleanSecondary.nilIfEmpty))
        case .inventoryItem:
            modelContext.insert(InventoryItemRecord(sku: cleanSecondary.nilIfEmpty ?? "SKU-\(Int(Date().timeIntervalSince1970))", name: cleanTitle, quantityOnHand: parsedAmount, unitCostHKD: 0, reorderPoint: 0))
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    @ViewBuilder
    func receiptAccountingNumericField() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview {
    AccountingView()
        .modelContainer(PreviewSampleData.makeExperimentsContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
