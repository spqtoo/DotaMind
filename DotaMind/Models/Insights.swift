//
//  Insights.swift
//  DotaMind
//
//  Советы на основе статистики игрока. Чистые функции — без сети и UI.
//

import Foundation

struct Insight: Identifiable, Sendable {
    enum Tone: Sendable { case positive, negative, neutral }

    let id: String
    let symbol: String
    let tone: Tone
    let title: String
    let detail: String
    var heroID: Int? = nil
}

enum InsightEngine {
    static func make(stats: ModeStats, mode: StatsMode, heroName: (Int) -> String) -> [Insight] {
        var result: [Insight] = []

        // 1. Текущая серия.
        if let first = stats.recentMatches.first {
            let streak = stats.recentMatches.prefix { $0.didWin == first.didWin }.count
            if streak >= 3 {
                result.append(first.didWin
                    ? Insight(id: "streak", symbol: "flame.fill", tone: .positive,
                              title: "\(streak) \(plural(streak, "победа", "победы", "побед")) подряд",
                              detail: "Ты в потоке — самое время для любимых героев.")
                    : Insight(id: "streak", symbol: "cloud.rain.fill", tone: .negative,
                              title: "\(streak) \(plural(streak, "поражение", "поражения", "поражений")) подряд",
                              detail: "Тильт — главный враг винрейта. Сделай паузу или смени героя."))
            }
        }

        // 2. В форме за последние 30 дней.
        if let hot = (stats.details?.heroesLast30Days ?? []).filter({ $0.games >= 5 }).max(by: { $0.winrate < $1.winrate }),
           hot.winrate >= 0.55 {
            result.append(Insight(id: "hot", symbol: "chart.line.uptrend.xyaxis", tone: .positive,
                                  title: "В форме: \(heroName(hot.heroID))",
                                  detail: "\(percent(hot.winrate)) побед за 30 дней (\(hot.games) \(plural(hot.games, "игра", "игры", "игр"))).",
                                  heroID: hot.heroID))
        }

        // 3. Сильнейший герой на дистанции.
        let solid = stats.heroes.filter { $0.games >= 30 }
        if let best = solid.max(by: { $0.winrate < $1.winrate }), best.winrate >= 0.52 {
            result.append(Insight(id: "best", symbol: "crown.fill", tone: .positive,
                                  title: "Сильнейший герой: \(heroName(best.heroID))",
                                  detail: "\(percent(best.winrate)) на \(best.games) играх. Бери, когда нужна победа.",
                                  heroID: best.heroID))
        }

        // 4. Герой, который не идёт.
        if let worst = stats.heroes.filter({ $0.games >= 20 }).min(by: { $0.winrate < $1.winrate }),
           worst.winrate < 0.47 {
            result.append(Insight(id: "worst", symbol: "exclamationmark.triangle.fill", tone: .negative,
                                  title: "\(heroName(worst.heroID)) даётся тяжело",
                                  detail: "\(percent(worst.winrate)) на \(worst.games) играх. Посмотри билды или отложи героя.",
                                  heroID: worst.heroID))
        }

        // 5. Неудобный противник.
        if let nemesis = stats.heroes.filter({ $0.againstGames >= 30 }).min(by: { $0.againstWinrate < $1.againstWinrate }),
           nemesis.againstWinrate < 0.46 {
            result.append(Insight(id: "nemesis", symbol: "bolt.shield.fill", tone: .negative,
                                  title: "Против \(heroName(nemesis.heroID)) — \(percent(nemesis.againstWinrate))",
                                  detail: "\(nemesis.againstGames) игр против. Стоит продумать контрпик и предметы под него.",
                                  heroID: nemesis.heroID))
        }

        // 6. Лучший тиммейт.
        if let mate = (stats.details?.peers ?? []).filter({ $0.games >= 10 }).max(by: { $0.winrate < $1.winrate }), mate.winrate >= 0.5 {
            result.append(Insight(id: "peer", symbol: "person.2.fill", tone: .positive,
                                  title: "Лучший тиммейт: \(mate.name)",
                                  detail: "\(percent(mate.winrate)) побед в \(mate.games) \(plural(mate.games, "игре", "играх", "играх")) вместе. Зови в пати."))
        }

        // 7. Короткие против длинных игр.
        let (shortLimit, longLimit) = mode.durationBuckets
        let short = stats.recentMatches.filter { $0.duration < TimeInterval(shortLimit * 60) }
        let long = stats.recentMatches.filter { $0.duration >= TimeInterval(longLimit * 60) }
        if short.count >= 8, long.count >= 8 {
            let s = winrate(short), l = winrate(long)
            if abs(s - l) >= 0.08 {
                result.append(Insight(id: "duration", symbol: "timer", tone: .neutral,
                                      title: s > l ? "Ты силён в быстрых играх" : "Ты силён в затяжных играх",
                                      detail: "До \(shortLimit) мин — \(percent(s)), после \(longLimit) мин — \(percent(l)). "
                                        + (s > l ? "Играй агрессивнее и закрывай раньше." : "Не форсируй: твоя игра — лейт.")))
            }
        }

        // 8. Сторона карты.
        if let details = stats.details, details.radiant.games >= 30, details.dire.games >= 30,
           let r = details.radiant.winrate, let d = details.dire.winrate {
            if abs(r - d) >= 0.04 {
                result.append(Insight(id: "side", symbol: r > d ? "sun.max.fill" : "moon.stars.fill", tone: .neutral,
                                      title: r > d ? "За Radiant ты играешь лучше" : "За Dire ты играешь лучше",
                                      detail: "Radiant — \(percent(r)), Dire — \(percent(d))."))
            }
        }

        return result
    }

    private static func winrate(_ matches: [MatchSummary]) -> Double {
        matches.isEmpty ? 0 : Double(matches.filter(\.didWin).count) / Double(matches.count)
    }
}

func percent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0)))
}

/// Русское склонение: 1 игра, 2 игры, 5 игр.
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}
