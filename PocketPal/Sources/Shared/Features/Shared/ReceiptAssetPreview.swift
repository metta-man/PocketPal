import SwiftUI

struct ReceiptAssetPreview: View {
    let asset: ReceiptAsset?

    @Environment(\.serviceContainer) private var services
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let asset {
                switch asset.kind {
                case .image:
                    imagePreview(for: asset)
                case .pdf:
                    pdfPreview(for: asset)
                }
            } else {
                ContentUnavailableView("No Receipt Asset", systemImage: "doc")
            }
        }
        .frame(minHeight: 240)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func imagePreview(for asset: ReceiptAsset) -> some View {
        if let image {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: asset.id) {
                    image = loadPlatformImage(from: services.fileStorageService.fileURL(forRelativePath: asset.storageRelativePath))
                }
        }
    }

    private func pdfPreview(for asset: ReceiptAsset) -> some View {
        PDFPreviewView(url: services.fileStorageService.fileURL(forRelativePath: asset.storageRelativePath))
    }
}
