//
//  LoginView.swift
//  DotaMind
//

import SwiftUI

// ANDROID (Material 3): FilledButton «Войти через Steam» + OutlinedTextField для Friend ID.
struct LoginView: View {
    @Environment(AuthManager.self) private var auth

    @State private var manualID = ""
    @State private var manualError: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                VStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Theme.gold.gradient)
                    Text("DotaMind")
                        .font(.largeTitle.weight(.bold))
                    Text("Статистика, которой нет в самой Доте:\nтвои герои и винрейт в Turbo.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await auth.signInWithSteam() }
                } label: {
                    HStack {
                        if auth.isSigningIn { ProgressView() }
                        Text("Войти через Steam").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(auth.isSigningIn)

                if let error = auth.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Или по Friend ID / ссылке на профиль")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("123456789 или steamcommunity.com/profiles/…", text: $manualID)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($fieldFocused)
                            .submitLabel(.go)
                            .onSubmit(submitManual)
                        Button("Найти", action: submitManual)
                            .buttonStyle(.glass)
                            .disabled(manualID.isEmpty)
                    }
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                    Text(manualError ?? "Friend ID — в Доте: Профиль → идентификатор под ником.")
                        .font(.caption)
                        .foregroundStyle(manualError == nil ? Color.secondary : Color.red)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground() }
    }

    private func submitManual() {
        guard let id = SteamID.parse(manualID) else {
            manualError = "Не похоже на SteamID. Короткие ссылки вида /id/имя пока не поддерживаются."
            Haptics.shared.error()
            return
        }
        manualError = nil
        fieldFocused = false
        Task { await auth.signIn(steamID64: id) }
    }
}
