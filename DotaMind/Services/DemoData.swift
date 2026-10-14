//
//  DemoData.swift
//  DotaMind
//
//  Офлайн-снимок ответов OpenDota и картинок (DemoData/, собирается
//  Scripts/make_demo_data.py). Нужен, когда сети нет — например, в
//  симуляторе со сломанным DNS. Ответы ищутся по нормализованному ключу
//  «путь после /api/ + отсортированные параметры».
//

import Foundation

enum DemoData {
    private struct Manifest: Decodable {
        let api: [String: String]
        let images: [String: String]
        let account_id: Int
        let created: TimeInterval
    }

    private static let manifest: Manifest? = {
        guard let url = Bundle.main.url(forResource: "demo_manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()

    /// Запуск с `-DMOffline YES` — сразу брать снимок, не ходя в сеть.
    static var isForced: Bool { UserDefaults.standard.bool(forKey: "DMOffline") }

    static var accountID: Int? { manifest?.account_id }
    static var createdAt: Date? { manifest.map { Date(timeIntervalSince1970: $0.created) } }

    static func apiResponse(for url: URL) -> Data? {
        guard let name = manifest?.api[key(for: url)] else { return nil }
        return file(name).flatMap { try? Data(contentsOf: $0) }
    }

    static func localImage(for remote: URL) -> URL? {
        manifest?.images[remote.absoluteString].flatMap(file)
    }

    static func key(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = (components?.path ?? "").replacingOccurrences(of: "/api/", with: "")
        let query = (components?.queryItems ?? [])
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return query.isEmpty ? path : "\(path)?\(query)"
    }

    private static func file(_ name: String) -> URL? {
        let ns = name as NSString
        return Bundle.main.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension)
    }
}
