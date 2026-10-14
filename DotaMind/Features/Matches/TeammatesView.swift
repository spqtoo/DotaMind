//
//  TeammatesView.swift
//  DotaMind
//
//  Лучшие напарники в выбранном режиме и винрейт соло/в пати.
//

import SwiftUI

/// Короткий блок на вкладке «Матчи»: топ-3 тиммейта + ссылка на весь список.
struct TeammatesBlock: View {
    let store: PlayerStore

    var body: some View {
        if let peers = store.currentStats.value?.details?.peers, !peers.isEmpty {
            GlassSection("Напарники") {
                NavigationLink { TeammatesView(store: store) } label: {
                    Text("Все \(peers.count)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.gold)
                }
            } content: {
                VStack(spacing: 12) {
                    if let party = store.currentExtras?.party, party.count >= 2 {
                        PartyStrip(party: party)
                    }
                    ForEach(TeammatesView.best(peers).prefix(3)) { PeerRow(peer: $0) }
                }
            }
        }
    }
}

struct TeammatesView: View {
    let store: PlayerStore

    @State private var sort: Sort = .winrate
    @State private var compareWith: Peer?

    enum Sort: String, CaseIterable, Identifiable {
        case winrate = "Лучший винрейт"
        case games = "Больше игр"
        var id: String { rawValue }
    }

    /// Лучшие — по винрейту, но только с 10+ играми вместе (иначе 2 из 2 — «лучший»).
    static func best(_ peers: [Peer]) -> [Peer] {
        peers.filter { $0.games >= 10 }.sorted { $0.winrate > $1.winrate }
    }

    private var peers: [Peer] {
        let all = store.currentStats.value?.details?.peers ?? []
        return sort == .winrate ? Self.best(all) : all.sorted { $0.games > $1.games }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let party = store.currentExtras?.party, !party.isEmpty {
                    GlassSection("Соло или в пати") {
                        Text("где известен размер пати").font(.caption).foregroundStyle(.secondary)
                    } content: {
                        VStack(spacing: 12) {
                            ForEach(party) { p in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(p.title).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(percent(p.winrate))
                                            .font(.subheadline.weight(.bold).monospacedDigit())
                                            .foregroundStyle(winrateColor(p.winrate))
                                        Text("\(p.games)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            .frame(width: 44, alignment: .trailing)
                                    }
                                    WinrateBar(winrate: p.winrate)
                                }
                            }
                        }
                    }
                }

                // ANDROID (Material 3): SegmentedButton.
                Picker("Сортировка", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                GlassSection("Тиммейты · \(store.mode.title)") {
                    Text("нажми — сравнить").font(.caption).foregroundStyle(.secondary)
                } content: {
                    VStack(spacing: 12) {
                        ForEach(peers) { peer in
                            Button { compareWith = peer } label: { PeerRow(peer: peer) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Напарники")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $compareWith) { peer in
            CompareView(store: store, initialFriend: SteamID.steamID64(fromAccountID: peer.id))
        }
    }
}

struct PeerRow: View {
    let peer: Peer

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: peer.avatarURL)
                .frame(width: 40, height: 40)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(peer.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(percent(peer.winrate))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(winrateColor(peer.winrate))
                }
                WinrateBar(winrate: peer.winrate)
                Text("\(peer.games) \(plural(peer.games, "игра", "игры", "игр")) вместе")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Компактная строка «соло / пати» — по размеру пати, где игр больше всего.
private struct PartyStrip: View {
    let party: [PartyRecord]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(party.filter { $0.games >= 10 }.prefix(4)) { p in
                VStack(spacing: 2) {
                    Text(percent(p.winrate))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(winrateColor(p.winrate))
                    Text(p.size == 1 ? "соло" : "пати \(p.size)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.05), in: .rect(cornerRadius: 12))
            }
        }
    }
}
