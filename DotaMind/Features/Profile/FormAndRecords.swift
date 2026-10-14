//
//  FormAndRecords.swift
//  DotaMind
//

import Charts
import SwiftUI

/// Винрейт по неделям за последние 12 недель + количество игр.
struct FormBlock: View {
    let store: PlayerStore

    var body: some View {
        if let form = store.currentExtras?.form, form.count >= 2 {
            let games = form.reduce(0) { $0 + $1.games }
            let wins = form.reduce(0) { $0 + $1.wins }
            GlassSection("Форма") {
                Text("\(games) \(plural(games, "игра", "игры", "игр")) за 12 недель · \(percent(Double(wins) / Double(max(games, 1))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } content: {
                FormChart(points: form)
            }
        }
    }
}

// ANDROID: Vico LineCartLayer с областью; выбор точки — CartesianMarker.
struct FormChart: View {
    let points: [FormPoint]
    @State private var selected: Date?

    private var selectedPoint: FormPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.weekStart.timeIntervalSince(selected)) < abs($1.weekStart.timeIntervalSince(selected)) }
    }

    /// Шкала по фактическому разбросу (с запасом и всегда с 50 %), иначе линия почти плоская.
    private var domain: ClosedRange<Double> {
        let values = points.map(\.winrate) + [0.5]
        let low = ((values.min() ?? 0.4) - 0.08).clamped(to: 0...0.45)
        let high = ((values.max() ?? 0.6) + 0.08).clamped(to: 0.55...1)
        return (low * 20).rounded(.down) / 20...(high * 20).rounded(.up) / 20
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("50%", 0.5))
                .foregroundStyle(.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(points) { p in
                // Площадь от нижней границы шкалы, а не от нуля — иначе вылезает за график.
                AreaMark(x: .value("Неделя", p.weekStart, unit: .weekOfYear),
                         yStart: .value("Низ", domain.lowerBound), yEnd: .value("Винрейт", p.winrate))
                    .foregroundStyle(.linearGradient(colors: [Theme.gold.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Неделя", p.weekStart, unit: .weekOfYear), y: .value("Винрейт", p.winrate))
                    .foregroundStyle(Theme.gold)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Неделя", p.weekStart, unit: .weekOfYear), y: .value("Винрейт", p.winrate))
                    .foregroundStyle(winrateColor(p.winrate))
                    .symbolSize(p.games > 20 ? 50 : 25)
            }
            if let s = selectedPoint {
                RuleMark(x: .value("Неделя", s.weekStart, unit: .weekOfYear))
                    .foregroundStyle(.white.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(percent(s.winrate)).font(.caption.weight(.bold))
                            Text("\(s.wins)–\(s.games - s.wins) · \(s.weekStart.formatted(.dateTime.day().month()))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(values: [domain.lowerBound, 0.5, domain.upperBound]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel { if let v = value.as(Double.self) { Text(percent(v)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartXSelection(value: $selected)
        .chartPlotStyle { $0.clipped() }
        .frame(height: 170)
        .accessibilityLabel("График винрейта по неделям")
    }
}

/// Личные рекорды в режиме: тап открывает тот самый матч.
struct RecordsBlock: View {
    let store: PlayerStore
    let columns: Int

    var body: some View {
        if let records = store.currentExtras?.records, !records.isEmpty {
            GlassSection("Рекорды") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(records) { record in
                        NavigationLink(value: MatchRoute(id: record.matchID)) {
                            RecordTile(record: record, hero: record.heroID.map(store.hero))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct RecordTile: View {
    let record: PlayerRecord
    let hero: Hero?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Text(record.value)
                .font(.display(20).monospacedDigit())
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                if let hero { HeroPortrait(hero: hero, width: 34) }
                if let date = record.date {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Гипотетический рейтинг в Turbo (Elo по среднему рангу лобби). Только в режиме Turbo.
struct TurboRatingBlock: View {
    let store: PlayerStore
    @State private var showInfo = false

    var body: some View {
        if store.mode == .turbo, let r = store.turboRating {
            GlassSection("Турбо-рейтинг") {
                Button { showInfo.toggle() } label: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Как считается")
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        RankBadge(rank: r.rank, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("≈ \(r.rating.formatted())")
                                    .font(.display(30).monospacedDigit())
                                    .foregroundStyle(Theme.gold)
                                if let delta = r.change30Days, delta != 0 {
                                    Text("\(delta > 0 ? "+" : "")\(delta) за 30 дн.")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(delta > 0 ? Theme.win : Theme.loss)
                                }
                            }
                            Text("\(r.rank.title) · средний ранг лобби ≈ \(r.lobbyAverage.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if r.history.count >= 3 {
                        Chart(r.history) { p in
                            LineMark(x: .value("Неделя", p.date, unit: .weekOfYear), y: .value("Рейтинг", p.rating))
                                .foregroundStyle(Theme.gold)
                                .interpolationMethod(.monotone)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 110)
                    }
                    if showInfo {
                        Text("Valve не считает рейтинг для Turbo — это оценка по системе Elo. В каждом из \(r.games.formatted()) матчей соперником считается средний ранг лобби, победа над более сильным лобби даёт больше очков. Цифра сопоставима с обычным MMR, но это не официальный рейтинг.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .animation(.smooth, value: showInfo)
            }
        }
    }
}
