import SwiftUI
import UIKit

struct ProgressGalleryView: View {
    @EnvironmentObject var appState: AppState
    @Binding var launchCameraOnAppear: Bool
    @State private var photos: [ProgressPhoto] = []
    @State private var showingCamera = false
    @State private var showingCameraUnavailableAlert = false
    @State private var selectedPhoto: ProgressPhoto?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]
    private let store = ProgressPhotoStore.shared

    var body: some View {
        ScrollView {
            if photos.count >= 2 {
                CompareRow(first: photos.first!, latest: photos.last!, store: store)
                    .padding(.horizontal)
                    .padding(.top)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos.reversed()) { photo in
                    Button {
                        selectedPhoto = photo
                    } label: {
                        thumbnail(for: photo)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top)

            if photos.isEmpty {
                ContentUnavailableFallback()
                    .padding(.top, 60)
            }
        }
        .navigationTitle("Progress Photos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        showingCameraUnavailableAlert = true
                    }
                } label: {
                    Image(systemName: "camera.fill")
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { image in
                store.save(image, weightLbsAtCapture: appState.profile.currentWeightLbs)
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
        .alert("Camera Unavailable", isPresented: $showingCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device (likely the Simulator) has no camera. Try a real iPhone.")
        }
        .onAppear {
            reload()
            if launchCameraOnAppear {
                launchCameraOnAppear = false
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingCamera = true
                } else {
                    showingCameraUnavailableAlert = true
                }
            }
        }
    }

    private func reload() {
        photos = store.allPhotosSortedByDate()
    }

    private func thumbnail(for photo: ProgressPhoto) -> some View {
        Group {
            if let image = store.image(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.secondary.opacity(0.2))
            }
        }
        .frame(height: 130)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            Text(photo.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption2.weight(.semibold))
                .padding(4)
                .background(.black.opacity(0.5))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(4)
        }
    }
}

private struct CompareRow: View {
    let first: ProgressPhoto
    let latest: ProgressPhoto
    let store: ProgressPhotoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day 1 vs Today").font(.headline)
            HStack(spacing: 8) {
                comparePane(photo: first, label: "First")
                comparePane(photo: latest, label: "Latest")
            }
            if let w1 = first.weightLbsAtCapture, let w2 = latest.weightLbsAtCapture {
                Text("\(Int(w1)) lb → \(Int(w2)) lb  (\(w1 - w2 >= 0 ? "-" : "+")\(abs(Int(w1 - w2))) lb)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func comparePane(photo: ProgressPhoto, label: String) -> some View {
        VStack {
            if let image = store.image(for: photo) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 220).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PhotoDetailView: View {
    let photo: ProgressPhoto
    let store: ProgressPhotoStore
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if let image = store.image(for: photo) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
                if let weight = photo.weightLbsAtCapture {
                    Text("\(Int(weight)) lb").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
        }
    }
}

private struct ContentUnavailableFallback: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.on.rectangle").font(.largeTitle).foregroundStyle(.secondary)
            Text("No progress photos yet").font(.headline)
            Text("Take one today — same spot, same lighting, same pose each day makes the comparison actually mean something.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }
}
