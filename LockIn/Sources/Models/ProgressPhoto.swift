import Foundation

/// Metadata for a daily progress photo. The image bytes live on disk in the
/// app sandbox (see ProgressPhotoStore) — this struct only tracks the pointer
/// and the context needed to make a later comparison meaningful.
struct ProgressPhoto: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let fileName: String
    let weightLbsAtCapture: Double?

    init(id: UUID = UUID(), date: Date = Date(), fileName: String, weightLbsAtCapture: Double?) {
        self.id = id
        self.date = date
        self.fileName = fileName
        self.weightLbsAtCapture = weightLbsAtCapture
    }
}
