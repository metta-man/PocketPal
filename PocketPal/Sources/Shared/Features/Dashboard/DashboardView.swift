import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.receiptGroupedBackground
                    .ignoresSafeArea()

                List {
                    Section {
                        dashboardHero
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("Quick Stats") {
                        statsCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("Recent Activity") {
                        if recentReceipts.isEmpty {
                            emptyActivityCard
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(recentReceipts) { receipt in
                                ReceiptRowView(receipt: receipt)
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
            .navigationTitle("Dashboard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            #endif
        }
    }

    // MARK: - Computed Properties

    private var recentReceipts: [Receipt] {
        Array(receipts.prefix(5))
    }

    private var inboxCount: Int {
        receipts.filter { $0.reviewStatus == .inbox }.count
    }

    private var reviewedCount: Int {
        receipts.filter { $0.reviewStatus == .reviewed }.count
    }

    private var totalExpenses: Double {
        receipts.filter { $0.transactionKind == .expense }.compactMap { $0.totalAmount }.reduce(0, +)
    }

    private var totalExpensesHKD: Double {
        receipts.map(\.cashExpenseHKD).reduce(0, +)
    }

    private var totalIncomeHKD: Double {
        receipts.map(\.cashIncomeHKD).reduce(0, +)
    }

    private var netCashflowHKD: Double {
        totalIncomeHKD - totalExpensesHKD
    }

    private var dominantCurrency: Currency {
        let currencies = receipts.map { $0.resolvedCurrency.rawValue }
        let grouped = Dictionary(grouping: currencies, by: { $0 })
        return Currency(rawValue: grouped.max { $0.value.count < $1.value.count }?.key ?? Currency.hkd.rawValue) ?? .hkd
    }

    // MARK: - View Components

    private var dashboardHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wallet.pass.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.receiptAccentBlue)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("PocketPal")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Track income and expenses, keep original receipts, and prepare records for tax or reimbursement.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.receiptAccentBlue.opacity(0.28),
                    Color.receiptAccentCyan.opacity(0.20),
                    Color.receiptAccentGreen.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.receiptAccentBlue.opacity(0.22), lineWidth: 1)
        )
    }

    private var statsCard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            statChip(title: "\(inboxCount)", subtitle: "Inbox")
            statChip(title: "\(reviewedCount)", subtitle: "Reviewed")
            statChip(title: Currency.amountString(totalIncomeHKD, currencyCode: Currency.hkd.rawValue), subtitle: "Income")
            statChip(title: Currency.amountString(totalExpensesHKD, currencyCode: Currency.hkd.rawValue), subtitle: "Expenses")
            statChip(title: Currency.amountString(netCashflowHKD, currencyCode: Currency.hkd.rawValue), subtitle: "Net HKD")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func statChip(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyActivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No receipts yet")
                .font(.headline)
            Text("Import your first receipt to start tracking expenses.")
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
}

#Preview {
    DashboardView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
