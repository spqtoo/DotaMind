//
//  AchievementsBlock.swift
//  DotaMind
//

import SwiftUI

struct AchievementsBlock: View {
    let store: PlayerStore
    let columns: Int

    var body: some View {
        if let stats = store.currentStats.value, stats.games > 0 {
            let list = AchievementEngine.make(stats: stats, extras: store.currentExtras, turboRating: store.turboRating,
                                              mode: store.mode, heroName: { store.hero($0).name })
            let opened = list.filter { $0.tier != .none }.count
            GlassSection("Достижения") {
                Text("\(opened) из \(list.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } content: {
                // ANDROID (Material 3): LazyVerticalGrid из ElevatedCard; уровни — tonal-цвета вместо металла.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(list) { AchievementTile(achievement: $0) }
                }
            }
        }
    }
}

private struct AchievementTile: View {
    let achievement: Achievement

    private var colors: [Color] {
        switch achievement.tier {
        case .none: [Color(white: 0.3), Color(white: 0.2)]
        case .bronze: [Color(red: 0.85, green: 0.55, blue: 0.35), Color(red: 0.55, green: 0.32, blue: 0.18)]
        case .silver: [Color(white: 0.9), Color(white: 0.55)]
        case .gold: [Theme.gold, Color(red: 0.75, green: 0.5, blue: 0.15)]
        case .legend: [Color(red: 0.75, green: 0.55, blue: 1.0), Color(red: 0.35, green: 0.75, blue: 0.95)]
        }
    }

    var body: some View {
        let a = achievement
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: a.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(a.tier == .none ? Color.secondary : Color.black.opacity(0.75))
                    .frame(width: 38, height: 38)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
                    .opacity(a.tier == .none ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.title).font(.subheadline.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(a.tier.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(a.tier == .none ? Color.secondary : colors[0])
                }
            }
            Text(a.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            WinrateBar(winrate: a.progress, color: a.tier == .legend ? colors[0] : Theme.gold, height: 8)
            Text(a.nextThreshold.map { "\(a.format(a.value)) / \(a.format($0))" } ?? "\(a.format(a.value)) — максимум")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
