import SwiftData
import SwiftUI

enum PreviewSampleData {
    @MainActor
    static func makeContainer() -> ModelContainer {
        let container = try! PocketPalModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let reviewedReceipt = Receipt(
            importSource: .files,
            merchantName: "Cafe North",
            transactionDate: .now.addingTimeInterval(-86_400),
            totalAmount: 18.5,
            currencyCode: "USD",
            taxAmount: 1.5,
            category: "Meals",
            notes: "Team lunch",
            extractionConfidence: 0.8
        )
        reviewedReceipt.reviewStatus = .reviewed
        reviewedReceipt.reviewedAt = .now
        reviewedReceipt.searchText = "cafe north lunch subtotal total"

        let inboxReceipt = Receipt(
            importSource: .photos,
            merchantName: "Stationery World",
            transactionDate: .now,
            totalAmount: 42.0,
            currencyCode: "HKD",
            taxAmount: nil,
            category: "Office",
            extractionConfidence: 0.6
        )
        inboxReceipt.searchText = "stationery world office supplies"

        context.insert(reviewedReceipt)
        context.insert(inboxReceipt)

        return container
    }

    @MainActor
    static func detailPreview() -> some View {
        let container = makeContainer()
        let descriptor = FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.importedAt)])
        let receipt = try! container.mainContext.fetch(descriptor).first!
        return ReceiptDetailView(receipt: receipt)
    }
}
