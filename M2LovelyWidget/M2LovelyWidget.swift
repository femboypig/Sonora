import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private enum M2WidgetConfig {
    static let appGroupID = "group.ru.hippo.M2.shared"
    static let lovelyTracksDefaultsKey = "m2_widget_lovely_tracks_v1"
    static let randomTracksDefaultsKey = "m2_widget_random_tracks_v1"
    static let artworkDirectoryName = "m2_widget_artwork_v1"
    static let artworkFileNameKey = "artworkFileName"
    static let artworkThumbKey = "artworkThumb"
    static let deepLinkScheme = "m2"
    static let deepLinkHost = "widget"
    static let deepLinkPath = "/play"
    static let deepLinkTrackIDQueryItem = "trackID"
}

enum M2WidgetSongSource: String {
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
extension M2WidgetSongSource: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Song Source")
    }

    static var caseDisplayRepresentations: [M2WidgetSongSource: DisplayRepresentation] {
        [
            .lovely: DisplayRepresentation(title: "Lovely"),
            .random: DisplayRepresentation(title: "Random")
        ]
    }
}

@available(iOSApplicationExtension 17.0, *)
struct M2WidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "M2 Widget" }
    static var description: IntentDescription { IntentDescription("Choose whether the widget shows lovely songs or random songs.") }

    @Parameter(title: "Show")
    var source: M2WidgetSongSource?

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
    let source: M2WidgetSongSource
    let track: LovelyTrack?
}

private enum LovelyEntryFactory {
    static func makeEntry(for date: Date, source: M2WidgetSongSource, preview: Bool) -> LovelyEntry {
        let tracks = sharedTracks(for: source)
        if let track = tracks.randomElement() {
            return LovelyEntry(date: date, source: source, track: track)
        }

        if preview {
            return LovelyEntry(date: date,
                              source: source,
                              track: LovelyTrack(id: "preview",
                                                 title: "Song",
                                                 artist: "M2",
                                                 artworkURL: nil,
                                                 artworkThumb: nil))
        }

        return LovelyEntry(date: date, source: source, track: nil)
    }

    static func defaultSource() -> M2WidgetSongSource {
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

    private static func sharedTracks(for source: M2WidgetSongSource) -> [LovelyTrack] {
        switch source {
        case .lovely:
            let lovely = loadTracks(key: M2WidgetConfig.lovelyTracksDefaultsKey)
            if !lovely.isEmpty {
                return lovely
            }
            return loadTracks(key: M2WidgetConfig.randomTracksDefaultsKey)
        case .random:
            let random = loadTracks(key: M2WidgetConfig.randomTracksDefaultsKey)
            if !random.isEmpty {
                return random
            }
            return loadTracks(key: M2WidgetConfig.lovelyTracksDefaultsKey)
        }
    }

    private static func loadTracks(key: String) -> [LovelyTrack] {
        guard let defaults = UserDefaults(suiteName: M2WidgetConfig.appGroupID),
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
            let artworkFileNameRaw = (raw[M2WidgetConfig.artworkFileNameKey] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let artworkThumbRaw = (raw[M2WidgetConfig.artworkThumbKey] as? String ?? "")
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
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: M2WidgetConfig.appGroupID) else {
            return nil
        }

        return containerURL
            .appendingPathComponent(M2WidgetConfig.artworkDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

@available(iOSApplicationExtension 17.0, *)
private struct LovelyIntentProvider: AppIntentTimelineProvider {
    typealias Intent = M2WidgetConfigurationIntent

    func placeholder(in context: Context) -> LovelyEntry {
        LovelyEntry(date: Date(),
                    source: .lovely,
                    track: LovelyTrack(id: "placeholder",
                                       title: "Lovely Song",
                                       artist: "M2",
                                       artworkURL: nil,
                                       artworkThumb: nil))
    }

    func snapshot(for configuration: M2WidgetConfigurationIntent, in context: Context) async -> LovelyEntry {
        LovelyEntryFactory.makeEntry(for: Date(), source: configuration.source ?? .lovely, preview: context.isPreview)
    }

    func timeline(for configuration: M2WidgetConfigurationIntent, in context: Context) async -> Timeline<LovelyEntry> {
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
                                       artist: "M2",
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
                    Text("Open M2 to prepare songs")
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
        components.scheme = M2WidgetConfig.deepLinkScheme
        components.host = M2WidgetConfig.deepLinkHost
        components.path = M2WidgetConfig.deepLinkPath

        if let track = entry.track, !track.id.isEmpty {
            components.queryItems = [
                URLQueryItem(name: M2WidgetConfig.deepLinkTrackIDQueryItem, value: track.id)
            ]
        }

        return components.url ?? URL(string: "m2://widget/play")!
    }
}

@available(iOSApplicationExtension 17.0, *)
struct M2LovelyWidget: Widget {
    private let kind = "M2LovelyWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: M2WidgetConfigurationIntent.self,
                               provider: LovelyIntentProvider()) { entry in
            LovelyWidgetView(entry: entry)
                .m2WidgetAccentable(false)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("M2 Song")
        .description("Pick Lovely or Random in widget edit mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct M2LovelyWidgetLegacy: Widget {
    private let kind = "M2LovelyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LovelyLegacyProvider()) { entry in
            LovelyWidgetView(entry: entry)
                .m2WidgetAccentable(false)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("M2 Song")
        .description("Shows songs prepared in M2.")
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
