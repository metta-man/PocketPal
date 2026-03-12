import PDFKit
import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: (Result<ImportedReceiptDocument, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let completion: (Result<ImportedReceiptDocument, Error>) -> Void

        init(completion: @escaping (Result<ImportedReceiptDocument, Error>) -> Void) {
            self.completion = completion
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            completion(.failure(error))
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            defer { controller.dismiss(animated: true) }

            guard scan.pageCount > 0 else {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }

            let images = (0..<scan.pageCount).map(scan.imageOfPage)
            if images.count == 1, let jpegData = images[0].jpegData(compressionQuality: 0.9) {
                let document = ImportedReceiptDocument(
                    data: jpegData,
                    suggestedFilename: "scan-\(UUID().uuidString).jpg",
                    contentType: .jpeg
                )
                completion(.success(document))
                return
            }

            let pdfDocument = PDFDocument()
            for (index, image) in images.enumerated() {
                guard let page = PDFPage(image: image) else { continue }
                pdfDocument.insert(page, at: index)
            }

            guard let pdfData = pdfDocument.dataRepresentation() else {
                completion(.failure(CocoaError(.coderInvalidValue)))
                return
            }

            let document = ImportedReceiptDocument(
                data: pdfData,
                suggestedFilename: "scan-\(UUID().uuidString).pdf",
                contentType: .pdf
            )
            completion(.success(document))
        }
    }
}
