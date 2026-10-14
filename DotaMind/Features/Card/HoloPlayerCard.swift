//
//  HoloPlayerCard.swift
//  DotaMind
//
//  Карточка игрока в стиле суперредкой коллекционной карты:
//  голографическая фольга (HoloFoil.metal), блик, светящаяся радужная рамка
//  и 3D-наклон от гироскопа. Тап — перевернуть, долгое нажатие + движение
//  пальцем — покрутить вручную (в симуляторе гироскопа нет — там карточка
//  сама слегка покачивается).
//
//  Производительность: лицевая и оборотная стороны — Equatable и
//  растеризуются (drawingGroup), поэтому при наклоне их body не
//  пересчитывается. Каждый кадр меняются только 3D-трансформ и параметры
//  шейдера; рамка «бежит» через hueRotation поверх готового слоя.
//

import SwiftUI

/// Всё, что рисует карточка. Equatable — чтобы SwiftUI не перерисовывал
/// стороны карточки, пока данные не изменились.
struct CardModel: Equatable {
    struct TopHero: Equatable, Identifiable {
        let id: Int
        let name: String
        let imageURL: URL?
        let winrate: Double
        let games: Int
    }

    var nickname: String
    var accountID: Int
    var avatarURL: URL?
    var rank: Rank?
    /// Подпись под значком ранга: в Turbo показываем оценочный Turbo-ранг.
    var rankCaption: String?
    var modeTitle: String
    var signature: TopHero?
    var signatureAttribute: String?
    var topHeroes: [TopHero]
    var games: Int?
    var wins: Int?
    var losses: Int?
    var winrate: Double?
    var averages: Averages?
    var uniqueHeroes: Int?
    var radiantWinrate: Double?
    var direWinrate: Double?

    @MainActor
    init(summary: PlayerSummary, stats: ModeStats?, mode: StatsMode, turboRating: TurboRating? = nil, hero: (Int) -> Hero) {
        nickname = summary.nickname
        accountID = summary.accountID
        avatarURL = summary.avatarURL
        if mode == .turbo, let turboRating {
            rank = turboRating.rank
            rankCaption = "≈\(turboRating.rating)"
        } else {
            rank = summary.rank
        }
        modeTitle = mode.title
        let played = stats?.playedHeroes ?? []
        topHeroes = played.prefix(3).map {
            let h = hero($0.heroID)
            return TopHero(id: h.id, name: h.name, imageURL: h.imageURL, winrate: $0.winrate, games: $0.games)
        }
        signature = topHeroes.first
        signatureAttribute = played.first.map { hero($0.heroID).primaryAttribute } ?? nil
        games = stats?.games
        wins = stats?.wins
        losses = stats?.losses
        winrate = stats?.winrate
        averages = stats?.details?.averages
        uniqueHeroes = stats.map { $0.playedHeroes.count }
        radiantWinrate = stats?.details?.radiant.winrate
        direWinrate = stats?.details?.dire.winrate
    }
}

// ANDROID: голограмма — AGSL RuntimeShader (Android 13+, перенести HoloFoil.metal почти 1:1) через Modifier.graphicsLayer { renderEffect }; ниже 13 — без фольги.
// ANDROID: 3D-наклон — graphicsLayer { rotationX/rotationY; cameraDistance }. Рамка — Brush.sweepGradient с анимацией угла.
struct HoloPlayerCard: View {
    let model: CardModel

    @AppStorage(SettingsKeys.tiltEnabled) private var tiltEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragTilt: CGSize?
    @State private var flipAngle: Double = 0
    @State private var cardSize: CGSize = .zero

    private let corner: CGFloat = 28

    var body: some View {
        TiltSource(enabled: tiltEnabled && !reduceMotion, override: dragTilt) { tilt, time in
            ZStack {
                CardFront(model: model)
                    .equatable()
                    .drawingGroup()
                    .modifier(FaceVisibility(angle: flipAngle, isFront: true))
                CardBack(model: model)
                    .equatable()
                    .drawingGroup()
                    .rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                    .modifier(FaceVisibility(angle: flipAngle, isFront: false))
            }
            .overlay { FoilLayer(size: cardSize, tilt: tilt, time: time) }
            .clipShape(.rect(cornerRadius: corner))
            .overlay { RainbowBorder(corner: corner, lineWidth: 2.5, animated: !reduceMotion) }
            .background { CardGlow(corner: corner, animated: !reduceMotion) }
            .rotation3DEffect(.degrees(flipAngle), axis: (0, 1, 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tilt.height * 12), axis: (1, 0, 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tilt.width * -12), axis: (0, 1, 0), perspective: 0.5)
        }
        .aspectRatio(63.0 / 88.0, contentMode: .fit)
        .onGeometryChange(for: CGSize.self, of: \.size) { cardSize = $0 }
        .contentShape(.rect(cornerRadius: corner))
        .onTapGesture { flip() }
        .simultaneousGesture(manualTiltGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Нажми, чтобы перевернуть карточку")
        .accessibilityAction(named: "Перевернуть") { flip() }
    }

    private var accessibilitySummary: String {
        var parts = ["Карточка игрока \(model.nickname)", model.modeTitle]
        if let games = model.games { parts.append("\(games) матчей") }
        if let wr = model.winrate { parts.append("винрейт \(percent(wr))") }
        if let rank = model.rank { parts.append(rank.title) }
        return parts.joined(separator: ", ")
    }

    private var manualTiltGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragTilt == nil { Haptics.shared.soft() }
                let location = drag?.location ?? CGPoint(x: cardSize.width / 2, y: cardSize.height / 2)
                let x = (location.x / max(cardSize.width, 1) * 2 - 1).clamped(to: -1...1)
                let y = (location.y / max(cardSize.height, 1) * 2 - 1).clamped(to: -1...1)
                withAnimation(.interactiveSpring) { dragTilt = CGSize(width: -x, height: y) }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { dragTilt = nil }
            }
    }

    private func flip() {
        Haptics.shared.medium()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            flipAngle = flipAngle == 0 ? 180 : 0
        }
    }
}

// MARK: - Источник наклона

/// Отдаёт наклон: палец > гироскоп > покачивание (если гироскопа нет).
/// Перерисовывается только этот контейнер, а не данные карточки.
private struct TiltSource<Content: View>: View {
    let enabled: Bool
    let override: CGSize?
    @ViewBuilder let content: (CGSize, Double) -> Content

    @State private var motion = MotionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let override {
                content(override, 0)
            } else if !enabled {
                content(.zero, 0)
            } else if motion.isAvailable {
                content(motion.tilt, 0)
            } else {
                TimelineView(.animation(paused: scenePhase != .active)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    content(CGSize(width: sin(t * 0.7) * 0.55, height: cos(t * 0.5) * 0.35), t.truncatingRemainder(dividingBy: 1000))
                }
            }
        }
        .onAppear { if enabled { motion.start() } }
        .onDisappear { if enabled { motion.stop() } }
        .onChange(of: enabled) { _, on in on ? motion.start() : motion.stop() }
    }
}

// MARK: - Эффекты

private struct FoilLayer: View {
    let size: CGSize
    let tilt: CGSize
    let time: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .colorEffect(ShaderLibrary.holoFoil(.float2(size), .float2(tilt), .float(time), .float(0.7)))
                .blendMode(.plusLighter)
                .opacity(0.45)

            // Мягкий белый блик — как свет лампы на глянце.
            RadialGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.05), .clear],
                center: UnitPoint(x: 0.5 - tilt.width * 0.5, y: 0.4 - tilt.height * 0.5),
                startRadius: 0,
                endRadius: max(size.width, 1) * 0.9
            )
            .blendMode(.softLight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private let rainbow: [Color] = (0...12).map {
    Color(hue: Double($0) / 12, saturation: 0.75, brightness: 1)
}

/// Радужная рамка. Цвета «бегут» за счёт анимированного hueRotation —
/// геометрия и градиент не пересчитываются.
private struct RainbowBorder: View {
    let corner: CGFloat
    let lineWidth: CGFloat
    let animated: Bool
    @State private var hue: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .strokeBorder(AngularGradient(colors: rainbow, center: .center), lineWidth: lineWidth)
            .hueRotation(.degrees(hue))
            .allowsHitTesting(false)
            .onAppear {
                guard animated else { return }
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { hue = 360 }
            }
    }
}

/// Свечение вокруг карточки: размытие считается один раз (drawingGroup),
/// дальше анимируется только оттенок.
private struct CardGlow: View {
    let corner: CGFloat
    let animated: Bool
    @State private var hue: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .strokeBorder(AngularGradient(colors: rainbow, center: .center), lineWidth: 12)
            // Запас вокруг, чтобы размытие не обрезалось по границе слоя.
            .padding(40)
            .blur(radius: 18)
            .drawingGroup()
            .padding(-40)
            .hueRotation(.degrees(hue))
            .opacity(0.85)
            .allowsHitTesting(false)
            .onAppear {
                guard animated else { return }
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { hue = 360 }
            }
    }
}

/// Показывает только ту сторону, которая сейчас повёрнута к зрителю.
/// Animatable — чтобы переключение происходило ровно на 90°.
private struct FaceVisibility: ViewModifier, Animatable {
    var angle: Double
    let isFront: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity((angle < 90) == isFront ? 1 : 0)
    }
}

// MARK: - Лицевая сторона

private struct CardFront: View, Equatable {
    let model: CardModel

    private var accent: Color { Theme.attributeColor(model.signatureAttribute) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Шапка: ник и режим
            HStack(alignment: .center, spacing: 8) {
                Text(model.nickname)
                    .font(.display(22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 4)
                Text(model.modeTitle.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.gold.gradient, in: .capsule)
            }

            // «Окно» с артом главного героя
            ZStack(alignment: .bottom) {
                RemoteImage(url: model.signature?.imageURL)
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    }
                HStack(alignment: .bottom, spacing: 10) {
                    RemoteImage(url: model.avatarURL)
                        .frame(width: 54, height: 54)
                        .clipShape(.circle)
                        .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ГЛАВНЫЙ ГЕРОЙ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent)
                        Text(model.signature?.name ?? "—")
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let s = model.signature {
                            Text("\(s.games) \(plural(s.games, "игра", "игры", "игр")) · \(percent(s.winrate))")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .opacity(0.85)
                        }
                    }
                    Spacer(minLength: 0)
                    if let rank = model.rank {
                        VStack(spacing: 0) {
                            RankBadge(rank: rank, size: 58)
                            if let caption = model.rankCaption {
                                Text(caption)
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.3), Theme.gold],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            )

            // Главные цифры
            HStack(spacing: 0) {
                bigStat(model.games.map { $0.formatted() } ?? "—", "матчей")
                divider
                bigStat(model.winrate.map(percent) ?? "—", "побед", tint: model.winrate.map(winrateColor) ?? .white)
                divider
                bigStat(model.averages.map { Format.number($0.kda, digits: 2) } ?? "…", "KDA")
            }

            // Топ-3 героя
            HStack(spacing: 8) {
                ForEach(model.topHeroes) { hero in
                    VStack(spacing: 5) {
                        RemoteImage(url: hero.imageURL)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 8))
                        Text(percent(hero.winrate))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(winrateColor(hero.winrate))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Text("DOTAMIND")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                Spacer()
                Text("★ HOLO RARE · #\(String(model.accountID))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(Theme.gold.opacity(0.8))
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(CardBackground(accent: accent))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 34)
    }

    private func bigStat(_ value: String, _ caption: String, tint: Color = .white) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.display(22, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Оборот

private struct CardBack: View, Equatable {
    let model: CardModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.gold.gradient)
            Text("\(model.modeTitle.uppercased()) · ПОДРОБНО")
                .font(.system(size: 14, weight: .bold))

            if let a = model.averages {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        cell("Убийства", Format.number(a.kills))
                        cell("Смерти", Format.number(a.deaths))
                        cell("Помощь", Format.number(a.assists))
                    }
                    GridRow {
                        cell("GPM", Format.number(a.gpm, digits: 0))
                        cell("XPM", Format.number(a.xpm, digits: 0))
                        cell("Добивания", Format.number(a.lastHits, digits: 0))
                    }
                    GridRow {
                        cell("Ср. матч", Format.duration(a.duration))
                        cell("Героев", model.uniqueHeroes.map(String.init) ?? "—")
                        cell("Побед", model.wins?.formatted() ?? "—")
                    }
                    GridRow {
                        cell("Radiant", model.radiantWinrate.map(percent) ?? "—")
                        cell("Dire", model.direWinrate.map(percent) ?? "—")
                        cell("Поражений", model.losses?.formatted() ?? "—")
                    }
                }
            } else {
                ProgressView().tint(.white).frame(maxHeight: .infinity)
            }

            Spacer(minLength: 0)
            Text(model.rank?.title ?? "Без ранга")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.gold)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(CardBackground(accent: Theme.gold))
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).opacity(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}

private struct CardBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.08, blue: 0.16), Color(red: 0.05, green: 0.04, blue: 0.09)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [accent.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 320)
            // Еле заметный ромбовидный узор, как на рубашке карт.
            Canvas { ctx, size in
                let step: CGFloat = 18
                var path = Path()
                var row = 0
                var y: CGFloat = 0
                while y < size.height + step {
                    var x: CGFloat = row.isMultiple(of: 2) ? 0 : step / 2
                    while x < size.width + step {
                        path.addEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                        x += step
                    }
                    y += step / 2
                    row += 1
                }
                ctx.fill(path, with: .color(.white.opacity(0.10)))
            }
        }
    }
}

// MARK: - Картинка для «Поделиться»

/// Статичная версия карточки для экспорта в PNG: без анимаций и гироскопа,
/// фольга «застыла» под красивым углом.
// ANDROID: экспорт — rememberGraphicsLayer() + layer.toImageBitmap(), шаринг через FileProvider + Intent.ACTION_SEND.
struct ShareableCard: View {
    let model: CardModel
    private let corner: CGFloat = 28
    private let size = CGSize(width: 378, height: 528)

    var body: some View {
        CardFront(model: model)
            .overlay { FoilLayer(size: size, tilt: CGSize(width: 0.35, height: -0.25), time: 12) }
            .clipShape(.rect(cornerRadius: corner))
            .overlay { RainbowBorder(corner: corner, lineWidth: 3, animated: false) }
            .frame(width: size.width, height: size.height)
            .padding(28)
            .background(Color(red: 0.04, green: 0.04, blue: 0.07))
            .environment(\.colorScheme, .dark)
    }

    /// Скачивает все картинки карточки и рендерит PNG в 3×.
    @MainActor
    static func render(_ model: CardModel) async -> UIImage? {
        var urls = [model.avatarURL, model.signature?.imageURL, model.rank?.medalURL, model.rank?.starsURL]
        urls += model.topHeroes.map(\.imageURL)
        var images: [URL: UIImage] = [:]
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in Set(urls.compactMap { $0 }) {
                group.addTask {
                    if let bundled = await BundledImages.image(for: url) { return (url, bundled) }
                    let data = try? await URLSession.shared.data(from: url).0
                    return (url, data.flatMap(UIImage.init(data:)))
                }
            }
            for await (url, image) in group { images[url] = image }
        }
        let renderer = ImageRenderer(content: ShareableCard(model: model).environment(\.preloadedImages, images))
        renderer.scale = 3
        return renderer.uiImage
    }
}
