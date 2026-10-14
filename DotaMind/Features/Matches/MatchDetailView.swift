//
//  MatchDetailView.swift
//  DotaMind
//

import Charts
import SwiftUI

/// Навигация к матчу по ID — из списка матчей, рекордов и страницы героя.
struct MatchRoute: Hashable {
    let id: Int
}

struct MatchDetailView: View {
    let store: PlayerStore
    let matchID: Int

    @State private var detail: Loadable<MatchDetail> = .idle
    @State private var parseRequested = false
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch detail {
                case .loaded(let d):
                    content(d)
                case .failed(let message):
                    ErrorView(message: message) { await load() }
                default:
                    LoadingView(text: "Загружаем матч…")
                }
            }
            .padding(16)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { containerWidth = $0 }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Матч")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = URL(string: "https://www.opendota.com/matches/\(matchID)") {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ d: MatchDetail) -> some View {
        let me = (d.radiant + d.dire).first { $0.accountID == store.accountID }
        header(d, me: me)

        if d.isParsed, let gold = d.goldAdvantage {
            GlassSection("Преимущество по золоту") {
                AdvantageChart(values: gold)
            }
        } else {
            parseCard
        }

        let teams = [
            (title: "Radiant", lines: d.radiant, won: d.radiantWin, color: Theme.win),
            (title: "Dire", lines: d.dire, won: !d.radiantWin, color: Theme.loss)
        ]
        let layout = containerWidth > 900
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(spacing: 16))
        layout {
            ForEach(teams, id: \.title) { team in
                GlassSection(team.title) {
                    if team.won {
                        Label("Победа", systemImage: "trophy.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.gold)
                    }
                } content: {
                    VStack(spacing: 14) {
                        ForEach(team.lines) { line in
                            PlayerLineRow(line: line, isMe: line.accountID == store.accountID, store: store)
                        }
                    }
                }
            }
        }
    }

    private func header(_ d: MatchDetail, me: MatchDetail.Line?) -> some View {
        let myWin = me.map { $0.isRadiant == d.radiantWin }
        return VStack(spacing: 10) {
            if let myWin {
                Text(myWin ? "ПОБЕДА" : "ПОРАЖЕНИЕ")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(myWin ? Theme.win : Theme.loss)
            }
            HStack(spacing: 18) {
                Text("\(d.radiantScore)").foregroundStyle(Theme.win)
                Text(":").foregroundStyle(.secondary)
                Text("\(d.direScore)").foregroundStyle(Theme.loss)
            }
            .font(.display(40).monospacedDigit())
            Text("\(gameModeName(d.gameMode)) · \(Format.duration(d.duration)) · \(d.startTime.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let me {
                HStack(spacing: 10) {
                    HeroPortrait(hero: store.hero(me.heroID), width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ты на \(store.hero(me.heroID).name)").font(.subheadline.weight(.semibold))
                        Text("\(me.kills)/\(me.deaths)/\(me.assists) · \(me.netWorth.formatted()) золота")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var parseCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 4) {
                Text("Матч не разобран").font(.subheadline.weight(.semibold))
                Text(parseRequested
                     ? "Запрос отправлен. OpenDota разберёт реплей за несколько минут — потом обнови экран."
                     : "Графики золота и опыта появятся после разбора реплея.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !parseRequested {
                Button("Разобрать") {
                    Task {
                        try? await store.requestParse(matchID)
                        parseRequested = true
                        Haptics.shared.success()
                    }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func load() async {
        if detail.value == nil { detail = .loading }
        do {
            detail = .loaded(try await store.matchDetail(matchID))
        } catch is CancellationError {
        } catch {
            detail = .failed(error.localizedDescription)
        }
    }
}

private struct PlayerLineRow: View {
    let line: MatchDetail.Line
    let isMe: Bool
    let store: PlayerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HeroPortrait(hero: store.hero(line.heroID), width: 60)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(line.level)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 4)
                            .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                            .padding(2)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(.subheadline.weight(isMe ? .bold : .medium))
                        .foregroundStyle(isMe ? Theme.gold : .primary)
                        .lineLimit(1)
                    Text(store.hero(line.heroID).name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(line.kills)/\(line.deaths)/\(line.assists)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                    Text(line.netWorth.formatted(.number.notation(.compactName)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.gold)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(line.items.enumerated()), id: \.offset) { _, id in
                    ItemIcon(item: store.item(id), size: 30)
                }
                ItemIcon(item: store.item(line.neutral), size: 30, isNeutral: true)
            }
            Text("GPM \(line.gpm) · XPM \(line.xpm) · урон \(line.heroDamage.formatted(.number.notation(.compactName))) · добивания \(line.lastHits)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(isMe ? 8 : 0)
        .background {
            if isMe { RoundedRectangle(cornerRadius: 14).fill(Theme.gold.opacity(0.08)) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ItemIcon: View {
    let item: Item?
    var size: CGFloat = 30
    var isNeutral = false

    var body: some View {
        Group {
            if let item {
                RemoteImage(url: item.imageURL)
                    .accessibilityLabel(item.name)
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .frame(width: size * (isNeutral ? 1 : 1.36), height: size)
        .clipShape(isNeutral ? AnyShape(Circle()) : AnyShape(.rect(cornerRadius: 4)))
    }
}

/// График преимущества: выше нуля — Radiant, ниже — Dire.
// ANDROID: графики — библиотека Vico (compose-m3) или Canvas.
struct AdvantageChart: View {
    let values: [Int]

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { minute, value in
                // Две площади (выше и ниже нуля), чтобы раскрасить стороны по-разному.
                AreaMark(x: .value("Минута", minute), y: .value("Золото", max(value, 0)), series: .value("Сторона", "Radiant"))
                    .foregroundStyle(Theme.win.opacity(0.45))
                AreaMark(x: .value("Минута", minute), y: .value("Золото", min(value, 0)), series: .value("Сторона", "Dire"))
                    .foregroundStyle(Theme.loss.opacity(0.45))
                LineMark(x: .value("Минута", minute), y: .value("Золото", value), series: .value("Сторона", "Линия"))
                    .foregroundStyle(.white.opacity(0.8))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(y: .value("Ноль", 0)).foregroundStyle(.white.opacity(0.3))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text(abs(v).formatted(.number.notation(.compactName))) }
                }
            }
        }
        .chartXAxisLabel("минуты")
        .frame(height: 180)
    }
}
