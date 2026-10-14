//
//  MatchesView.swift
//  DotaMind
//

import SwiftUI

struct MatchesView: View {
    let store: PlayerStore

    @State private var showAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ModePicker(store: store)
                    SnapshotBanner(store: store)

                    switch store.currentStats {
                    case .loaded(let stats):
                        content(stats)
                    case .failed(let message):
                        ErrorView(message: message) { await store.loadAll(policy: .reload) }
                    default:
                        LoadingView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { AppBackground() }
            .navigationTitle("Матчи")
            .toolbar {
                if store.isRefreshing {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .refreshable { await store.loadAll(policy: .reload) }
            .task { await store.loadIfNeeded() }
            .navigationDestination(for: HeroRecord.self) { HeroDetailView(store: store, record: $0) }
            .navigationDestination(for: MatchRoute.self) { MatchDetailView(store: store, matchID: $0.id) }
        }
    }

    @ViewBuilder
    private func content(_ stats: ModeStats) -> some View {
        let insights = store.insights()
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Советы").font(.display(22, weight: .bold))
                ForEach(insights) { insight in
                    if let heroID = insight.heroID,
                       let record = stats.heroes.first(where: { $0.heroID == heroID && $0.games > 0 }) {
                        NavigationLink(value: record) { InsightCard(insight: insight, hero: store.hero(heroID)) }
                            .buttonStyle(.plain)
                    } else {
                        InsightCard(insight: insight, hero: insight.heroID.map(store.hero))
                    }
                }
            }
        }

        TeammatesBlock(store: store)

        if stats.recentMatches.isEmpty {
            ContentUnavailableView("Матчей пока нет", systemImage: "gamecontroller",
                                   description: Text("В режиме «\(store.mode.title)» OpenDota не нашёл игр."))
        } else {
            let recent = stats.recentMatches
            let shown = showAll ? recent : Array(recent.prefix(20))
            GlassSection("Последние матчи") {
                Text(formSummary(recent.prefix(20)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } content: {
                LazyVStack(spacing: 8) {
                    ForEach(shown) { match in
                        NavigationLink(value: MatchRoute(id: match.id)) {
                            MatchRow(match: match, hero: store.hero(match.heroID))
                        }
                        .buttonStyle(.plain)
                    }
                    if recent.count > shown.count {
                        Button("Показать ещё \(recent.count - shown.count)") {
                            withAnimation { showAll = true }
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func formSummary(_ matches: ArraySlice<MatchSummary>) -> String {
        let wins = matches.filter(\.didWin).count
        return "\(wins)–\(matches.count - wins) за \(matches.count)"
    }
}

struct InsightCard: View {
    let insight: Insight
    let hero: Hero?

    private var tint: Color {
        switch insight.tone {
        case .positive: Theme.win
        case .negative: Theme.loss
        case .neutral: Color(red: 0.45, green: 0.65, blue: 1.0)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.system(size: 15, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let hero {
                HeroPortrait(hero: hero, width: 56)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: 20))
    }
}

struct MatchRow: View {
    let match: MatchSummary
    let hero: Hero

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(match.didWin ? Theme.win : Theme.loss)
                .frame(width: 4, height: 40)
            HeroPortrait(hero: hero, width: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(hero.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(gameModeName(match.gameMode)) · \(Format.duration(match.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(match.kills)/\(match.deaths)/\(match.assists)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                Text(Format.relative(match.startTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.didWin ? "Победа" : "Поражение"), \(hero.name), \(match.kills) убийств, \(match.deaths) смертей, \(match.assists) помощи")
    }
}
