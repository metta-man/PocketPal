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
            List(filteredReceipts) { receipt in
                NavigationLink {
                    ReceiptDetailView(receipt: receipt)
                } label: {
                    ReceiptRowView(receipt: receipt)
                }
            }
            .navigationTitle("Archive")
            .searchable(text: $searchText, prompt: "Merchant or OCR text")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Status", selection: $filter) {
                        ForEach(ArchiveFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

#Preview {
    ArchiveView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
