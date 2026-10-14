//
//  MatchNotifier.swift
//  DotaMind
//
//  Уведомление после матча: «Победа · Troll Warlord · 12/3/9 · Турбо-рейтинг ≈1440 (+12)».
//  Фоновое обновление (BGAppRefresh) iOS запускает само, когда сочтёт нужным —
//  обычно раз в 20–60 минут, если приложением пользуются. Точного времени нет.
//
//  ANDROID (Material 3): WorkManager PeriodicWorkRequest (15+ мин) + NotificationCompat,
//  канал «Матчи»; на Android 13+ нужно разрешение POST_NOTIFICATIONS.
//

import BackgroundTasks
import Foundation
import UserNotifications

enum MatchNotifier {
    static let taskID = "spqtoo.DotaMind.refresh"
    static let enabledKey = "settings.notifyMatches"
    private static let lastMatchKey = "notifier.lastMatchID"
    private static let lastRatingKey = "notifier.lastTurboRating"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func schedule() {
        guard isEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Проверка новых матчей. Вызывается из фоновой задачи (DotaMindApp).
    static func check() async {
        schedule() // следующая проверка
        guard isEnabled,
              let steamID = try? KeychainStorage.shared.getString(for: .steamID64),
              let account = SteamID.accountID(fromSteamID64: steamID) else { return }
        let client = OpenDotaClient.shared
        guard let latest = try? await client.matches(account, mode: .all, limit: 5, policy: .reload),
              let newest = latest.map(\.match_id).max() else { return }

        let defaults = UserDefaults.standard
        let lastSeen = defaults.integer(forKey: lastMatchKey)
        defaults.set(newest, forKey: lastMatchKey)
        // Первый запуск — только запоминаем, чтобы не засыпать старыми матчами.
        guard lastSeen > 0 else { return }
        let fresh = latest.filter { $0.match_id > lastSeen }.sorted { $0.start_time < $1.start_time }.suffix(3)
        guard !fresh.isEmpty else { return }

        let names = (try? await client.heroStats()).map { Dictionary(uniqueKeysWithValues: $0.map { ($0.id, $0.localized_name) }) } ?? [:]

        var ratingLine: String?
        if fresh.contains(where: { $0.game_mode == 23 }),
           let history = try? await client.turboHistory(account, policy: .reload),
           let rating = TurboRatingEngine.compute(history) {
            let previous = defaults.object(forKey: lastRatingKey) as? Int
            defaults.set(rating.rating, forKey: lastRatingKey)
            let delta = previous.map { rating.rating - $0 }
            ratingLine = "Турбо-рейтинг ≈\(rating.rating)" + (delta.map { $0 == 0 ? "" : " (\($0 > 0 ? "+" : "")\($0))" } ?? "")
        }

        for (index, m) in fresh.enumerated() {
            let match = MatchSummary(m)
            let content = UNMutableNotificationContent()
            content.title = "\(match.didWin ? "Победа" : "Поражение") · \(names[match.heroID] ?? "Матч")"
            var body = "\(match.kills)/\(match.deaths)/\(match.assists) · \(gameModeName(match.gameMode)) · \(Format.duration(match.duration))"
            if index == fresh.count - 1, let ratingLine { body += "\n" + ratingLine }
            content.body = body
            content.sound = .default
            content.threadIdentifier = "matches"
            content.userInfo = ["matchID": match.id]
            let request = UNNotificationRequest(identifier: "match-\(match.id)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
