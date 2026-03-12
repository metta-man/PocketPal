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
    @State private var isShowingScanner = false
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No Receipts Yet",
                        systemImage: "tray",
                        description: Text("Import a receipt photo or PDF to start OCR and review.")
                    )
                } else {
                    List(receipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            ReceiptRowView(receipt: receipt)
                        }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    importMenu
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing Receipt...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        .task(id: selectedPhoto?.itemIdentifier) {
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

    @ViewBuilder
    private var importMenu: some View {
        Menu {
            Button("Import from Files") {
                isShowingFileImporter = true
            }

            #if os(iOS)
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
            }

            Button("Scan Receipt") {
                isShowingScanner = true
            }
            #endif
        } label: {
            Label("Import", systemImage: "plus")
        }
        .disabled(isImporting)
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

            let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
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
