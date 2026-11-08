import AppKit
import SwiftUI

/// The rounded island grows from the notch and shrinks before the panel hides.
struct IslandBannerView: View {
    @ObservedObject var presenter: BannerPresenter
    @ObservedObject var glm: GLMUsageStore
    @ObservedObject var codex: CodexUsageStore
    @ObservedObject var rex: RexAgentStore
    let notchWidth: CGFloat
    let panelHeight: CGFloat
    let buddyStore: BuddyStore
    private let islandWidth: CGFloat = 360
    private let contentHeight: CGFloat = 52
    private let islandHeight: CGFloat = 174

    var body: some View {
        ZStack(alignment: .top) {
            if let alert = presenter.quotaAlert {
                QuotaLiquidAlert(alert: alert, state: presenter.state, notchWidth: notchWidth)
            } else {
                surface
                if presenter.note == nil, let activity = presenter.agentActivity {
                    let mood = AgentEyes.mood(stage: activity.stage,
                                              hasBlocked: rex.snapshot.reports.contains { $0.state == .blocked },
                                              hasError: rex.snapshot.reports.contains { $0.state == .error })
                    let buddy = buddyStore.resolve()
                    if presenter.state == .collapsed, presenter.agentActivityVisible,
                       presenter.agentDetailHovered, activity.stage == .working {
                        agentDetails
                            .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                    }
                    QuotaLiquidAlert(activity: activity, state: presenter.agentActivityVisible ? .full : .collapsed,
                                     notchWidth: notchWidth, animateContent: presenter.state == .collapsed && presenter.agentActivityVisible,
                                     mood: mood, customBuddy: buddy)
                        .opacity(presenter.state == .collapsed ? 1 : 0)
                        .accessibilityHidden(presenter.state != .collapsed)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var surface: some View {
        let expanded = presenter.state == .full
        VStack(spacing: 0) {
            // Keep the real notch line clear so the surface reads as growing out of it.
            Color.clear.frame(height: presenter.note == nil ? 54 : 34)
            if let note = presenter.note {
                bannerContent(note)
                    .frame(width: islandWidth - 32, height: contentHeight)
                    .opacity(expanded ? 1 : 0)
            } else if expanded {
                usageContent
                    .frame(width: islandWidth - 80, height: islandHeight - 74)
                    .transition(.opacity)
            }
        }
        .frame(width: presenter.state.width, height: presenter.state.height, alignment: .top)
        .overlay(alignment: .top) {
            Button(action: presenter.expandFromView) {
                HStack(spacing: 0) {
                    minimalProvider(icon: "codex", name: "Codex", value: codex.error == nil ? codex.fiveHourRemaining : nil)
                    Spacer(minLength: 185)
                    minimalProvider(icon: "zai", name: "GLM", value: glm.error == nil ? glm.fiveHourRemainingPercent : nil)
                }
                .frame(width: islandWidth - 40, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show agent usage details")
            .opacity(presenter.state == .minimal ? 1 : 0)
            .allowsHitTesting(presenter.state != .full && presenter.note == nil)
            .accessibilityHidden(presenter.state == .full || presenter.note != nil)
            .frame(width: presenter.state.width, height: 32)
            .clipped()
        }
        .background {
            let shape = IslandShape(radius: expanded ? 34 : 16)
            if presenter.look != .systemExperimental {
                ZStack {
                    shape.fill(.black)
                        .shadow(color: .black.opacity(expanded ? 0.25 : 0), radius: 12, y: 12)
                    shape.fill(.black)
                        .shadow(color: .black.opacity(expanded ? 0.25 : 0), radius: 5, y: 4)
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            switch presenter.look {
            case .glassy:
                GlassSurface(look: presenter.look, shape: shape)
                // Opaque through the notch band, then a seamless fade into the
                // native glass below — multi-stop S-curve so the transition
                // reads organic, not boxy.
                shape.fill(.black)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.31),
                                .init(color: .black.opacity(0.9), location: 0.4),
                                .init(color: .black.opacity(0.62), location: 0.5),
                                .init(color: .black.opacity(0.32), location: 0.6),
                                .init(color: .black.opacity(0.12), location: 0.7),
                                .init(color: .black.opacity(0), location: 0.8),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            case .solid:
                shape.fill(.black)
            case .systemExperimental:
                PrivateGlassBackdrop()
            }
            if presenter.look != .solid {
                shape.fill(.black)
                    .opacity(presenter.state == .minimal ? 1 : 0)
            }
            shape.strokeBorder(.white.opacity(expanded ? (presenter.look == .glassy ? 0.25 : 0.12) : 0), lineWidth: 0.8)
        }
    }

    private var agentDetails: some View {
        let sections = rex.snapshot.activitySections
        let height = QuotaLiquidAlert.detailHeight(for: rex.snapshot, available: panelHeight - QuotaLiquidAlert.detailY)
        let panelX = QuotaLiquidAlert.detailX(notchWidth: notchWidth)
        let tailX = min(QuotaLiquidAlert.detailWidth - 16,
                        max(16, QuotaLiquidAlert.restingX(notchWidth: notchWidth) - panelX))
        let shape = AgentPanelShape(tailX: tailX)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Agent Activity")
                .font(.mono(14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, QuotaLiquidAlert.tailHeight + 8)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if rex.snapshot.connection == .partial {
                        Text("Rex data incomplete")
                            .font(.mono(10)).foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    ForEach(sections, id: \.state) { section in
                        let color = activityColor(section.state)
                        HStack(spacing: 7) {
                            Circle().fill(color).frame(width: 6, height: 6)
                            Text(activityLabel(section.state)).fontWeight(.semibold)
                            Text("\(section.count)").foregroundStyle(.white.opacity(0.55))
                        }
                        .font(.mono(11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(.white.opacity(0.07))
                        ForEach(section.groups, id: \.key) { group in
                            activityRow(group.key, count: group.count, color: color)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .foregroundStyle(.white)
        .frame(width: QuotaLiquidAlert.detailWidth, height: height + QuotaLiquidAlert.tailHeight, alignment: .bottom)
        .background {
            GlassSurface(look: presenter.look, shape: shape,
                         glassTint: presenter.look == .glassy ? .black.opacity(0.45) : nil,
                         blackFill: presenter.look == .glassy ? 0.4 : nil,
                         tailX: tailX, dimOverlay: true)
            if presenter.look != .systemExperimental {
                shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
            }
        }
        .offset(x: panelX, y: QuotaLiquidAlert.detailY - QuotaLiquidAlert.tailHeight)
        .frame(width: 440, height: panelHeight, alignment: .topLeading)
        .preferredColorScheme(.dark)
    }

    private func activityRow(_ group: RexActivityGroup, count: Int, color: Color) -> some View {
        let name = "\(group.agent.rawValue)\(group.isSubagent ? " subagent" : "")"
        return HStack(alignment: .top, spacing: 10) {
            Circle().strokeBorder(color, lineWidth: 2).frame(width: 12, height: 12).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: group.title ?? name)
                    .font(.mono(12, weight: .semibold)).lineLimit(2)
                Text(verbatim: name)
                    .font(.mono(10)).foregroundStyle(.white.opacity(0.6))
                if let model = group.model {
                    Text(verbatim: model).font(.mono(10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityLabel(_ state: RexAgentState) -> String {
        switch state {
        case .blocked: return "Needs input"
        case .error: return "Error"
        case .working: return "Working"
        case .idle: return "Idle"
        case .done: return "Completed"
        case .unknown: return "Unknown"
        }
    }

    private func activityColor(_ state: RexAgentState) -> Color {
        switch state {
        case .blocked: return .orange
        case .error: return .red
        case .working: return .blue
        case .done: return .green
        case .idle, .unknown: return .gray
        }
    }

    private func minimalProvider(icon: String, name: String, value: Double?) -> some View {
        HStack(spacing: 4) {
            ProviderIcon(name: icon, size: 14)
            Text(percentage(value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), 5 hour remaining \(percentage(value))")
    }

    private var usageContent: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 14) {
                    providerColumn(name: "Codex", icon: "codex",
                                   value: codex.error == nil ? codex.fiveHourRemaining : nil,
                                   reset: codex.error == nil ? codex.primaryResetAt : nil,
                                   weekly: codex.error == nil ? codex.secondaryRemaining : nil,
                                   weeklyReset: codex.error == nil ? codex.secondaryResetAt : nil,
                                   status: codex.error ?? (codex.signInState == .signingIn ? "Signing in…" : "Sign in via menu"),
                                   showWeekly: true, now: context.date)
                    Rectangle().fill(.white.opacity(0.16)).frame(width: 1)
                    providerColumn(name: "GLM", icon: "zai",
                                   value: glm.error == nil ? glm.fiveHourRemainingPercent : nil,
                                   reset: glm.error == nil ? glm.fiveHourResetAt : nil,
                                   weekly: nil, weeklyReset: nil,
                                   status: glm.error ?? (glm.hasKey ? "Loading…" : "Set API key via menu"),
                                   showWeekly: false, now: context.date)
                }
                Text(rex.snapshot.summary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .monospacedDigit()
            .preferredColorScheme(.dark)
        }
    }

    private func providerColumn(name: String, icon: String, value: Double?, reset: Date?, weekly: Double?, weeklyReset: Date?, status: String, showWeekly: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProviderIcon(name: icon)
                Text(name.uppercased())
                    .font(.mono(9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            HStack(alignment: .center) {
                Text(value.map(percentage) ?? "—")
                    .font(.mono(18, weight: .semibold))
                Spacer(minLength: 2)
                if let value {
                    ZStack {
                        Circle().stroke(.white.opacity(0.17), lineWidth: 3)
                        Circle().trim(from: 0, to: min(1, max(0, value / 100)))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                }
            }
            HStack(spacing: 3) {
                if value == nil {
                    Text(status).lineLimit(1).truncationMode(.tail)
                } else {
                    Text("5h")
                    if let reset, let countdown = ResetCountdown.text(until: reset, now: now) {
                        Text("· ↻ \(countdown)")
                    }
                }
            }
            .font(.mono(9))
            .foregroundStyle(.white.opacity(0.7))
            if showWeekly {
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
                HStack(spacing: 4) {
                    Text("1w")
                    Text(percentage(weekly))
                    if let weeklyReset, let countdown = ResetCountdown.text(until: weeklyReset, now: now), weekly != nil {
                        Text(countdown).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .font(.mono(9))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .help(value == nil ? status : "\(name): remaining usage")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), 5 hour remaining \(percentage(value))\(showWeekly ? ", 1 week remaining \(percentage(weekly))" : "")")
    }

    private func percentage(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    private func bannerContent(_ notification: PulauNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.app)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
        .preferredColorScheme(.dark)
    }
}

struct QuotaLiquidAlert: View {
    private enum Content {
        case quota(QuotaAlert)
        case agent(AgentActivity)
    }
    private let content: Content
    private let animateContent: Bool
    var mood: AgentEyes.Mood = .glance
    var customBuddy: NSImage?
    let state: IslandState
    let notchWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phaseStart = Date.now
    @State private var from: CGFloat = 0
    @State private var target: CGFloat = 0
    @State private var animationPaused = false

    init(alert: QuotaAlert, state: IslandState, notchWidth: CGFloat) {
        content = .quota(alert)
        animateContent = false
        self.state = state
        self.notchWidth = notchWidth
    }

    init(activity: AgentActivity, state: IslandState, notchWidth: CGFloat, animateContent: Bool,
         mood: AgentEyes.Mood = .glance, customBuddy: NSImage? = nil) {
        content = .agent(activity)
        self.animateContent = animateContent
        self.mood = mood
        self.customBuddy = customBuddy
        self.state = state
        self.notchWidth = notchWidth
    }

    static let duration = 2.0
    static let diameter: CGFloat = 23.04
    static let bubbleWidth: CGFloat = 28
    static let bubbleHeight: CGFloat = 20
    static let bubbleRadius: CGFloat = 7

    private static var bubbleRect: CGRect {
        CGRect(x: 0, y: (32 - bubbleHeight) / 2, width: bubbleWidth, height: bubbleHeight)
    }

    private static func bubblePath(centerX: CGFloat) -> Path {
        var rect = bubbleRect
        rect.origin.x = centerX - bubbleWidth / 2
        return Path(roundedRect: rect, cornerSize: CGSize(width: bubbleRadius, height: bubbleRadius), style: .continuous)
    }
    static let detailWidth: CGFloat = 320
    static let detailY: CGFloat = 43
    static let tailHeight: CGFloat = 16

    static func detailX(notchWidth: CGFloat) -> CGFloat {
        min(440 - detailWidth - 8, max(8, restingX(notchWidth: notchWidth) - detailWidth / 2))
    }

    static func detailHeight(for snapshot: RexSnapshot, available: CGFloat) -> CGFloat {
        let sections = snapshot.activitySections
        let rows = sections.reduce(0) { $0 + $1.groups.count }
        return min(available, max(190, 66 + CGFloat(sections.count * 30 + rows * 58)))
    }

    static func progress(elapsed: TimeInterval, closing: Bool) -> CGFloat {
        let t = min(1, max(0, elapsed / duration))
        return CGFloat(closing ? 1 - t : t)
    }

    static func spread(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, (progress - 0.12) / 0.88))
        return t * t * (3 - 2 * t)
    }

    static func restingX(notchWidth: CGFloat) -> CGFloat {
        let edge = 220 + notchWidth / 2
        return edge - 20 + diameter / 2 + (55.5 - diameter / 2) * 0.7
    }

    static func outsideNotch(notchWidth: CGFloat) -> Path {
        var mask = Path(CGRect(x: 0, y: 0, width: 440, height: 72))
        mask.addPath(IslandShape(radius: 7).path(in: CGRect(x: 220 - notchWidth / 2, y: 0, width: notchWidth, height: 32)))
        return mask
    }

    static func bridge(circleX: CGFloat, notchWidth: CGFloat) -> Path {
        let start = 220 + notchWidth / 2 - 20
        let end = circleX - bubbleWidth / 2 + 6
        let gap = end - start
        let finalGap = restingX(notchWidth: notchWidth) - bubbleWidth / 2 + 6 - start
        let breakGap = finalGap * 0.88
        let pinchStart = breakGap * 0.75
        guard gap > 0, gap < breakGap else { return Path() }
        let t = min(1, max(0, (gap - pinchStart) / (breakGap - pinchStart)))
        let pinch = 1 - t * t * (3 - 2 * t)
        let halfBase = 15 * pinch
        let halfNeck = min(diameter / 2 - 0.5, 300.0 / 31.0) * pinch
        var path = Path()
        path.move(to: CGPoint(x: start, y: 16 - halfBase))
        path.addCurve(to: CGPoint(x: end, y: 16 - halfNeck),
                      control1: CGPoint(x: start + gap * 0.4, y: 16 - halfBase),
                      control2: CGPoint(x: end - gap * 0.35, y: 16 - halfNeck))
        path.addLine(to: CGPoint(x: end, y: 16 + halfNeck))
        path.addCurve(to: CGPoint(x: start, y: 16 + halfBase),
                      control1: CGPoint(x: end - gap * 0.35, y: 16 + halfNeck),
                      control2: CGPoint(x: start + gap * 0.4, y: 16 + halfBase))
        path.closeSubpath()
        return path
    }

    var body: some View {
        TimelineView(.animation(paused: animationPaused)) { timeline in
            let amount = Self.progress(elapsed: timeline.date.timeIntervalSince(phaseStart), closing: false)
            let progress = reduceMotion ? 1.0 : from + (target - from) * amount
            let spread = Self.spread(progress)
            let origin = 220 + notchWidth / 2 - 20 - Self.diameter / 2
            let restingX = Self.restingX(notchWidth: notchWidth)
            let circleX = origin + (restingX - origin) * spread
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.clip(to: Self.outsideNotch(notchWidth: notchWidth), style: FillStyle(eoFill: true))
                    if reduceMotion {
                        context.fill(Self.bubblePath(centerX: restingX), with: .color(.black))
                    } else if progress > 0 {
                        context.fill(Self.bridge(circleX: circleX, notchWidth: notchWidth), with: .color(.black))
                        context.fill(Self.bubblePath(centerX: circleX), with: .color(.black))
                    }
                }
                .accessibilityHidden(true)
                bubbleContent
                .foregroundStyle(.white)
                .frame(width: Self.bubbleWidth, height: Self.bubbleHeight)
                .offset(x: (reduceMotion ? restingX : circleX) - Self.bubbleWidth / 2, y: (32 - Self.bubbleHeight) / 2)
                .opacity(min(1, max(0, (spread - 0.8) / 0.15)))
            }
            .frame(width: 440, height: 72)
        }
        .opacity(reduceMotion && state != .full ? 0 : 1)
        .onAppear {
            from = 0
            target = state == .full ? 1 : 0
            phaseStart = .now
        }
        .onChange(of: state) { old, new in
            guard old != new else { return }
            let amount = Self.progress(elapsed: Date.now.timeIntervalSince(phaseStart), closing: false)
            from += (target - from) * amount
            target = new == .full ? 1 : 0
            phaseStart = .now
        }
        .task(id: state == .full) {
            animationPaused = false
            do { try await Task.sleep(for: .seconds(Self.duration + 0.05)) } catch { return }
            animationPaused = true
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch content {
        case .quota(let alert):
            VStack(spacing: 0) {
                ProviderIcon(name: alert.provider == .glm ? "zai" : "codex", size: 8)
                Text("\(alert.remaining)%")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
            }
        case .agent(let activity):
            VStack(spacing: 0) {
                if activity.stage == .done {
                    Text(activity.label)
                        .font(.system(size: 7, weight: .bold))
                    Text("Done")
                        .font(.system(size: 6, weight: .bold))
                } else if let buddy = customBuddy {
                    BuddyAssetView(image: buddy, animate: animateContent)
                } else {
                    AgentEyes(animate: animateContent, mood: mood)
                }
            }
        }
    }

    private var accessibilityText: String {
        switch content {
        case .quota(let alert):
            return "\(alert.provider == .glm ? "GLM" : "Codex"), 5 hour remaining \(alert.remaining) percent"
        case .agent(let activity):
            return activity.accessibility
        }
    }
}

/// Renders a user-chosen buddy image; GIFs animate through NSImageView.
struct BuddyAssetView: NSViewRepresentable {
    let image: NSImage
    let animate: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = image
        view.animates = animate
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image
        view.animates = animate
    }
}

struct AgentEyes: View {
    enum Mood { case glance, curious, dizzy }

    let animate: Bool
    var mood: Mood = .glance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func gazeOffset(at time: TimeInterval) -> CGFloat {
        CGFloat(sin(time * .pi / 2) * 1.4)
    }

    /// Eyes close briefly every ~4 seconds; pure function of time for tests.
    static func blinkScale(at time: TimeInterval) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: 4.2)
        guard phase < 0.14 else { return 1 }
        return 1 - 0.92 * CGFloat(sin(phase / 0.14 * .pi))
    }

    /// Working agents glance around; a blocked peer makes the buddy look up; an error looks dizzy.
    static func mood(stage: AgentActivity.Stage, hasBlocked: Bool, hasError: Bool) -> Mood {
        stage == .done ? .glance : hasError ? .dizzy : hasBlocked ? .curious : .glance
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animate || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let offset = animate && !reduceMotion && mood == .glance ? Self.gazeOffset(at: time) : 0
            let blink = animate && !reduceMotion ? Self.blinkScale(at: time) : 1
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    eye(offset: offset, blink: blink, time: time)
                    eye(offset: offset, blink: blink, time: time)
                }
                mouth(mood: mood, time: time, animate: animate && !reduceMotion)
            }
        }
        .accessibilityHidden(true)
    }

    /// Tiny mouth under the eyes; pure function of time for tests.
    static func mouthWidth(at time: TimeInterval, animate: Bool) -> CGFloat {
        guard animate else { return 4 }
        let phase = time.truncatingRemainder(dividingBy: 1.8)
        return 3 + 1.6 * CGFloat(abs(sin(phase / 1.8 * .pi)))
    }

    @ViewBuilder
    private func mouth(mood: Mood, time: TimeInterval, animate: Bool) -> some View {
        let width = Self.mouthWidth(at: time, animate: animate)
        switch mood {
        case .dizzy:
            Capsule().fill(.white).frame(width: 4, height: 1.2)
        case .curious:
            Circle().trim(from: 0.55, to: 1).stroke(.white, lineWidth: 1).frame(width: 4, height: 4)
        default:
            Capsule().fill(.white).frame(width: width, height: 1.2)
        }
    }

    private func eye(offset: CGFloat, blink: CGFloat, time: TimeInterval) -> some View {
        Group {
            if mood == .dizzy {
                ZStack {
                    Capsule().fill(.white).frame(width: 7, height: 1.4).rotationEffect(.degrees(45))
                    Capsule().fill(.white).frame(width: 7, height: 1.4).rotationEffect(.degrees(-45))
                }
            } else {
                Circle().fill(.white)
                    .frame(width: 7, height: 7 * blink)
                    .overlay {
                        if blink > 0.4 {
                            Circle().fill(.black)
                                .frame(width: 3, height: 3)
                                .offset(x: offset, y: mood == .curious ? -1.6 : 0)
                        }
                    }
                    .offset(y: blink < 1 ? (7 - 7 * blink) / 2 : 0)
            }
        }
    }
}

private struct ProviderIcon: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: "circle.dashed").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// iOS 27-style semi glass black: Liquid Glass tinted dark on macOS 26+,
/// HUD material fallback below.
struct IslandGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.tintColor = NSColor.black.withAlphaComponent(0.2)
            glass.cornerRadius = 0
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        return material
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// A top-edge bridge with concave shoulders and continuous-looking lower corners.
struct IslandShape: InsettableShape {
    var radius: CGFloat
    var insetAmount: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, insetAmount) }
        set { radius = newValue.first; insetAmount = newValue.second }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let flare: CGFloat = 20
        let shoulder: CGFloat = 18
        let left = rect.minX + flare, right = rect.maxX - flare
        let r = min(radius, (rect.height - shoulder) / 2, (right - left) / 2)
        let k: CGFloat = 0.55228475
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
                   control1: CGPoint(x: rect.maxX - flare * k, y: rect.minY),
                   control2: CGPoint(x: right, y: rect.minY + shoulder * (1 - k)))
        p.addLine(to: CGPoint(x: right, y: rect.maxY - r))
        p.addCurve(to: CGPoint(x: right - r, y: rect.maxY),
                   control1: CGPoint(x: right, y: rect.maxY - r * (1 - k)),
                   control2: CGPoint(x: right - r * (1 - k), y: rect.maxY))
        p.addLine(to: CGPoint(x: left + r, y: rect.maxY))
        p.addCurve(to: CGPoint(x: left, y: rect.maxY - r),
                   control1: CGPoint(x: left + r * (1 - k), y: rect.maxY),
                   control2: CGPoint(x: left, y: rect.maxY - r * (1 - k)))
        p.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                   control1: CGPoint(x: left, y: rect.minY + shoulder * (1 - k)),
                   control2: CGPoint(x: rect.minX + flare * k, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
