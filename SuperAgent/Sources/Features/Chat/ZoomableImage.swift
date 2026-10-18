import Photos
import SwiftUI

/// `.fullScreenCover(item:)` needs Identifiable; a raw Int index doesn't
/// qualify on its own.
struct IdentifiedInt: Identifiable { let value: Int; var id: Int { value } }

/// A picture you can pinch to zoom, double-tap to zoom in or reset, and pan
/// once zoomed — the one gesture set every "look closer at this" surface
/// reuses (a file's own image view, the full-screen viewer below).
struct ZoomableImage: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 5
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, min(lastScale * value, maxScale))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { reset() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = doubleTapScale
                        lastScale = doubleTapScale
                    }
                }
            }
            .animation(.interactiveSpring(), value: scale)
    }

    private func reset() {
        withAnimation(.spring(response: 0.3)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}

/// Full-screen viewer for one or more pictures — swipe between them, pinch
/// any one of them, Done to leave. What tapping a chat picture opens.
struct ImageViewerSheet: View {
    let images: [UIImage]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    /// What Save said, shown for a moment over the picture.
    @State private var saved: String?

    private var current: UIImage? { images.indices.contains(index) ? images[index] : nil }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                    ZoomableImage(image: img).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if let saved {
                    Label(saved, systemImage: saved == "Saved to Photos" ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .superFont(14, weight: .semibold)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar {
                // Keep it: straight into Photos, or anywhere else through the
                // share sheet (Copy, AirDrop, Files). A picture you could only
                // look at, and then lose, was the whole of this screen before.
                ToolbarItemGroup(placement: .topBarLeading) {
                    if let image = current {
                        Button { save(image) } label: { Image(systemName: "square.and.arrow.down") }
                            .foregroundStyle(.white)
                            .accessibilityLabel("Save to Photos")
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Image", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(.white)
                        .accessibilityLabel("Share")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func save(_ image: UIImage) {
        PhotoSaver.save(image) { ok in
            withAnimation(.easeOut(duration: 0.2)) { saved = ok ? "Saved to Photos" : "Allow Photos access in Settings to save" }
            if ok { Haptics.tap() }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.2)) { saved = nil }
            }
        }
    }
}

/// Writes a picture into Photos (add-only access: it can save, not read).
enum PhotoSaver {
    static func save(_ image: UIImage, done: @escaping @MainActor (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in done(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Task { @MainActor in done(ok) }
            }
        }
    }
}
