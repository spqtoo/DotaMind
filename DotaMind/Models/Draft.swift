//
//  Draft.swift
//  DotaMind
//
//  Драфт-помощник: по твоей личной статистике советует, кого взять
//  против выбранных врагов (и с выбранными союзниками). Чистые функции.
//
//  Данные: /players/{id}/heroes в выбранном режиме — общий винрейт на
//  каждом герое, и тот же запрос с against_hero_id=<враг> / with_hero_id=<союзник>
//  для каждого выбранного героя по отдельности.
//

import Foundation

struct DraftSuggestion: Identifiable, Sendable {
    struct Reason: Identifiable, Sendable {
        let heroID: Int        // враг или союзник
        let isEnemy: Bool
        let games: Int
        let wins: Int
        var id: String { "\(isEnemy ? "e" : "a")\(heroID)" }
    }

    let heroID: Int
    let score: Double          // ожидаемый винрейт 0…1
    let baseWinrate: Double    // общий винрейт на герое (сглаженный)
    let games: Int             // всего игр на герое
    let reasons: [Reason]      // матчи против/вместе с выбранными
    var id: Int { heroID }
}

enum DraftEngine {
    /// Сглаживание к 50 %: как будто у каждого героя есть ещё `prior` игр с винрейтом 50 %.
    /// Без этого 2 из 2 побед (100 %) обгоняли бы 200 игр с 58 %.
    static let prior = 10.0
    static let minimumGames = 5

    static func smoothed(wins: Int, games: Int) -> Double {
        (Double(wins) + prior * 0.5) / (Double(games) + prior)
    }

    /// - overall: все герои игрока в режиме
    /// - versus: для каждого выбранного врага — твои герои в матчах против него
    /// - with: для каждого выбранного союзника — твои герои в матчах вместе с ним
    /// - excluded: уже занятые герои (враги, союзники, баны)
    static func suggest(overall: [HeroRecord],
                        versus: [Int: [HeroRecord]],
                        with allies: [Int: [HeroRecord]],
                        excluded: Set<Int>,
                        limit: Int = 10) -> [DraftSuggestion] {
        let candidates = overall.filter { $0.games >= minimumGames && !excluded.contains($0.heroID) }
        return candidates.map { hero -> DraftSuggestion in
            let base = smoothed(wins: hero.wins, games: hero.games)
            var deltas: [Double] = []
            var reasons: [DraftSuggestion.Reason] = []

            for (enemy, records) in versus {
                guard let r = records.first(where: { $0.heroID == hero.heroID }), r.games > 0 else { continue }
                // Отклонение от твоего обычного винрейта на герое; сглаживаем к нему же.
                let vs = (Double(r.wins) + prior * base) / (Double(r.games) + prior)
                deltas.append(vs - base)
                reasons.append(.init(heroID: enemy, isEnemy: true, games: r.games, wins: r.wins))
            }
            for (ally, records) in allies {
                guard let r = records.first(where: { $0.heroID == hero.heroID }), r.games > 0 else { continue }
                let with = (Double(r.wins) + prior * base) / (Double(r.games) + prior)
                deltas.append(with - base)
                reasons.append(.init(heroID: ally, isEnemy: false, games: r.games, wins: r.wins))
            }

            let score = base + deltas.reduce(0, +)
            return DraftSuggestion(heroID: hero.heroID, score: score.clamped(to: 0...1), baseWinrate: base,
                                   games: hero.games, reasons: reasons.sorted { $0.games > $1.games })
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }
}
