import SwiftData
import SwiftUI

#if os(iOS)
import PhotosUI
#endif

enum ReceiptListScope: String, CaseIterable, Identifiable {
    case pending = "待確認"
    case all = "全部"
    case reviewed = "已確認"
    case neverExtracted = "未抽取"
    case incomplete = "資料不完整"
    case undated = "未填日期"

    func includes(_ receipt: Receipt) -> Bool {
        switch self {
        case .all: return true
        case .pending: return receipt.reviewStatus != .reviewed
        case .reviewed: return receipt.reviewStatus == .reviewed
        case .neverExtracted: return GeminiReceiptSelection.neverExtracted.includes(receipt)
        case .incomplete: return !receipt.taxReadiness.fieldIssues.isEmpty
        case .undated: return receipt.transactionDate == nil
        }
    }

    var id: String { rawValue }
}

enum GeminiReceiptSelection {
    case neverExtracted, unconfirmed, all

    var title: String {
        switch self {
        case .neverExtracted: return "只處理未用過 Gemini"
        case .unconfirmed: return "只處理未確認"
        case .all: return "全部重新抽取"
        }
    }

    func includes(_ receipt: Receipt) -> Bool {
        guard receipt.asset != nil else { return false }
        switch self {
        case .neverExtracted: return receipt.extractionProvider != .gemini
        case .unconfirmed: return receipt.reviewStatus != .reviewed
        case .all: return true
        }
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var services
    @Query(sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)])
    private var allReceipts: [Receipt]
    var selectedLedger: ReceiptLedger = .personal
    @Environment(\.receiptWorkspace) private var workspace
    @State private var lockID = UUID()
    @State private var showTools = false
    private var receipts: [Receipt] { allReceipts.filter { selectedLedger.includes($0) } }

    @State private var isShowingFileImporter = false
    @State private var isShowingManualEntry = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var geminiBatchMessage: String?
    @State private var isConfirmingGeminiBatch = false
    @State private var isRunningGeminiBatch = false
    @State private var hasSavedGeminiAPIKey = false
    @State private var geminiSelection = GeminiReceiptSelection.neverExtracted
    @State private var confirmedBatch: [Receipt] = []
    @State private var batchCompleted = 0
    @State private var batchTotal = 0
    @State private var batchStatus: String?
    @State private var stopBatchRequested = false
    private var searchText: String {
        get { workspace.searches[selectedLedger] ?? "" }
        nonmutating set { workspace.searches[selectedLedger] = newValue }
    }
    private var searchBinding: Binding<String> { Binding(get: { searchText }, set: { searchText = $0 }) }
    @State private var reviewRoute: ReceiptReviewRoute?
    private var scope: ReceiptListScope {
        get { workspace.filters[selectedLedger] ?? .pending }
        nonmutating set { workspace.filters[selectedLedger] = newValue }
    }
    private var scopeBinding: Binding<ReceiptListScope> { Binding(get: { scope }, set: { scope = $0 }) }
    private var blocksSwitch: Bool {
        let common = isImporting || isRunningGeminiBatch || isShowingManualEntry || reviewRoute != nil || isShowingFileImporter || isConfirmingGeminiBatch || isSelectingConfirmations
        #if os(iOS)
        return common || isShowingScanner || !selectedPhotos.isEmpty
        #else
        return common
        #endif
    }
    @State private var isSelectingConfirmations = false
    @State private var selectedConfirmationIDs: Set<UUID> = []
    @State private var confirmationSummary: String?
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoSelectionTrigger = UUID()
    @State private var isShowingScanner = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                selectedLedger.background
                    .ignoresSafeArea()

                List {
                    Section {
                        homeHeader
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    if !receipts.isEmpty {
                        Section {
                            filterCard
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }

                        Section(sectionTitle) {
                            if filteredReceipts.isEmpty {
                                emptyStateCard
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(filteredReceipts) { receipt in
                                    Button {
                                        reviewRoute = ReceiptReviewRoute(receipt: receipt, queue: filteredReceipts)
                                    } label: {
                                        ReceiptRowView(receipt: receipt)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }

                        bottomSpacer
                    }
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
            .navigationTitle(selectedLedger == .personal ? "個人 · 收支明細" : "業務 · 收據")
            .searchable(text: searchBinding, prompt: "搜尋商戶、分類或 OCR 文字")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(selectedLedger.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(selectedLedger.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        #if os(iOS)
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("掃描收據", systemImage: "doc.viewfinder")
                        }
                        #endif

                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label("匯入檔案", systemImage: "folder")
                        }

                        Button {
                            isShowingManualEntry = true
                        } label: {
                            Label("手動記錄", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增收據")
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("儲存收據...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .navigationDestination(item: $reviewRoute) { route in
                ReceiptDetailView(receipt: route.receipt,
                                  reviewQueue: route.isReviewSession ? route.queue : nil)
            }
            .navigationDestination(isPresented: $isShowingManualEntry) {
                ManualEntryView(initialExpenseType: selectedLedger.expenseType)
            }
            .onAppear(perform: loadGeminiKeyState)
        }
        .onAppear {
            showTools = selectedLedger == .business
            if workspace.captureRequested {
                workspace.captureRequested = false
                #if os(iOS)
                isShowingScanner = true
                #else
                isShowingFileImporter = true
                #endif
            }
        }
        .onChange(of: blocksSwitch) { _, locked in workspace.setLocked(locked, owner: lockID) }
        .onDisappear { if !blocksSwitch { workspace.setLocked(false, owner: lockID) } }
        .sheet(isPresented: $isSelectingConfirmations) { batchConfirmationSheet }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .alert("匯入失敗", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "未知錯誤")
        }
        .sheet(isPresented: $isConfirmingGeminiBatch) {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(geminiSelection.title)：\(confirmedBatch.count) 張").font(.title2.bold())
                Text("原始收據及辨識文字會傳送到 Google Gemini，更新抽取欄位。已確認收據會改回待核對；附件、備註及支出用途會保留。")
                Button("開始處理 \(confirmedBatch.count) 張") {
                    isConfirmingGeminiBatch = false
                    Task { await runGeminiBatch() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("receipts.gemini.start")
                Button("取消", role: .cancel) { isConfirmingGeminiBatch = false }
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .presentationDetents([.medium, .large])
        }
        .alert("Gemini 處理結果", isPresented: Binding(
            get: { geminiBatchMessage != nil },
            set: { if !$0 { geminiBatchMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(geminiBatchMessage ?? "")
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingScanner) {
            DocumentScannerView { result in
                switch result {
                case .success(let document):
                    Task {
                        await importDocuments([.inMemory(document)], source: .scanner)
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .ignoresSafeArea()
        }
        .task(id: photoSelectionTrigger) {
            guard !selectedPhotos.isEmpty else { return }
            await importSelectedPhotos(selectedPhotos)
            self.selectedPhotos = []
        }
        #endif
        #if os(macOS)
        .dropDestination(for: URL.self) { items, _ in
            Task {
                await importDocuments(items.map(ReceiptImportInput.file), source: .dragDrop)
            }
            return true
        }
        #endif
    }

    private var pendingReceipts: [Receipt] {
        receipts.filter { $0.reviewStatus != .reviewed }
    }

    private var readyCount: Int {
        pendingReceipts.filter { $0.taxReadiness.fieldIssues.isEmpty }.count
    }

    private var missingCount: Int {
        pendingReceipts.filter { !$0.taxReadiness.fieldIssues.isEmpty }.count
    }

    private var processingCount: Int {
        pendingReceipts.filter { $0.processingState.isActive }.count
    }

    private func candidates(for selection: GeminiReceiptSelection) -> [Receipt] {
        receipts.filter { selection.includes($0) && services.importReceiptUseCase.canManuallyExtract($0) }
    }

    private var reviewCoachReceipt: Receipt? {
        if let receipt = pendingReceipts.first(where: {
            !$0.taxReadiness.fieldIssues.isEmpty
        }) {
            return receipt
        }

        if let receipt = pendingReceipts.first(where: { $0.processingState == .ready }) {
            return receipt
        }

        return pendingReceipts.first
    }

    private var filteredReceipts: [Receipt] {
        let scopedReceipts = receipts.filter { scope.includes($0) }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else {
            return scopedReceipts
        }

        return scopedReceipts.filter { receipt in
            receipt.displayMerchantName.localizedLowercase.contains(query)
                || receipt.searchText.localizedLowercase.contains(query)
                || (receipt.category ?? "").localizedLowercase.contains(query)
        }
    }

    private var sectionTitle: String { scope.rawValue }

    #if os(iOS)
    private var photoSelectionBinding: Binding<[PhotosPickerItem]> {
        Binding(
            get: { selectedPhotos },
            set: { newValue in
                selectedPhotos = newValue
                if !newValue.isEmpty {
                    photoSelectionTrigger = UUID()
                }
            }
        )
    }
    #endif

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedLedger == .personal ? "生活中每一筆收支，都留喺呢度。" : "加入收據，再核對抽取結果。")
                .font(.subheadline).foregroundStyle(.secondary)
            DisclosureGroup("收據處理工具", isExpanded: $showTools) {
            if !pendingReceipts.isEmpty {
                Button("批量確認收據…") {
                    selectedConfirmationIDs = []
                    confirmationSummary = nil
                    isSelectingConfirmations = true
                }
                .buttonStyle(.bordered)
                .disabled(isRunningGeminiBatch)
                .accessibilityIdentifier("receipts.review.batch")
            }
            geminiExistingReceiptsCard

            }

            #if os(iOS)
            PrimaryCaptureButton(
                title: "掃描收據",
                subtitle: "影低收據，自動填入商戶、日期和金額。",
                systemImage: "doc.viewfinder",
                isDisabled: isImporting
            ) {
                isShowingScanner = true
            }
            #else
            PrimaryCaptureButton(
                title: "匯入收據",
                subtitle: "加入 PDF、JPG、PNG 或 HEIC 檔案。",
                systemImage: "folder",
                isDisabled: isImporting
            ) {
                isShowingFileImporter = true
            }
            #endif

            secondaryImportActions
        }
    }

    private var ledgerTotals: some View {
        let confirmed = receipts.filter { $0.reviewStatus == .reviewed && $0.totalAmount != nil }
        let codes = Set(confirmed.map { $0.currencyCode ?? "未指定幣種" }).sorted()
        return VStack(alignment: .leading, spacing: 6) {
            Text("已確認收支 · 全部日期").font(.caption).foregroundStyle(.secondary)
            if codes.isEmpty { Text("未有已確認金額").font(.subheadline) }
            ForEach(codes, id: \.self) { code in
                let entries = confirmed.filter { ($0.currencyCode ?? "未指定幣種") == code }
                let expenses = entries.filter { $0.transactionKind == .expense }.reduce(0.0) { $0 + ($1.totalAmount ?? 0) }
                let income = entries.filter { $0.transactionKind == .income }.reduce(0.0) { $0 + ($1.totalAmount ?? 0) }
                Text("\(code) · 支出 \(expenses.formatted()) · 收入 \(income.formatted())")
                    .font(.subheadline)
            }
        }
    }

    private var geminiExistingReceiptsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gemini 收據處理", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.receiptAccentBlue)

            Text(hasSavedGeminiAPIKey
                 ? "選擇今次要處理的範圍。只處理未用過 Gemini，會保留已有成功結果。"
                 : "先到設定儲存 Gemini API key。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                prepareGeminiBatch(selection: .neverExtracted)
            } label: {
                Text("只處理未用過 Gemini（\(candidates(for: .neverExtracted).count)）")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.receiptAccentBlue)
            .disabled(isRunningGeminiBatch)
            .accessibilityIdentifier("receipts.gemini.processExisting")

            Button("只處理未確認（\(candidates(for: .unconfirmed).count)）") {
                prepareGeminiBatch(selection: .unconfirmed)
            }
            .buttonStyle(.bordered)
            .disabled(isRunningGeminiBatch)
            .accessibilityIdentifier("receipts.gemini.unconfirmed")
            Text("未確認範圍包括已有 Gemini 結果、但尚未確認的收據。")
                .font(.caption).foregroundStyle(.secondary)

            Menu("更多選項") {
                Button("全部有附件收據重新抽取…") {
                    prepareGeminiBatch(selection: .all)
                }
                .accessibilityIdentifier("receipts.gemini.reprocessAll")
            }
            .disabled(isRunningGeminiBatch)

            if isRunningGeminiBatch {
                ProgressView(value: Double(batchCompleted), total: Double(max(batchTotal, 1)))
                Text("已處理 \(batchCompleted) / \(batchTotal) 張").font(.subheadline.bold())
                Button(stopBatchRequested ? "完成目前一張後停止" : "停止後續處理") {
                    stopBatchRequested = true
                }
                .buttonStyle(.bordered)
                .disabled(stopBatchRequested)
            }
            if let batchStatus {
                Text(batchStatus)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("receipts.gemini.status")
            }
        }
        .padding(18)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func loadGeminiKeyState() {
        do {
            let key = try services.keychainService.retrieveSecureString(key: AppPreferences.geminiAPIKeyKey)
            hasSavedGeminiAPIKey = key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } catch {
            hasSavedGeminiAPIKey = false
        }
    }

    private func prepareGeminiBatch(selection: GeminiReceiptSelection) {
        loadGeminiKeyState()
        guard hasSavedGeminiAPIKey else {
            batchStatus = "未能開始：請先到設定儲存 Gemini API key。"
            return
        }
        geminiSelection = selection
        confirmedBatch = candidates(for: selection)
        guard !confirmedBatch.isEmpty else {
            batchStatus = "「\(selection.title)」暫時冇符合條件的收據，或相關收據正在處理中。"
            return
        }
        batchStatus = "已選擇 \(confirmedBatch.count) 張，請確認開始。"
        isConfirmingGeminiBatch = true
    }

    @MainActor
    private func runGeminiBatch() async {
        guard !isRunningGeminiBatch else { return }
        let candidates = confirmedBatch
        guard !candidates.isEmpty else { return }
        isRunningGeminiBatch = true
        stopBatchRequested = false
        batchCompleted = 0
        batchTotal = candidates.count
        defer { isRunningGeminiBatch = false }
        var succeeded = 0
        var failed = 0
        var lastError: String?
        for receipt in candidates {
            if stopBatchRequested || Task.isCancelled { break }
            guard !receipt.isDeleted, receipt.modelContext != nil, geminiSelection.includes(receipt) else { batchCompleted += 1; continue }
            batchStatus = "正在處理第 \(batchCompleted + 1) 張：\(receipt.displayMerchantName)。等候 Gemini 回覆…"
            var attempt = 0
            var completed = false
            while !stopBatchRequested && !Task.isCancelled {
                do {
                    try await services.importReceiptUseCase.enhanceWithCloud(
                        for: receipt, modelContext: modelContext, uploadConsentGranted: true,
                        allowReplacingConfirmedReceipt: geminiSelection != .unconfirmed && receipt.reviewStatus == .reviewed
                    )
                    succeeded += 1
                    completed = true
                    break
                } catch let quota as GeminiQuotaError {
                    if let delay = quota.retryDelay(attempt: attempt) {
                        attempt += 1
                        for seconds in stride(from: Int(ceil(delay)), through: 1, by: -1) {
                            batchStatus = "Gemini 限流，\(seconds) 秒後重試目前收據（\(attempt)/2）。已完成 \(succeeded) 張。"
                            if stopBatchRequested || Task.isCancelled { break }
                            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                            catch { stopBatchRequested = true; break }
                        }
                    } else {
                        failed += 1
                        completed = true
                        lastError = quota.localizedDescription
                        stopBatchRequested = true
                        break
                    }
                } catch {
                    failed += 1
                    completed = true
                    lastError = error.localizedDescription
                    break
                }
            }
            if !completed { break }
            batchCompleted += 1
        }
        let remaining = batchTotal - batchCompleted
        batchStatus = "處理結束：成功 \(succeeded) 張，失敗 \(failed) 張，未處理 \(remaining) 張。" +
            (lastError.map { " 最後錯誤：" + $0 } ?? " 請到待確認核對結果。")
        geminiBatchMessage = batchStatus
    }

    private var confirmableReceipts: [Receipt] {
        pendingReceipts.filter { $0.taxReadiness.fieldIssues.isEmpty }
    }

    private var batchConfirmationSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("請核對商戶與金額，再勾選要確認的收據。資料未齊的收據需先補齊。")
                    Button("全選可確認的 \(confirmableReceipts.count) 張") {
                        selectedConfirmationIDs = Set(confirmableReceipts.map(\.id))
                    }
                    .buttonStyle(.borderless)
                    Button("取消全選") { selectedConfirmationIDs = [] }
                        .buttonStyle(.borderless)
                }
                Section("待確認收據") {
                    ForEach(pendingReceipts) { receipt in
                        let issues = receipt.taxReadiness.fieldIssues
                        Toggle(isOn: Binding(
                            get: { selectedConfirmationIDs.contains(receipt.id) },
                            set: { selected in
                                if selected { selectedConfirmationIDs.insert(receipt.id) }
                                else { selectedConfirmationIDs.remove(receipt.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(receipt.displayMerchantName).font(.headline)
                                if let amount = receipt.totalAmount {
                                    Text("\(receipt.currencyCode ?? "") \(amount.formatted())")
                                }
                                if let category = receipt.category { Text(category).font(.caption) }
                                if !issues.isEmpty {
                                    Text(issues.map(\.title).joined(separator: "、"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!issues.isEmpty)
                    }
                }
                if let confirmationSummary { Text(confirmationSummary) }
            }
            .navigationTitle("批量確認")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { isSelectingConfirmations = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("確認已選 \(selectedConfirmationIDs.count) 張") { confirmSelectedReceipts() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedConfirmationIDs.isEmpty)
                    .padding()
            }
        }
    }

    private func confirmSelectedReceipts() {
        let selected = pendingReceipts.filter { selectedConfirmationIDs.contains($0.id) }
        var saved = 0
        var failed = 0
        for receipt in selected {
            do {
                try ReceiptReviewPersistence.save(receipt: receipt,
                    values: ReceiptReviewValues(receipt: receipt), confirmed: true) {
                    try modelContext.save()
                }
                selectedConfirmationIDs.remove(receipt.id)
                saved += 1
            } catch { failed += 1 }
        }
        confirmationSummary = "已確認 \(saved) 張。" + (failed > 0 ? "另有 \(failed) 張未能儲存或資料已改變，請重新核對。" : "")
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(emptyStateTitle)
                .font(.headline)
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private var bottomSpacer: some View {
        Section {
            Color.clear
                .frame(height: 76)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("收據範圍", selection: scopeBinding) {
                ForEach(ReceiptListScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 10) {
                Label("\(receipts.count) 張總數", systemImage: "archivebox")
                Spacer()
                Label("\(processingCount) 處理中", systemImage: "text.viewfinder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(16)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var secondaryImportActions: some View {
        LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 10) {
            actionButton(
                title: "手動輸入",
                subtitle: "自行填寫，不讀取圖片",
                systemImage: "plus.circle"
            ) {
                isShowingManualEntry = true
            }

            actionButton(
                title: "檔案",
                subtitle: "PDF, JPG, PNG, HEIC",
                systemImage: "folder"
            ) {
                isShowingFileImporter = true
            }

            #if os(iOS)
            PhotosPicker(
                selection: photoSelectionBinding,
                maxSelectionCount: nil,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                actionLabel(
                    title: "匯入相片",
                    subtitle: "可多選，每張獨立處理",
                    systemImage: "photo.on.rectangle"
                )
            }
            .buttonStyle(.plain)
            #endif
        }
        .disabled(isImporting)
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 10, alignment: .top)]
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title: title, subtitle: subtitle, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.receiptAccentBlue)
                .frame(width: 34, height: 34)
                .background(Color.receiptAccentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(14)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.receiptOutline.opacity(0.16), lineWidth: 1)
        )
    }

    private var emptyStateTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "找不到相關收據"
        }

        switch scope {
        case .neverExtracted, .incomplete, .undated:
            return "沒有符合條件的收據"
        case .pending:
            return "沒有待確認收據"
        case .all:
            return "未有收據"
        case .reviewed:
            return "未有已完成收據"
        }
    }

    private var emptyStateMessage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "試下搜尋商戶、分類或 OCR 文字。"
        }

        switch scope {
        case .neverExtracted, .incomplete, .undated:
            return "可以切換範圍查看其他收據。"
        case .pending:
            return "匯入第一張收據，PocketPal 會保留原始檔案並提示要補齊嘅資料。"
        case .all:
            return "用上方按鈕掃描、匯入檔案，或者先手動記錄一筆。"
        case .reviewed:
            return "確認完成後，收據會留喺呢度，方便日後搜尋。"
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importDocuments(urls.map(ReceiptImportInput.file), source: .files)
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importDocuments(_ inputs: [ReceiptImportInput], source: ReceiptImportSource) async {
        guard !inputs.isEmpty else { return }

        let importExpenseType = selectedLedger.expenseType
        isImporting = true
        defer { isImporting = false }

        var failures: [String] = []

        for input in inputs {
            do {
                _ = try await services.importReceiptUseCase.execute(
                    input: input,
                    source: source,
                    modelContext: modelContext,
                    expenseType: importExpenseType
                )
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        if let firstFailure = failures.first {
            if failures.count == 1 {
                importErrorMessage = firstFailure
            } else {
                importErrorMessage = "\(failures.count) 張收據未能匯入。第一個錯誤：\(firstFailure)"
            }
        }
    }

    #if os(iOS)
    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var documents: [ReceiptImportInput] = []
        var failures: [String] = []

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                let contentType = item.supportedContentTypes.first(where: {
                    $0.conforms(to: .image) && $0 != .image
                }) ?? item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
                let filename = "photo-\(UUID().uuidString).\(contentType.preferredFilenameExtension ?? "jpg")"
                let document = ImportedReceiptDocument(data: data, suggestedFilename: filename, contentType: contentType)
                documents.append(.inMemory(document))
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        await importDocuments(documents, source: .photos)

        if importErrorMessage == nil, let firstFailure = failures.first {
            if failures.count == 1 {
                importErrorMessage = firstFailure
            } else {
                importErrorMessage = "\(failures.count) 張相未能載入。第一個錯誤：\(firstFailure)"
            }
        }
    }
    #endif
}

#Preview {
    InboxView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}

private struct ReviewCoachCard: View {
    let receipt: Receipt

    private var firstIssue: ReceiptReadinessIssue? {
        receipt.taxReadiness.fieldIssues.first
    }

    private var ctaTitle: String {
        firstIssue == nil ? "完成呢張" : "處理呢張"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: firstIssue == nil ? "checkmark.seal.fill" : "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(firstIssue == nil ? .receiptAccentGreen : .receiptAccentBlue)
                    .frame(width: 36, height: 36)
                    .background(Color.receiptElevatedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("下一張要睇")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(receipt.displayMerchantName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(alignment: .center, spacing: 10) {
                issueLabel

                Spacer(minLength: 8)

                Label(ctaTitle, systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.receiptAccentBlue)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.receiptCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.receiptOutline.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("開啟收據詳情")
    }

    @ViewBuilder
    private var issueLabel: some View {
        if let firstIssue {
            Label(firstIssue.localizedTitle, systemImage: firstIssue.systemImage)
                .font(.caption)
                .foregroundStyle(.receiptAccentOrange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("資料已齊，可以確認資料", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.receiptAccentGreen)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension Receipt {
    var isTaxExportCandidate: Bool {
        transactionKind == .expense && expenseType.isTaxDeductible
    }
}
