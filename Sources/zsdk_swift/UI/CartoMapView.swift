import SwiftUI
import UIKit

/// A static, non-interactive map that renders CartoDB dark raster tiles exactly
/// like the Flutter app's `flutter_map`: it fetches the same
/// `dark_all/{z}/{x}/{y}@2x.png` tiles and paints them in a grid. There is no
/// map engine (no MapKit / Google), so it matches the app's provider and look
/// one-to-one, with a pin at the event location.
struct CartoMapView: View {

    let latitude: Double
    let longitude: Double
    /// Pin tint, matching the app's white `location_on` marker.
    var markerColor: Color = .white

    // Same tile source, subdomains, and zoom as the app.
    private let zoom = 15
    /// CartoDB "@2x" tiles are 512px; drawn at 256pt for retina crispness
    /// (matching flutter_map's `retinaMode`).
    private let tileSize: CGFloat = 256

    var body: some View {
        GeometryReader { geo in
            TileGrid(
                latitude: latitude,
                longitude: longitude,
                zoom: zoom,
                tileSize: tileSize,
                size: geo.size
            )
            .overlay {
                // Pin centered on the event coordinate — the app's location_on,
                // 32pt (its bottom tip sits on the point).
                MaterialIcon(.locationOn, size: 32, color: markerColor)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
            }
        }
        .background(ZTheme.background)
    }
}

/// Fetches and lays out the raster tiles covering `size`, centered on the
/// given coordinate.
private struct TileGrid: View {

    let latitude: Double
    let longitude: Double
    let zoom: Int
    let tileSize: CGFloat
    let size: CGSize

    @State private var tiles: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            ForEach(specs, id: \.key) { spec in
                if let image = tiles[spec.key] {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: tileSize, height: tileSize)
                        .position(x: spec.center.x, y: spec.center.y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: taskID) { await loadTiles() }
    }

    private var taskID: String {
        "\(latitude),\(longitude),\(zoom),\(Int(size.width))x\(Int(size.height))"
    }

    // MARK: - Tile math (Web Mercator)

    /// One tile to draw: its cache key, remote URL, and center point in the view.
    private struct TileSpec {
        let key: String
        let url: URL
        let center: CGPoint
    }

    private var specs: [TileSpec] {
        guard size.width > 0, size.height > 0 else { return [] }

        let n = pow(2.0, Double(zoom))
        let fx = (longitude + 180.0) / 360.0 * n
        let latRad = latitude * .pi / 180.0
        let fy = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n

        let cols = Int(ceil(size.width / tileSize)) + 2
        let rows = Int(ceil(size.height / tileSize)) + 2
        let maxIndex = Int(n)

        var result: [TileSpec] = []
        for dx in -(cols / 2 + 1)...(cols / 2 + 1) {
            for dy in -(rows / 2 + 1)...(rows / 2 + 1) {
                let tileX = Int(floor(fx)) + dx
                let tileY = Int(floor(fy)) + dy
                guard tileY >= 0, tileY < maxIndex else { continue }
                let wrappedX = ((tileX % maxIndex) + maxIndex) % maxIndex

                // Top-left corner of this tile, in view points.
                let originX = size.width / 2 - CGFloat(fx - Double(tileX)) * tileSize
                let originY = size.height / 2 - CGFloat(fy - Double(tileY)) * tileSize

                let sub = ["a", "b", "c", "d"][(wrappedX + tileY) % 4]
                let urlString = "https://\(sub).basemaps.cartocdn.com/dark_all/\(zoom)/\(wrappedX)/\(tileY)@2x.png"
                guard let url = URL(string: urlString) else { continue }

                result.append(TileSpec(
                    key: "\(zoom)/\(wrappedX)/\(tileY)",
                    url: url,
                    center: CGPoint(x: originX + tileSize / 2, y: originY + tileSize / 2)
                ))
            }
        }
        return result
    }

    private func loadTiles() async {
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for spec in specs where tiles[spec.key] == nil {
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: spec.url),
                          let image = UIImage(data: data) else {
                        return (spec.key, nil)
                    }
                    return (spec.key, image)
                }
            }
            for await (key, image) in group {
                if let image { tiles[key] = image }
            }
        }
    }
}
