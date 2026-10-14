// AuthManager.swift
import Foundation
import Observation
import UIKit

// Менеджер авторизации.
// Хранит текущий SteamID64 в Keychain; SwiftUI следит за ним через @Observable.
@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    // Текущий SteamID64 (nil, если не авторизованы).
    private(set) var steamID64: String?
    private(set) var isSigningIn = false
    var lastError: String?

    var isLoggedIn: Bool { steamID64 != nil }

    private init() {
        // Восстанавливаем из Keychain при старте — операция быстрая.
        self.steamID64 = try? KeychainStorage.shared.getString(for: .steamID64)
        #if DEBUG
        // Для симулятора и скриншотов: запуск с аргументом `-DMSteamID <SteamID64>`.
        if let forced = UserDefaults.standard.string(forKey: "DMSteamID") {
            self.steamID64 = forced
        }
        #endif
    }

    // Вход через Steam OpenID.
    func signInWithSteam() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let id = try await SteamAuthService.shared.signIn()
            await store(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // Вход по введённому SteamID / Friend ID / ссылке на профиль.
    func signIn(steamID64 id: String) async {
        await store(id)
    }

    // Выход: удаляем ключ и сбрасываем состояние.
    func signOut() {
        try? KeychainStorage.shared.remove(.steamID64)
        steamID64 = nil
    }

    private func store(_ id: String) async {
        do {
            // Keychain не требует главного потока — пишем на фоне.
            try await Task.detached(priority: .utility) {
                try KeychainStorage.shared.setString(id, for: .steamID64)
            }.value
            steamID64 = id
            lastError = nil
        } catch {
            lastError = "Не удалось сохранить вход: \(error.localizedDescription)"
        }
    }
}
