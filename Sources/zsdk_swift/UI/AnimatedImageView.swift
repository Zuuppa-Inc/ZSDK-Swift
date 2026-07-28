import SwiftUI
import UIKit
import ImageIO

/// Loads an image from a URL and plays it if it's an animated GIF, matching the
/// app (where event banners are often GIFs). Static images render normally.
/// Dependency-free: decodes frames + per-frame durations with ImageIO.
struct AnimatedImageView: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                // Loading placeholder in the app's card color.
                ZTheme.secondaryBackground
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .task(id: url) { await load() }
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
