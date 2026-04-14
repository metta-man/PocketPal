import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    @Query(sort: [SortDescriptor(\Connection.createdAt, order: .reverse)])
    private var connections: [Connection]

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

                    Section("Connections") {
                        if connections.isEmpty {
                            connectionsEmptyCard
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(connections) { connection in
                                connectionRow(connection)
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
        receipts.compactMap { $0.totalAmount }.reduce(0, +)
    }

    private var totalExpensesHKD: Double {
        receipts.compactMap(\.amountInHKD).reduce(0, +)
    }

    private var dominantCurrency: Currency {
        let currencies = receipts.map { $0.resolvedCurrency.rawValue }
        let grouped = Dictionary(grouping: currencies, by: { $0 })
        return Currency(rawValue: grouped.max { $0.value.count < $1.value.count }?.key ?? Currency.hkd.rawValue) ?? .hkd
    }

    // MARK: - View Components

    private var dashboardHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to PocketPal")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Track your expenses, manage receipts, and prepare for tax season all in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.14), Color.mint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var statsCard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            statChip(title: "\(inboxCount)", subtitle: "Inbox")
            statChip(title: "\(reviewedCount)", subtitle: "Reviewed")
            statChip(title: Currency.amountString(totalExpenses, currencyCode: dominantCurrency.rawValue), subtitle: "Entered")
            statChip(title: Currency.amountString(totalExpensesHKD, currencyCode: Currency.hkd.rawValue), subtitle: "HKD Total")
            statChip(title: "\(connections.count)", subtitle: "Connected")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
        .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private var connectionsEmptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Accounts")
                        .font(.headline)
                    Text("Link your email and shopping accounts to auto-import receipts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundStyle(.receiptAccentBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func connectionRow(_ connection: Connection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: connection.provider.systemImage)
                .font(.title3)
                .foregroundStyle(.receiptAccentBlue)
                .frame(width: 32, height: 32)
                .background(Color.receiptAccentBlue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName)
                    .font(.headline)
                if let lastSync = connection.lastSyncAt {
                    Text("Last sync: \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not yet synced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if connection.syncEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.receiptAccentGreen)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }
}

#Preview {
    DashboardView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
