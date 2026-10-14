//
//  SteamID.swift
//  DotaMind
//

import Foundation

enum SteamID {
    private static let base: UInt64 = 76561197960265728

    /// SteamID64 → 32-битный account_id, который использует OpenDota и сама Dota.
    static func accountID(fromSteamID64 steam64: String) -> Int? {
        guard let v = UInt64(steam64), v > base else { return nil }
        return Int(v - base)
    }

    static func steamID64(fromAccountID id: Int) -> String {
        String(base + UInt64(id))
    }

    /// Понимает SteamID64, Friend ID из Доты (account_id) и ссылки
    /// вида steamcommunity.com/profiles/7656… или opendota.com/players/123….
    static func parse(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.host() != nil {
            let parts = url.pathComponents
            if let i = parts.firstIndex(where: { $0 == "profiles" || $0 == "players" }), i + 1 < parts.count {
                return parse(parts[i + 1])
            }
            return nil
        }
        guard !text.isEmpty, text.allSatisfy(\.isNumber), let n = UInt64(text) else { return nil }
        if n > base { return text }
        if n > 0, n < UInt64(UInt32.max) { return steamID64(fromAccountID: Int(n)) }
        return nil
    }
}
