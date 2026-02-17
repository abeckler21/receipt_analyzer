import SwiftUI
import VisionKit

/// Native iOS document scanner UI (cropping + perspective correction).
struct DocumentScannerView: UIViewControllerRepresentable {
    typealias Callback = (Result<[UIImage], Error>) -> Void
    let onComplete: Callback

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: Callback

        init(onComplete: @escaping Callback) { self.onComplete = onComplete }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onComplete(.failure(NSError(domain: "scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])))
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onComplete(.failure(error))
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            onComplete(.success(images))
        }
    }
}
