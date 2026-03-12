import SwiftUI

struct ReceiptRowView: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            ReceiptThumbnailView(asset: receipt.asset)

            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.displayMerchantName)
                    .font(.headline)
                    .lineLimit(1)

                if let totalAmount = receipt.totalAmount {
                    Text(receiptAmountString(totalAmount, currencyCode: receipt.currencyCode))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                Text(receipt.transactionDate ?? receipt.importedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if receipt.reviewStatus == .reviewed {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private func receiptAmountString(_ amount: Double, currencyCode: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}
