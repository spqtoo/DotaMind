//
//  MatchModels.swift
//  DotaMind
//
//  Детали матча, предметы, форма и рекорды — готовые к показу модели.
//

import Foundation

struct Item: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let imageURL: URL?
    let cost: Int

    static func catalog(_ dto: [String: OpenDotaDTO.ItemConstant]) -> [Int: Item] {
        var result: [Int: Item] = [:]
        for (key, value) in dto {
            // У рецептов и служебных предметов нет картинок — им место не в UI.
            guard let img = value.img, !key.hasPrefix("recipe_") else { continue }
            // Без query-параметра ?t=…: так URL совпадает с офлайн-снимком.
            let path = img.split(separator: "?").first.map(String.init) ?? img
            result[value.id] = Item(id: value.id, name: value.dname ?? key,
                                    imageURL: URL(string: "https://cdn.cloudflare.steamstatic.com" + path),
                                    cost: value.cost ?? 0)
        }
        return result
    }
}

struct MatchDetail: Sendable {
    struct Line: Identifiable, Sendable {
        let id: Int // player_slot
        let accountID: Int?
        let name: String
        let heroID: Int
        let isRadiant: Bool
        let kills, deaths, assists: Int
        let lastHits, denies: Int
        let gpm, xpm: Int
        let netWorth: Int
        let heroDamage, towerDamage, healing: Int
        let level: Int
        let rank: Rank?
        let items: [Int?]          // 6 слотов, nil — пусто
        let neutral: Int?
        let hasScepter, hasShard: Bool
    }

    let id: Int
    let radiantWin: Bool
    let duration: TimeInterval
    let startTime: Date
    let gameMode: Int?
    let radiantScore: Int
    let direScore: Int
    let radiant: [Line]
    let dire: [Line]
    /// Преимущество Radiant в золоте по минутам; nil — матч не разобран.
    let goldAdvantage: [Int]?
    let xpAdvantage: [Int]?

    var isParsed: Bool { goldAdvantage?.isEmpty == false }

    init(_ dto: OpenDotaDTO.MatchDetail) {
        id = dto.match_id
        radiantWin = dto.radiant_win ?? false
        duration = TimeInterval(dto.duration)
        startTime = Date(timeIntervalSince1970: TimeInterval(dto.start_time))
        gameMode = dto.game_mode
        radiantScore = dto.radiant_score ?? 0
        direScore = dto.dire_score ?? 0
        goldAdvantage = dto.radiant_gold_adv
        xpAdvantage = dto.radiant_xp_adv

        let lines = dto.players.map { p -> Line in
            let slot = p.player_slot ?? 0
            let item: (Int?) -> Int? = { ($0 ?? 0) > 0 ? $0 : nil }
            return Line(
                id: slot,
                accountID: p.account_id,
                name: p.personaname ?? "Аноним",
                heroID: p.hero_id,
                isRadiant: p.isRadiant ?? (slot < 128),
                kills: p.kills ?? 0, deaths: p.deaths ?? 0, assists: p.assists ?? 0,
                lastHits: p.last_hits ?? 0, denies: p.denies ?? 0,
                gpm: p.gold_per_min ?? 0, xpm: p.xp_per_min ?? 0,
                netWorth: p.net_worth ?? 0,
                heroDamage: p.hero_damage ?? 0, towerDamage: p.tower_damage ?? 0, healing: p.hero_healing ?? 0,
                level: p.level ?? 0,
                rank: p.rank_tier.map { Rank(tier: $0, leaderboard: nil) },
                items: [p.item_0, p.item_1, p.item_2, p.item_3, p.item_4, p.item_5].map(item),
                neutral: item(p.item_neutral),
                hasScepter: (p.aghanims_scepter ?? 0) > 0,
                hasShard: (p.aghanims_shard ?? 0) > 0
            )
        }
        radiant = lines.filter(\.isRadiant).sorted { $0.id < $1.id }
        dire = lines.filter { !$0.isRadiant }.sorted { $0.id < $1.id }
    }
}

/// Точка графика формы: неделя и результат за неё.
struct FormPoint: Identifiable, Sendable {
    let weekStart: Date
    let games: Int
    let wins: Int
    var id: Date { weekStart }
    var winrate: Double { games > 0 ? Double(wins) / Double(games) : 0 }

    /// Группирует результаты по неделям (последние `weeks` недель, пустые — пропускаются).
    static func weekly(_ results: [OpenDotaDTO.MatchResult], weeks: Int = 12, now: Date = .now) -> [FormPoint] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1),
                                            to: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now)
        else { return [] }

        var buckets: [Date: (games: Int, wins: Int)] = [:]
        for r in results {
            let date = Date(timeIntervalSince1970: TimeInterval(r.start_time))
            guard date >= firstWeek, let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let didWin = (r.radiant_win ?? false) == ((r.player_slot ?? 0) < 128)
            buckets[week, default: (0, 0)].games += 1
            if didWin { buckets[week, default: (0, 0)].wins += 1 }
        }
        return buckets.map { FormPoint(weekStart: $0.key, games: $0.value.games, wins: $0.value.wins) }
            .sorted { $0.weekStart < $1.weekStart }
    }
}

struct PlayerRecord: Identifiable, Sendable {
    let id: String     // поле OpenDota
    let title: String
    let value: String
    let raw: Int       // число без форматирования (секунды для duration)
    let heroID: Int?
    let matchID: Int
    let date: Date?

    /// Какие рекорды показываем и как форматировать значение.
    static let fields: [(field: String, title: String, format: @Sendable (OpenDotaDTO.RecordMatch) -> Int?)] = [
        ("kills", "Больше всего убийств", \.kills),
        ("assists", "Больше всего помощи", \.assists),
        ("gold_per_min", "Лучший GPM", \.gold_per_min),
        ("hero_damage", "Больше всего урона", \.hero_damage),
        ("last_hits", "Больше всего добиваний", \.last_hits),
        ("duration", "Самый долгий матч", \.duration)
    ]
}

struct HeroItemStat: Identifiable, Sendable {
    let itemID: Int
    let games: Int
    let wins: Int
    var id: Int { itemID }
    var winrate: Double { games > 0 ? Double(wins) / Double(games) : 0 }
}

/// Твой показатель на герое против перцентилей всех игроков.
struct BenchmarkComparison: Identifiable, Sendable {
    let id: String
    let title: String
    let yours: Double
    let median: Double
    /// Примерный перцентиль, в который ты попадаешь (0…1).
    let percentile: Double
}
