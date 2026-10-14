//
//  Haptics.swift
//  DotaMind
//
//  Created by Степан Соловьёв on 05.11.2025.
//

import UIKit

// ANDROID: LocalHapticFeedback / View.performHapticFeedback(HapticFeedbackConstants.CONFIRM …).
@MainActor
public final class Haptics {

    public static let shared = Haptics()

    // MARK: - Configuration

    // Включение/выключение хаптиков пользователем
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isEnabled) }
    }

    // Минимальный интервал между срабатываниями, чтобы не спамить
    public var minimumInterval: TimeInterval = 0.035

    // Если включён режим энергосбережения — можно ослаблять или пропускать
    public var respectLowPowerMode: Bool = true

    private enum Keys {
        static let isEnabled = "haptics.isEnabled"
    }

    // MARK: - Generators cache

    private var notificationGenerator: UINotificationFeedbackGenerator?
    private var selectionGenerator: UISelectionFeedbackGenerator?
    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private var lastFireDate: Date?

    private init() {
        // По умолчанию включено, если ещё не задано
        if UserDefaults.standard.object(forKey: Keys.isEnabled) == nil {
            UserDefaults.standard.set(true, forKey: Keys.isEnabled)
        }
    }

    // MARK: - Public API

    /// Разогреть генераторы, например вызвать в AppDelegate/SceneDelegate при старте
    public func prewarm() {
        guard isAllowed else { return }
        prepareNotification()
        prepareSelection()
        prepareImpact(.light)
        prepareImpact(.medium)
        prepareImpact(.heavy)
        if #available(iOS 13.0, *) {
            prepareImpact(.soft)
            prepareImpact(.rigid)
        }
    }

    // Notifications: success, warning, error
    public func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard canFire else { return }
        let generator = notificationGenerator ?? {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            notificationGenerator = g
            return g
        }()
        generator.notificationOccurred(type)
        didFire()
    }

    // Selection change (например, при выборе пункта меню/таба)
    public func selectionChanged() {
        guard canFire else { return }
        let generator = selectionGenerator ?? {
            let g = UISelectionFeedbackGenerator()
            g.prepare()
            selectionGenerator = g
            return g
        }()
        generator.selectionChanged()
        didFire()
    }

    // Удобные шорткаты
    public func success() { notification(.success) }
    public func warning() { notification(.warning) }
    public func error()   { notification(.error) }

    public func light(intensity: CGFloat? = nil)  { impact(.light, intensity: intensity) }
    public func medium(intensity: CGFloat? = nil) { impact(.medium, intensity: intensity) }
    public func heavy(intensity: CGFloat? = nil)  { impact(.heavy, intensity: intensity) }

    @available(iOS 13.0, *)
    public func soft(intensity: CGFloat? = nil)   { impact(.soft, intensity: intensity) }

    @available(iOS 13.0, *)
    public func rigid(intensity: CGFloat? = nil)  { impact(.rigid, intensity: intensity) }

    // MARK: - Impact

    public func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat? = nil) {
        guard canFire else { return }
        let generator = impactGenerators[style] ?? {
            let g = UIImpactFeedbackGenerator(style: style)
            g.prepare()
            impactGenerators[style] = g
            return g
        }()

        if let intensity, #available(iOS 13.0, *) {
            generator.impactOccurred(intensity: clamp(intensity, 0...1))
        } else {
            generator.impactOccurred()
        }
        didFire()
    }

    // MARK: - Prepare (optional, но полезно перед анимациями)

    public func prepareNotification() {
        guard isAllowed else { return }
        if notificationGenerator == nil {
            notificationGenerator = UINotificationFeedbackGenerator()
        }
        notificationGenerator?.prepare()
    }

    public func prepareSelection() {
        guard isAllowed else { return }
        if selectionGenerator == nil {
            selectionGenerator = UISelectionFeedbackGenerator()
        }
        selectionGenerator?.prepare()
    }

    public func prepareImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isAllowed else { return }
        if impactGenerators[style] == nil {
            impactGenerators[style] = UIImpactFeedbackGenerator(style: style)
        }
        impactGenerators[style]?.prepare()
    }

    // MARK: - Helpers

    private var isAllowed: Bool {
        guard isEnabled else { return false }
        if respectLowPowerMode, ProcessInfo.processInfo.isLowPowerModeEnabled {
            // В режиме энергосбережения можно “смягчить” стратегию:
            // либо полностью запретить, либо оставить только лёгкие импакты.
            return true
        }
        return true
    }

    private var canFire: Bool {
        guard isAllowed else { return false }
        if let last = lastFireDate, Date().timeIntervalSince(last) < minimumInterval {
            return false
        }
        return true
    }

    private func didFire() {
        lastFireDate = Date()
        // Подготовим повторный удар, чтобы снизить латентность
        notificationGenerator?.prepare()
        selectionGenerator?.prepare()
        impactGenerators.values.forEach { $0.prepare() }
    }

    private func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
