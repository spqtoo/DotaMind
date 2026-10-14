//
//  SettingsView.swift
//  DotaMind
//

import SwiftUI

// ANDROID (Material 3): LazyColumn из ListItem + Switch; секции — заголовки labelLarge.
struct SettingsView: View {
    let store: PlayerStore

    @Environment(AuthManager.self) private var auth
    @AppStorage(SettingsKeys.defaultMode) private var defaultMode: StatsMode = .turbo
    @AppStorage(SettingsKeys.tiltEnabled) private var tiltEnabled = true
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(MatchNotifier.enabledKey) private var notifyMatches = false

    @State private var refreshState: RefreshState = .idle
    @State private var confirmSignOut = false

    enum RefreshState: Equatable { case idle, running, done, failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let s = store.summary.value {
                        HStack(spacing: 14) {
                            RemoteImage(url: s.avatarURL)
                                .frame(width: 52, height: 52)
                                .clipShape(.circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.nickname).font(.headline)
                                Text("Friend ID: \(String(s.accountID))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        if let url = URL(string: "https://www.opendota.com/players/\(s.accountID)") {
                            Link("Открыть на OpenDota", destination: url)
                        }
                    }
                    Button("Выйти", role: .destructive) { confirmSignOut = true }
                } header: {
                    Text("Аккаунт")
                }

                Section {
                    Picker("Режим по умолчанию", selection: $defaultMode) {
                        ForEach(StatsMode.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Статистика")
                } footer: {
                    Text(defaultMode.subtitle)
                }

                Section {
                    if let s = store.summary.value {
                        Button {
                            UIPasteboard.general.string = String(s.accountID)
                            Haptics.shared.success()
                        } label: {
                            LabeledContent("Скопировать Friend ID", value: String(s.accountID))
                        }
                    }
                } header: {
                    Text("Виджет")
                } footer: {
                    Text("Добавь виджет DotaMind на экран «Домой», удерживай его → «Изменить виджет» и вставь Friend ID. Там же выбирается режим: Turbo, обычные или все.")
                }

                Section {
                    Toggle("Уведомлять о новых матчах", isOn: $notifyMatches)
                        .onChange(of: notifyMatches) { _, on in
                            guard on else { MatchNotifier.schedule(); return }
                            Task {
                                if await MatchNotifier.requestPermission() {
                                    MatchNotifier.schedule()
                                } else {
                                    notifyMatches = false
                                }
                            }
                        }
                } header: {
                    Text("Уведомления")
                } footer: {
                    Text("После матча придёт результат и изменение турбо-рейтинга. iOS сама решает, когда проверять — обычно раз в 20–60 минут, поэтому уведомление может прийти не сразу.")
                }

                Section("Интерфейс") {
                    Toggle("Наклон карточки по гироскопу", isOn: $tiltEnabled)
                    Toggle("Вибрация", isOn: $hapticsEnabled)
                }

                Section {
                    Button {
                        Task { await requestRefresh() }
                    } label: {
                        HStack {
                            Text("Запросить обновление истории")
                            Spacer()
                            switch refreshState {
                            case .running: ProgressView()
                            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            case .idle: EmptyView()
                            }
                        }
                    }
                    .disabled(refreshState == .running)
                    Button("Очистить кэш") {
                        Task { await store.clearCache() }
                    }
                } header: {
                    Text("Данные")
                } footer: {
                    if case .failed(let message) = refreshState {
                        Text(message)
                    } else {
                        Text("Статистика берётся из OpenDota. Если матчей не хватает — в Доте включи «Настройки → Социальное → Expose Public Match Data» и запроси обновление: OpenDota подтянет историю за несколько минут.")
                    }
                }

                Section {
                    LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    Link("Данные: OpenDota API", destination: URL(string: "https://www.opendota.com")!)
                } footer: {
                    Text("DotaMind не связан с Valve. Dota 2 — товарный знак Valve Corporation.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Настройки")
            .task { await store.loadIfNeeded() }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { auth.signOut() }
            }
        }
    }

    private func requestRefresh() async {
        refreshState = .running
        do {
            try await store.requestHistoryRefresh()
            refreshState = .done
            Haptics.shared.success()
        } catch {
            refreshState = .failed(error.localizedDescription)
            Haptics.shared.error()
        }
    }
}
