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

        let travelReceipt = Receipt(
            importSource: .files,
            merchantName: "Metro Transit",
            transactionDate: .now.addingTimeInterval(-172_800),
            totalAmount: 24.0,
            currencyCode: "HKD",
            category: "Travel",
            extractionConfidence: 0.9
        )
        travelReceipt.reviewStatus = .reviewed
        travelReceipt.reviewedAt = .now
        travelReceipt.searchText = "metro transit octopus travel"

        let groceriesReceipt = Receipt(
            importSource: .files,
            merchantName: "Fresh Market",
            transactionDate: .now.addingTimeInterval(-604_800),
            totalAmount: 56.4,
            currencyCode: "HKD",
            taxAmount: nil,
            category: "Groceries",
            notes: "Weekly restock",
            extractionConfidence: 0.84
        )
        groceriesReceipt.reviewStatus = .reviewed
        groceriesReceipt.reviewedAt = .now
        groceriesReceipt.searchText = "fresh market groceries vegetables"

        context.insert(reviewedReceipt)
        context.insert(inboxReceipt)
        context.insert(travelReceipt)
        context.insert(groceriesReceipt)

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
