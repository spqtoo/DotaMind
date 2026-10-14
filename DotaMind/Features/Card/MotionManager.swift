//
//  MotionManager.swift
//  DotaMind
//
//  Наклон телефона для голографической карточки.
//

import CoreMotion
import Observation
import SwiftUI

/// Отдаёт наклон устройства в диапазоне −1…1 по обеим осям.
/// «Ноль» — то положение, в котором пользователь держит телефон: опорная точка
/// медленно подтягивается к текущему положению, поэтому карточка сама
/// возвращается в центр, если сменить позу.
// ANDROID: SensorManager + TYPE_GRAVITY (или GAME_ROTATION_VECTOR), та же логика дрейфа опорной точки и low-pass.
@MainActor
@Observable
final class MotionManager {
    static let shared = MotionManager()

    private(set) var tilt: CGSize = .zero
    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var reference: SIMD3<Double>?
    @ObservationIgnored private var subscribers = 0

    private init() {
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func start() {
        subscribers += 1
        guard subscribers == 1, motion.isDeviceMotionAvailable else { return }
        reference = nil
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let g = data?.gravity else { return }
            let gravity = SIMD3(g.x, g.y, g.z)
            MainActor.assumeIsolated { self?.handle(gravity) }
        }
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        motion.stopDeviceMotionUpdates()
        tilt = .zero
    }

    private func handle(_ gravity: SIMD3<Double>) {
        let ref = reference ?? gravity
        // Медленный дрейф опорной точки — ~3 секунды до полного «перецентрирования».
        reference = ref + (gravity - ref) * 0.006

        let sensitivity = 3.2
        let x = ((gravity.x - ref.x) * sensitivity).clamped(to: -1...1)
        let y = ((gravity.y - ref.y) * -sensitivity).clamped(to: -1...1)

        // Лёгкий low-pass, чтобы убрать дрожание рук.
        tilt = CGSize(width: tilt.width + (x - tilt.width) * 0.25,
                      height: tilt.height + (y - tilt.height) * 0.25)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
