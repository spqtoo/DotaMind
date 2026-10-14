//
//  HeroDetailView.swift
//  DotaMind
//

import SwiftUI

struct HeroDetailView: View {
    let store: PlayerStore
    let record: HeroRecord

    @State private var detail: Loadable<HeroDetail> = .idle

    private var hero: Hero { store.hero(record.heroID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Игр", value: record.games.formatted())
                    StatTile(title: "Побед", value: record.wins.formatted(), tint: .green)
                    StatTile(title: "Винрейт", value: percent(record.winrate), tint: winrateColor(record.winrate))
                }

                switch detail {
                case .loaded(let d):
                    content(d)
                case .failed(let message):
                    ErrorView(message: message) { await load() }
                default:
                    LoadingView(text: "Собираем статистику героя…")
                }
            }
            .padding(16)
        }
        .background { AppBackground() }
        .navigationTitle(hero.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: hero.imageURL)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(hero.name).font(.title.weight(.heavy))
                Text(([store.mode.title] + hero.roles.prefix(3)).joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .clipShape(.rect(cornerRadius: 24))
    }

    @ViewBuilder
    private func content(_ d: HeroDetail) -> some View {
        let a = d.averages
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Средний KDA",
                     value: "\(Format.number(a.kills))/\(Format.number(a.deaths))/\(Format.number(a.assists))",
                     symbol: "scope")
            StatTile(title: "Средний матч", value: Format.duration(a.duration), symbol: "timer")
            StatTile(title: "GPM", value: Format.number(a.gpm, digits: 0), symbol: "dollarsign.circle")
            StatTile(title: "Добивания", value: Format.number(a.lastHits, digits: 0), symbol: "target")
        }

        if !d.items.isEmpty {
            GlassSection("С чем ты выигрываешь") {
                Text("последние 100 игр").font(.caption).foregroundStyle(.secondary)
            } content: {
                VStack(spacing: 10) {
                    ForEach(d.items) { stat in
                        let item = store.item(stat.itemID)
                        HStack(spacing: 12) {
                            ItemIcon(item: item, size: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item?.name ?? "Предмет #\(stat.itemID)").font(.subheadline)
                                    Spacer()
                                    Text(percent(stat.winrate))
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(winrateColor(stat.winrate))
                                }
                                WinrateBar(winrate: stat.winrate)
                            }
                            Text("\(stat.games)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }

        if !d.benchmarks.isEmpty {
            GlassSection("Ты против всех игроков") {
                Text("медиана на герое").font(.caption).foregroundStyle(.secondary)
            } content: {
                VStack(spacing: 12) {
                    ForEach(d.benchmarks) { b in
                        BenchmarkRow(benchmark: b)
                    }
                }
            }
        } else if store.mode == .turbo {
            Label("Сравнение со всеми игроками доступно для обычных режимов: в Turbo золото и опыт идут вдвое быстрее, и цифры несопоставимы.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }

        if !d.toughestOpponents.isEmpty {
            GlassSection("Сложнее всего против") {
                matchupList(d.toughestOpponents, games: \.againstGames, winrate: \.againstWinrate)
            }
        }
        if !d.bestAllies.isEmpty {
            GlassSection("Лучшие союзники") {
                matchupList(d.bestAllies, games: \.withGames, winrate: \.withWinrate)
            }
        }
        if !d.matches.isEmpty {
            GlassSection("Последние игры на герое") {
                VStack(spacing: 8) {
                    ForEach(d.matches) { match in
                        NavigationLink(value: MatchRoute(id: match.id)) { MatchRow(match: match, hero: hero) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func matchupList(_ records: [HeroRecord], games: KeyPath<HeroRecord, Int>, winrate: KeyPath<HeroRecord, Double>) -> some View {
        VStack(spacing: 10) {
            ForEach(records) { r in
                let other = store.hero(r.heroID)
                HStack(spacing: 12) {
                    HeroPortrait(hero: other, width: 52)
                    Text(other.name).font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(percent(r[keyPath: winrate]))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(winrateColor(r[keyPath: winrate]))
                        Text("\(r[keyPath: games]) \(plural(r[keyPath: games], "игра", "игры", "игр"))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do {
            detail = .loaded(try await store.heroDetail(heroID: record.heroID))
        } catch is CancellationError {
        } catch {
            detail = .failed(error.localizedDescription)
        }
    }
}

private struct BenchmarkRow: View {
    let benchmark: BenchmarkComparison

    private var formatted: (yours: String, median: String) {
        let digits = benchmark.yours < 10 ? 2 : 0
        return (Format.number(benchmark.yours, digits: digits), Format.number(benchmark.median, digits: digits))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(benchmark.title).font(.subheadline)
                Spacer()
                Text(formatted.yours)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(benchmark.yours >= benchmark.median ? Theme.win : Theme.loss)
                Text("/ \(formatted.median)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Полоса перцентиля: где ты среди всех игроков на герое.
            WinrateBar(winrate: benchmark.percentile, color: Theme.gold)
                .overlay {
                    // Отметка медианы (50-й перцентиль).
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.75)).frame(width: 2, height: 15)
                            .position(x: geo.size.width * 0.5, y: geo.size.height / 2)
                    }
                }
            Text("лучше, чем \(percent(benchmark.percentile)) игроков")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
