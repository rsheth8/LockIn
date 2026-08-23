import SwiftUI
import UIKit
import Charts

/// The evidence tab: the promise grid (what you did), the weight trend (what it
/// produced), and the photo record (what it looks like). Grid first on purpose —
/// behaviour is the thing you control, weight is only the lagging indicator.
struct ProgressGalleryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accent) private var accent
    @Binding var launchCameraOnAppear: Bool
    @State private var photos: [ProgressPhoto] = []
    @State private var showingCamera = false
    @State private var showingCameraUnavailableAlert = false
    @State private var selectedPhoto: ProgressPhoto?

    private let store = ProgressPhotoStore.shared
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    ScreenHeader(title: "Record", subtitle: "What you actually did") {
                        Button(action: launchCamera) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.surface)
                                .frame(width: 42, height: 42)
                                .background(Theme.ink, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    promiseSection
                    weightSection
                    photoSection
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                // Clears the floating tab bar so the last row isn't trapped under it.
                .padding(.bottom, 96)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { image in
                store.save(image, weightLbsAtCapture: appState.profile.currentWeightLbs)
                Haptics.confirm()
                reload()
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, store: store) {
                store.delete(photo)
                selectedPhoto = nil
                reload()
            }
        }
        .alert("No Camera", isPresented: $showingCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device (likely the Simulator) has no camera. Try a real iPhone.")
        }
        .onAppear {
            reload()
            if launchCameraOnAppear {
                launchCameraOnAppear = false
                launchCamera()
            }
        }
    }

    // MARK: - Promise grid

    private var promiseSection: some View {
        PromiseGridSection(records: appState.dayRecords, accent: accent)
    }

    // MARK: - Weight trend

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Weight", trailing: weightDeltaSummary)

            if appState.profile.weightHistory.count < 2 {
                emptyNote("Two weigh-ins and this becomes a trend line. Right now it's a dot.")
            } else {
                Chart {
                    ForEach(appState.profile.weightHistory, id: \.date) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightLbs))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(accent.color)
                        AreaMark(x: .value("Date", entry.date), y: .value("Weight", entry.weightLbs))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.linearGradient(
                                colors: [accent.color.opacity(0.16), accent.color.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    RuleMark(y: .value("Goal", appState.profile.goalWeightLbs))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.signal)
                        .annotation(position: .top, alignment: .leading) {
                            Text("GOAL \(Int(appState.profile.goalWeightLbs))")
                                .font(Theme.mono(9, weight: .semibold))
                                .foregroundStyle(Theme.signal)
                        }
                }
                // Scale to the data, never from zero. A weight axis anchored at
                // 0 squashes a real 15 lb change into a flat line at the top of
                // the chart and hides the only thing the chart exists to show.
                .chartYScale(domain: weightDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel().font(Theme.mono(9)).foregroundStyle(Theme.inkMuted)
                        AxisGridLine().foregroundStyle(Theme.rule)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(Theme.mono(9)).foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(height: 170)
            }
        }
    }

    /// Y range covering the weigh-ins plus the goal line, with a little padding
    /// so the trend line never touches the frame edges.
    private var weightDomain: ClosedRange<Double> {
        let weights = appState.profile.weightHistory.map(\.weightLbs)
        guard let low = weights.min(), let high = weights.max() else {
            return (appState.profile.currentWeightLbs - 10)...(appState.profile.currentWeightLbs + 10)
        }
        let goal = appState.profile.goalWeightLbs
        let padding = max((high - low) * 0.18, 3)
        return (min(low, goal) - padding)...(max(high, goal) + padding)
    }

    /// Shows the delta once there's actually a delta to show — a lone weigh-in
    /// rendering as "−0 lb" reads like failure rather than "no data yet".
    private var weightDeltaSummary: String {
        guard let first = appState.profile.weightHistory.first,
              let last = appState.profile.weightHistory.last,
              first.weightLbs != last.weightLbs else {
            return "\(Int(appState.profile.currentWeightLbs)) lb"
        }
        let delta = last.weightLbs - first.weightLbs
        let sign = delta < 0 ? "−" : "+"
        return "\(sign)\(abs(Int(delta))) lb"
    }

    // MARK: - Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Photos", trailing: photos.isEmpty ? "—" : "\(photos.count)")

            if photos.count >= 2, let first = photos.first, let latest = photos.last {
                CompareRow(first: first, latest: latest, store: store)
            }

            if photos.isEmpty {
                emptyNote("Same spot, same light, same pose — every day. The scale lies on any given morning; this doesn't.")
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(photos.reversed()) { photo in
                        Button { selectedPhoto = photo } label: { thumbnail(for: photo) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func thumbnail(for photo: ProgressPhoto) -> some View {
        Group {
            if let image = store.image(for: photo) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.surfaceMuted)
            }
        }
        .frame(height: 138)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text(photo.date, format: .dateTime.month(.abbreviated).day())
                .font(Theme.mono(9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(5)
        }
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).ledgerLabel()
            Spacer()
            Text(trailing)
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func launchCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Haptics.tap()
            showingCamera = true
        } else {
            showingCameraUnavailableAlert = true
        }
    }

    private func reload() {
        photos = store.allPhotosSortedByDate()
    }
}

// MARK: - Day 1 vs today

private struct CompareRow: View {
    let first: ProgressPhoto
    let latest: ProgressPhoto
    let store: ProgressPhotoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                pane(photo: first, caption: "Day 1")
                pane(photo: latest, caption: "Today")
            }
            if let w1 = first.weightLbsAtCapture, let w2 = latest.weightLbsAtCapture, w1 != w2 {
                Text("\(Int(w1)) lb → \(Int(w2)) lb")
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private func pane(photo: ProgressPhoto, caption: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = store.image(for: photo) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 230).clipped()
            } else {
                Rectangle().fill(Theme.surfaceMuted).frame(height: 230)
            }
            Text(caption)
                .font(Theme.mono(9, weight: .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(7)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Detail

private struct PhotoDetailView: View {
    let photo: ProgressPhoto
    let store: ProgressPhotoStore
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                VStack(spacing: 14) {
                    if let image = store.image(for: photo) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if let weight = photo.weightLbsAtCapture {
                        Text("\(Int(weight)) lb")
                            .font(Theme.mono(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(Theme.gutter)
            }
            .navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.inkMuted)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive, action: onDelete)
                        .foregroundStyle(Theme.signal)
                }
            }
        }
    }
}
