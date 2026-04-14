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

                        if let itemDescription = receipt.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !itemDescription.isEmpty {
                            Text(itemDescription)
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.75))
                                .lineLimit(2)
                        }

                        Text(receipt.transactionDate ?? receipt.importedAt, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if let totalAmount = receipt.totalAmount {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Currency.amountString(totalAmount, currencyCode: receipt.currencyCode))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if let convertedAmount = receipt.amountInHKD,
                               receipt.resolvedCurrency != .hkd {
                                Text("≈ \(Currency.amountString(convertedAmount, currencyCode: Currency.hkd.rawValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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

    @ViewBuilder
    private var statusPill: some View {
        switch receipt.processingState {
        case .queued:
            ReceiptStatusPill(title: "Queued", tint: .receiptAccentOrange, systemImage: "clock")
        case .runningOCR:
            ReceiptStatusPill(title: "Reading Text", tint: .receiptAccentOrange, systemImage: "text.viewfinder")
        case .ready:
            if receipt.reviewStatus == .reviewed {
                ReceiptStatusPill(title: "Reviewed", tint: .receiptAccentGreen, systemImage: "checkmark.seal.fill")
            } else {
                ReceiptStatusPill(title: "Ready", tint: .receiptAccentGreen, systemImage: "sparkles")
            }
        case .failed:
            ReceiptStatusPill(title: "Needs Retry", tint: .receiptAccentRed, systemImage: "exclamationmark.triangle.fill")
        }
    }
}
