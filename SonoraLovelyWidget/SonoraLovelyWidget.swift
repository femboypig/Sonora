import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private enum SonoraWidgetConfig {
    static let appGroupID = "group.ru.hippo.Sonora.shared"
    static let lovelyTracksDefaultsKey = "sonora_widget_lovely_tracks_v1"
    static let randomTracksDefaultsKey = "sonora_widget_random_tracks_v1"
    static let artworkDirectoryName = "sonora_widget_artwork_v1"
    static let artworkFileNameKey = "artworkFileName"
    static let artworkThumbKey = "artworkThumb"
    static let deepLinkScheme = "sonora"
    static let deepLinkHost = "widget"
    static let deepLinkPath = "/play"
    static let deepLinkTrackIDQueryItem = "trackID"
    static let accentHexDefaultsKey = "sonora.settings.accentHex"
    static let legacyAccentDefaultsKey = "sonora.settings.accentColor"
}

enum SonoraWidgetSongSource: String {
    case songOfTheDay
    case random

    var title: String {
        switch self {
        case .songOfTheDay:
            return "Song of the Day"
        case .random:
            return "Random"
        }
    }
}

@available(iOS 17.0, *)
extension SonoraWidgetSongSource: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Song Source")
    }

    static var caseDisplayRepresentations: [SonoraWidgetSongSource: DisplayRepresentation] {
        [
            .songOfTheDay: DisplayRepresentation(title: "Song of the Day"),
            .random: DisplayRepresentation(title: "Random")
        ]
    }
}

@available(iOS 17.0, *)
struct SonoraWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Sonora Widget" }
    static var description: IntentDescription { IntentDescription("Choose Song of the Day or Random songs.") }

    @Parameter(title: "Source", default: .songOfTheDay)
    var source: SonoraWidgetSongSource
}

private struct LovelyTrack: Hashable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let artworkThumb: String?
}

private struct LovelyEntry: TimelineEntry {
    let date: Date
    let source: SonoraWidgetSongSource
    let track: LovelyTrack?
}

private enum LovelyEntryFactory {
    static func makeEntry(for date: Date, source: SonoraWidgetSongSource, preview: Bool) -> LovelyEntry {
        let tracks = sharedTracks(for: source)
        if let track = tracks.randomElement() {
            return LovelyEntry(date: date, source: source, track: track)
        }

        if preview {
            return LovelyEntry(date: date,
                              source: source,
                              track: LovelyTrack(id: "preview",
                                                 title: "Song",
                                                 artist: "Sonora",
                                                 artworkURL: nil,
                                                 artworkThumb: nil))
        }

        return LovelyEntry(date: date, source: source, track: nil)
    }

    static func defaultSource() -> SonoraWidgetSongSource {
        let songOfTheDayTracks = sharedTracks(for: .songOfTheDay)
        if !songOfTheDayTracks.isEmpty {
            return .songOfTheDay
        }

        let random = sharedTracks(for: .random)
        if !random.isEmpty {
            return .random
        }

        return .songOfTheDay
    }

    private static func sharedTracks(for source: SonoraWidgetSongSource) -> [LovelyTrack] {
        switch source {
        case .songOfTheDay:
            let lovely = loadTracks(key: SonoraWidgetConfig.lovelyTracksDefaultsKey)
            if !lovely.isEmpty {
                return lovely
            }
            return loadTracks(key: SonoraWidgetConfig.randomTracksDefaultsKey)
        case .random:
            let random = loadTracks(key: SonoraWidgetConfig.randomTracksDefaultsKey)
            if !random.isEmpty {
                return random
            }
            return loadTracks(key: SonoraWidgetConfig.lovelyTracksDefaultsKey)
        }
    }

    private static func loadTracks(key: String) -> [LovelyTrack] {
        guard let defaults = UserDefaults(suiteName: SonoraWidgetConfig.appGroupID),
              let rawTracks = defaults.array(forKey: key) as? [[String: Any]] else {
            return []
        }

        return rawTracks.compactMap { raw in
            guard let rawID = raw["id"] as? String else {
                return nil
            }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty {
                return nil
            }

            let titleRaw = (raw["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artistRaw = (raw["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artworkFileNameRaw = (raw[SonoraWidgetConfig.artworkFileNameKey] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let artworkThumbRaw = (raw[SonoraWidgetConfig.artworkThumbKey] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LovelyTrack(
                id: id,
                title: titleRaw.isEmpty ? "Unknown Song" : titleRaw,
                artist: artistRaw.isEmpty ? "Unknown Artist" : artistRaw,
                artworkURL: widgetArtworkURL(fileName: artworkFileNameRaw),
                artworkThumb: artworkThumbRaw.isEmpty ? nil : artworkThumbRaw
            )
        }
    }

    private static func widgetArtworkURL(fileName: String) -> URL? {
        guard !fileName.isEmpty,
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SonoraWidgetConfig.appGroupID) else {
            return nil
        }

        return containerURL
            .appendingPathComponent(SonoraWidgetConfig.artworkDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

@available(iOS 17.0, *)
private struct LovelyIntentProvider: AppIntentTimelineProvider {
    typealias Intent = SonoraWidgetConfigurationIntent

    func placeholder(in context: Context) -> LovelyEntry {
        LovelyEntry(date: Date(),
                    source: .songOfTheDay,
                    track: LovelyTrack(id: "placeholder",
                                       title: "Song of the Day",
                                       artist: "Sonora",
                                       artworkURL: nil,
                                       artworkThumb: nil))
    }

    func snapshot(for configuration: SonoraWidgetConfigurationIntent, in context: Context) async -> LovelyEntry {
        LovelyEntryFactory.makeEntry(for: Date(), source: configuration.source, preview: context.isPreview)
    }

    func timeline(for configuration: SonoraWidgetConfigurationIntent, in context: Context) async -> Timeline<LovelyEntry> {
        let now = Date()
        let source = configuration.source
        var entries: [LovelyEntry] = []

        for step in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: step * 30, to: now) ?? now
            entries.append(LovelyEntryFactory.makeEntry(for: date, source: source, preview: context.isPreview))
        }

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
}

private struct LovelyLegacyProvider: TimelineProvider {
    func placeholder(in context: Context) -> LovelyEntry {
        LovelyEntry(date: Date(),
                    source: .songOfTheDay,
                    track: LovelyTrack(id: "placeholder",
                                       title: "Song of the Day",
                                       artist: "Sonora",
                                       artworkURL: nil,
                                       artworkThumb: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (LovelyEntry) -> Void) {
        let source = LovelyEntryFactory.defaultSource()
        completion(LovelyEntryFactory.makeEntry(for: Date(), source: source, preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LovelyEntry>) -> Void) {
        let now = Date()
        let source = LovelyEntryFactory.defaultSource()
        var entries: [LovelyEntry] = []

        for step in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: step * 30, to: now) ?? now
            entries.append(LovelyEntryFactory.makeEntry(for: date, source: source, preview: context.isPreview))
        }

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }
}

private struct LovelyWidgetView: View {
    let entry: LovelyEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        cardImageView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .clipped()
        .clipShape(ContainerRelativeShape())
        .widgetURL(widgetURL)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    @ViewBuilder
    private var cardImageView: some View {
        if #available(iOSApplicationExtension 18.0, *), !isFullColor {
            Image(uiImage: renderedCardImage)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
        } else {
            Image(uiImage: renderedCardImage)
                .resizable()
                .scaledToFill()
        }
    }

    private var isSmall: Bool {
        family == .systemSmall
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var isFullColor: Bool {
        renderingMode == .fullColor
    }

    private var renderedCardImage: UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: metrics.canvasSize, format: format)

        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: metrics.canvasSize)
            let palette = palette
            let cardPath = UIBezierPath(roundedRect: bounds, cornerRadius: metrics.cornerRadius)
            palette.background.setFill()
            cardPath.fill()
            palette.border.setStroke()
            cardPath.lineWidth = 1
            cardPath.stroke()

            let content = bounds.insetBy(dx: metrics.outerInset, dy: metrics.outerInset)
            drawCapsuleLabel(in: content, palette: palette)
            drawArtwork(in: content, context: context.cgContext, palette: palette)
            drawTextBlock(in: content, palette: palette)
        }
    }

    private var palette: WidgetPalette {
        let accent = resolvedAccentColor
        let baseBackground = isDark
        ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        : UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        let title = isDark
        ? UIColor.white
        : UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
        let subtitle = isDark
        ? UIColor.white.withAlphaComponent(0.68)
        : UIColor(red: 0.33, green: 0.34, blue: 0.35, alpha: 1)
        let borderBase = blend(baseBackground, accent, ratio: isDark ? 0.24 : 0.16)
        return WidgetPalette(
            background: baseBackground,
            border: borderBase.withAlphaComponent(isDark ? 0.30 : 0.12),
            accent: accent,
            title: title,
            subtitle: subtitle,
            brand: blend(title, accent, ratio: 0.24),
            artworkPlaceholder: blend(baseBackground, accent, ratio: isDark ? 0.28 : 0.14),
            artworkBorder: accent.withAlphaComponent(isDark ? 0.34 : 0.20)
        )
    }

    private var metrics: WidgetMetrics {
        isSmall
        ? WidgetMetrics(
            canvasSize: CGSize(width: 170, height: 170),
            cornerRadius: 36,
            outerInset: 14,
            artworkSize: 46,
            titleFontSize: 17,
            artistFontSize: 11,
            brandFontSize: 9,
            titleHeight: 46
        )
        : WidgetMetrics(
            canvasSize: CGSize(width: 364, height: 170),
            cornerRadius: 36,
            outerInset: 16,
            artworkSize: 54,
            titleFontSize: 18,
            artistFontSize: 12,
            brandFontSize: 9,
            titleHeight: 50
        )
    }

    private var titleText: String {
        entry.track?.title ?? "Open Sonora"
    }

    private var artistText: String {
        let artist = entry.track?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if artist.isEmpty || artist.lowercased() == "unknown artist" {
            return entry.track == nil ? "Add tracks in Sonora" : "Sonora"
        }
        return artist
    }

    private var sourceLabelText: String {
        entry.source == .songOfTheDay ? "Song of the Day" : "Random"
    }

    private func drawCapsuleLabel(in content: CGRect, palette: WidgetPalette) {
        let font = UIFont.systemFont(ofSize: isSmall ? 9 : 10, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.accent
        ]
        let size = (sourceLabelText as NSString).size(withAttributes: attributes)
        let rect = CGRect(
            x: content.minX,
            y: content.minY + 2,
            width: size.width + 18,
            height: size.height + 8
        )
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        palette.artworkPlaceholder.setFill()
        path.fill()
        palette.artworkBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
        (sourceLabelText as NSString).draw(
            in: rect.insetBy(dx: 9, dy: 4),
            withAttributes: attributes
        )
    }

    private func drawArtwork(in content: CGRect, context cg: CGContext, palette: WidgetPalette) {
        let rect = CGRect(
            x: content.maxX - metrics.artworkSize,
            y: content.minY,
            width: metrics.artworkSize,
            height: metrics.artworkSize
        )

        cg.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        path.addClip()
        if let artwork = artworkImage {
            artwork.draw(in: rect)
        } else {
            palette.artworkPlaceholder.setFill()
            path.fill()
            let config = UIImage.SymbolConfiguration(pointSize: metrics.artworkSize * 0.34, weight: .semibold)
            let tint = palette.title.withAlphaComponent(0.82)
            if let note = UIImage(systemName: "music.note", withConfiguration: config)?
                .withTintColor(tint, renderingMode: .alwaysOriginal) {
                let noteRect = CGRect(
                    x: rect.midX - (note.size.width / 2),
                    y: rect.midY - (note.size.height / 2),
                    width: note.size.width,
                    height: note.size.height
                )
                note.draw(in: noteRect)
            }
        }
        cg.restoreGState()

        let border = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        palette.artworkBorder.setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    private func drawTextBlock(in content: CGRect, palette: WidgetPalette) {
        let brandFont = UIFont.monospacedSystemFont(ofSize: metrics.brandFontSize, weight: .semibold)
        let titleFont = UIFont.systemFont(ofSize: metrics.titleFontSize, weight: .bold)
        let artistFont = UIFont.systemFont(ofSize: metrics.artistFontSize, weight: .medium)

        let brandText = "SONORA"
        let brandAttributes: [NSAttributedString.Key: Any] = [
            .font: brandFont,
            .foregroundColor: palette.brand
        ]
        let brandSize = (brandText as NSString).size(withAttributes: brandAttributes)
        let brandRect = CGRect(
            x: content.maxX - brandSize.width,
            y: content.maxY - brandSize.height,
            width: brandSize.width,
            height: brandSize.height
        )
        (brandText as NSString).draw(in: brandRect, withAttributes: brandAttributes)

        let artistAttributes: [NSAttributedString.Key: Any] = [
            .font: artistFont,
            .foregroundColor: palette.subtitle
        ]
        let artistHeight = artistFont.lineHeight
        let textRight = min(brandRect.minX - 10, content.maxX - (isSmall ? 0 : metrics.artworkSize + 14))
        let textWidth = max(textRight - content.minX, 72)
        let artistRect = CGRect(
            x: content.minX,
            y: content.maxY - artistHeight,
            width: textWidth,
            height: artistHeight
        )

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byTruncatingTail
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: palette.title,
            .paragraphStyle: titleStyle
        ]
        let measuredTitleBounds = (titleText as NSString).boundingRect(
            with: CGSize(width: textWidth, height: metrics.titleHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttributes,
            context: nil
        )
        let measuredTitleHeight = max(
            titleFont.lineHeight,
            min(ceil(measuredTitleBounds.height), metrics.titleHeight)
        )
        let titleRect = CGRect(
            x: content.minX,
            y: artistRect.minY - measuredTitleHeight - 2,
            width: textWidth,
            height: measuredTitleHeight
        )

        (titleText as NSString).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttributes,
            context: nil
        )
        (artistText as NSString).draw(in: artistRect, withAttributes: artistAttributes)
    }

    private var resolvedAccentColor: UIColor {
        if let image = artworkImage, let artworkAccent = dominantAccentColor(from: image) {
            return artworkAccent
        }
        return settingsAccentColor
    }

    private var settingsAccentColor: UIColor {
        guard let defaults = UserDefaults(suiteName: SonoraWidgetConfig.appGroupID) else {
            return legacyAccentColor(for: 0)
        }
        if let hex = defaults.string(forKey: SonoraWidgetConfig.accentHexDefaultsKey),
           let color = colorFromHex(hex) {
            return normalizedAccentColor(color)
        }
        return legacyAccentColor(for: defaults.integer(forKey: SonoraWidgetConfig.legacyAccentDefaultsKey))
    }

    private func legacyAccentColor(for raw: Int) -> UIColor {
        switch raw {
        case 1:
            return UIColor(red: 0.31, green: 0.64, blue: 1.0, alpha: 1.0)
        case 2:
            return UIColor(red: 0.22, green: 0.83, blue: 0.62, alpha: 1.0)
        case 3:
            return UIColor(red: 1.0, green: 0.48, blue: 0.40, alpha: 1.0)
        default:
            return UIColor(red: 1.0, green: 0.83, blue: 0.08, alpha: 1.0)
        }
    }

    private func colorFromHex(_ hexString: String) -> UIColor? {
        var normalized = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard normalized.count == 6, let rgb = Int(normalized, radix: 16) else {
            return nil
        }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    private func blend(_ base: UIColor, _ accent: UIColor, ratio: CGFloat) -> UIColor {
        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        var ar: CGFloat = 0
        var ag: CGFloat = 0
        var ab: CGFloat = 0
        var aa: CGFloat = 0
        guard base.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
              accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa) else {
            return base
        }
        let clamped = min(max(ratio, 0), 1)
        let inverse = 1 - clamped
        return UIColor(
            red: (br * inverse) + (ar * clamped),
            green: (bg * inverse) + (ag * clamped),
            blue: (bb * inverse) + (ab * clamped),
            alpha: 1
        )
    }

    private func normalizedAccentColor(_ color: UIColor) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }
        let adjustedSaturation = max(saturation, 0.38)
        let adjustedBrightness = isDark
        ? min(max(brightness, 0.72), 0.94)
        : min(max(brightness, 0.44), 0.82)
        return UIColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: 1.0)
    }

    private func dominantAccentColor(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let sampleSide = 24
        let bytesPerPixel = 4
        let bytesPerRow = sampleSide * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleSide * sampleSide * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: sampleSide,
            height: sampleSide,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))

        struct Bucket {
            var weight: CGFloat = 0
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
        }

        var buckets: [Int: Bucket] = [:]

        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = CGFloat(pixels[index]) / 255.0
            let green = CGFloat(pixels[index + 1]) / 255.0
            let blue = CGFloat(pixels[index + 2]) / 255.0
            let alpha = CGFloat(pixels[index + 3]) / 255.0
            if alpha < 0.35 {
                continue
            }

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var resolvedAlpha: CGFloat = 0
            let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
            guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &resolvedAlpha) else {
                continue
            }
            if brightness < 0.16 || saturation < 0.18 {
                continue
            }

            let key = (Int(hue * 12) << 8) | (Int(saturation * 4) << 4) | Int(brightness * 4)
            let weight = (0.45 + (saturation * 0.55)) * (0.55 + (brightness * 0.45))
            var bucket = buckets[key] ?? Bucket()
            bucket.weight += weight
            bucket.red += red * weight
            bucket.green += green * weight
            bucket.blue += blue * weight
            buckets[key] = bucket
        }

        guard let best = buckets.values.max(by: { $0.weight < $1.weight }), best.weight > 0 else {
            return nil
        }

        let color = UIColor(
            red: best.red / best.weight,
            green: best.green / best.weight,
            blue: best.blue / best.weight,
            alpha: 1
        )
        return normalizedAccentColor(color)
    }

    private var artworkImage: UIImage? {
        if let artworkPath = entry.track?.artworkURL?.path, !artworkPath.isEmpty,
           let image = UIImage(contentsOfFile: artworkPath) {
            return image
        }

        if let base64 = entry.track?.artworkThumb,
           let data = Data(base64Encoded: base64),
           let image = UIImage(data: data) {
            return image
        }

        return nil
    }

    private var widgetURL: URL {
        var components = URLComponents()
        components.scheme = SonoraWidgetConfig.deepLinkScheme
        components.host = SonoraWidgetConfig.deepLinkHost
        components.path = SonoraWidgetConfig.deepLinkPath

        if let track = entry.track, !track.id.isEmpty {
            components.queryItems = [
                URLQueryItem(name: SonoraWidgetConfig.deepLinkTrackIDQueryItem, value: track.id)
            ]
        }

        return components.url ?? URL(string: "sonora://widget/play")!
    }

    private struct WidgetPalette {
        let background: UIColor
        let border: UIColor
        let accent: UIColor
        let title: UIColor
        let subtitle: UIColor
        let brand: UIColor
        let artworkPlaceholder: UIColor
        let artworkBorder: UIColor
    }

    private struct WidgetMetrics {
        let canvasSize: CGSize
        let cornerRadius: CGFloat
        let outerInset: CGFloat
        let artworkSize: CGFloat
        let titleFontSize: CGFloat
        let artistFontSize: CGFloat
        let brandFontSize: CGFloat
        let titleHeight: CGFloat
    }
}

@available(iOS 17.0, *)
struct SonoraLovelyWidget: Widget {
    private let kind = "SonoraLovelyWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SonoraWidgetConfigurationIntent.self,
                               provider: LovelyIntentProvider()) { entry in
            LovelyWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Sonora Song")
        .description("Pick Song of the Day or Random in widget edit mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SonoraLovelyWidgetLegacy: Widget {
    private let kind = "SonoraLovelyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LovelyLegacyProvider()) { entry in
            LovelyWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Sonora Song")
        .description("Shows songs prepared in Sonora.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
