import SwiftUI

struct ReceiptRowView: View {
    let receipt: Receipt

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ReceiptThumbnailView(asset: receipt.asset)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.displayMerchantName)
                            .font(.headline)
                            .lineLimit(2)

                        Text(receipt.transactionDate ?? receipt.importedAt, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if let totalAmount = receipt.totalAmount {
                        Text(receiptAmountString(totalAmount, currencyCode: receipt.currencyCode))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 8) {
                    statusPill

                    ReceiptStatusPill(
                        title: receipt.importSource.rawValue.capitalized,
                        tint: .blue,
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private func receiptAmountString(_ amount: Double, currencyCode: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    @ViewBuilder
    private var statusPill: some View {
        switch receipt.processingState {
        case .queued:
            ReceiptStatusPill(title: "Queued", tint: .orange, systemImage: "clock")
        case .runningOCR:
            ReceiptStatusPill(title: "Reading Text", tint: .orange, systemImage: "text.viewfinder")
        case .ready:
            if receipt.reviewStatus == .reviewed {
                ReceiptStatusPill(title: "Reviewed", tint: .green, systemImage: "checkmark.seal.fill")
            } else {
                ReceiptStatusPill(title: "Ready", tint: .green, systemImage: "sparkles")
            }
        case .failed:
            ReceiptStatusPill(title: "Needs Retry", tint: .red, systemImage: "exclamationmark.triangle.fill")
        }
    }
}
