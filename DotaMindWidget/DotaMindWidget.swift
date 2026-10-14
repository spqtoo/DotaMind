//
//  DotaMindWidget.swift
//  DotaMindWidget
//
//  Виджет «Домой»: винрейт и последние матчи в выбранном режиме (по умолчанию
//  Turbo). Friend ID задаётся в настройках виджета (удерживать → «Изменить
//  виджет»): так не нужен App Group, и проект подписывается бесплатным Apple ID.
//  Код самодостаточный — таргет виджета не видит файлы приложения.
//
//  ANDROID (Material 3): Jetpack Glance (GlanceAppWidget) + GlanceTheme; конфигурация —
//  отдельная Activity (android:configure) с полем Friend ID и выбором режима;
//  обновление — WorkManager раз в 30 мин.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Настройки виджета

enum WidgetMode: String, AppEnum {
    case turbo, normal, all

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Режим"
    static let caseDisplayRepresentations: [WidgetMode: DisplayRepresentation] = [
        .turbo: "Turbo", .normal: "Обычные", .all: "Все"
    ]

    var title: String {
        switch self {
        case .turbo: "TURBO"
        case .normal: "ОБЫЧНЫЕ"
        case .all: "ВСЕ"
        }
    }

    /// То же правило, что в приложении: без significant=0 Turbo не считается.
    var query: String {
        switch self {
        case .turbo: "game_mode=23&significant=0"
        case .normal: ""
        case .all: "significant=0"
        }
    }
}

struct DotaMindWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Статистика DotaMind"
    static let description = IntentDescription("Винрейт и последние матчи. Friend ID есть в приложении: Настройки → Аккаунт.")

    @Parameter(title: "Friend ID")
    var friendID: String?

    @Parameter(title: "Режим", default: .turbo)
    var mode: WidgetMode
}

// MARK: - Данные

struct WidgetEntry: TimelineEntry {
    struct Match: Identifiable {
        let id: Int
        let didWin: Bool
        let kills, deaths, assists: Int
        let heroName: String
    }

    let date: Date
    let mode: WidgetMode
    let nickname: String?
    let wins: Int
    let losses: Int
    let recent: [Match]
    let message: String?

    var winrate: Double? { wins + losses > 0 ? Double(wins) / Double(wins + losses) : nil }

    static func placeholder(_ mode: WidgetMode = .turbo) -> WidgetEntry {
        WidgetEntry(date: .now, mode: mode, nickname: "jixapka", wins: 1633, losses: 1735,
                    recent: (0..<10).map { Match(id: $0, didWin: $0 % 3 != 0, kills: 12, deaths: 4, assists: 9, heroName: "Troll Warlord") },
                    message: nil)
    }
}

private enum WidgetAPI {
    private struct WL: Decodable { let win: Int; let lose: Int }
    private struct Player: Decodable {
        struct Profile: Decodable { let personaname: String? }
        let profile: Profile?
    }
    private struct Match: Decodable {
        let match_id: Int
        let player_slot: Int?
        let radiant_win: Bool?
        let hero_id: Int
        let kills: Int?
        let deaths: Int?
        let assists: Int?
    }
    private struct HeroConst: Decodable { let id: Int; let localized_name: String }

    static func accountID(from text: String?) -> Int? {
        let digits = (text ?? "").filter(\.isNumber)
        guard let n = UInt64(digits), n > 0 else { return nil }
        let base: UInt64 = 76561197960265728
        return n > base ? Int(n - base) : Int(n)
    }

    static func load(account: Int, mode: WidgetMode) async throws -> WidgetEntry {
        let base = "https://api.opendota.com/api/players/\(account)"
        let q = mode.query
        async let wl: WL = get("\(base)/wl?\(q)")
        async let player: Player = get(base)
        async let matches: [Match] = get("\(base)/matches?\(q)\(q.isEmpty ? "" : "&")limit=10")
        async let heroes: [String: HeroConst] = get("https://api.opendota.com/api/constants/heroes")
        let (w, p, m) = try await (wl, player, matches)
        let names = (try? await heroes).map { Dictionary(uniqueKeysWithValues: $0.values.map { ($0.id, $0.localized_name) }) } ?? [:]
        return WidgetEntry(
            date: .now, mode: mode, nickname: p.profile?.personaname, wins: w.win, losses: w.lose,
            recent: m.map {
                WidgetEntry.Match(id: $0.match_id,
                                  didWin: ($0.radiant_win ?? false) == (($0.player_slot ?? 0) < 128),
                                  kills: $0.kills ?? 0, deaths: $0.deaths ?? 0, assists: $0.assists ?? 0,
                                  heroName: names[$0.hero_id] ?? "Герой")
            },
            message: nil
        )
    }

    private static func get<T: Decodable>(_ string: String) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: URL(string: string)!)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .placeholder() }

    func snapshot(for configuration: DotaMindWidgetIntent, in context: Context) async -> WidgetEntry {
        if context.isPreview { return .placeholder(configuration.mode) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: DotaMindWidgetIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let entry = await entry(for: configuration)
        // Матч в Turbo идёт ~20 минут — обновляться чаще смысла нет.
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: DotaMindWidgetIntent) async -> WidgetEntry {
        guard let account = WidgetAPI.accountID(from: configuration.friendID) else {
            return WidgetEntry(date: .now, mode: configuration.mode, nickname: nil, wins: 0, losses: 0, recent: [],
                               message: "Удерживай виджет → «Изменить» и введи Friend ID")
        }
        do {
            return try await WidgetAPI.load(account: account, mode: configuration.mode)
        } catch {
            return WidgetEntry(date: .now, mode: configuration.mode, nickname: nil, wins: 0, losses: 0, recent: [],
                               message: "Нет связи с OpenDota")
        }
    }
}

// MARK: - Вид

private let gold = Color(red: 0.98, green: 0.76, blue: 0.36)
private let win = Color(red: 0.24, green: 0.70, blue: 0.52)  // = Theme.win в приложении
private let loss = Color(red: 0.80, green: 0.30, blue: 0.34) // = Theme.loss

struct WidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let message = entry.message {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    Spacer()
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } else if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.16), Color(red: 0.04, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var header: some View {
        HStack {
            Text(entry.mode.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(gold, in: .capsule)
            Spacer()
            if let nickname = entry.nickname {
                Text(nickname).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var winrateText: some View {
        Text(entry.winrate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
            .font(.system(size: 34, weight: .bold).monospacedDigit())
            .foregroundStyle(gold)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(entry.recent.prefix(10).reversed()) { m in
                Circle().fill(m.didWin ? win : loss).frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("Последние матчи: \(entry.recent.prefix(10).filter(\.didWin).count) побед из \(min(entry.recent.count, 10))")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            winrateText
            Text("\(entry.wins.formatted())–\(entry.losses.formatted())")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            dots.padding(.top, 2)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                winrateText
                Text("\(entry.wins.formatted())–\(entry.losses.formatted())")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                dots.padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.recent.prefix(4)) { m in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5).fill(m.didWin ? win : loss).frame(width: 3, height: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.heroName).font(.caption2.weight(.semibold)).lineLimit(1)
                            Text("\(m.kills)/\(m.deaths)/\(m.assists)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Виджет

struct DotaMindStatsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DotaMindStats", intent: DotaMindWidgetIntent.self, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("DotaMind")
        .description("Винрейт и последние матчи в Turbo или других режимах.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DotaMindWidgetBundle: WidgetBundle {
    var body: some Widget {
        DotaMindStatsWidget()
    }
}

#Preview(as: .systemMedium) {
    DotaMindStatsWidget()
} timeline: {
    WidgetEntry.placeholder()
}
