//
//  CompareView.swift
//  DotaMind
//
//  Сравнение с другом: две колонки цифр в одном режиме и общие герои.
//  Друг загружается отдельным PlayerStore — тем же кодом, что и свой профиль.
//

import SwiftUI

struct CompareView: View {
    let store: PlayerStore
    /// SteamID64 друга, которого открыть сразу (например, по тапу на тиммейта).
    var initialFriend: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var friend: PlayerStore?
    @State private var input = ""
    @State private var inputError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let friend {
                        CompareContent(me: store, friend: friend)
                    } else {
                        picker
                    }
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { AppBackground() }
            .onAppear { if friend == nil, let initialFriend { select(initialFriend) } }
            .navigationTitle(friend == nil ? "Сравнить с другом" : "Сравнение · \(store.mode.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                }
                if friend != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Другой игрок") { withAnimation { friend = nil } }
                    }
                }
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Friend ID или ссылка на профиль").font(.subheadline.weight(.semibold))
                HStack {
                    TextField("123456789", text: $input)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(submit)
                    Button("Сравнить", action: submit)
                        .buttonStyle(.glassProminent)
                        .disabled(input.isEmpty)
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                if let inputError {
                    Text(inputError).font(.caption).foregroundStyle(Theme.loss)
                }
            }

            if let peers = store.currentStats.value?.details?.peers.prefix(8), !peers.isEmpty {
                GlassSection("Твои тиммейты") {
                    VStack(spacing: 10) {
                        ForEach(Array(peers)) { peer in
                            Button {
                                select(SteamID.steamID64(fromAccountID: peer.id))
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(url: peer.avatarURL)
                                        .frame(width: 40, height: 40)
                                        .clipShape(.circle)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text("\(peer.games) \(plural(peer.games, "игра", "игры", "игр")) вместе · \(percent(peer.winrate))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func submit() {
        guard let id = SteamID.parse(input) else {
            inputError = "Не похоже на Friend ID или ссылку на профиль Steam."
            Haptics.shared.error()
            return
        }
        guard id != store.steamID64 else {
            inputError = "Это твой собственный аккаунт 🙂"
            return
        }
        select(id)
    }

    private func select(_ steamID64: String) {
        inputError = nil
        Haptics.shared.light()
        let other = PlayerStore(steamID64: steamID64, mode: store.mode)
        withAnimation { friend = other }
        Task { await other.loadAll(policy: .normal) }
    }
}

private struct CompareContent: View {
    let me: PlayerStore
    let friend: PlayerStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlayerHeader(store: me, isMe: true)
            Text("VS")
                .font(.display(18))
                .foregroundStyle(Theme.gold)
                .padding(.top, 28)
            PlayerHeader(store: friend, isMe: false)
        }

        if let a = me.currentStats.value, let b = friend.currentStats.value {
            GlassSection("Цифры") {
                VStack(spacing: 12) {
                    row("Матчей", a.games, b.games) { $0.formatted() }
                    row("Винрейт", a.winrate ?? 0, b.winrate ?? 0) { percent($0) }
                    if let da = a.details?.averages, let db = b.details?.averages {
                        row("KDA", da.kda, db.kda) { Format.number($0, digits: 2) }
                        row("GPM", da.gpm, db.gpm) { Format.number($0, digits: 0) }
                        row("XPM", da.xpm, db.xpm) { Format.number($0, digits: 0) }
                        row("Смерти", da.deaths, db.deaths, lowerIsBetter: true) { Format.number($0) }
                        row("Добивания", da.lastHits, db.lastHits) { Format.number($0, digits: 0) }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    row("Героев", a.playedHeroes.count, b.playedHeroes.count) { "\($0)" }
                }
            }

            let shared = sharedHeroes(a, b)
            if !shared.isEmpty {
                GlassSection("Общие герои") {
                    Text("от 10 игр у обоих").font(.caption).foregroundStyle(.secondary)
                } content: {
                    VStack(spacing: 10) {
                        ForEach(shared, id: \.mine.heroID) { pair in
                            let hero = me.hero(pair.mine.heroID)
                            HStack(spacing: 10) {
                                Text(percent(pair.mine.winrate))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(pair.mine.winrate >= pair.theirs.winrate ? Theme.gold : .secondary)
                                    .frame(width: 52, alignment: .leading)
                                Spacer()
                                HeroPortrait(hero: hero, width: 52)
                                Text(hero.name).font(.caption).lineLimit(1).frame(width: 100)
                                Spacer()
                                Text(percent(pair.theirs.winrate))
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(pair.theirs.winrate > pair.mine.winrate ? Theme.gold : .secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        } else if case .failed(let message) = friend.currentStats {
            ErrorView(message: message) { await friend.loadAll(policy: .reload) }
        } else {
            LoadingView(text: "Загружаем статистику друга…")
        }
    }

    /// Строка сравнения: у кого лучше — подсвечено золотом.
    private func row<T: Comparable>(_ title: String, _ mine: T, _ theirs: T, lowerIsBetter: Bool = false,
                                    format: (T) -> String) -> some View {
        let iWin = lowerIsBetter ? mine < theirs : mine > theirs
        let theyWin = lowerIsBetter ? theirs < mine : theirs > mine
        return HStack {
            Text(format(mine))
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(iWin ? Theme.gold : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(format(theirs))
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(theyWin ? Theme.gold : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func sharedHeroes(_ a: ModeStats, _ b: ModeStats) -> [(mine: HeroRecord, theirs: HeroRecord)] {
        let theirs = Dictionary(uniqueKeysWithValues: b.playedHeroes.map { ($0.heroID, $0) })
        return a.playedHeroes
            .compactMap { mine in theirs[mine.heroID].map { (mine, $0) } }
            .filter { $0.0.games >= 10 && $0.1.games >= 10 }
            .sorted { $0.0.games + $0.1.games > $1.0.games + $1.1.games }
            .prefix(8)
            .map { (mine: $0.0, theirs: $0.1) }
    }
}

private struct PlayerHeader: View {
    let store: PlayerStore
    let isMe: Bool

    var body: some View {
        VStack(spacing: 8) {
            let s = store.summary.value
            RemoteImage(url: s?.avatarURL)
                .frame(width: 64, height: 64)
                .clipShape(.circle)
                .overlay(Circle().strokeBorder(isMe ? Theme.gold : .white.opacity(0.4), lineWidth: 2))
            Text(s?.nickname ?? "…")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let rank = s?.rank {
                RankBadge(rank: rank, size: 40)
            }
            if let top = store.currentStats.value?.playedHeroes.first {
                HeroPortrait(hero: store.hero(top.heroID), width: 72)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
