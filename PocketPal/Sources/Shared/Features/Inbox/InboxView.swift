import SwiftData
import SwiftUI

#if os(iOS)
import PhotosUI
#endif

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.serviceContainer) private var services
    @Query(
        filter: #Predicate<Receipt> { receipt in
            receipt.reviewStatusRawValue != "reviewed"
        },
        sort: [SortDescriptor(\Receipt.importedAt, order: .reverse)]
    )
    private var receipts: [Receipt]

    @State private var isShowingFileImporter = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoSelectionTrigger = UUID()
    @State private var isShowingScanner = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Color.receiptGroupedBackground
                    .ignoresSafeArea()

                List {
                    Section {
                        inboxHero
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    if receipts.isEmpty {
                        Section {
                            emptyStateCard
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        Section {
                            ForEach(receipts) { receipt in
                                NavigationLink {
                                    ReceiptDetailView(receipt: receipt)
                                } label: {
                                    ReceiptRowView(receipt: receipt)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.receiptGroupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.receiptGroupedBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .overlay {
                if isImporting {
                    ProgressView("Saving Receipt...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .alert("Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingScanner) {
            DocumentScannerView { result in
                switch result {
                case .success(let document):
                    Task {
                        await importDocument(.inMemory(document), source: .scanner)
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .ignoresSafeArea()
        }
        .task(id: photoSelectionTrigger) {
            guard let selectedPhoto else { return }
            await importSelectedPhoto(selectedPhoto)
            self.selectedPhoto = nil
        }
        #endif
        #if os(macOS)
        .dropDestination(for: URL.self) { items, _ in
            Task {
                for item in items {
                    await importDocument(.file(item), source: .dragDrop)
                }
            }
            return true
        }
        #endif
    }

    private var processingCount: Int {
        receipts.filter { $0.processingState.isActive }.count
    }

    private var readyCount: Int {
        receipts.filter { $0.processingState == .ready && $0.reviewStatus != .reviewed }.count
    }

    #if os(iOS)
    private var photoSelectionBinding: Binding<PhotosPickerItem?> {
        Binding(
            get: { selectedPhoto },
            set: { newValue in
                selectedPhoto = newValue
                if newValue != nil {
                    photoSelectionTrigger = UUID()
                }
            }
        )
    }
    #endif

    private var inboxHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Capture receipts without losing the original file.")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every import is copied into app storage, queued for OCR, and kept ready for later verification or export.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                summaryChip(title: "\(receipts.count)", subtitle: "Inbox")
                summaryChip(title: "\(readyCount)", subtitle: "Ready")
                summaryChip(title: "\(processingCount)", subtitle: "Processing")
            }

            importActions
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func summaryChip(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing waiting for review")
                .font(.headline)
            Text("Import a photo, a scanned document, or a PDF receipt. OCR will run in the background for image receipts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.receiptCardBackground)
        )
    }

    private var importActions: some View {
        LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 12) {
            actionButton(
                title: "Files",
                subtitle: "PDF, JPG, PNG, HEIC",
                systemImage: "folder"
            ) {
                isShowingFileImporter = true
            }

            #if os(iOS)
            PhotosPicker(selection: photoSelectionBinding, matching: .images, preferredItemEncoding: .current) {
                actionLabel(
                    title: "Photos",
                    subtitle: "Import from library",
                    systemImage: "photo.on.rectangle"
                )
            }
            .buttonStyle(.plain)

            actionButton(
                title: "Scan",
                subtitle: "Use the camera",
                systemImage: "doc.viewfinder"
            ) {
                isShowingScanner = true
            }
            #endif
        }
        .disabled(isImporting)
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 10, alignment: .top)]
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]
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
                .foregroundStyle(.orange)

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
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    await importDocument(.file(url), source: .files)
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importDocument(_ input: ReceiptImportInput, source: ReceiptImportSource) async {
        isImporting = true
        defer { isImporting = false }

        do {
            _ = try await services.importReceiptUseCase.execute(
                input: input,
                source: source,
                modelContext: modelContext
            )
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    #if os(iOS)
    private func importSelectedPhoto(_ item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let contentType = item.supportedContentTypes.first(where: {
                $0.conforms(to: .image) && $0 != .image
            }) ?? item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
            let filename = "photo-\(UUID().uuidString).\(contentType.preferredFilenameExtension ?? "jpg")"
            let document = ImportedReceiptDocument(data: data, suggestedFilename: filename, contentType: contentType)

            _ = try await services.importReceiptUseCase.execute(
                input: .inMemory(document),
                source: .photos,
                modelContext: modelContext
            )
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
    #endif
}

#Preview {
    InboxView()
        .modelContainer(PreviewSampleData.makeContainer())
        .environment(\.serviceContainer, ServiceContainer())
}
