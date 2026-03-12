import SwiftData
import SwiftUI

private enum ArchiveFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case reviewed = "Reviewed"
    case unreviewed = "Unreviewed"

    var id: String { rawValue }
}

struct ArchiveView: View {
    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    @State private var searchText = ""
    @State private var filter: ArchiveFilter = .all

    private var filteredReceipts: [Receipt] {
        receipts.filter { receipt in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .reviewed:
                matchesFilter = receipt.reviewStatus == .reviewed
            case .unreviewed:
                matchesFilter = receipt.reviewStatus != .reviewed
            }

            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }

            let query = searchText.localizedLowercase
            return receipt.displayMerchantName.localizedLowercase.contains(query)
                || receipt.searchText.localizedLowercase.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Archive")
                            .font(.title2.weight(.bold))
                        Text("Search merchants or raw OCR text, then narrow by review state.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Status", selection: $filter) {
                            ForEach(ArchiveFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.receiptCardBackground)
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(filteredReceipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            ReceiptRowView(receipt: receipt)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.receiptGroupedBackground)
            .searchable(text: $searchText, prompt: "Merchant or OCR text")
        }
    }
}

#Preview {
    ArchiveView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
