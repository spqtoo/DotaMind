//
//  Theme.swift
//  DotaMind
//
//  Тёмная тема в духе Доты. Палитра намеренно узкая: золото — акцент
//  бренда, зелёный/красный — только победа/поражение, остальное —
//  оттенки белого. Фон — приглушённый размытый арт главного героя.
//

import SwiftUI

// ANDROID (Material 3): darkColorScheme(primary = gold, …) + свои tertiary/error для win/loss. Dynamic Color выключить — у приложения свой бренд.
enum Theme {
    static let gold = Color(red: 0.98, green: 0.76, blue: 0.36)
    /// Приглушённые «изумруд» и «гранат»: спокойнее неоновых зелёного и красного.
    static let win = Color(red: 0.24, green: 0.70, blue: 0.52)
    static let loss = Color(red: 0.80, green: 0.30, blue: 0.34)

    /// Цвет основного атрибута героя (как в самой Доте).
    static func attributeColor(_ attribute: String?) -> Color {
        switch attribute {
        case "str": Color(red: 0.93, green: 0.32, blue: 0.25)
        case "agi": Color(red: 0.30, green: 0.85, blue: 0.45)
        case "int": Color(red: 0.30, green: 0.62, blue: 1.00)
        case "all": Color(red: 0.85, green: 0.60, blue: 1.00)
        default: gold
        }
    }
}

extension Font {
    /// Крупные цифры и заголовки: SF Pro с табличными цифрами.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Фон

/// Арт и цвет, которыми окрашен фон экранов. Задаются один раз в RootView.
extension EnvironmentValues {
    @Entry var ambientArt: URL? = nil
    @Entry var ambientTint: Color = Theme.gold
}

/// Статичный фон: размытый арт героя + цветное свечение на почти чёрном.
/// Специально без анимации: стекло поверх анимированного фона пересчитывает
/// преломление каждый кадр, и интерфейс начинает подтормаживать.
// ANDROID (Material 3): Box с AsyncImage(blur 60dp через Modifier.blur, Android 12+) + Brush.radialGradient; ниже 12 — без блюра, только градиент.
struct AppBackground: View {
    @Environment(\.ambientArt) private var art
    @Environment(\.ambientTint) private var tint

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07)

            if let art {
                RemoteImage(url: art)
                    .frame(height: 480)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .blur(radius: 60)
                    .opacity(0.32)
                    .transition(.opacity)
            }

            RadialGradient(colors: [tint.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 500)
            LinearGradient(colors: [.clear, Color(red: 0.03, green: 0.03, blue: 0.06).opacity(0.9)],
                           startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom)
        }
        .compositingGroup()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: art)
        .accessibilityHidden(true)
    }
}
