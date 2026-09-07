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
            itemDescription: "Chicken sandwich combo",
            transactionDate: .now.addingTimeInterval(-86_400),
            totalAmount: 18.5,
            currencyCode: "USD",
            taxAmount: 1.5,
            category: "Meals",
            notes: "Team lunch",
            extractionConfidence: 0.8,
            expenseType: .business,
            taxCategory: .meals
        )
        reviewedReceipt.reviewStatus = .reviewed
        reviewedReceipt.reviewedAt = .now
        reviewedReceipt.searchText = "cafe north lunch subtotal total"

        let inboxReceipt = Receipt(
            importSource: .photos,
            merchantName: "Stationery World",
            itemDescription: "A4 printer paper",
            transactionDate: .now,
            totalAmount: 42.0,
            currencyCode: "HKD",
            taxAmount: nil,
            category: "Office",
            extractionConfidence: 0.6,
            expenseType: .business
        )
        inboxReceipt.searchText = "stationery world office supplies"

        let travelReceipt = Receipt(
            importSource: .files,
            merchantName: "Metro Transit",
            itemDescription: "Airport express ticket",
            transactionDate: .now.addingTimeInterval(-172_800),
            totalAmount: 24.0,
            currencyCode: "HKD",
            category: "Travel",
            extractionConfidence: 0.9,
            expenseType: .reimbursable,
            taxCategory: .travel
        )
        travelReceipt.reviewStatus = .reviewed
        travelReceipt.reviewedAt = .now
        travelReceipt.searchText = "metro transit octopus travel"

        let groceriesReceipt = Receipt(
            importSource: .files,
            merchantName: "Fresh Market",
            itemDescription: "Vegetables and fruit",
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

        let incomeEntry = Receipt(
            importSource: .manual,
            transactionKind: .income,
            processingState: .ready,
            merchantName: "North Star Studio",
            itemDescription: "Design retainer",
            transactionDate: .now.addingTimeInterval(-259_200),
            totalAmount: 8_000,
            currencyCode: "HKD",
            category: "Client Payment",
            notes: "May invoice payment"
        )
        incomeEntry.reviewStatus = .reviewed
        incomeEntry.reviewedAt = .now
        incomeEntry.searchText = "north star studio client payment"

        context.insert(reviewedReceipt)
        context.insert(inboxReceipt)
        context.insert(travelReceipt)
        context.insert(groceriesReceipt)
        context.insert(incomeEntry)

        return container
    }

    @MainActor
    static func makeExperimentsContainer() -> ModelContainer {
        let container = try! PocketPalModelContainer.makeExperiments(isStoredInMemoryOnly: true)
        let context = container.mainContext

        context.insert(AccountingAccount(code: "1000", name: "Cash and Bank", accountType: .asset))
        context.insert(AccountingAccount(code: "5000", name: "Business Expenses", accountType: .expense))
        context.insert(BankTransaction(
            accountName: "Cash and Bank",
            postedAt: .now.addingTimeInterval(-86_400),
            descriptionText: "Cafe North",
            amountHKD: -145,
            suggestedCategory: "Meals"
        ))
        context.insert(ClientRecord(name: "North Star Studio", email: "hello@example.com"))
        context.insert(InvoiceRecord(
            invoiceNumber: "INV-001",
            clientName: "North Star Studio",
            dueDate: .now.addingTimeInterval(604_800),
            amountHKD: 8_000
        ))

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
