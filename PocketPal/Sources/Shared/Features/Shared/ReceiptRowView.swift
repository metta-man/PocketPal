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
                            Text(amountLabel(totalAmount))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(receipt.transactionKind == .income ? .receiptAccentGreen : .primary)

                            if let convertedAmount = receipt.amountInHKD,
                               receipt.resolvedCurrency != .hkd {
                                Text("≈ \(amountLabel(convertedAmount, currencyCode: Currency.hkd.rawValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    statusPill

                    ReceiptStatusPill(
                        title: receipt.transactionKind.localizedDisplayName,
                        tint: receipt.transactionKind == .income ? .receiptAccentGreen : .receiptAccentBlue,
                        systemImage: receipt.transactionKind.systemImage
                    )

                    if receipt.transactionKind == .expense, receipt.expenseType.isTaxDeductible {
                        ReceiptStatusPill(
                            title: receipt.taxReadiness.localizedReadinessLabel,
                            tint: receipt.taxReadiness.isReadyForTaxExport ? .receiptAccentGreen : .receiptAccentOrange,
                            systemImage: receipt.taxReadiness.isReadyForTaxExport ? "checkmark" : "checklist"
                        )
                    }
                }

                if let issuePreview = taxIssuePreview {
                    Label(issuePreview.localizedTitle, systemImage: issuePreview.systemImage)
                        .font(.caption)
                        .foregroundStyle(.receiptAccentOrange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
        .accessibilityElement(children: .combine)
    }

    private func amountLabel(_ amount: Double, currencyCode: String? = nil) -> String {
        let prefix = receipt.transactionKind == .income ? "+" : "-"
        return "\(prefix)\(Currency.amountString(amount, currencyCode: currencyCode ?? receipt.currencyCode))"
    }

    private var taxIssuePreview: ReceiptReadinessIssue? {
        guard receipt.transactionKind == .expense,
              receipt.expenseType.isTaxDeductible,
              !receipt.taxReadiness.isReadyForTaxExport else {
            return nil
        }

        return receipt.taxReadiness.issues.first
    }

    @ViewBuilder
    private var statusPill: some View {
        switch receipt.processingState {
        case .queued:
            ReceiptStatusPill(title: "等候處理", tint: .receiptAccentOrange, systemImage: "clock")
        case .runningOCR:
            ReceiptStatusPill(title: "讀取文字", tint: .receiptAccentOrange, systemImage: "text.viewfinder")
        case .ready:
            if receipt.reviewStatus == .reviewed {
                ReceiptStatusPill(title: "已審核", tint: .receiptAccentGreen, systemImage: "checkmark.seal.fill")
            } else {
                ReceiptStatusPill(title: "待審核", tint: .receiptAccentGreen, systemImage: "sparkles")
            }
        case .failed:
            ReceiptStatusPill(title: "需要重試", tint: .receiptAccentRed, systemImage: "exclamationmark.triangle.fill")
        }
    }
}
