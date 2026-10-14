//
//  HeroListView.swift
//  DotaMind
//

import SwiftUI

/// Все сыгранные герои с поиском и сортировкой.
struct HeroListView: View {
    let store: PlayerStore

    @State private var query = ""
    @State private var sort: Sort = .games

    enum Sort: String, CaseIterable, Identifiable {
        case games = "По играм"
        case winrate = "По винрейту"
        case recent = "Недавние"
        var id: String { rawValue }
    }

    private var records: [HeroRecord] {
        let played = (store.currentStats.value?.heroes ?? []).filter { $0.games > 0 }
        let filtered = query.isEmpty ? played : played.filter {
            store.hero($0.heroID).name.localizedStandardContains(query)
        }
        switch sort {
        case .games: return filtered
        // Для сортировки по винрейту отсекаем случайные 1–2 игры.
        case .winrate: return filtered.filter { $0.games >= 5 }.sorted { $0.winrate > $1.winrate }
        case .recent: return filtered.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
    }

    var body: some View {
        List(records) { record in
            NavigationLink(value: record) {
                HeroRow(record: record, hero: store.hero(record.heroID))
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Герои · \(store.mode.title)")
        .searchable(text: $query, prompt: "Найти героя")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }
}
