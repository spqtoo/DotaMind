//
//  StatsMode.swift
//  DotaMind
//

import Foundation

/// Какие матчи учитывать в статистике.
///
/// Важно: по умолчанию эндпоинты игрока в OpenDota считают только «significant»
/// матчи, а Turbo к ним не относится. Без `significant=0` запрос с `game_mode=23`
/// вернёт 0 игр даже у тех, кто играет только в Turbo.
enum StatsMode: String, CaseIterable, Identifiable, Sendable {
    case turbo
    case normal
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turbo: "Turbo"
        case .normal: "Обычные"
        case .all: "Все"
        }
    }

    var subtitle: String {
        switch self {
        case .turbo: "Только Turbo"
        case .normal: "All Pick, рейтинг и прочие стандартные режимы"
        case .all: "Все матчи, включая Turbo"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .turbo:
            [URLQueryItem(name: "game_mode", value: "23"), URLQueryItem(name: "significant", value: "0")]
        case .normal:
            [] // значение OpenDota по умолчанию: significant=1, Turbo исключён
        case .all:
            [URLQueryItem(name: "significant", value: "0")]
        }
    }

    /// Пороги «короткой» и «длинной» игры в минутах — в Turbo игры заметно быстрее.
    var durationBuckets: (short: Int, long: Int) {
        switch self {
        case .turbo: (20, 30)
        case .normal, .all: (30, 45)
        }
    }
}

enum SettingsKeys {
    static let defaultMode = "settings.defaultMode"
    static let tiltEnabled = "settings.cardTiltEnabled"
    static let hapticsEnabled = "haptics.isEnabled" // ключ из Haptics.swift
}

/// Название режима игры по ID OpenDota (для бейджей в списке матчей).
func gameModeName(_ id: Int?) -> String {
    switch id {
    case 1: "All Pick"
    case 2: "Captains Mode"
    case 3: "Random Draft"
    case 4: "Single Draft"
    case 5: "All Random"
    case 16: "Captains Draft"
    case 18: "Ability Draft"
    case 20: "All Random DM"
    case 21: "1v1 Mid"
    case 22: "All Pick"
    case 23: "Turbo"
    default: "Другой режим"
    }
}
