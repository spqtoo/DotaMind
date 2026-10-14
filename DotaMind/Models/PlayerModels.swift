//
//  PlayerModels.swift
//  DotaMind
//
//  Доменные модели, готовые к показу. Собираются из DTO в PlayerStore.
//

import Foundation

struct Hero: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let imageURL: URL?   // широкий портрет 256×144
    let iconURL: URL?    // маленькая квадратная иконка
    let primaryAttribute: String?
    let roles: [String]

    private static let cdn = "https://cdn.cloudflare.steamstatic.com"

    init(_ dto: OpenDotaDTO.HeroStat) {
        id = dto.id
        name = dto.localized_name
        imageURL = dto.img.flatMap { URL(string: Self.cdn + $0) }
        iconURL = dto.icon.flatMap { URL(string: Self.cdn + $0) }
        primaryAttribute = dto.primary_attr
        roles = dto.roles ?? []
    }

    /// Заглушка, если справочник ещё не загрузился или герой новый.
    init(unknownID id: Int) {
        self.id = id
        name = "Герой #\(id)"
        imageURL = nil
        iconURL = nil
        primaryAttribute = nil
        roles = []
    }
}

struct Rank: Sendable, Hashable {
    /// rank_tier из OpenDota: десятки — медаль (1 Herald … 8 Immortal), единицы — звёзды.
    let tier: Int
    let leaderboard: Int?

    var medal: Int { tier / 10 }
    var stars: Int { tier % 10 }

    var medalName: String {
        ["", "Herald", "Guardian", "Crusader", "Archon", "Legend", "Ancient", "Divine", "Immortal"][safe: medal] ?? "Unranked"
    }

    var title: String {
        if medal == 8 {
            return leaderboard.map { "Immortal #\($0)" } ?? "Immortal"
        }
        return stars > 0 ? "\(medalName) \(stars)" : medalName
    }

    var medalURL: URL? {
        URL(string: "https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_\(medal).png")
    }

    var starsURL: URL? {
        guard medal < 8, stars > 0 else { return nil }
        return URL(string: "https://www.opendota.com/assets/images/dota2/rank_icons/rank_star_\(stars).png")
    }
}

struct PlayerSummary: Sendable {
    let accountID: Int
    let nickname: String
    let avatarURL: URL?
    let profileURL: URL?
    let rank: Rank?
    let isPlus: Bool
}

struct HeroRecord: Identifiable, Sendable, Hashable {
    let heroID: Int
    let games: Int
    let wins: Int
    let lastPlayed: Date?
    let withGames: Int
    let withWins: Int
    let againstGames: Int
    let againstWins: Int

    var id: Int { heroID }
    var winrate: Double { games > 0 ? Double(wins) / Double(games) : 0 }
    var withWinrate: Double { withGames > 0 ? Double(withWins) / Double(withGames) : 0 }
    var againstWinrate: Double { againstGames > 0 ? Double(againstWins) / Double(againstGames) : 0 }

    init(_ dto: OpenDotaDTO.PlayerHero) {
        heroID = dto.hero_id
        games = dto.games
        wins = dto.win
        lastPlayed = dto.last_played.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        withGames = dto.with_games ?? 0
        withWins = dto.with_win ?? 0
        againstGames = dto.against_games ?? 0
        againstWins = dto.against_win ?? 0
    }
}

/// Средние значения по матчам из /totals.
struct Averages: Sendable, Equatable {
    var kills: Double = 0
    var deaths: Double = 0
    var assists: Double = 0
    var gpm: Double = 0
    var xpm: Double = 0
    var lastHits: Double = 0
    var heroDamage: Double = 0
    var duration: TimeInterval = 0

    var kda: Double { (kills + assists) / max(deaths, 1) }

    init() {}

    init(_ totals: [OpenDotaDTO.Total]) {
        func avg(_ field: String) -> Double {
            guard let t = totals.first(where: { $0.field == field }), t.n > 0 else { return 0 }
            return t.sum / Double(t.n)
        }
        kills = avg("kills")
        deaths = avg("deaths")
        assists = avg("assists")
        gpm = avg("gold_per_min")
        xpm = avg("xp_per_min")
        lastHits = avg("last_hits")
        heroDamage = avg("hero_damage")
        duration = avg("duration")
    }
}

struct MatchSummary: Identifiable, Sendable, Hashable {
    let id: Int
    let heroID: Int
    let didWin: Bool
    let kills: Int
    let deaths: Int
    let assists: Int
    let duration: TimeInterval
    let startTime: Date
    let gameMode: Int?
    let partySize: Int?

    init(_ dto: OpenDotaDTO.Match) {
        id = dto.match_id
        heroID = dto.hero_id
        // Слоты 0–127 — Radiant, 128+ — Dire.
        let isRadiant = (dto.player_slot ?? 0) < 128
        didWin = (dto.radiant_win ?? false) == isRadiant
        kills = dto.kills ?? 0
        deaths = dto.deaths ?? 0
        assists = dto.assists ?? 0
        duration = TimeInterval(dto.duration)
        startTime = Date(timeIntervalSince1970: TimeInterval(dto.start_time))
        gameMode = dto.game_mode
        partySize = dto.party_size
    }

    var opendotaURL: URL? { URL(string: "https://www.opendota.com/matches/\(id)") }
}

struct Peer: Identifiable, Sendable {
    let id: Int
    let name: String
    let avatarURL: URL?
    let games: Int
    let wins: Int
    var winrate: Double { games > 0 ? Double(wins) / Double(games) : 0 }
}

struct SideRecord: Sendable {
    let games: Int
    let wins: Int
    var winrate: Double? { games > 0 ? Double(wins) / Double(games) : nil }
}

/// Всё, что нужно экранам для одного режима статистики.
/// Грузится в два этапа: сначала быстрые запросы (победы, герои, матчи),
/// затем тяжёлые — `details` остаётся nil, пока они не придут.
struct ModeStats: Sendable {
    struct Details: Sendable {
        let averages: Averages
        let heroesLast30Days: [HeroRecord]
        let peers: [Peer]
        let radiant: SideRecord
        let dire: SideRecord
    }

    let wins: Int
    let losses: Int
    let heroes: [HeroRecord]          // все сыгранные герои, по убыванию игр
    let recentMatches: [MatchSummary] // по убыванию даты
    var details: Details?

    var games: Int { wins + losses }
    var winrate: Double? { games > 0 ? Double(wins) / Double(games) : nil }
    var playedHeroes: [HeroRecord] { heroes.filter { $0.games > 0 } }
}

/// Детали по одному герою в выбранном режиме.
struct HeroDetail: Sendable {
    let averages: Averages
    let matches: [MatchSummary]
    let toughestOpponents: [HeroRecord] // против кого хуже всего, когда играешь этим героем
    let bestAllies: [HeroRecord]
    let items: [HeroItemStat]           // предметы в финальном инвентаре и винрейт с ними
    let benchmarks: [BenchmarkComparison] // пусто для Turbo: там золото и опыт идут быстрее
}

/// Третий этап загрузки режима: график формы и рекорды.
struct ModeExtras: Sendable {
    let form: [FormPoint]
    let records: [PlayerRecord]
    let party: [PartyRecord]
}

/// Винрейт по размеру пати. OpenDota знает размер пати не у всех матчей.
struct PartyRecord: Identifiable, Sendable {
    let size: Int
    let wins: Int
    let losses: Int
    var id: Int { size }
    var games: Int { wins + losses }
    var winrate: Double { games > 0 ? Double(wins) / Double(games) : 0 }
    var title: String { size == 1 ? "Соло" : "Пати из \(size)" }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
