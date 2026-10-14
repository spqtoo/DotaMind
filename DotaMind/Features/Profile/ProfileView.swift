//
//  ProfileView.swift
//  DotaMind
//

import SwiftUI

// ANDROID (Material 3): Scaffold + LazyColumn; колонки — по WindowSizeClass (Compact/Medium/Expanded), как здесь по ширине.
struct ProfileView: View {
    let store: PlayerStore

    @State private var width: CGFloat = 0
    @State private var showCompare = false
    @State private var path = NavigationPath()
    @State private var sharedCard: SharedCard?
    @State private var renderingCard = false

    struct SharedCard: Identifiable {
        let image: UIImage
        var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    /// Колонки по ширине, а не по типу устройства: так раскладка верна и на
    /// iPad в Split View, и на разложенном складном iPhone.
    private var columns: Int {
        switch width {
        case ..<700: 1
        case ..<1150: 2
        default: 3
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    ModePicker(store: store)
                        .frame(maxWidth: columns == 1 ? .infinity : 560)
                    SnapshotBanner(store: store)

                    switch (store.summary, store.currentStats) {
                    case (.loaded(let summary), let stats):
                        layout(summary: summary, stats: stats)
                    case (.failed(let message), _), (_, .failed(let message)):
                        ErrorView(message: message) { await store.loadAll(policy: .reload) }
                    default:
                        LoadingView()
                    }
                }
                .padding(.horizontal, columns == 1 ? 16 : 28)
                .padding(.bottom, 24)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .scrollIndicators(.hidden)
            .background { AppBackground() }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.isRefreshing {
                    ToolbarItem(placement: .topBarLeading) { ProgressView() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await shareCard() } } label: {
                        if renderingCard { ProgressView() } else { Label("Поделиться карточкой", systemImage: "square.and.arrow.up") }
                    }
                    .disabled(store.summary.value == nil || renderingCard)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCompare = true } label: {
                        Label("Сравнить с другом", systemImage: "person.2")
                    }
                }
            }
            .sheet(item: $sharedCard) { ShareCardSheet(image: $0.image) }
            .sheet(isPresented: $showCompare) { CompareView(store: store, initialFriend: debugCompareFriend) }
            #if DEBUG
            .onChange(of: store.currentStats.value != nil, initial: true) { _, loaded in
                if loaded { openDebugRoute() }
            }
            #endif
            .refreshable { await store.loadAll(policy: .reload) }
            .task { await store.loadIfNeeded() }
            .navigationDestination(for: HeroRecord.self) { HeroDetailView(store: store, record: $0) }
            .navigationDestination(for: MatchRoute.self) { MatchDetailView(store: store, matchID: $0.id) }
        }
    }

    private func shareCard() async {
        guard let summary = store.summary.value else { return }
        renderingCard = true
        defer { renderingCard = false }
        await store.ensureCatalogs()
        let model = CardModel(summary: summary, stats: store.currentStats.value, mode: store.mode,
                              turboRating: store.turboRating, hero: store.hero)
        if let image = await ShareableCard.render(model) {
            Haptics.shared.success()
            sharedCard = SharedCard(image: image)
        }
    }

    #if DEBUG
    /// `-DMOpen match:<id> | hero:<id> | compare:<friendID>` — сразу открыть экран (для скриншотов).
    private func openDebugRoute() {
        guard path.isEmpty, !showCompare, let raw = UserDefaults.standard.string(forKey: "DMOpen") else { return }
        let parts = raw.split(separator: ":").map(String.init)
        guard parts.count == 2, let id = Int(parts[1]) else { return }
        switch parts[0] {
        case "match": path.append(MatchRoute(id: id))
        case "hero":
            if let record = store.currentStats.value?.playedHeroes.first(where: { $0.heroID == id }) { path.append(record) }
        case "compare": showCompare = true
        case "share": Task { await shareCard() }
        default: break
        }
    }
    #endif

    private var debugCompareFriend: String? {
        #if DEBUG
        let raw = UserDefaults.standard.string(forKey: "DMOpen") ?? ""
        if raw.hasPrefix("compare:"), let id = Int(raw.dropFirst(8)) { return SteamID.steamID64(fromAccountID: id) }
        #endif
        return nil
    }

    @ViewBuilder
    private func layout(summary: PlayerSummary, stats: Loadable<ModeStats>) -> some View {
        let card = HoloPlayerCard(model: CardModel(summary: summary, stats: stats.value, mode: store.mode,
                                                   turboRating: store.turboRating, hero: store.hero))
        if let s = stats.value, s.games == 0 {
            card.frame(maxWidth: 420)
            NoMatchesView()
        } else if let s = stats.value {
            switch columns {
            case 1:
                card.padding(.horizontal, 6)
                SummaryBlock(stats: s)
                TurboRatingBlock(store: store)
                FormBlock(store: store)
                HeroesBlock(stats: s, store: store, limit: 6)
                RecordsBlock(store: store, columns: 2)
                AchievementsBlock(store: store, columns: 2)
            case 2:
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 18) {
                        card
                        RecordsBlock(store: store, columns: 2)
                        AchievementsBlock(store: store, columns: 2)
                    }
                    .frame(width: min(400, width * 0.42))
                    VStack(spacing: 14) {
                        SummaryBlock(stats: s)
                        TurboRatingBlock(store: store)
                        FormBlock(store: store)
                        HeroesBlock(stats: s, store: store, limit: 8)
                    }
                }
            default:
                HStack(alignment: .top, spacing: 24) {
                    card.frame(width: 380)
                    VStack(spacing: 14) {
                        SummaryBlock(stats: s)
                        TurboRatingBlock(store: store)
                        FormBlock(store: store)
                        RecordsBlock(store: store, columns: 3)
                        AchievementsBlock(store: store, columns: 3)
                    }
                    HeroesBlock(stats: s, store: store, limit: 10)
                        .frame(width: min(400, width * 0.3))
                }
            }
        } else {
            card.frame(maxWidth: 420)
            LoadingView()
        }
    }
}

/// Turbo / Обычные / Все. Сегментированный Picker на iOS 26 сам в стекле.
// ANDROID (Material 3): SingleChoiceSegmentedButtonRow с тремя SegmentedButton.
struct ModePicker: View {
    let store: PlayerStore

    var body: some View {
        Picker("Режим", selection: Binding(
            get: { store.mode },
            set: { mode in
                Haptics.shared.selectionChanged()
                Task { await store.setMode(mode) }
            }
        )) {
            ForEach(StatsMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}

/// Пометка, что на экране офлайн-снимок, а не живые данные.
// ANDROID (Material 3): Banner-стиль — Card(containerColor = secondaryContainer) с иконкой CloudOff.
struct SnapshotBanner: View {
    let store: PlayerStore

    var body: some View {
        if let date = store.snapshotDate {
            Label("Нет связи с OpenDota — показан снимок от \(date.formatted(date: .abbreviated, time: .omitted))",
                  systemImage: "icloud.slash")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(Theme.gold.opacity(0.15)), in: .rect(cornerRadius: 16))
        }
    }
}

private struct NoMatchesView: View {
    var body: some View {
        ContentUnavailableView(
            "Нет матчей в этом режиме",
            systemImage: "questionmark.circle",
            description: Text("Если ты точно играл — проверь, что в настройках Доты включено «Expose Public Match Data», и запроси обновление истории в Настройках.")
        )
    }
}

/// Победы/поражения и средние за матч.
private struct SummaryBlock: View {
    let stats: ModeStats

    var body: some View {
        VStack(spacing: 14) {
            WinLossBar(wins: stats.wins, losses: stats.losses)
            let a = stats.details?.averages
            MetricStrip(items: [
                .init(title: "K/D/A", value: a.map { "\(Format.number($0.kills, digits: 0))/\(Format.number($0.deaths, digits: 0))/\(Format.number($0.assists, digits: 0))" } ?? "…"),
                .init(title: "GPM", value: a.map { Format.number($0.gpm, digits: 0) } ?? "…", tint: Theme.gold),
                .init(title: "XPM", value: a.map { Format.number($0.xpm, digits: 0) } ?? "…"),
                .init(title: "Матч", value: a.map { Format.duration($0.duration) } ?? "…")
            ])
        }
    }
}

private struct HeroesBlock: View {
    let stats: ModeStats
    let store: PlayerStore
    let limit: Int

    var body: some View {
        let played = stats.playedHeroes
        GlassSection("Герои") {
            NavigationLink {
                HeroListView(store: store)
            } label: {
                Text("Все \(played.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }
        } content: {
            VStack(spacing: 12) {
                ForEach(played.prefix(limit)) { record in
                    NavigationLink(value: record) {
                        HeroRow(record: record, hero: store.hero(record.heroID))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct HeroRow: View {
    let record: HeroRecord
    let hero: Hero

    var body: some View {
        HStack(spacing: 12) {
            HeroPortrait(hero: hero, width: 76)
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(Theme.attributeColor(hero.primaryAttribute))
                        .frame(height: 3)
                        .clipShape(.rect(cornerRadius: 1.5))
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(hero.name)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text(percent(record.winrate))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(winrateColor(record.winrate))
                }
                WinrateBar(winrate: record.winrate)
                Text("\(record.games) \(plural(record.games, "игра", "игры", "игр")) · \(record.wins) \(plural(record.wins, "победа", "победы", "побед"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Предпросмотр карточки-картинки и системное меню «Поделиться».
private struct ShareCardSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    .padding(.horizontal, 24)
                // ANDROID (Material 3): Intent.ACTION_SEND с PNG через FileProvider; кнопка — FilledButton.
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Моя карточка DotaMind", image: Image(uiImage: image))) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: .infinity)
            .background { AppBackground() }
            .navigationTitle("Карточка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
