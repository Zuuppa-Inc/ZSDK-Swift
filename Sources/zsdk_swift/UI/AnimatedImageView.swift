import SwiftUI
import UIKit
import ImageIO

/// Loads an image from a URL and plays it if it's an animated GIF, matching the
/// app (where event banners and avatars are often GIFs). Static images render
/// normally. Dependency-free: decodes frames + per-frame durations with ImageIO.
///
/// The decoded frames are rendered through a `UIImageView` (via
/// ``GIFImageView``), NOT SwiftUI's `Image` — SwiftUI's `Image` only ever shows
/// the first frame of an animated `UIImage`, which is why GIFs previously
/// appeared static. `UIImageView` plays animated images automatically.
///
/// Callers pick a `contentMode` (`.fill` crops to fill, `.fit` preserves the
/// natural aspect ratio) and, optionally, a loading placeholder — mirroring how
/// the call sites used `AsyncImage`:
///
/// ```swift
/// AnimatedImageView(url: url, contentMode: .fill) {
///     ZTheme.secondaryBackground
/// }
/// .frame(width: 85, height: 85)
/// .clipShape(RoundedRectangle(cornerRadius: 8))
/// ```
struct AnimatedImageView<Placeholder: View>: View {
    let url: URL
    let contentMode: ContentMode
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                imageView(image)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    /// Renders the loaded image through a `UIImageView` so animated GIFs play.
    /// `.fit` sizes the view to the image's natural aspect ratio (for the
    /// full-width covers); `.fill` fills whatever frame the caller sets and
    /// crops the overflow (relying on the caller's `.clipShape`/`.clipped`).
    @ViewBuilder
    private func imageView(_ image: UIImage) -> some View {
        switch contentMode {
        case .fit:
            let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
            GIFImageView(image: image, contentMode: .scaleAspectFit)
                .aspectRatio(ratio, contentMode: .fit)
        case .fill:
            GIFImageView(image: image, contentMode: .scaleAspectFill)
        }
    }

    private func load() async {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        let decoded = Self.decode(data)
        await MainActor.run { self.image = decoded }
    }

    /// Decodes `data` into an animated `UIImage` when it's a multi-frame GIF,
    /// otherwise a single-frame image.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }

        var frames: [UIImage] = []
        var totalDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            totalDuration += frameDuration(source, i)
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    /// Per-frame delay from the GIF metadata (unclamped, then clamped like
    /// browsers do to avoid 0ms frames).
    private static func frameDuration(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0.1
        return delay < 0.011 ? 0.1 : delay
    }
}

extension AnimatedImageView where Placeholder == Color {
    /// Convenience for callers that just want a `Color.clear` placeholder.
    init(url: URL, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode, placeholder: { Color.clear })
    }
}

/// A thin `UIImageView` wrapper that plays animated `UIImage`s. It fills
/// whatever size SwiftUI proposes (so the caller's `.frame`/`.aspectRatio`
/// governs layout) and crops via the image view's own content mode.
private struct GIFImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        // Don't let the image's intrinsic size fight SwiftUI's proposed layout.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image !== image { uiView.image = image }
        uiView.contentMode = contentMode
    }

    /// Fill the proposed size (falling back to the image's own size only when a
    /// dimension is left unspecified). The caller's frame/aspectRatio already
    /// resolved concrete proposals for the layouts that need a specific shape.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: proposal.height ?? uiView.intrinsicContentSize.height
        )
    }
}
