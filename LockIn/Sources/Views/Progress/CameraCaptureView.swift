import SwiftUI
import UIKit
import AVFoundation

/// Thin UIKit bridge for camera capture — SwiftUI has no native camera control,
/// so this wraps UIImagePickerController pinned to .camera (never the photo
/// library, so there's no accidental picker into unrelated personal photos).
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Whether offering "Take a photo" is honest.
    ///
    /// Not `UIImagePickerController.isSourceTypeAvailable(.camera)`, which the
    /// callers used to ask and which answers *true* on a simulator that has no
    /// capture device at all — so every "hidden where there's no camera" guard
    /// in the app was quietly failing open onto a dead black sheet. Asking for
    /// the device itself is the question that has a real answer.
    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
