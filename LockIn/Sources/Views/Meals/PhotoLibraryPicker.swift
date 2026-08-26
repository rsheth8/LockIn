import SwiftUI
import PhotosUI
import UIKit

/// Picks one existing photo from the library.
///
/// Uses `PHPickerViewController` rather than `UIImagePickerController`
/// deliberately: PHPicker runs out-of-process, so it needs **no photo-library
/// permission at all** and the app only ever receives the single image the
/// user chose. That matches how the rest of this app treats photos — and the
/// picked image is still only used to produce an embedding, never stored.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        // Ask for the decoded image rather than the original file — we only
        // need pixels, and this avoids pulling a full-size HEIC off disk.
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        let dismiss: DismissAction

        init(onPick: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                dismiss()
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let self else { return }
                // The provider calls back off the main thread.
                Task { @MainActor in
                    if let image = object as? UIImage {
                        self.onPick(image)
                    }
                    self.dismiss()
                }
            }
        }
    }
}
