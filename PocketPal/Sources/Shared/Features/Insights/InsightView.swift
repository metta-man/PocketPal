import SwiftData
import SwiftUI

private enum InsightDateRange: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case last30Days = "30 Days"
    case thisMonth = "This Month"

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
    var total: Double { receipts.compactMap(\.totalAmount).reduce(0, +) }
}

struct InsightView: View {
    @Query(sort: [SortDescriptor(\Receipt.transactionDate, order: .reverse), SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    @State private var selectedDateRange: InsightDateRange = .last30Days
    @State private var selectedCategory = "All Categories"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.receiptGroupedBackground
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
                                title: "No categorized expenses yet",
                                message: "Review receipts and add categories to compare spending patterns here."
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

                    Section("Expenses by Date") {
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }

    private var receiptsWithAmounts: [Receipt] {
        receipts.filter { $0.totalAmount != nil }
    }

    private var filteredReceipts: [Receipt] {
        receiptsWithAmounts.filter { receipt in
            guard matchesDateRange(receipt) else { return false }
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
                total: receipts.compactMap(\.totalAmount).reduce(0, +),
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
                amount: receipts.compactMap(\.totalAmount).reduce(0, +)
            )
        }
        .sorted { lhs, rhs in
            if lhs.amount == rhs.amount {
                return lhs.currencyCode < rhs.currencyCode
            }
            return lhs.amount > rhs.amount
        }
    }

    private var insightHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("See where your money goes over time.")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Filter receipts by date and category, then compare spending totals without leaving PocketPal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: summaryColumns, spacing: 10) {
                summaryChip(title: "\(filteredReceipts.count)", subtitle: "Expenses")
                summaryChip(title: topCategory, subtitle: "Top Category")
            }

            if currencyTotals.isEmpty {
                Text("No expense totals available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(currencyTotals) { total in
                            summaryChip(
                                title: amountString(total.amount, currencyCode: total.currencyCode),
                                subtitle: "Spend"
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
                colors: [Color.blue.opacity(0.14), Color.mint.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.headline)

            Picker("Date Range", selection: $selectedDateRange) {
                ForEach(InsightDateRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: $selectedCategory) {
                ForEach(categoryOptions, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func categoryRow(_ insight: CategoryInsight) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.name)
                    .font(.headline)
                Text("\(insight.count) \(insight.count == 1 ? "expense" : "expenses")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(amountString(insight.total, currencyCode: dominantCurrencyCode(for: insight.name)))
                .font(.headline.weight(.semibold))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func dailyCard(_ day: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(day.date, format: .dateTime.day().month(.wide).year())
                    .font(.headline)
                Spacer()
                Text(amountString(day.total, currencyCode: dominantCurrencyCode(for: day.receipts)))
                    .font(.headline.weight(.semibold))
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

                    Text(amountString(receipt.totalAmount ?? 0, currencyCode: normalizedCurrencyCode(for: receipt)))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        let referenceDate = receipt.transactionDate ?? receipt.importedAt
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
