import SwiftUI
import UIKit

/// Camera proof for workouts / meals / weigh-ins. The UIImage is classified
/// on-device and then dropped — never written to Photos or disk.
struct CheckInProofSheet: View {
    let event: ScheduledEvent
    var onVerified: () -> Void
    var onOverride: () -> Void
    var onCancel: () -> Void

    @State private var showCamera = false
    @State private var status: String = CheckInVerifier.expectedProof(for: .workout)
    @State private var busy = false
    @State private var canOverride = false
    @Environment(\.accent) private var accent

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(event.title)
                    .font(Theme.hero)
                    .foregroundStyle(Theme.ink)
                Text(CheckInVerifier.expectedProof(for: event.kind))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(canOverride ? Theme.signal : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Photos are checked on this device and discarded immediately. Nothing is saved.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)

                Spacer()

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        // Simulator / no camera — treat as override-eligible.
                        status = "No camera on this device. Use override to continue."
                        canOverride = true
                    }
                } label: {
                    Text(busy ? "Checking…" : "Take proof photo")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                if canOverride {
                    Button(action: onOverride) {
                        Text("Override — tech issue, count it anyway")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(Theme.signal)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.signal.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button("Cancel", action: onCancel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.gutter)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Verify")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { image in
                    Task { await handleCapture(image) }
                }
            }
            .onAppear {
                status = CheckInVerifier.expectedProof(for: event.kind)
            }
        }
    }

    private func handleCapture(_ image: UIImage) async {
        busy = true
        defer {
            // Drop our only reference; UIImagePicker already dismissed.
            busy = false
        }
        let result = await CheckInVerifier.verify(image: image, for: event.kind)
        // Explicitly ignore the image after classification.
        _ = image.size

        switch result {
        case .verified(let reason):
            status = reason
            Haptics.confirm()
            onVerified()
        case .unclear(let reason), .failed(let reason):
            status = reason
            canOverride = true
            Haptics.miss()
        }
    }
}
