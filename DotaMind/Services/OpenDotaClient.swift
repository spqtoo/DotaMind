//
//  OpenDotaClient.swift
//  DotaMind
//

import CryptoKit
import Foundation

enum OpenDotaError: LocalizedError {
    case badStatus(Int)
    case rateLimited
    case notCached

    var errorDescription: String? {
        switch self {
        case .rateLimited: "OpenDota ограничивает частоту запросов. Подожди минуту и обнови."
        case .badStatus(let code): "OpenDota ответил ошибкой \(code)."
        case .notCached: "Нет сохранённых данных."
        }
    }
}

enum CachePolicy: Sendable {
    /// Свежий кэш (до 5 минут) или сеть; при ошибке сети — старый кэш или снимок.
    case normal
    /// Только сохранённое на диске, любой давности. Для мгновенного показа при запуске.
    case cacheOnly
    /// Всегда сеть (pull-to-refresh); при ошибке — как .normal.
    case reload
}

/// Клиент OpenDota. Ответы хранятся в памяти и на диске (Caches/opendota),
/// поэтому повторный запуск показывает прошлые данные мгновенно, пока свежие
/// догружаются. Без API-ключа лимит ~60 запросов в минуту.
// ANDROID: Ktor/Retrofit + kotlinx.serialization; кэш — OkHttp Cache + файлы в cacheDir (как Caches/opendota). CachePolicy перенести как есть.
actor OpenDotaClient {
    static let shared = OpenDotaClient()

    private let base = URL(string: "https://api.opendota.com/api")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var memory: [URL: (date: Date, data: Data)] = [:]
    private let ttl: TimeInterval = 5 * 60
    private let diskDirectory = URL.cachesDirectory.appending(path: "opendota", directoryHint: .isDirectory)

    /// Дата офлайн-снимка, если последний ответ пришёл из DemoData, иначе nil.
    private(set) var snapshotDate: Date?

    init() {
        let config = URLSessionConfiguration.default
        // /totals по большому числу матчей OpenDota иногда считает дольше 30 с.
        config.timeoutIntervalForRequest = 90
        session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Эндпоинты игрока

    func player(_ accountID: Int, policy: CachePolicy = .normal) async throws -> OpenDotaDTO.Player {
        try await get("players/\(accountID)", policy: policy)
    }

    func winLoss(_ accountID: Int, mode: StatsMode, extra: [URLQueryItem] = [], policy: CachePolicy = .normal) async throws -> OpenDotaDTO.WL {
        try await get("players/\(accountID)/wl", mode.queryItems + extra, policy: policy)
    }

    func heroes(_ accountID: Int, mode: StatsMode, extra: [URLQueryItem] = [], policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.PlayerHero] {
        try await get("players/\(accountID)/heroes", mode.queryItems + extra, policy: policy)
    }

    func totals(_ accountID: Int, mode: StatsMode, extra: [URLQueryItem] = [], policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.Total] {
        try await get("players/\(accountID)/totals", mode.queryItems + extra, policy: policy)
    }

    func counts(_ accountID: Int, mode: StatsMode, policy: CachePolicy = .normal) async throws -> OpenDotaDTO.Counts {
        try await get("players/\(accountID)/counts", mode.queryItems, policy: policy)
    }

    func peers(_ accountID: Int, mode: StatsMode, policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.Peer] {
        try await get("players/\(accountID)/peers", mode.queryItems, policy: policy)
    }

    func matches(_ accountID: Int, mode: StatsMode, limit: Int, extra: [URLQueryItem] = [], policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.Match] {
        try await get("players/\(accountID)/matches",
                      mode.queryItems + extra + [URLQueryItem(name: "limit", value: String(limit))],
                      policy: policy)
    }

    /// Лучший матч игрока по полю (рекорд): сортировка по убыванию, один матч.
    func record(_ accountID: Int, mode: StatsMode, field: String, policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.RecordMatch] {
        try await get("players/\(accountID)/matches", mode.queryItems + [
            URLQueryItem(name: "sort", value: field),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "project", value: field),
            URLQueryItem(name: "project", value: "hero_id"),
            URLQueryItem(name: "project", value: "start_time")
        ], policy: policy)
    }

    /// Результаты всех матчей за `days` дней — для графика формы. Лёгкий ответ: 3 поля.
    func results(_ accountID: Int, mode: StatsMode, days: Int, policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.MatchResult] {
        try await get("players/\(accountID)/matches", mode.queryItems + [
            URLQueryItem(name: "date", value: String(days)),
            URLQueryItem(name: "project", value: "start_time")
        ], policy: policy)
    }

    /// Все Turbo-матчи с рангом лобби — сырьё для турбо-рейтинга (~400 КБ на 3 000 игр).
    func turboHistory(_ accountID: Int, policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.MatchResult] {
        try await get("players/\(accountID)/matches", StatsMode.turbo.queryItems + [
            URLQueryItem(name: "project", value: "average_rank"),
            URLQueryItem(name: "project", value: "start_time")
        ], policy: policy)
    }

    /// Матчи на герое с итоговыми предметами — для «с чем ты чаще выигрываешь».
    func heroItems(_ accountID: Int, mode: StatsMode, heroID: Int, policy: CachePolicy = .normal) async throws -> [OpenDotaDTO.MatchWithItems] {
        try await get("players/\(accountID)/matches", mode.queryItems + [
            URLQueryItem(name: "hero_id", value: String(heroID)),
            URLQueryItem(name: "limit", value: "100")
        ] + (0...5).map { URLQueryItem(name: "project", value: "item_\($0)") }, policy: policy)
    }

    func match(_ matchID: Int, policy: CachePolicy = .normal) async throws -> OpenDotaDTO.MatchDetail {
        try await get("matches/\(matchID)", policy: policy)
    }

    /// Перцентили показателей всех игроков на герое (для сравнения «ты против всех»).
    func benchmarks(heroID: Int) async throws -> OpenDotaDTO.Benchmarks {
        try await get("benchmarks", [URLQueryItem(name: "hero_id", value: String(heroID))], policy: .normal)
    }

    /// Просит OpenDota разобрать реплей матча (графики золота, тайминги). Занимает минуты.
    func requestParse(_ matchID: Int) async throws {
        var request = URLRequest(url: base.appending(path: "request/\(matchID)"))
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try check(response)
        memory = memory.filter { $0.key.path().hasSuffix("matches/\(matchID)") == false }
    }

    /// Справочник предметов (~350 КБ) — неделя на диске.
    func items() async throws -> [String: OpenDotaDTO.ItemConstant] {
        let url = base.appending(path: "constants/items")
        if let disk = readDisk(url), Date().timeIntervalSince(disk.date) < 7 * 24 * 3600,
           let items = try? decoder.decode([String: OpenDotaDTO.ItemConstant].self, from: disk.data) {
            return items
        }
        return try await get("constants/items", policy: .reload)
    }

    /// Просит OpenDota заново подтянуть историю матчей игрока из Steam.
    func requestHistoryRefresh(_ accountID: Int) async throws {
        var request = URLRequest(url: base.appending(path: "players/\(accountID)/refresh"))
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try check(response)
        memory.removeAll()
    }

    // MARK: - Справочник героев

    /// /heroStats весит ~1 МБ и меняется только с патчами — неделя на диске.
    func heroStats() async throws -> [OpenDotaDTO.HeroStat] {
        let url = base.appending(path: "heroStats")
        if let disk = readDisk(url), Date().timeIntervalSince(disk.date) < 7 * 24 * 3600,
           let heroes = try? decoder.decode([OpenDotaDTO.HeroStat].self, from: disk.data) {
            return heroes
        }
        return try await get("heroStats", policy: .reload)
    }

    func clearCache() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Кэш и сеть

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = [], policy: CachePolicy) async throws -> T {
        var url = base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }

        switch policy {
        case .cacheOnly:
            if let hit = memory[url] ?? readDisk(url) { return try decoder.decode(T.self, from: hit.data) }
            if let data = DemoData.apiResponse(for: url), DemoData.isForced { return try decoder.decode(T.self, from: data) }
            throw OpenDotaError.notCached
        case .normal:
            if let hit = memory[url], Date().timeIntervalSince(hit.date) < ttl {
                return try decoder.decode(T.self, from: hit.data)
            }
        case .reload:
            break
        }

        let data = try await fetch(url)
        let value = try decoder.decode(T.self, from: data)
        memory[url] = (Date(), data)
        if snapshotDate == nil { writeDisk(url, data) }
        return value
    }

    private func fetch(_ url: URL) async throws -> Data {
        if DemoData.isForced, let data = DemoData.apiResponse(for: url) {
            snapshotDate = DemoData.createdAt
            return data
        }
        do {
            let (data, response) = try await session.data(from: url)
            try check(response)
            snapshotDate = nil
            return data
        } catch let error as URLError where error.code != .cancelled {
            // Нет сети: сначала свои сохранённые ответы, потом офлайн-снимок.
            if let disk = readDisk(url) { return disk.data }
            guard let data = DemoData.apiResponse(for: url) else { throw error }
            snapshotDate = DemoData.createdAt
            return data
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 { throw OpenDotaError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw OpenDotaError.badStatus(http.statusCode) }
    }

    private func diskURL(_ url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appending(path: hash + ".json")
    }

    private func readDisk(_ url: URL) -> (date: Date, data: Data)? {
        let file = diskURL(url)
        guard let data = try? Data(contentsOf: file),
              let date = (try? FileManager.default.attributesOfItem(atPath: file.path()))?[.modificationDate] as? Date
        else { return nil }
        return (date, data)
    }

    private func writeDisk(_ url: URL, _ data: Data) {
        try? data.write(to: diskURL(url), options: .atomic)
    }
}
