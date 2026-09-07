import SwiftUI

struct ReceiptStatusPill: View {
    let title: String
    let tint: Color
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.18), in: Capsule())
    }
}

struct ReceiptHomeHeader: View {
    let pendingCount: Int
    let readyCount: Int
    let missingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("收據 Inbox")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("掃描、匯入、補齊資料，令每張收據都可以安心報稅或報銷。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ReceiptReadinessSummary(items: [
                .init(value: "\(pendingCount)", title: "待確認", systemImage: "tray.full", tint: .receiptAccentBlue),
                .init(value: "\(readyCount)", title: "資料已齊", systemImage: "checkmark.circle", tint: .receiptAccentGreen),
                .init(value: "\(missingCount)", title: "要補齊", systemImage: "exclamationmark.triangle.fill", tint: .receiptAccentOrange)
            ])
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.receiptOutline.opacity(0.18), lineWidth: 1)
        )
    }

    private var headline: String {
        if pendingCount == 0 {
            return "今日沒有待確認收據。"
        }

        return "\(pendingCount) 張收據等你處理。"
    }
}

struct ReceiptReadinessSummary: View {
    struct Item: Identifiable {
        let id: String
        let value: String
        let title: String
        let systemImage: String
        let tint: Color

        init(
            id: String? = nil,
            value: String,
            title: String,
            systemImage: String,
            tint: Color
        ) {
            self.id = id ?? title
            self.value = value
            self.title = title
            self.systemImage = systemImage
            self.tint = tint
        }
    }

    let items: [Item]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: item.systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.tint)
                            .frame(width: 22, height: 22)
                            .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(item.value)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct PrimaryCaptureButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.84)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.receiptAccentBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

struct ReviewIssueList: View {
    let issues: [ReceiptReadinessIssue]
    var readyTitle = "可以匯出"
    var readyMessage = "必要資料已齊，可以放入稅務匯出。"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(issues.isEmpty ? .receiptAccentGreen : .receiptAccentOrange)
                    .frame(width: 38, height: 38)
                    .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(issues.isEmpty ? readyTitle : "需要補齊")
                        .font(.headline)
                    Text(issues.isEmpty ? readyMessage : "先處理以下項目，這張收據先算真正完成。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: issue.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.receiptAccentOrange)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.localizedTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(issue.localizedDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(14)
                .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension ReceiptReadinessIssue {
    var localizedTitle: String {
        switch id {
        case "review":
            return "待確認"
        case "processing":
            return "OCR 未完成"
        case "merchant":
            return "缺少商戶"
        case "date":
            return "缺少日期"
        case "amount":
            return "缺少金額"
        case "category":
            return "缺少分類"
        case "taxCategory":
            return "缺少稅務分類"
        case "proof":
            return "沒有收據附件"
        case "futureDate":
            return "日期在未來"
        default:
            return title
        }
    }

    var localizedDetail: String {
        switch id {
        case "review":
            return "核對原始收據並確認資料後，才會納入正式匯出。"
        case "processing":
            return "完成 OCR 或處理匯入錯誤後，先可以完成審核。"
        case "merchant":
            return "填上供應商或商戶名稱。"
        case "date":
            return "填上交易日期，方便搜尋、報表和匯出。"
        case "amount":
            return "填上實付總額。"
        case "category":
            return "選擇支出分類，方便之後搜尋和匯出。"
        case "taxCategory":
            return "選擇這筆支出在稅務匯出入面應該點樣歸類。"
        case "proof":
            return "業務或報銷支出需附上原始收據才可以確認及匯出。"
        case "futureDate":
            return "更正日期後，才可以完成審核或匯出。"
        default:
            return detail
        }
    }
}

extension ReceiptTaxReadiness {
    var localizedReadinessLabel: String {
        isReadyForTaxExport ? "可匯出" : (fieldIssues.isEmpty ? "待確認" : "\(fieldIssues.count) 項要補")
    }
}

extension Receipt {
    var localizedProcessingStatusLabel: String {
        switch processingState {
        case .queued:
            return "等候處理"
        case .runningOCR:
            return "讀取文字"
        case .ready:
            return reviewStatus == .reviewed ? "已確認" : "待確認"
        case .failed:
            return "需要重試"
        }
    }
}

extension ReceiptImportSource {
    var localizedDisplayName: String {
        switch self {
        case .files:
            return "檔案"
        case .photos:
            return "相簿"
        case .scanner:
            return "掃描"
        case .dragDrop:
            return "拖放"
        case .manual:
            return "手動"
        }
    }
}

extension TransactionKind {
    var localizedDisplayName: String {
        switch self {
        case .expense:
            return "支出"
        case .income:
            return "收入"
        }
    }
}

extension ExpenseType {
    var localizedDisplayName: String {
        switch self {
        case .personal:
            return "個人"
        case .business:
            return "業務"
        case .reimbursable:
            return "可報銷"
        }
    }
}

extension TaxCategory {
    var localizedDisplayName: String {
        switch self {
        case .deductible:
            return "可扣稅支出"
        case .nonDeductible:
            return "不可扣稅"
        case .travel:
            return "交通 / 差旅"
        case .meals:
            return "餐飲 / 招待"
        case .office:
            return "辦公用品"
        case .equipment:
            return "設備"
        case .utilities:
            return "水電 / 網絡"
        case .professionalServices:
            return "專業服務"
        case .uncategorized:
            return "未分類"
        }
    }
}

extension Currency {
    var localizedDisplayName: String {
        switch self {
        case .hkd:
            return "港元"
        case .cny:
            return "人民幣"
        case .usd:
            return "美元"
        }
    }
}

extension AppPreferences {
    static func localizedTaxYearDescription(referenceDate: Date = .now) -> String {
        let calendar = Calendar.current
        let startMonth = taxYearStartMonth
        let year = calendar.component(.year, from: referenceDate)
        let month = calendar.component(.month, from: referenceDate)
        let startYear = month >= startMonth ? year : year - 1

        guard let startDate = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)),
              let nextStartDate = calendar.date(byAdding: .year, value: 1, to: startDate),
              let endDate = calendar.date(byAdding: .day, value: -1, to: nextStartDate) else {
            return "課稅年度"
        }

        let format = Date.FormatStyle.dateTime
            .day()
            .month(.wide)
            .year()
            .locale(Locale(identifier: "zh_Hant_HK"))
        return "\(startDate.formatted(format)) 至 \(endDate.formatted(format))"
    }
}
