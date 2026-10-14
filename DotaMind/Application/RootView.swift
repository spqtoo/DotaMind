//
//  RootView.swift
//  DotaMind
//

import SwiftUI

/// Корень приложения: экран входа или три вкладки.
/// Таб-бар — стандартный TabView: на iOS 26 он сам рисуется в Liquid Glass.
struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        content
            .animation(.smooth, value: auth.steamID64)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let steamID = auth.steamID64 {
                MainTabView(steamID64: steamID)
                    // Новый аккаунт — новая иерархия, чтобы не тащить чужие данные.
                    .id(steamID)
            } else {
                LoginView()
            }
        }
    }
}

private struct MainTabView: View {
    let steamID64: String

    @State private var selection: Tab = Self.initialTab
    @AppStorage(SettingsKeys.defaultMode) private var defaultMode: StatsMode = .turbo
    @State private var store: PlayerStore?

    enum Tab: String, Hashable { case profile, matches, draft, settings }

    /// DEBUG: `-DMTab matches` открывает нужную вкладку (для скриншотов).
    private static var initialTab: Tab {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "DMTab"), let tab = Tab(rawValue: raw) { return tab }
        #endif
        return .profile
    }

    private var signatureAttribute: String? {
        guard let store, let top = store.currentStats.value?.playedHeroes.first else { return nil }
        return store.hero(top.heroID).primaryAttribute
    }

    var body: some View {
        // ANDROID (Material 3): TabView → NavigationBar (снизу) на телефоне, NavigationRail на планшете/раскладушке.
        TabView(selection: $selection) {
            SwiftUI.Tab("Профиль", systemImage: "person.crop.rectangle.stack", value: Tab.profile) {
                if let store { ProfileView(store: store) }
            }
            SwiftUI.Tab("Матчи", systemImage: "list.bullet.rectangle.portrait", value: Tab.matches) {
                if let store { MatchesView(store: store) }
            }
            SwiftUI.Tab("Драфт", systemImage: "square.grid.3x2", value: Tab.draft) {
                if let store { DraftView(store: store) }
            }
            SwiftUI.Tab("Настройки", systemImage: "gearshape", value: Tab.settings) {
                if let store { SettingsView(store: store) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Фон всех экранов окрашен главным героем игрока в текущем режиме.
        .environment(\.ambientArt, store?.signatureArt)
        .environment(\.ambientTint, Theme.attributeColor(signatureAttribute))
        .onChange(of: selection) { Haptics.shared.selectionChanged() }
        .onAppear {
            if store == nil {
                store = PlayerStore(steamID64: steamID64, mode: defaultMode)
            }
        }
    }
}
