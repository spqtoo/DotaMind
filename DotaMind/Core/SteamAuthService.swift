// SteamAuthService.swift
import Foundation
import AuthenticationServices
import UIKit

// Сервис авторизации через Steam OpenID.
// Здесь важна корректная презентация ASWebAuthenticationSession (main thread).
// ANDROID: Steam OpenID через Custom Tabs + intent-filter на dotamind://auth/steam.
final class SteamAuthService: NSObject {
    @MainActor static let shared = SteamAuthService()

    // В Info.plist добавь URL Types → URL Schemes: "dotamind"
    private let callbackScheme = "dotamind"
    private let callbackPath = "auth/steam"

    private var session: ASWebAuthenticationSession?

    // Окно-якорь для презентации веб-сессии (важно для iPad и сцен с несколькими окнами).
    private weak var anchorWindow: ASPresentationAnchor?

    // На время разработки возвращаем заглушку SteamID.
    // TODO: выключить, когда реальный OpenID-вход будет проверен на устройстве.
    // Steam может не принять кастомную схему в openid.return_to — тогда нужен https-редирект.
    static let useStub = true
    static let stubSteamID64 = "76561199211436527"

    @MainActor
    func signIn() async throws -> String {
        if Self.useStub { return Self.stubSteamID64 }

        let returnURL = "\(callbackScheme)://\(callbackPath)"
        let realm = "\(callbackScheme)://"

        var comps = URLComponents(string: "https://steamcommunity.com/openid/login")!
        comps.queryItems = [
            .init(name: "openid.ns", value: "http://specs.openid.net/auth/2.0"),
            .init(name: "openid.mode", value: "checkid_setup"),
            .init(name: "openid.return_to", value: returnURL),
            .init(name: "openid.realm", value: realm),
            .init(name: "openid.identity", value: "http://specs.openid.net/auth/2.0/identifier_select"),
            .init(name: "openid.claimed_id", value: "http://specs.openid.net/auth/2.0/identifier_select")
        ]
        let authURL = comps.url!

        // Якорь для презентации — ключевое окно активной сцены.
        self.anchorWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, err in
                if let err = err {
                    continuation.resume(throwing: err)
                    return
                }
                guard
                    let url = url,
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                    let claimed = items.first(where: { $0.name == "openid.claimed_id" })?.value
                else {
                    continuation.resume(throwing: NSError(domain: "SteamAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid callback"]))
                    return
                }

                // claimed_id выглядит как https://steamcommunity.com/openid/id/7656119...
                guard let steamID = claimed.components(separatedBy: "/").last, steamID.allSatisfy({ $0.isNumber }) else {
                    continuation.resume(throwing: NSError(domain: "SteamAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "SteamID not found"]))
                    return
                }

                // Для продакшена стоит дополнительно верифицировать openid.sig через check_authentication.
                continuation.resume(returning: steamID)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            _ = session.start()
        }
    }
}

@MainActor
extension SteamAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 1) Пробуем окно, из которого был запущен логин
        if let w = anchorWindow {
            return w
        }
        // 2) Иначе — активная сцена и её ключевое окно
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return window
        }
        // 3) Фоллбек: главное окно приложения, если доступно
        // 3) Как крайняя мера — первое окно любой сцены или новое окно на ней
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first {
            return window
        }
        return ASPresentationAnchor(windowScene: scenes.first!)
    }
}

