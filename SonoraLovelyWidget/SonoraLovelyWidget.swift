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
}

enum SonoraWidgetSongSource: String {
    case lovely
    case random

    var title: String {
        switch self {
        case .lovely:
            return "Lovely"
        case .random:
            return "Random"
        }
    }
}

@available(iOSApplicationExtension 17.0, *)
extension SonoraWidgetSongSource: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Song Source")
    }

    static var caseDisplayRepresentations: [SonoraWidgetSongSource: DisplayRepresentation] {
        [
            .lovely: DisplayRepresentation(title: "Lovely"),
            .random: DisplayRepresentation(title: "Random")
        ]
    }
}

@available(iOSApplicationExtension 17.0, *)
struct SonoraWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Sonora Widget" }
    static var description: IntentDescription { IntentDescription("Choose whether the widget shows lovely songs or random songs.") }

    @Parameter(title: "Show")
    var source: SonoraWidgetSongSource?

    init() {
        self.source = .lovely
    }
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
        let lovely = sharedTracks(for: .lovely)
        if !lovely.isEmpty {
            return .lovely
        }

        let random = sharedTracks(for: .random)
        if !random.isEmpty {
            return .random
        }

        return .lovely
    }

    private static func sharedTracks(for source: SonoraWidgetSongSource) -> [LovelyTrack] {
        switch source {
        case .lovely:
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

@available(iOSApplicationExtension 17.0, *)
private struct LovelyIntentProvider: AppIntentTimelineProvider {
    typealias Intent = SonoraWidgetConfigurationIntent

    func placeholder(in context: Context) -> LovelyEntry {
        LovelyEntry(date: Date(),
                    source: .lovely,
                    track: LovelyTrack(id: "placeholder",
                                       title: "Lovely Song",
                                       artist: "Sonora",
                                       artworkURL: nil,
                                       artworkThumb: nil))
    }

    func snapshot(for configuration: SonoraWidgetConfigurationIntent, in context: Context) async -> LovelyEntry {
        LovelyEntryFactory.makeEntry(for: Date(), source: configuration.source ?? .lovely, preview: context.isPreview)
    }

    func timeline(for configuration: SonoraWidgetConfigurationIntent, in context: Context) async -> Timeline<LovelyEntry> {
        let now = Date()
        let source = configuration.source ?? .lovely
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
                    source: .lovely,
                    track: LovelyTrack(id: "placeholder",
                                       title: "Lovely Song",
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isDark = (colorScheme == .dark)
        let isVibrant = (renderingMode == .vibrant)
        let background = isVibrant ? (isDark ? Color.black : Color.white) : (isDark ? Color.black : Color.white)
        let primaryText = isVibrant ? (isDark ? Color.white : Color.black) : (isDark ? Color.white : Color.black)
        let secondaryText = isVibrant
        ? (isDark ? Color.white.opacity(0.78) : Color.black.opacity(0.70))
        : (isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.62))

        ZStack(alignment: .bottomLeading) {
            background

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(entry.source.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .textCase(.uppercase)

                    Spacer(minLength: 0)

                    if let artwork = artworkImage {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipped()
                            .cornerRadius(7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
                            )
                    }
                }

                Spacer(minLength: 0)

                if let track = entry.track {
                    Text(track.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)

                    if !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       track.artist.lowercased() != "unknown artist" {
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                } else {
                    Text("Open Sonora to prepare songs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryText.opacity(0.88))
                        .lineLimit(2)
                }

                Text("Tap to play")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText.opacity(0.95))
                    .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .widgetURL(widgetURL)
        .m2WidgetContainerBackground {
            background
        }
        .m2WidgetTint(Color.clear)
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
}

@available(iOSApplicationExtension 17.0, *)
struct SonoraLovelyWidget: Widget {
    private let kind = "SonoraLovelyWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SonoraWidgetConfigurationIntent.self,
                               provider: LovelyIntentProvider()) { entry in
            LovelyWidgetView(entry: entry)
                .m2WidgetAccentable(false)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Sonora Song")
        .description("Pick Lovely or Random in widget edit mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SonoraLovelyWidgetLegacy: Widget {
    private let kind = "SonoraLovelyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LovelyLegacyProvider()) { entry in
            LovelyWidgetView(entry: entry)
                .m2WidgetAccentable(false)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Sonora Song")
        .description("Shows songs prepared in Sonora.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension View {
    @ViewBuilder
    func m2WidgetAccentable(_ accentable: Bool) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.widgetAccentable(accentable)
        } else {
            self
        }
    }

    @ViewBuilder
    func m2WidgetTint(_ tint: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.tint(tint)
        } else {
            self
        }
    }

    @ViewBuilder
    func m2WidgetContainerBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget, content: background)
        } else {
            self.background(background())
        }
    }
}
