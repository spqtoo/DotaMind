//
//  PlayerStore.swift
//  DotaMind
//
//  Единый источник данных игрока для всех вкладок.
//  Держит профиль, справочник героев и статистику по каждому режиму.
//

import Foundation
import Observation

enum Loadable<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }
}

// ANDROID: ViewModel + StateFlow<UiState>; async let → coroutineScope { async {} }. Один ViewModel на аккаунт, общий для вкладок (activity-scoped).
@MainActor
@Observable
final class PlayerStore {
    let steamID64: String
    let accountID: Int

    private(set) var mode: StatsMode
    private(set) var summary: Loadable<PlayerSummary> = .idle
    private(set) var stats: [StatsMode: Loadable<ModeStats>] = [:]
    private(set) var heroes: [Int: Hero] = [:]
    private(set) var items: [Int: Item] = [:]
    private(set) var extras: [StatsMode: ModeExtras] = [:]
    /// Оценка рейтинга в Turbo (не зависит от выбранного режима).
    private(set) var turboRating: TurboRating?
    /// Не nil, если показываем офлайн-снимок вместо живых данных.
    private(set) var snapshotDate: Date?

    private let client = OpenDotaClient.shared

    init(steamID64: String, mode: StatsMode) {
        self.steamID64 = steamID64
        self.accountID = SteamID.accountID(fromSteamID64: steamID64) ?? 0
        self.mode = mode
    }

    var currentStats: Loadable<ModeStats> { stats[mode] ?? .idle }

    func hero(_ id: Int) -> Hero { heroes[id] ?? Hero(unknownID: id) }
    func item(_ id: Int?) -> Item? { id.flatMap { items[$0] } }
    var currentExtras: ModeExtras? { extras[mode] }

    /// Арт самого играемого героя в текущем режиме — для фона экранов.
    var signatureArt: URL? {
        currentStats.value?.heroes.first { $0.games > 0 }.flatMap { hero($0.heroID).imageURL }
    }

    func insights() -> [Insight] {
        guard let s = currentStats.value else { return [] }
        return InsightEngine.make(stats: s, mode: mode) { hero($0).name }
    }

    // MARK: - Загрузка

    /// Идёт ли сетевое обновление поверх уже показанных данных.
    private(set) var isRefreshing = false

    func setMode(_ newMode: StatsMode) async {
        guard newMode != mode else { return }
        mode = newMode
        if stats[newMode]?.value == nil {
            await loadStats(policy: .cacheOnly)
            await loadExtras(policy: .cacheOnly)
        }
        await refresh(policy: .normal)
    }

    /// Первая загрузка экрана: ничего не делает, если данные уже есть.
    func loadIfNeeded() async {
        if case .idle = summary { await loadAll(policy: .normal) }
        else if case .idle = currentStats { await loadAll(policy: .normal) }
    }

    /// Сначала мгновенно показываем сохранённое на диске, затем обновляем из сети.
    func loadAll(policy: CachePolicy) async {
        if policy != .reload {
            async let s: Void = loadSummary(policy: .cacheOnly)
            async let m: Void = loadStats(policy: .cacheOnly)
            _ = await (s, m)
            await loadExtras(policy: .cacheOnly)
            await loadTurboRating(policy: .cacheOnly)
        }
        await refresh(policy: policy)
    }

    private func refresh(policy: CachePolicy) async {
        isRefreshing = true
        async let s: Void = loadSummary(policy: policy)
        async let h: Void = loadHeroes()
        async let i: Void = loadItems()
        async let m: Void = loadStats(policy: policy)
        _ = await (s, h, i, m)
        async let e: Void = loadExtras(policy: policy)
        async let r: Void = loadTurboRating(policy: policy)
        _ = await (e, r)
        isRefreshing = false
        snapshotDate = await client.snapshotDate
    }

    private func loadHeroes() async {
        guard heroes.isEmpty, let list = try? await client.heroStats() else { return }
        heroes = Dictionary(uniqueKeysWithValues: list.map { ($0.id, Hero($0)) })
    }

    /// Дождаться справочников героев и предметов (нужны для имён и картинок).
    func ensureCatalogs() async {
        async let h: Void = loadHeroes()
        async let i: Void = loadItems()
        _ = await (h, i)
    }

    private func loadItems() async {
        guard items.isEmpty, let dto = try? await client.items() else { return }
        items = Item.catalog(dto)
    }

    /// График формы за 12 недель и личные рекорды. Не критично — без ошибок на экране.
    private func loadExtras(policy: CachePolicy) async {
        let mode = self.mode, id = accountID, client = self.client
        async let results = try? client.results(id, mode: mode, days: 84, policy: policy)
        let records = await withTaskGroup(of: PlayerRecord?.self) { group in
            for spec in PlayerRecord.fields {
                group.addTask {
                    guard let m = try? await client.record(id, mode: mode, field: spec.field, policy: policy).first,
                          let raw = spec.format(m), raw > 0 else { return nil }
                    let value = spec.field == "duration" ? Format.duration(TimeInterval(raw)) : raw.formatted()
                    return PlayerRecord(id: spec.field, title: spec.title, value: value, raw: raw, heroID: m.hero_id,
                                        matchID: m.match_id,
                                        date: m.start_time.map { Date(timeIntervalSince1970: TimeInterval($0)) })
                }
            }
            var list: [PlayerRecord] = []
            for await r in group { if let r { list.append(r) } }
            return list
        }
        let party = await withTaskGroup(of: PartyRecord?.self) { group in
            for size in 1...5 {
                group.addTask {
                    guard let wl = try? await client.winLoss(id, mode: mode, extra: [URLQueryItem(name: "party_size", value: String(size))],
                                                             policy: policy),
                          wl.win + wl.lose > 0 else { return nil }
                    return PartyRecord(size: size, wins: wl.win, losses: wl.lose)
                }
            }
            var list: [PartyRecord] = []
            for await r in group { if let r { list.append(r) } }
            return list.sorted { $0.size < $1.size }
        }
        let order = PlayerRecord.fields.map(\.field)
        let form = FormPoint.weekly(await results ?? [])
        guard !form.isEmpty || !records.isEmpty || !party.isEmpty else { return }
        extras[mode] = ModeExtras(form: form,
                                  records: records.sorted { order.firstIndex(of: $0.id)! < order.firstIndex(of: $1.id)! },
                                  party: party)
    }

    private func loadTurboRating(policy: CachePolicy) async {
        guard let history = try? await client.turboHistory(accountID, policy: policy) else { return }
        let id = accountID
        // Пересчёт по 3 000+ матчам — вне главного потока.
        let rating = await Task.detached(priority: .utility) { TurboRatingEngine.compute(history) }.value
        guard id == accountID, let rating else { return }
        turboRating = rating
    }

    /// Советы для драфта: по одному запросу на каждого выбранного врага/союзника.
    func draft(enemies: [Int], allies: [Int]) async throws -> [DraftSuggestion] {
        let id = accountID, mode = self.mode, client = self.client
        guard let overall = currentStats.value?.heroes else { return [] }
        func fetch(_ heroes: [Int], param: String) async throws -> [Int: [HeroRecord]] {
            try await withThrowingTaskGroup(of: (Int, [HeroRecord]).self) { group in
                for hero in heroes {
                    group.addTask {
                        let rows = try await client.heroes(id, mode: mode, extra: [URLQueryItem(name: param, value: String(hero))])
                        return (hero, rows.filter { $0.games > 0 }.map(HeroRecord.init))
                    }
                }
                var result: [Int: [HeroRecord]] = [:]
                for try await (hero, rows) in group { result[hero] = rows }
                return result
            }
        }
        async let versus = fetch(enemies, param: "against_hero_id")
        async let with = fetch(allies, param: "with_hero_id")
        let (v, w) = try await (versus, with)
        return DraftEngine.suggest(overall: overall, versus: v, with: w, excluded: Set(enemies + allies))
    }

    func matchDetail(_ matchID: Int) async throws -> MatchDetail {
        MatchDetail(try await client.match(matchID))
    }

    func requestParse(_ matchID: Int) async throws {
        try await client.requestParse(matchID)
    }

    private func loadSummary(policy: CachePolicy) async {
        do {
            let p = try await client.player(accountID, policy: policy)
            summary = .loaded(PlayerSummary(
                accountID: accountID,
                nickname: p.profile?.personaname ?? "Игрок \(accountID)",
                avatarURL: p.profile?.avatarfull.flatMap(URL.init(string:)),
                profileURL: p.profile?.profileurl.flatMap(URL.init(string:)),
                rank: p.rank_tier.map { Rank(tier: $0, leaderboard: p.leaderboard_rank) },
                isPlus: p.profile?.plus ?? false
            ))
        } catch {
            guard policy != .cacheOnly, summary.value == nil else { return }
            summary = .failed(error.localizedDescription)
        }
    }

    /// Два этапа: быстрые запросы → карточка уже видна; тяжёлые → `details`.
    private func loadStats(policy: CachePolicy) async {
        let mode = self.mode, id = accountID, client = self.client
        if policy != .cacheOnly, stats[mode]?.value == nil { stats[mode] = .loading }

        do {
            async let wl = client.winLoss(id, mode: mode, policy: policy)
            async let heroes = client.heroes(id, mode: mode, policy: policy)
            async let matches = client.matches(id, mode: mode, limit: 100, policy: policy)
            async let details = Self.loadDetails(client: client, id: id, mode: mode, policy: policy)

            let (w, h, m) = try await (wl, heroes, matches)
            stats[mode] = .loaded(ModeStats(
                wins: w.win,
                losses: w.lose,
                heroes: h.filter { $0.games > 0 || ($0.against_games ?? 0) > 0 }
                    .map(HeroRecord.init)
                    .sorted { $0.games > $1.games },
                recentMatches: m.map(MatchSummary.init).sorted { $0.startTime > $1.startTime },
                details: stats[mode]?.value?.details
            ))

            if let d = await details, case .loaded(var current) = stats[mode] {
                current.details = d
                stats[mode] = .loaded(current)
            }
        } catch is CancellationError {
            if stats[mode]?.value == nil { stats[mode] = .idle }
        } catch {
            guard policy != .cacheOnly else { return }
            if stats[mode]?.value == nil { stats[mode] = .failed(error.localizedDescription) }
        }
    }

    /// Тяжёлые запросы. Ошибка здесь не ломает экран — просто нет подробностей.
    private nonisolated static func loadDetails(client: OpenDotaClient, id: Int, mode: StatsMode, policy: CachePolicy) async -> ModeStats.Details? {
        do {
            async let totals = client.totals(id, mode: mode, policy: policy)
            async let heroes30 = client.heroes(id, mode: mode, extra: [URLQueryItem(name: "date", value: "30")], policy: policy)
            async let counts = client.counts(id, mode: mode, policy: policy)
            async let peers = client.peers(id, mode: mode, policy: policy)
            let (t, h30, c, p) = try await (totals, heroes30, counts, peers)
            let radiant = c.is_radiant?["1"], dire = c.is_radiant?["0"]
            return ModeStats.Details(
                averages: Averages(t),
                heroesLast30Days: h30.filter { $0.games > 0 }.map(HeroRecord.init),
                peers: p.filter { $0.with_games > 0 }.map {
                    Peer(id: $0.account_id, name: $0.personaname ?? "Игрок \($0.account_id)",
                         avatarURL: $0.avatarfull.flatMap(URL.init(string:)),
                         games: $0.with_games, wins: $0.with_win)
                },
                radiant: SideRecord(games: radiant?.games ?? 0, wins: radiant?.win ?? 0),
                dire: SideRecord(games: dire?.games ?? 0, wins: dire?.win ?? 0)
            )
        } catch {
            return nil
        }
    }

    func heroDetail(heroID: Int) async throws -> HeroDetail {
        let heroQuery = [URLQueryItem(name: "hero_id", value: String(heroID))]
        let id = accountID, mode = self.mode, client = self.client
        async let totals = client.totals(id, mode: mode, extra: heroQuery)
        async let matches = client.matches(id, mode: mode, limit: 20, extra: heroQuery)
        async let matchups = client.heroes(id, mode: mode, extra: heroQuery)
        async let itemMatches = try? client.heroItems(id, mode: mode, heroID: heroID)
        // Для Turbo сравнение с общими перцентилями бессмысленно: золото и опыт там ×2.
        async let bench = mode == .turbo ? nil : try? client.benchmarks(heroID: heroID)
        let (t, m, h) = try await (totals, matches, matchups)
        let averages = Averages(t)
        // Цены предметов нужны для фильтра — справочник мог ещё не догрузиться.
        await loadItems()

        let records = h.map(HeroRecord.init)
        return HeroDetail(
            averages: averages,
            matches: m.map(MatchSummary.init).sorted { $0.startTime > $1.startTime },
            toughestOpponents: Array(records.filter { $0.againstGames >= 5 }
                .sorted { $0.againstWinrate < $1.againstWinrate }.prefix(5)),
            bestAllies: Array(records.filter { $0.withGames >= 5 && $0.heroID != heroID }
                .sorted { $0.withWinrate > $1.withWinrate }.prefix(5)),
            items: Self.itemStats(await itemMatches ?? [], catalog: items),
            benchmarks: Self.compare(averages, with: await bench)
        )
    }

    /// Предметы из финального инвентаря: сколько раз собирал и как часто побеждал.
    /// Дешёвые расходники отсекаем, чтобы в топе были «настоящие» предметы.
    private static func itemStats(_ matches: [OpenDotaDTO.MatchWithItems], catalog: [Int: Item]) -> [HeroItemStat] {
        var counts: [Int: (games: Int, wins: Int)] = [:]
        for m in matches {
            let didWin = (m.radiant_win ?? false) == ((m.player_slot ?? 0) < 128)
            for item in Set(m.items) where (catalog[item]?.cost ?? 0) >= 1000 {
                counts[item, default: (0, 0)].games += 1
                if didWin { counts[item, default: (0, 0)].wins += 1 }
            }
        }
        let minGames = max(3, matches.count / 10)
        return counts.filter { $0.value.games >= minGames }
            .map { HeroItemStat(itemID: $0.key, games: $0.value.games, wins: $0.value.wins) }
            .sorted { $0.games > $1.games }
            .prefix(8)
            .sorted { $0.winrate > $1.winrate }
    }

    private static func compare(_ a: Averages, with bench: OpenDotaDTO.Benchmarks?) -> [BenchmarkComparison] {
        guard let bench, a.duration > 0 else { return [] }
        let minutes = a.duration / 60
        let mine: [(key: String, title: String, value: Double)] = [
            ("gold_per_min", "GPM", a.gpm),
            ("xp_per_min", "XPM", a.xpm),
            ("last_hits_per_min", "Добивания в минуту", a.lastHits / minutes),
            ("hero_damage_per_min", "Урон в минуту", a.heroDamage / minutes),
            ("kills_per_min", "Убийства в минуту", a.kills / minutes)
        ]
        return mine.compactMap { spec in
            guard let points = bench.result[spec.key]?.sorted(by: { $0.percentile < $1.percentile }),
                  let median = points.first(where: { $0.percentile >= 0.5 })?.value, spec.value > 0 else { return nil }
            let percentile = points.last(where: { $0.value <= spec.value })?.percentile ?? 0.05
            return BenchmarkComparison(id: spec.key, title: spec.title, yours: spec.value, median: median, percentile: percentile)
        }
    }

    func requestHistoryRefresh() async throws {
        try await client.requestHistoryRefresh(accountID)
    }

    func clearCache() async {
        await client.clearCache()
        stats = [:]
        extras = [:]
        heroes = [:]
        items = [:]
        summary = .idle
        await loadAll(policy: .reload)
    }
}
