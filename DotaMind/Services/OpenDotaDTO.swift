//
//  OpenDotaDTO.swift
//  DotaMind
//
//  «Сырые» ответы OpenDota. Имена полей — как в JSON, без логики.
//  В UI их не тащим: PlayerStore превращает их в доменные модели (Models/).
//

import Foundation

enum OpenDotaDTO {
    struct Player: Decodable, Sendable {
        struct Profile: Decodable, Sendable {
            let account_id: Int?
            let personaname: String?
            let avatarfull: String?
            let steamid: String?
            let profileurl: String?
            let plus: Bool?
        }
        let profile: Profile?
        let rank_tier: Int?
        let leaderboard_rank: Int?
    }

    struct WL: Decodable, Sendable {
        let win: Int
        let lose: Int
    }

    /// Строка /players/{id}/heroes: игры на герое, а также с ним и против него.
    struct PlayerHero: Decodable, Sendable {
        let hero_id: Int
        let last_played: Int?
        let games: Int
        let win: Int
        let with_games: Int?
        let with_win: Int?
        let against_games: Int?
        let against_win: Int?
    }

    struct HeroStat: Decodable, Sendable {
        let id: Int
        let localized_name: String
        let name: String
        let img: String?
        let icon: String?
        let primary_attr: String?
        let roles: [String]?
    }

    struct Match: Decodable, Sendable {
        let match_id: Int
        let player_slot: Int?
        let radiant_win: Bool?
        let game_mode: Int?
        let hero_id: Int
        let start_time: Int
        let duration: Int
        let kills: Int?
        let deaths: Int?
        let assists: Int?
        let party_size: Int?
    }

    /// Элемент /players/{id}/totals: сумма поля `field` по `n` матчам.
    struct Total: Decodable, Sendable {
        let field: String
        let n: Int
        let sum: Double
    }

    struct Peer: Decodable, Sendable {
        let account_id: Int
        let personaname: String?
        let avatarfull: String?
        let with_games: Int
        let with_win: Int
        let last_played: Int?
    }

    struct Counts: Decodable, Sendable {
        struct Bucket: Decodable, Sendable {
            let games: Int
            let win: Int
        }
        /// "0" — Dire, "1" — Radiant.
        let is_radiant: [String: Bucket]?
    }

    /// Полный матч /matches/{id}. Графики преимущества есть только у разобранных матчей.
    struct MatchDetail: Decodable, Sendable {
        struct Player: Decodable, Sendable {
            let account_id: Int?
            let personaname: String?
            let hero_id: Int
            let player_slot: Int?
            let isRadiant: Bool?
            let kills: Int?
            let deaths: Int?
            let assists: Int?
            let last_hits: Int?
            let denies: Int?
            let gold_per_min: Int?
            let xp_per_min: Int?
            let net_worth: Int?
            let hero_damage: Int?
            let tower_damage: Int?
            let hero_healing: Int?
            let level: Int?
            let rank_tier: Int?
            let item_0: Int?
            let item_1: Int?
            let item_2: Int?
            let item_3: Int?
            let item_4: Int?
            let item_5: Int?
            let item_neutral: Int?
            let aghanims_scepter: Int?
            let aghanims_shard: Int?
        }
        let match_id: Int
        let radiant_win: Bool?
        let duration: Int
        let start_time: Int
        let game_mode: Int?
        let radiant_score: Int?
        let dire_score: Int?
        let radiant_gold_adv: [Int]?
        let radiant_xp_adv: [Int]?
        let players: [Player]
    }

    /// Элемент /constants/items (ключ словаря — внутреннее имя предмета).
    struct ItemConstant: Decodable, Sendable {
        let id: Int
        let img: String?
        let dname: String?
        let cost: Int?
    }

    /// Матч с предметами — для статистики предметов на герое.
    struct MatchWithItems: Decodable, Sendable {
        let match_id: Int
        let player_slot: Int?
        let radiant_win: Bool?
        let item_0: Int?
        let item_1: Int?
        let item_2: Int?
        let item_3: Int?
        let item_4: Int?
        let item_5: Int?

        var items: [Int] { [item_0, item_1, item_2, item_3, item_4, item_5].compactMap { $0 }.filter { $0 > 0 } }
    }

    /// Лучший матч по полю — /matches?sort=<field>&limit=1&project=...
    struct RecordMatch: Decodable, Sendable {
        let match_id: Int
        let hero_id: Int?
        let start_time: Int?
        let kills: Int?
        let assists: Int?
        let gold_per_min: Int?
        let xp_per_min: Int?
        let hero_damage: Int?
        let last_hits: Int?
        let duration: Int?
    }

    /// Минимум для графика формы и турбо-рейтинга.
    struct MatchResult: Decodable, Sendable {
        let start_time: Int
        let player_slot: Int?
        let radiant_win: Bool?
        /// Средний rank_tier лобби (есть у ~97 % матчей, в т.ч. Turbo).
        var average_rank: Int? = nil
    }

    struct Benchmarks: Decodable, Sendable {
        struct Point: Decodable, Sendable {
            let percentile: Double
            let value: Double
        }
        let hero_id: Int
        let result: [String: [Point]]
    }
}
