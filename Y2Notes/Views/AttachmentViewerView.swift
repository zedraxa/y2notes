import SwiftUI

/// Full-screen viewer for attachment content.
/// - Image: pinch-zoom viewer with dismiss-on-swipe-down.
/// - PDF: single-page viewer.
/// - Link: placeholder (SFSafariViewController handled externally).
struct AttachmentViewerView: View {
    let attachment: AttachmentObject
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    imageViewer(image)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            await loadFullImage()
        }
    }

    // MARK: - Image Viewer

    @ViewBuilder
    private func imageViewer(_ img: UIImage) -> some View {
        GeometryReader { geo in
            let imgSize = img.size
            let fitScale = min(
                geo.size.width / imgSize.width,
                geo.size.height / imgSize.height
            )
            let displayW = imgSize.width * fitScale
            let displayH = imgSize.height * fitScale

            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displayW * scale, height: displayH * scale)
                .offset(offset)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = max(lastScale * value.magnification, 0.5)
                        }
                        .onEnded { _ in
                            if scale < 1.0 {
                                withAnimation(.spring(response: 0.3)) { scale = 1.0 }
                            }
                            lastScale = scale
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                            // Dismiss hint: drag down with no zoom
                            if scale <= 1.0 && value.translation.height > 150 {
                                dismiss()
                            }
                        }
                        .onEnded { _ in
                            if scale <= 1.0 {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = .zero
                                }
                                lastOffset = .zero
                            } else {
                                lastOffset = offset
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                        }
                        lastScale = scale
                    }
                }
        }
    }

    // MARK: - Loading

    private func loadFullImage() async {
        let store = AttachmentStore.shared
        // Try full-res first, fall back to thumbnail
        if let fullRes = store.fullResImage(for: attachment.id) {
            self.image = fullRes
            return
        }
        // Load from disk on background
        let url = store.contentURL(
            noteID: noteID,
            attachmentID: attachment.id,
            ext: attachment.fileExtension
        )
        if let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            self.image = img
            return
        }
        // Fall back to thumbnail
        self.image = store.thumbnail(for: attachment.id, noteID: noteID)
    }
}
