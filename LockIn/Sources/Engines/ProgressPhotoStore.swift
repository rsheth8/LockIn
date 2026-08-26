import Foundation
import UIKit

/// Stores daily progress photos as JPEGs in the app's sandboxed Documents
/// directory — never the system Photos library and never synced anywhere —
/// so they stay private to this device by default. Metadata (date, linked
/// weight) is tracked separately via PersistenceStore.
/// Main-actor confined: it writes photo metadata through `PersistenceStore`,
/// which owns a `ModelContext` and must stay on one actor.
@MainActor
final class ProgressPhotoStore {
    static let shared = ProgressPhotoStore()

    private let directory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Exclude from iCloud/device backup — these are sensitive personal photos,
        // and backup is an extra place they could leak from if an account is compromised.
        var excluded = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        return dir
    }()

    @discardableResult
    func save(_ image: UIImage, weightLbsAtCapture: Double?) -> ProgressPhoto? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let photo = ProgressPhoto(fileName: fileName, weightLbsAtCapture: weightLbsAtCapture)
        var all = PersistenceStore.shared.loadProgressPhotos()
        all.append(photo)
        PersistenceStore.shared.saveProgressPhotos(all)
        return photo
    }

    func image(for photo: ProgressPhoto) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(photo.fileName).path)
    }

    func delete(_ photo: ProgressPhoto) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(photo.fileName))
        var all = PersistenceStore.shared.loadProgressPhotos()
        all.removeAll { $0.id == photo.id }
        PersistenceStore.shared.saveProgressPhotos(all)
    }

    func allPhotosSortedByDate() -> [ProgressPhoto] {
        PersistenceStore.shared.loadProgressPhotos().sorted { $0.date < $1.date }
    }
}
