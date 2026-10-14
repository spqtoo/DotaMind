//
//  Achievements.swift
//  DotaMind
//
//  Достижения с уровнями (бронза → серебро → золото → легенда), считаются
//  из уже загруженной статистики режима. Чистые функции.
//

import Foundation

struct Achievement: Identifiable, Sendable {
    enum Tier: Int, Sendable, Comparable {
        case none, bronze, silver, gold, legend
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .none: "Не открыто"
            case .bronze: "Бронза"
            case .silver: "Серебро"
            case .gold: "Золото"
            case .legend: "Легенда"
            }
        }
    }

    let id: String
    let title: String
    let symbol: String
    let detail: String          // что именно считается
    let value: Int
    let thresholds: [Int]       // 4 порога: бронза, серебро, золото, легенда
    var format: @Sendable (Int) -> String = { $0.formatted() }

    var tier: Tier {
        Tier(rawValue: thresholds.lastIndex { value >= $0 }.map { $0 + 1 } ?? 0) ?? .none
    }

    /// Прогресс до следующего уровня 0…1 (1 — максимальный уровень взят).
    var progress: Double {
        guard tier != .legend else { return 1 }
        let next = thresholds[tier.rawValue]
        let previous = tier == .none ? 0 : thresholds[tier.rawValue - 1]
        return Double(value - previous) / Double(max(next - previous, 1))
    }

    var nextThreshold: Int? { tier == .legend ? nil : thresholds[tier.rawValue] }
}

enum AchievementEngine {
    static func make(stats: ModeStats, extras: ModeExtras?, turboRating: TurboRating?,
                     mode: StatsMode, heroName: (Int) -> String) -> [Achievement] {
        func record(_ field: String) -> Int { extras?.records.first { $0.id == field }?.raw ?? 0 }

        let played = stats.playedHeroes
        let mainHero = played.first
        let streak: Int = {
            if mode == .turbo, let turboRating { return turboRating.bestWinStreak }
            // Для других режимов — по последним 100 матчам (вся история слишком тяжёлая).
            var best = 0, current = 0
            for m in stats.recentMatches.reversed() {
                current = m.didWin ? current + 1 : 0
                best = max(best, current)
            }
            return best
        }()

        var list: [Achievement] = [
            Achievement(id: "veteran", title: "Ветеран", symbol: "shield.lefthalf.filled",
                        detail: "Матчей в режиме «\(mode.title)»", value: stats.games,
                        thresholds: [500, 1000, 2500, 5000]),
            Achievement(id: "winner", title: "Победитель", symbol: "trophy.fill",
                        detail: "Побед", value: stats.wins, thresholds: [250, 500, 1000, 2500]),
            Achievement(id: "main", title: "Мастер героя", symbol: "person.fill.checkmark",
                        detail: mainHero.map { "Игр на \(heroName($0.heroID))" } ?? "Игр на одном герое",
                        value: mainHero?.games ?? 0, thresholds: [50, 100, 250, 500]),
            Achievement(id: "collector", title: "Коллекционер", symbol: "square.grid.3x3.fill",
                        detail: "Разных героев", value: played.count, thresholds: [25, 50, 100, 120]),
            Achievement(id: "streak", title: "В огне", symbol: "flame.fill",
                        detail: mode == .turbo ? "Лучшая серия побед" : "Лучшая серия за последние 100 игр",
                        value: streak, thresholds: [5, 7, 10, 15]),
            Achievement(id: "killer", title: "Убийца", symbol: "scope",
                        detail: "Убийств за матч (рекорд)", value: record("kills"), thresholds: [15, 20, 30, 40]),
            Achievement(id: "rich", title: "Миллионер", symbol: "dollarsign.circle.fill",
                        detail: "Лучший GPM", value: record("gold_per_min"), thresholds: [800, 1200, 1800, 2500]),
            Achievement(id: "marathon", title: "Марафонец", symbol: "timer",
                        detail: "Самый долгий матч", value: record("duration") / 60,
                        thresholds: [45, 60, 75, 90], format: { "\($0) мин" })
        ]
        if mode == .turbo, let turboRating {
            list.append(Achievement(id: "climb", title: "Восхождение", symbol: "chart.line.uptrend.xyaxis",
                                    detail: "Турбо-рейтинг: Crusader → Archon → Legend → Ancient",
                                    value: turboRating.rating, thresholds: [1540, 2310, 3080, 3850]))
        }
        // Открытые — первыми, внутри по уровню.
        return list.sorted { ($0.tier, $0.progress) > ($1.tier, $1.progress) }
    }
}
