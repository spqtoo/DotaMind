//
//  TurboRating.swift
//  DotaMind
//
//  Гипотетический рейтинг для Turbo: Valve его не считает, поэтому
//  оцениваем по Elo. Соперник в каждом матче — средний ранг лобби
//  (average_rank из OpenDota), результат — победа/поражение.
//  Чистые функции: без сети и UI.
//

import Foundation

struct TurboRating: Sendable {
    struct Point: Identifiable, Sendable {
        let date: Date
        let rating: Int
        var id: Date { date }
    }

    let rating: Int
    let games: Int
    let lobbyAverage: Int       // средний MMR лобби за последние 100 игр
    let change30Days: Int?      // изменение за 30 дней
    let bestWinStreak: Int      // лучшая серия побед за всю историю Turbo
    let history: [Point]        // по неделе — последнее значение недели

    var rank: Rank { Rank(tier: RankMMR.tier(forMMR: rating), leaderboard: nil) }
}

/// Перевод медалей в MMR и обратно (приблизительная сетка Valve:
/// 770 MMR на медаль, ~154 на звезду; Divine — по 200, Immortal от 5 620).
enum RankMMR {
    static func mmr(forTier tier: Int) -> Int {
        let medal = tier / 10, star = max(tier % 10, 1)
        switch medal {
        case 8...: return 5620
        case 7: return 4620 + (star - 1) * 200 + 100
        default: return (max(medal, 1) - 1) * 770 + (star - 1) * 154 + 77
        }
    }

    static func tier(forMMR mmr: Int) -> Int {
        if mmr >= 5620 { return 80 }
        if mmr >= 4620 { return 70 + min(5, (mmr - 4620) / 200 + 1) }
        let clamped = max(mmr, 0)
        return (clamped / 770 + 1) * 10 + min(5, (clamped % 770) / 154 + 1)
    }
}

enum TurboRatingEngine {
    /// Минимум матчей с рангом лобби, чтобы оценка что-то значила.
    static let minimumGames = 30

    static func compute(_ results: [OpenDotaDTO.MatchResult], now: Date = .now) -> TurboRating? {
        let matches = results
            .filter { ($0.average_rank ?? 0) > 0 }
            .sorted { $0.start_time < $1.start_time }
        guard matches.count >= minimumGames else { return nil }

        // Старт — средний MMR лобби первых 20 игр: так рейтинг не «разгоняется» с нуля.
        var rating = Double(matches.prefix(20).reduce(0) { $0 + RankMMR.mmr(forTier: $1.average_rank!) }) / 20
        var weekly: [Date: Int] = [:]
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let monthAgo = now.addingTimeInterval(-30 * 24 * 3600)
        var ratingMonthAgo: Double?
        var streak = 0, bestStreak = 0

        for (index, m) in matches.enumerated() {
            let lobby = Double(RankMMR.mmr(forTier: m.average_rank!))
            let didWin = (m.radiant_win ?? false) == ((m.player_slot ?? 0) < 128)
            let expected = 1 / (1 + pow(10, (lobby - rating) / 400))
            // Калибровка: первые 100 игр — быстрее, дальше — как ~25 MMR за игру.
            let k: Double = index < 100 ? 40 : 25
            let date = Date(timeIntervalSince1970: TimeInterval(m.start_time))
            if date < monthAgo { ratingMonthAgo = rating }
            rating += k * ((didWin ? 1 : 0) - expected)
            streak = didWin ? streak + 1 : 0
            bestStreak = max(bestStreak, streak)
            if let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start {
                weekly[week] = Int(rating.rounded())
            }
        }

        let recent = matches.suffix(100)
        let lobbyAverage = recent.reduce(0) { $0 + RankMMR.mmr(forTier: $1.average_rank!) } / recent.count
        let history = weekly.map { TurboRating.Point(date: $0.key, rating: $0.value) }
            .sorted { $0.date < $1.date }
            .suffix(26) // полгода

        return TurboRating(
            rating: Int(rating.rounded()),
            games: matches.count,
            lobbyAverage: lobbyAverage,
            change30Days: ratingMonthAgo.map { Int((rating - $0).rounded()) },
            bestWinStreak: bestStreak,
            history: Array(history)
        )
    }
}
