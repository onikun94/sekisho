import SwiftUI

extension Color {
    // Sampled from the generated illustration corners so artwork and canvas
    // read as one continuous field instead of an image placed on a card.
    static let sekishoPaper = Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255)
    static let sekishoInk = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let sekishoVermilion = Color(red: 0.72, green: 0.27, blue: 0.20)
    static let sekishoSage = Color(red: 0.38, green: 0.47, blue: 0.35)
    static let sekishoSand = Color(red: 0.72, green: 0.61, blue: 0.46)

    static let limitBackground = sekishoPaper
    static let limitBlue = sekishoVermilion
    static let limitGreen = sekishoSage
    static let limitRed = Color(red: 0.70, green: 0.20, blue: 0.16)
}

struct CardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.sekishoInk.opacity(0.14))
                    .frame(height: 1)
            }
    }
}

struct StatusPill: View {
    var label: String
    var systemImage: String
    var tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(label)
    }
}

struct AirySection<Content: View>: View {
    var title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sekishoInk.opacity(0.64))

            content
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.sekishoInk.opacity(0.14))
                        .frame(height: 1)
                }
        }
    }
}

struct AiryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.sekishoPaper)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Color.sekishoInk.opacity(configuration.isPressed ? 0.76 : 1),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HandwrittenAssetText: View {
    var assetName: String
    var label: String
    var height: CGFloat

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(label)
    }
}

struct SekishoSceneBackdrop: View {
    var isLimited: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .fill(
                        isLimited
                            ? Color.limitRed.opacity(0.92)
                            : Color.sekishoVermilion.opacity(0.92)
                    )
                    .frame(width: size * 0.82, height: size * 0.82)
                    .offset(x: size * 0.03, y: -size * 0.05)

                Capsule()
                    .fill(Color.sekishoSage.opacity(isLimited ? 0.54 : 0.88))
                    .frame(width: size * 1.04, height: size * 0.17)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -size * 0.03, y: size * 0.26)

                Capsule()
                    .fill(Color.sekishoPaper.opacity(0.22))
                    .frame(width: size * 0.76, height: size * 0.025)
                    .rotationEffect(.degrees(-9))
                    .offset(x: -size * 0.11, y: size * 0.23)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct SekishoMascotImage: View {
    var assetName: String
    var accessibilityLabel: String

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .accessibilityLabel(accessibilityLabel)
    }
}

struct AnimatedSekishoMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapStartedAt = Date.distantPast
    @State private var tapCount = 0

    var assetName: String
    var accessibilityLabel: String
    var isLimited: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let motion = motionValues(at: timeline.date)

                ZStack {
                    Ellipse()
                        .fill(Color.sekishoInk.opacity(isLimited ? 0.12 : 0.16))
                        .frame(
                            width: proxy.size.width * 0.48,
                            height: proxy.size.height * 0.052
                        )
                        .scaleEffect(x: motion.shadowScale, y: 1)
                        .blur(radius: 4)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height * 0.82
                        )

                    SekishoMascotImage(
                        assetName: assetName,
                        accessibilityLabel: accessibilityLabel
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(
                        x: motion.scaleX,
                        y: motion.scaleY,
                        anchor: .bottom
                    )
                    .rotationEffect(.degrees(Double(motion.roll)), anchor: .bottom)
                    .rotation3DEffect(
                        .degrees(Double(motion.yaw)),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .center,
                        perspective: 0.28
                    )
                    .offset(
                        x: motion.horizontalOffset,
                        y: motion.verticalOffset
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            react()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("タップすると番人が反応します")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "番人に声をかける") {
            react()
        }
    }

    private func react() {
        guard !reduceMotion else {
            return
        }

        tapStartedAt = .now
        tapCount += 1
    }

    private func motionValues(at date: Date) -> MascotMotionValues {
        guard !reduceMotion else {
            return .still
        }

        let seconds = date.timeIntervalSinceReferenceDate
        let cycleDuration = isLimited ? 4.4 : 2.8
        let phase = seconds * .pi * 2 / cycleDuration
        let breath = CGFloat(sin(phase))
        let sway = CGFloat(sin(seconds * .pi * 2 / (isLimited ? 6.4 : 4.4)))

        let perkPeriod = 5.4
        let perkDuration = 1.15
        let perkElapsed = seconds.truncatingRemainder(dividingBy: perkPeriod) - 3.9
        let isPerkingUp = !isLimited && perkElapsed >= 0 && perkElapsed < perkDuration
        let perkProgress = isPerkingUp ? perkElapsed / perkDuration : 0
        let perkUp = isPerkingUp
            ? CGFloat(pow(sin(perkProgress * .pi), 2))
            : 0
        let perkWiggle = isPerkingUp
            ? CGFloat(sin(perkProgress * .pi * 2)) * perkUp
            : 0

        let tapDuration = isLimited ? 0.62 : 0.76
        let tapElapsed = date.timeIntervalSince(tapStartedAt)
        let isTapActive = tapElapsed >= 0 && tapElapsed < tapDuration
        let tapProgress = isTapActive ? tapElapsed / tapDuration : 1
        let tapEnvelope = CGFloat(isTapActive ? 1 - tapProgress : 0)
        let tapWave = CGFloat(sin(tapProgress * .pi * (isLimited ? 2 : 3))) * tapEnvelope
        let tapLift = CGFloat(abs(sin(tapProgress * .pi * 2))) * tapEnvelope

        let idleVertical = breath * (isLimited ? 2.8 : 6.2) - perkUp * 7.5
        let tapVertical = tapLift * (isLimited ? 4 : 13)
        let verticalOffset = idleVertical - tapVertical
        let horizontalOffset = sway * (isLimited ? 1.4 : 3.2) + perkWiggle * 2.2
        let breathAmount = breath * (isLimited ? 0.008 : 0.020)

        return MascotMotionValues(
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            scaleX: 1 - breathAmount * 0.55 - perkUp * 0.010 - tapWave * 0.014,
            scaleY: 1 + breathAmount + perkUp * 0.026 + tapWave * (isLimited ? 0.014 : 0.038),
            roll: sway * (isLimited ? 0.85 : 1.6)
                + perkWiggle * 1.4
                + tapWave * (isLimited ? 0.8 : 2.2),
            yaw: sway * (isLimited ? 1.6 : 4.0),
            shadowScale: 1 + verticalOffset * 0.008
        )
    }
}

private struct MascotMotionValues {
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let roll: CGFloat
    let yaw: CGFloat
    let shadowScale: CGFloat

    static let still = MascotMotionValues(
        horizontalOffset: 0,
        verticalOffset: 0,
        scaleX: 1,
        scaleY: 1,
        roll: 0,
        yaw: 0,
        shadowScale: 1
    )
}

struct WoodenProgressBar: View {
    var progress: Double
    var isLimited: Bool

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let innerHeight = max(proxy.size.height - 10, 4)
            let innerWidth = max(proxy.size.width - 18, 0)

            ZStack {
                Capsule()
                    .fill(Color(red: 0.37, green: 0.22, blue: 0.13))

                Capsule()
                    .fill(Color(red: 0.77, green: 0.61, blue: 0.42))
                    .padding(3)

                Capsule()
                    .fill(Color.sekishoPaper.opacity(0.9))
                    .frame(width: innerWidth, height: innerHeight)

                HStack(spacing: 0) {
                    Capsule()
                        .fill(isLimited ? Color.limitRed : Color.sekishoSage)
                        .frame(
                            width: max(innerWidth * clampedProgress, clampedProgress > 0 ? innerHeight : 0),
                            height: innerHeight
                        )

                    Spacer(minLength: 0)
                }
                .frame(width: innerWidth, height: innerHeight)
                .clipShape(Capsule())

                HStack {
                    WoodBarEndCap()
                    Spacer()
                    WoodBarEndCap()
                }
            }
        }
    }
}

private struct WoodBarEndCap: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(red: 0.45, green: 0.29, blue: 0.17))
            .frame(width: 8)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.sekishoInk.opacity(0.26), lineWidth: 1)
            }
    }
}

struct WoodenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.sekishoPaper)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Color(red: 0.39, green: 0.24, blue: 0.15)
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.sekishoSand.opacity(0.6), lineWidth: 2)
                    .padding(3)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
