import SwiftUI

struct ReceiptThumbnailView: View {
    let asset: ReceiptAsset?

    @Environment(\.serviceContainer) private var services
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.receiptSecondaryFill)
                    Image(systemName: asset?.kind == .pdf ? "doc.richtext" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: asset?.id) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let asset else {
            image = nil
            return
        }

        let candidatePath = asset.thumbnailRelativePath ?? (asset.kind == .image ? asset.storageRelativePath : nil)
        guard let candidatePath else {
            image = nil
            return
        }

        image = loadPlatformImage(from: services.fileStorageService.fileURL(forRelativePath: candidatePath))
    }
}
