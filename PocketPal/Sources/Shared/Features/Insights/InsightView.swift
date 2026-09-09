import SwiftData
import SwiftUI

private enum InsightDateRange: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case last30Days = "30 Days"
    case thisMonth = "This Month"

    var id: String { rawValue }
}

private enum InsightTransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case income = "Income"
    case expenses = "Expenses"

    var id: String { rawValue }
}

private struct CategoryInsight: Identifiable {
    let name: String
    let total: Double
    let count: Int

    var id: String { name }
}

private struct CurrencyTotal: Identifiable {
    let currencyCode: String
    let amount: Double

    var id: String { currencyCode }
}

private struct DailyInsight: Identifiable {
    let date: Date
    let receipts: [Receipt]

    var id: Date { date }
    var totalHKD: Double { receipts.compactMap(\.signedAmountInHKD).reduce(0, +) }
}

struct InsightView: View {
    @Query(sort: [SortDescriptor(\Receipt.transactionDate, order: .reverse), SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var allReceipts: [Receipt]
    var ledger: ReceiptLedger = .personal
    private var receipts: [Receipt] { allReceipts.filter { ledger.includes($0) && $0.reviewStatus == .reviewed } }

    @Environment(\.receiptWorkspace) private var workspace
    private var selectedDateRange: InsightDateRange {
        get { InsightDateRange(rawValue: workspace.insightFilters[ledger]?["range"] ?? "") ?? .last30Days }
        nonmutating set { workspace.insightFilters[ledger, default: [:]]["range"] = newValue.rawValue }
    }
    private var rangeBinding: Binding<InsightDateRange> { Binding(get: { selectedDateRange }, set: { selectedDateRange = $0 }) }
    private var selectedTransactionFilter: InsightTransactionFilter {
        get { InsightTransactionFilter(rawValue: workspace.insightFilters[ledger]?["kind"] ?? "") ?? .all }
        nonmutating set { workspace.insightFilters[ledger, default: [:]]["kind"] = newValue.rawValue }
    }
    private var kindBinding: Binding<InsightTransactionFilter> { Binding(get: { selectedTransactionFilter }, set: { selectedTransactionFilter = $0 }) }
    private var selectedCategory: String {
        get { workspace.insightFilters[ledger]?["category"] ?? "All Categories" }
        nonmutating set { workspace.insightFilters[ledger, default: [:]]["category"] = newValue }
    }
    private var categoryBinding: Binding<String> { Binding(get: { selectedCategory }, set: { selectedCategory = $0 }) }

    var body: some View {
        NavigationStack {
            ZStack {
                ledger.background
                    .ignoresSafeArea()

                List {
                    Section {
                        insightHero
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        filterCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("Category Breakdown") {
                        if categoryBreakdown.isEmpty {
                            emptyCard(
                                title: "No categorized entries yet",
                                message: "Review entries and add categories to compare income and spending patterns here."
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(categoryBreakdown) { insight in
                                categoryRow(insight)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }

                    Section("Money by Date") {
                        if dailyBreakdown.isEmpty {
                            emptyCard(
                                title: "Nothing in this range",
                                message: "Try a wider date range or switch back to all categories."
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(dailyBreakdown) { day in
                                dailyCard(day)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
            }
            .navigationTitle("\(ledger.title) · 分析")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ledger.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(ledger.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            #endif
        }
    }

    private var receiptsWithAmounts: [Receipt] {
        receipts.filter { $0.totalAmount != nil }
    }

    private var filteredReceipts: [Receipt] {
        receiptsWithAmounts.filter { receipt in
            guard matchesDateRange(receipt) else { return false }
            guard matchesTransactionFilter(receipt) else { return false }
            guard selectedCategory != "All Categories" else { return true }
            return normalizedCategoryName(for: receipt) == selectedCategory
        }
    }

    private var categoryOptions: [String] {
        let categories = Set(receiptsWithAmounts.map(normalizedCategoryName(for:)))
        return ["All Categories"] + categories.sorted()
    }

    private var categoryBreakdown: [CategoryInsight] {
        let grouped = Dictionary(grouping: filteredReceipts, by: normalizedCategoryName(for:))

        return grouped.map { category, receipts in
            CategoryInsight(
                name: category,
                total: receipts.compactMap(\.signedAmountInHKD).reduce(0, +),
                count: receipts.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.total == rhs.total {
                return lhs.name < rhs.name
            }
            return lhs.total > rhs.total
        }
    }

    private var dailyBreakdown: [DailyInsight] {
        let grouped = Dictionary(grouping: filteredReceipts) { receipt in
            calendar.startOfDay(for: receipt.transactionDate ?? receipt.importedAt)
        }

        return grouped.map { DailyInsight(date: $0.key, receipts: $0.value.sorted(by: compareReceipts)) }
            .sorted { $0.date > $1.date }
    }

    private var topCategory: String {
        categoryBreakdown.first?.name ?? "No data"
    }

    private var currencyTotals: [CurrencyTotal] {
        let grouped = Dictionary(grouping: filteredReceipts, by: { normalizedCurrencyCode(for: $0) })

        return grouped.map { code, receipts in
            CurrencyTotal(
                currencyCode: code,
                amount: receipts.map { signedAmount(for: $0) }.reduce(0, +)
            )
        }
        .sorted { lhs, rhs in
            if lhs.amount == rhs.amount {
                return lhs.currencyCode < rhs.currencyCode
            }
            return lhs.amount > rhs.amount
        }
    }

    private var incomeHKD: Double {
        filteredReceipts
            .map(\.cashIncomeHKD)
            .reduce(0, +)
    }

    private var expenseHKD: Double {
        filteredReceipts
            .map(\.cashExpenseHKD)
            .reduce(0, +)
    }

    private var netHKD: Double {
        incomeHKD - expenseHKD
    }

    private var insightHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("See where your money goes over time.")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Filter entries by date, type, and category, then compare income, spending, and net cash flow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: summaryColumns, spacing: 10) {
                summaryChip(title: "\(filteredReceipts.count)", subtitle: "Entries")
                summaryChip(title: amountString(incomeHKD, currencyCode: Currency.hkd.rawValue), subtitle: "Income")
                summaryChip(title: amountString(expenseHKD, currencyCode: Currency.hkd.rawValue), subtitle: "Expenses")
                summaryChip(title: amountString(netHKD, currencyCode: Currency.hkd.rawValue), subtitle: "Net HKD")
                summaryChip(title: topCategory, subtitle: "Top Category")
            }

            if currencyTotals.isEmpty {
                Text("No totals available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(currencyTotals) { total in
                            summaryChip(
                                title: amountString(total.amount, currencyCode: total.currencyCode),
                                subtitle: "Net"
                            )
                            .frame(width: 140, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.receiptAccentViolet.opacity(0.24),
                    Color.receiptAccentBlue.opacity(0.16),
                    Color.receiptAccentGreen.opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.receiptAccentViolet.opacity(0.22), lineWidth: 1)
        )
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.headline)

            Picker("Date Range", selection: rangeBinding) {
                ForEach(InsightDateRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Picker("Type", selection: kindBinding) {
                ForEach(InsightTransactionFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: categoryBinding) {
                ForEach(categoryOptions, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func summaryChip(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func categoryRow(_ insight: CategoryInsight) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.name)
                    .font(.headline)
                Text("\(insight.count) \(insight.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(amountString(insight.total, currencyCode: Currency.hkd.rawValue))
                .font(.headline.weight(.semibold))
                .foregroundStyle(insight.total >= 0 ? .receiptAccentGreen : .primary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func dailyCard(_ day: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(day.date, format: .dateTime.day().month(.wide).year())
                    .font(.headline)
                Spacer()
                Text(amountString(day.totalHKD, currencyCode: Currency.hkd.rawValue))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(day.totalHKD >= 0 ? .receiptAccentGreen : .primary)
            }

            ForEach(day.receipts) { receipt in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receipt.displayMerchantName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(normalizedCategoryName(for: receipt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(amountString(signedAmount(for: receipt), currencyCode: normalizedCurrencyCode(for: receipt)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(receipt.transactionKind == .income ? .receiptAccentGreen : .primary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func emptyCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 10, alignment: .top)]
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale.current
        return calendar
    }

    private func matchesDateRange(_ receipt: Receipt) -> Bool {
        guard let referenceDate = receipt.transactionDate else { return selectedDateRange == .allTime }
        let now = Date()

        switch selectedDateRange {
        case .allTime:
            return true
        case .last30Days:
            guard let startDate = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return referenceDate >= startDate
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return true }
            return interval.contains(referenceDate)
        }
    }

    private func matchesTransactionFilter(_ receipt: Receipt) -> Bool {
        switch selectedTransactionFilter {
        case .all:
            return true
        case .income:
            return receipt.transactionKind == .income
        case .expenses:
            return receipt.transactionKind == .expense
        }
    }

    private func normalizedCategoryName(for receipt: Receipt) -> String {
        let trimmed = receipt.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }

    private func normalizedCurrencyCode(for receipt: Receipt) -> String {
        let trimmed = receipt.currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "USD" : trimmed.uppercased()
    }

    private func dominantCurrencyCode(for category: String) -> String {
        dominantCurrencyCode(for: filteredReceipts.filter { normalizedCategoryName(for: $0) == category })
    }

    private func dominantCurrencyCode(for receipts: [Receipt]) -> String {
        let currencyGroups = Dictionary(grouping: receipts, by: normalizedCurrencyCode(for:))
        return currencyGroups.max { lhs, rhs in lhs.value.count < rhs.value.count }?.key ?? "USD"
    }

    private func amountString(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func signedAmount(for receipt: Receipt) -> Double {
        NSDecimalNumber(decimal: receipt.cashIncome - receipt.cashExpense).doubleValue
    }

    private func compareReceipts(lhs: Receipt, rhs: Receipt) -> Bool {
        let lhsDate = lhs.transactionDate ?? lhs.importedAt
        let rhsDate = rhs.transactionDate ?? rhs.importedAt

        if lhsDate == rhsDate {
            return lhs.displayMerchantName < rhs.displayMerchantName
        }

        return lhsDate > rhsDate
    }
}

#Preview {
    InsightView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
