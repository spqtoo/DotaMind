//
//  DotaMindApp.swift
//  DotaMind
//

import SwiftUI

@main
struct DotaMindApp: App {
    @State private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // AsyncImage ходит через URLSession.shared — даём ему нормальный кэш,
        // чтобы портреты героев и аватары не качались каждый раз заново.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 300 * 1024 * 1024)
        Haptics.shared.prewarm()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                // Дота — тёмная игра: тёмная тема и золотой акцент всегда.
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { MatchNotifier.schedule() }
        }
        // Фоновая проверка новых матчей → локальное уведомление.
        .backgroundTask(.appRefresh(MatchNotifier.taskID)) {
            await MatchNotifier.check()
        }
    }
}
