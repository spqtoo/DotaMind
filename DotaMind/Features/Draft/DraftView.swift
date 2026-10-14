//
//  DraftView.swift
//  DotaMind
//
//  Вкладка «Драфт»: выбираешь врагов (и союзников) — получаешь своих
//  героев с лучшим ожидаемым винрейтом по ТВОЕЙ статистике.
//

import SwiftUI

struct DraftView: View {
    let store: PlayerStore

    @State private var enemies: [Int] = []
    @State private var allies: [Int] = []
    @State private var picking: Side?
    @State private var result: Loadable<[DraftSuggestion]> = .idle

    enum Side: String, Identifiable {
        case enemy, ally
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ModePicker(store: store)
                    // ANDROID (Material 3): слоты — OutlinedCard / InputChip; выбор героя — ModalBottomSheet.
                    slots(title: "Враги", heroes: enemies, max: 5, side: .enemy)
                    slots(title: "Союзники", heroes: allies, max: 4, side: .ally)
                    results
                }
                .padding(16)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { AppBackground() }
            .navigationTitle("Драфт")
            .toolbar {
                if !enemies.isEmpty || !allies.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сбросить") {
                            withAnimation { enemies = []; allies = [] }
                        }
                    }
                }
            }
            .sheet(item: $picking) { side in
                HeroPicker(store: store, excluded: Set(enemies + allies)) { hero in
                    withAnimation {
                        if side == .enemy { enemies.append(hero) } else { allies.append(hero) }
                    }
                }
            }
            .task(id: TaskKey(enemies: enemies, allies: allies, mode: store.mode, loaded: store.currentStats.value != nil)) {
                await recalculate()
            }
            .task { await store.loadIfNeeded() }
            #if DEBUG
            // `-DMDraft 2,8,14` — сразу выбрать врагов (для скриншотов).
            .onAppear {
                if enemies.isEmpty, let raw = UserDefaults.standard.string(forKey: "DMDraft") {
                    enemies = raw.split(separator: ",").compactMap { Int($0) }
                }
            }
            #endif
            .navigationDestination(for: HeroRecord.self) { HeroDetailView(store: store, record: $0) }
            .navigationDestination(for: MatchRoute.self) { MatchDetailView(store: store, matchID: $0.id) }
        }
    }

    private struct TaskKey: Equatable {
        let enemies: [Int], allies: [Int], mode: StatsMode, loaded: Bool
    }

    private func slots(title: String, heroes: [Int], max: Int, side: Side) -> some View {
        GlassSection(title) {
            Text("\(heroes.count)/\(max)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(heroes, id: \.self) { id in
                    Button {
                        Haptics.shared.light()
                        withAnimation {
                            if side == .enemy { enemies.removeAll { $0 == id } } else { allies.removeAll { $0 == id } }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            HeroPortrait(hero: store.hero(id), width: 92)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .padding(3)
                                }
                            Text(store.hero(id).name).font(.caption2).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Убрать \(store.hero(id).name)")
                }
                if heroes.count < max {
                    Button { picking = side } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.secondary)
                                .frame(width: 92, height: 52)
                                .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                            Text("Добавить").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if enemies.isEmpty && allies.isEmpty {
            ContentUnavailableView("Добавь героев врага",
                                   systemImage: "person.3.sequence",
                                   description: Text("Подскажу, на ком у тебя лучше шансы против этого драфта — по твоим собственным матчам в режиме «\(store.mode.title)»."))
        } else {
            switch result {
            case .loaded(let list) where list.isEmpty:
                ContentUnavailableView("Мало данных", systemImage: "questionmark.circle",
                                       description: Text("Сыграй больше матчей в этом режиме — нужно от 5 игр на герое."))
            case .loaded(let list):
                GlassSection("Тебе подойдут") {
                    Text("ожидаемый винрейт").font(.caption).foregroundStyle(.secondary)
                } content: {
                    VStack(spacing: 14) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, s in
                            suggestionRow(s, place: index + 1)
                        }
                    }
                }
            case .failed(let message):
                ErrorView(message: message) { await recalculate() }
            default:
                LoadingView(text: "Считаем драфт…")
            }
        }
    }

    private func suggestionRow(_ s: DraftSuggestion, place: Int) -> some View {
        let hero = store.hero(s.heroID)
        let record = store.currentStats.value?.heroes.first { $0.heroID == s.heroID }
        return NavigationLink(value: record) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("\(place)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(place <= 3 ? Theme.gold : .secondary)
                        .frame(width: 18)
                    HeroPortrait(hero: hero, width: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(hero.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                            Spacer()
                            Text(percent(s.score))
                                .font(.system(size: 17, weight: .bold).monospacedDigit())
                                .foregroundStyle(winrateColor(s.score))
                        }
                        WinrateBar(winrate: s.score)
                        Text("обычно \(percent(s.baseWinrate)) · \(s.games) \(plural(s.games, "игра", "игры", "игр"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !s.reasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(s.reasons) { r in
                                let wr = r.games > 0 ? Double(r.wins) / Double(r.games) : 0
                                HStack(spacing: 4) {
                                    Text(r.isEnemy ? "vs" : "c").foregroundStyle(.secondary)
                                    Text(store.hero(r.heroID).name).lineLimit(1)
                                    Text("\(r.wins)–\(r.games - r.wins)").foregroundStyle(winrateColor(wr))
                                }
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.07), in: .capsule)
                            }
                        }
                        .padding(.leading, 30)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(record == nil)
    }

    private func recalculate() async {
        guard !(enemies.isEmpty && allies.isEmpty), store.currentStats.value != nil else { return }
        if result.value == nil { result = .loading }
        do {
            // Небольшая пауза: если человек быстро добавляет героев, не шлём лишние запросы.
            try await Task.sleep(for: .milliseconds(350))
            result = .loaded(try await store.draft(enemies: enemies, allies: allies))
        } catch is CancellationError {
        } catch {
            result = .failed(error.localizedDescription)
        }
    }
}

/// Сетка всех героев с поиском и фильтром по атрибуту.
struct HeroPicker: View {
    let store: PlayerStore
    let excluded: Set<Int>
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var attribute: String?

    private var heroes: [Hero] {
        store.heroes.values
            .filter { !excluded.contains($0.id) }
            .filter { attribute == nil || $0.primaryAttribute == attribute }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 12) {
                    ForEach(heroes) { hero in
                        Button {
                            Haptics.shared.selectionChanged()
                            onPick(hero.id)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                HeroPortrait(hero: hero, width: 96)
                                Text(hero.name).font(.caption2).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background { AppBackground() }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти героя")
            .navigationTitle("Выбери героя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Атрибут", selection: $attribute) {
                            Text("Все").tag(String?.none)
                            Text("Сила").tag(String?.some("str"))
                            Text("Ловкость").tag(String?.some("agi"))
                            Text("Интеллект").tag(String?.some("int"))
                            Text("Универсальные").tag(String?.some("all"))
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
