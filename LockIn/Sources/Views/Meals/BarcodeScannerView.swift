import SwiftUI
import AVFoundation
import AudioToolbox

/// Live barcode scanner for packaged food.
///
/// This is the most accurate lookup in the app and the cheapest: a barcode
/// names one exact manufactured product, so Open Food Facts can return the
/// manufacturer's own numbers with no name matching, no estimate, and no API
/// key. Photo recognition guesses what a food *is*; a barcode simply knows.
///
/// Nothing is recorded. Frames are inspected for barcode metadata by the
/// system and discarded — no capture output, no file, no photo library.
struct BarcodeScannerView: View {
    /// Called once, with the first code found, then the scanner stops.
    let onScan: (String) -> Void

    /// Whether tapping "Scan a barcode" can lead anywhere, so the button isn't
    /// offered on hardware that can't honour it.
    static var isAvailable: Bool {
        if CameraCaptureView.isAvailable { return true }
        #if DEBUG
        // Without this the single most accurate lookup in the app is the one
        // path that can never be exercised on a simulator — including during
        // the guided demo. Practice codes stand in for the camera there.
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        if CameraCaptureView.isAvailable {
            BarcodeCameraView(onScan: onScan).ignoresSafeArea()
        } else {
            #if DEBUG
            PracticeBarcodeView(onScan: onScan)
            #else
            NoCameraView()
            #endif
        }
    }
}

private struct BarcodeCameraView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        let controller = BarcodeScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerController, context: Context) {}
}

#if !DEBUG
/// Shown only on a release build with no usable camera, which in practice
/// means a device that has one but is blocked from using it.
private struct NoCameraView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "camera.fill").font(.system(size: 34))
                    .foregroundStyle(Theme.inkMuted)
                Text("No camera available")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Scan the nutrition label from a saved photo instead, or type the numbers in.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                Button("Close") { dismiss() }.padding(.top, 8)
            }
            .padding(32)
        }
    }
}
#endif

#if DEBUG
/// Stand-in for the camera on the simulator: the practice codes, tappable.
///
/// These aren't canned responses — each one is a real EAN-13 that goes to the
/// live Open Food Facts API, so what comes back is the same thing a scan of
/// the physical box would return. `LockIn/Tools/make_practice_labels.py`
/// renders the matching scannable sheet for testing on real hardware.
private struct PracticeBarcodeView: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No camera on the simulator. Pick a code to look up for real.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(DemoMode.practiceBarcodes) { practice in
                            Button {
                                Haptics.tap()
                                onScan(practice.code)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(practice.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(practice.code)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.gutter)
                }
            }
            .navigationTitle("Practice barcodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }
}
#endif

final class BarcodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    /// Guards against the delegate firing repeatedly for the same barcode while
    /// the session winds down.
    private var hasScanned = false

    /// The symbologies actually printed on food packaging. EAN-13 and UPC-A
    /// cover essentially all groceries; the rest are here for the occasional
    /// store-printed label.
    private static let symbologies: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code128, .code39, .itf14
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        addChrome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !session.isRunning else { return }
        // startRunning blocks; the docs are explicit that it belongs off the
        // main thread or the presentation animation stutters.
        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // Must be set *after* the output is attached — the available types are
        // empty until then, and assigning an unsupported type traps.
        output.metadataObjectTypes = Self.symbologies.filter {
            output.availableMetadataObjectTypes.contains($0)
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    /// A framing rectangle and a way out. Without the cutout it's just a black
    /// screen and people don't know how close to hold the box.
    private func addChrome() {
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 12
        view.addSubview(box)

        let hint = UILabel()
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.text = "Point at the barcode"
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 15, weight: .medium)
        hint.textAlignment = .center
        view.addSubview(hint)

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle("Cancel", for: .normal)
        cancel.tintColor = .white
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)

        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            box.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
            box.heightAnchor.constraint(equalTo: box.widthAnchor, multiplier: 0.6),
            hint.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 20),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20)
        ])
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }

        hasScanned = true
        AudioServicesPlaySystemSound(1057)
        session.stopRunning()
        onScan?(value)
        dismiss(animated: true)
    }
}
