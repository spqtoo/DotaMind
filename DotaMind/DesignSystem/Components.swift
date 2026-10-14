//
//  Components.swift
//  DotaMind
//
//  Общие элементы интерфейса. Стекло — нативный Liquid Glass (glassEffect).
//

import SwiftUI

// MARK: - Картинки

/// Картинка по URL, которая занимает ровно предложенный размер и не
/// раздувает раскладку (важно для .fill внутри ScrollView).
// ANDROID: Coil AsyncImage(contentScale = Crop) в Box фиксированного размера.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @Environment(\.preloadedImages) private var preloaded

    var body: some View {
        Color.clear
            .overlay {
                if let url, let image = preloaded[url] ?? BundledImages.image(for: url) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                } else {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: contentMode)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                }
            }
            .clipped()
    }
}

extension EnvironmentValues {
    /// Заранее скачанные картинки — для ImageRenderer, который не ждёт AsyncImage.
    @Entry var preloadedImages: [URL: UIImage] = [:]
}

/// Картинки из офлайн-снимка, декодированные один раз.
@MainActor
enum BundledImages {
    private static var cache: [URL: UIImage] = [:]

    static func image(for remote: URL) -> UIImage? {
        if let hit = cache[remote] { return hit }
        guard let file = DemoData.localImage(for: remote),
              let image = UIImage(contentsOfFile: file.path()) else { return nil }
        cache[remote] = image
        return image
    }
}

/// Портрет героя 16:9 со скруглением.
struct HeroPortrait: View {
    let hero: Hero
    var width: CGFloat = 64

    var body: some View {
        RemoteImage(url: hero.imageURL)
            .frame(width: width, height: width * 9 / 16)
            .clipShape(.rect(cornerRadius: width / 8))
            .accessibilityLabel(hero.name)
    }
}

struct RankBadge: View {
    let rank: Rank
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RemoteImage(url: rank.medalURL, contentMode: .fit)
            if let stars = rank.starsURL {
                RemoteImage(url: stars, contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(rank.title)
    }
}

// MARK: - Статистика

// ANDROID (Material 3): ElevatedCard / Card(colors = surfaceContainerHigh) вместо glassEffect.
struct StatTile: View {
    let title: String
    let value: String
    var symbol: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Text(value)
                .font(.display(20))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// Строка из нескольких метрик в одной стеклянной плашке.
// ANDROID (Material 3): Card + Row с VerticalDivider.
struct MetricStrip: View {
    struct Item: Identifiable {
        let title: String
        let value: String
        var tint: Color = .primary
        var id: String { title }
    }
    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 30)
                }
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(.display(17))
                        .foregroundStyle(item.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// Победы против поражений одной полосой.
// ANDROID (Material 3): два LinearProgressIndicator-сегмента или Canvas с RoundedRect; цвета — tertiary/error.
struct WinLossBar: View {
    let wins: Int
    let losses: Int

    var body: some View {
        let total = max(wins + losses, 1)
        VStack(spacing: 8) {
            HStack {
                Label("\(wins.formatted()) побед", systemImage: "arrow.up.right")
                    .foregroundStyle(Theme.win)
                Spacer()
                Label("\(losses.formatted()) поражений", systemImage: "arrow.down.right")
                    .foregroundStyle(Theme.loss)
                    .labelStyle(TrailingIconLabelStyle())
            }
            .font(.footnote.weight(.semibold))
            GeometryReader { geo in
                HStack(spacing: 4) {
                    GlassFill(color: Theme.win)
                        .frame(width: max(0, geo.size.width - 4) * Double(wins) / Double(total))
                    GlassFill(color: Theme.loss)
                }
            }
            .frame(height: 13)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}

// MARK: - Стеклянные полосы

/// Подложка полосы: еле заметная, чтобы стекло заливки было главным.
// ANDROID (Material 3): трек = surfaceContainerHighest.
struct BarTrack: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.06))
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Плоская заливка из Liquid Glass, подкрашенная цветом результата.
// ANDROID (Material 3): LinearProgressIndicator(color = …, trackColor = surfaceContainerHighest, strokeCap = Round) — без стекла.
struct GlassFill: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.55))
            .glassEffect(.regular.tint(color.opacity(0.4)), in: .capsule)
    }
}

/// Полоска винрейта: стеклянная, плавно наполняется при появлении.
struct WinrateBar: View {
    let winrate: Double
    var color: Color? = nil
    var height: CGFloat = 12

    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                BarTrack()
                GlassFill(color: color ?? winrateColor(winrate))
                    .frame(width: max(height, geo.size.width * (shown ? winrate : 0)))
                    .opacity(winrate > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.05)) { shown = true } }
        .accessibilityHidden(true)
    }
}

func winrateColor(_ wr: Double) -> Color {
    switch wr {
    case 0.55...: Theme.win
    case 0.5..<0.55: Theme.win.mix(with: .white, by: 0.3)
    case 0.45..<0.5: Color(white: 0.72)
    default: Theme.loss
    }
}

/// Карточка-секция со стеклом и заголовком.
// ANDROID (Material 3): ElevatedCard с заголовком titleMedium и TextButton справа.
struct GlassSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.display(15, weight: .bold))
                Spacer()
                trailing
            }
            content
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

struct LoadingView: View {
    var text = "Загружаем статистику…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

// ANDROID (Material 3): Column(иконка, bodyMedium, FilledTonalButton «Повторить»).
struct ErrorView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Не получилось загрузить", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Повторить") { Task { await retry() } }
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Форматирование

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
