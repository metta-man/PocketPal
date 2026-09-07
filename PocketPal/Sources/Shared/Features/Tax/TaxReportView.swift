import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum TaxReportRange: String, CaseIterable, Identifiable {
    case currentTaxYear = "本課稅年度"
    case allTime = "全部"

    var id: String { rawValue }
}

struct TaxReportView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Receipt.transactionDate, order: .reverse), SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var receipts: [Receipt]

    @State private var reviewRoute: ReceiptReviewRoute?
    @State private var selectedRange: TaxReportRange = .currentTaxYear
    @State private var exportDocument: TaxReportExportDocument?
    @State private var isShowingExporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.receiptGroupedBackground
                    .ignoresSafeArea()

                List {
                    Section {
                        taxHero
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        filterCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("快速整理") {
                        quickActionsCard
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section("待確認 / 補齊") {
                        if needsReviewReceipts.isEmpty {
                            emptyCard(title: "全部可以匯出", message: "這個範圍內沒有待確認或缺漏資料的收據。")
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(needsReviewReceipts) { receipt in
                                Button {
                                    reviewRoute = ReceiptReviewRoute(receipt: receipt, queue: needsReviewReceipts)
                                } label: {
                                    TaxReceiptRow(receipt: receipt)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    Section("可匯出") {
                        if readyReceipts.isEmpty {
                            emptyCard(title: "未有可匯出收據", message: "先核對並確認收據，再匯出 CSV。")
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(readyReceipts) { receipt in
                                NavigationLink {
                                    ReceiptDetailView(receipt: receipt)
                                } label: {
                                    TaxReceiptRow(receipt: receipt)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    bottomSpacer
                }
                .listStyle(.plain)
                #if os(iOS)
                .scrollContentBackground(.hidden)
                .safeAreaPadding(.bottom, 72)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 82)
                }
                #endif
            }
            .navigationTitle("稅務")
            .navigationDestination(item: $reviewRoute) { route in
                ReceiptDetailView(receipt: route.receipt, reviewQueue: route.queue)
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prepareTaxExport()
                    } label: {
                        Label("匯出", systemImage: "square.and.arrow.up")
                    }
                    .disabled(readyReceipts.isEmpty)
                }
            }
        }
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "PocketPal-Tax-\(exportDateStamp).csv"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("稅務匯出失敗", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知錯誤")
        }
    }

    private var filteredReceipts: [Receipt] {
        receipts.filter { receipt in
            receipt.transactionKind == .expense && receipt.expenseType.isTaxDeductible
        }
        .filter { receipt in
            guard selectedRange == .currentTaxYear,
                  let interval = TaxExportService.taxYearInterval() else {
                return true
            }

            return interval.contains(receipt.transactionDate ?? receipt.importedAt)
        }
    }

    private var summary: TaxReportSummary {
        TaxExportService.summary(for: filteredReceipts)
    }

    private var needsReviewReceipts: [Receipt] {
        filteredReceipts.filter { !$0.taxReadiness.isReadyForTaxExport }
    }

    private var readyReceipts: [Receipt] {
        filteredReceipts.filter(\.taxReadiness.isReadyForTaxExport)
    }

    private var taxHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("稅務匯出")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("只匯出已確認、資料齊全的業務同可報銷支出。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ReceiptReadinessSummary(items: [
                .init(value: "\(summary.readyCount)", title: "可匯出", systemImage: "checkmark.seal.fill", tint: .receiptAccentGreen),
                .init(value: "\(summary.needsReviewCount)", title: "待處理", systemImage: "exclamationmark.triangle.fill", tint: .receiptAccentOrange),
                .init(value: Currency.amountString(summary.deductibleTotalHKD, currencyCode: Currency.hkd.rawValue), title: "業務 HKD", systemImage: "building.2.fill", tint: .receiptAccentBlue),
                .init(value: Currency.amountString(summary.reimbursableTotalHKD, currencyCode: Currency.hkd.rawValue), title: "報銷", systemImage: "arrowshape.turn.up.left.fill", tint: .receiptAccentGreen)
            ])
        }
        .padding(20)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.receiptOutline.opacity(0.18), lineWidth: 1)
        )
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("範圍")
                .font(.headline)

            Picker("範圍", selection: $selectedRange) {
                ForEach(TaxReportRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedRange == .currentTaxYear ? AppPreferences.localizedTaxYearDescription() : "PocketPal 入面所有稅務相關支出。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                applyTaxCategorySuggestions()
            } label: {
                actionRow(
                    title: "套用稅務建議",
                    subtitle: "用收據分類補上空白稅務分類。",
                    systemImage: "wand.and.stars"
                )
            }
            .buttonStyle(.plain)
            .disabled(filteredReceipts.allSatisfy { $0.taxCategory != nil })

            Divider()

            if let first = needsReviewReceipts.first {
                Button {
                    reviewRoute = ReceiptReviewRoute(receipt: first, queue: needsReviewReceipts)
                } label: {
                    actionRow(title: "逐張核對", subtitle: "核對原始收據，確認後直接處理下一張。",
                              systemImage: "checkmark.seal")
                }
                .buttonStyle(.plain)
            }

        }
        .padding(18)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.receiptAccentGreen)
                .frame(width: 34, height: 34)
                .background(Color.receiptAccentGreen.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func emptyCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var bottomSpacer: some View {
        Section {
            Color.clear
                .frame(height: 76)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    private func applyTaxCategorySuggestions() {
        for receipt in filteredReceipts where receipt.taxCategory == nil {
            receipt.reviewStatus = .inbox
            receipt.reviewedAt = nil
            receipt.taxCategory = receipt.taxReadiness.suggestedTaxCategory
            receipt.touch()
            receipt.rebuildSearchText()
        }

        saveChanges()
    }

    private func prepareTaxExport() {
        exportDocument = TaxReportExportDocument(data: TaxExportService.makeConfirmedTaxCSVData(receipts: filteredReceipts))
        isShowingExporter = true
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var exportDateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}

private struct TaxReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: receipt.taxReadiness.isReadyForTaxExport ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(receipt.taxReadiness.isReadyForTaxExport ? .receiptAccentGreen : .receiptAccentOrange)
                    .frame(width: 34, height: 34)
                    .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.displayMerchantName)
                        .font(.headline)
                        .lineLimit(2)

                    Text(receipt.transactionDate ?? receipt.importedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let totalAmount = receipt.totalAmount {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Currency.amountString(totalAmount, currencyCode: receipt.currencyCode))
                            .font(.headline.weight(.semibold))
                        Text(receipt.expenseType.localizedDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                ReceiptStatusPill(
                    title: receipt.taxReadiness.localizedReadinessLabel,
                    tint: receipt.taxReadiness.isReadyForTaxExport ? .receiptAccentGreen : .receiptAccentOrange,
                    systemImage: receipt.taxReadiness.isReadyForTaxExport ? "checkmark" : "checklist"
                )

                if let taxCategory = receipt.taxCategory {
                    ReceiptStatusPill(title: taxCategory.localizedDisplayName, tint: .receiptAccentBlue, systemImage: taxCategory.systemImage)
                }
            }

            if let firstIssue = receipt.taxReadiness.issues.first {
                Label(firstIssue.localizedTitle, systemImage: firstIssue.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct TaxReportExportDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    TaxReportView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
