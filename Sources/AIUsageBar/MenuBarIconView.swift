import AppKit

enum CenterSymbol {
    case checkmark
    case exclamation
    case questionMark
}

/// Data for one service's ring + text block in the menu bar.
struct ServiceIconData {
    struct QuotaRings: Equatable {
        let fiveHour: Double?
        let weekly: Double
    }

    let ringFraction: Double
    let topText: String
    let bottomText: String
    /// Optional ring color; nil uses the default menu bar tint.
    let ringColor: NSColor?
    let centerSymbol: CenterSymbol?
    let quotaRings: QuotaRings?

    init(ringFraction: Double, topText: String, bottomText: String, ringColor: NSColor? = nil,
         centerSymbol: CenterSymbol? = nil, quotaRings: QuotaRings? = nil) {
        self.ringFraction = ringFraction
        self.topText = topText
        self.bottomText = bottomText
        self.ringColor = ringColor
        self.centerSymbol = centerSymbol
        self.quotaRings = quotaRings
    }

    static func claude(fiveHour: Double?, weekly: Double?, ringColor: NSColor?) -> Self {
        guard let fiveHour = self.clampedPercent(fiveHour), let weekly = self.clampedPercent(weekly)
        else { return self.symbolOnly(.questionMark, ringColor: ringColor) }
        return Self(ringFraction: fiveHour / 100, topText: self.percentageText(fiveHour),
                    bottomText: self.percentageText(weekly), ringColor: ringColor,
                    quotaRings: QuotaRings(fiveHour: fiveHour / 100, weekly: weekly / 100))
    }

    static func codex(rateLimits: RateLimitSnapshot?, ringColor: NSColor?) -> Self {
        guard let weekly = self.clampedPercent(rateLimits?.weeklyRemainingPercent)
        else { return self.symbolOnly(.questionMark, ringColor: ringColor) }
        let fiveHour = self.clampedPercent(rateLimits?.fiveHourRemainingPercent)
        return Self(
            ringFraction: (fiveHour ?? weekly) / 100,
            topText: fiveHour.map(self.percentageText) ?? "",
            bottomText: self.percentageText(weekly),
            ringColor: ringColor,
            quotaRings: QuotaRings(fiveHour: fiveHour.map { $0 / 100 }, weekly: weekly / 100)
        )
    }

    static func antigravity(windows: AntigravityQuotaSnapshot.MenuWindows, isStale: Bool, ringColor: NSColor?) -> Self {
        if isStale {
            return self.symbolOnly(.exclamation, ringColor: ringColor)
        }
        guard let fiveHours = windows.fiveHours, let weekly = windows.weekly
        else { return self.symbolOnly(.questionMark, ringColor: ringColor) }
        return Self(
            ringFraction: fiveHours.remainingFraction,
            topText: fiveHours.percentageText,
            bottomText: weekly.percentageText,
            ringColor: ringColor,
            quotaRings: QuotaRings(fiveHour: fiveHours.remainingFraction, weekly: weekly.remainingFraction)
        )
    }

    static func grok(weekly: SubscriptionWindow?, ringColor: NSColor?) -> Self {
        guard let weekly else { return self.symbolOnly(.questionMark, ringColor: ringColor) }
        return Self(ringFraction: weekly.remainingFraction, topText: "", bottomText: weekly.percentageText,
                    ringColor: ringColor)
    }

    static func deepSeek(balance: Double?, todayCost: Double?, settings: DeepSeekBalanceSettings, ringColor: NSColor?) -> Self {
        guard let balance, let todayCost else { return self.symbolOnly(.questionMark, ringColor: ringColor) }
        return Self(ringFraction: settings.ringFraction(for: balance), topText: String(format: "%.2f", todayCost),
                    bottomText: String(format: "%.2f", balance), ringColor: ringColor,
                    centerSymbol: settings.isLowBalance(balance) ? .exclamation : .checkmark)
    }

    private static func symbolOnly(_ symbol: CenterSymbol, ringColor: NSColor?) -> Self {
        Self(ringFraction: 0, topText: "", bottomText: "", ringColor: ringColor, centerSymbol: symbol)
    }

    private static func clampedPercent(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
    }

    private static func percentageText(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}

@MainActor
struct MenuBarIconView {
    let services: [ServiceIconData]
    let showsNumbers: Bool
    let ringStyle: MenuBarRingStyle

    init(services: [ServiceIconData], showsNumbers: Bool, ringStyle: MenuBarRingStyle = .single) {
        self.services = services
        self.showsNumbers = showsNumbers
        self.ringStyle = ringStyle
    }

    // MARK: - Layout constants

    private static let ringDiameter: CGFloat = 18
    private static let ringLineWidth: CGFloat = 2.0
    private static let dualRingLineWidth: CGFloat = 1.5
    private static let innerRingInset: CGFloat = 3
    private static let weeklyRingAlpha: CGFloat = 0.78
    private static let textGap: CGFloat = 4
    private static let sectionGap: CGFloat = 8
    private static let iconHeight: CGFloat = 22
    private static let trackAlpha: CGFloat = 0.3
    private static let secondaryTextAlpha: CGFloat = 0.55

    private static let topFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let bottomFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

    private static let topAttrs: [NSAttributedString.Key: Any] = [
        .font: MenuBarIconView.topFont,
        .foregroundColor: NSColor.black,
    ]
    private static let bottomAttrs: [NSAttributedString.Key: Any] = [
        .font: MenuBarIconView.bottomFont,
        .foregroundColor: NSColor.black.withAlphaComponent(MenuBarIconView.secondaryTextAlpha),
    ]

    // MARK: - Rendering

    func renderedImage() -> NSImage {
        let hasColors = self.services.contains { $0.ringColor != nil }
        let baseColor: NSColor = .white

        let blocks = self.services.map { Self.measureBlock($0, showsNumbers: self.showsNumbers) }
        let totalWidth = blocks.reduce(CGFloat(0)) { $0 + $1.width }
            + CGFloat(max(0, blocks.count - 1)) * Self.sectionGap

        let image = NSImage(
            size: NSSize(width: ceil(totalWidth), height: Self.iconHeight),
            flipped: true
        ) { _ in
            var x: CGFloat = 0
            for (i, block) in blocks.enumerated() {
                Self.drawBlock(block, at: x, baseColor: baseColor, showsNumbers: self.showsNumbers, ringStyle: self.ringStyle)
                x += block.width
                if i < blocks.count - 1 {
                    if self.showsNumbers {
                        let sepX = x + Self.sectionGap / 2
                        let sepPath = NSBezierPath()
                        sepPath.move(to: NSPoint(x: sepX, y: Self.iconHeight * 0.2))
                        sepPath.line(to: NSPoint(x: sepX, y: Self.iconHeight * 0.8))
                        sepPath.lineWidth = 0.5
                        baseColor.withAlphaComponent(0.25).setStroke()
                        sepPath.stroke()
                    }
                    x += Self.sectionGap
                }
            }
            return true
        }

        image.isTemplate = !hasColors
        return image
    }

    // MARK: - Per-block measurement & drawing

    private struct MeasuredBlock {
        let data: ServiceIconData
        let topSize: NSSize
        let bottomSize: NSSize
        let width: CGFloat
    }

    private static func measureBlock(_ data: ServiceIconData, showsNumbers: Bool) -> MeasuredBlock {
        guard showsNumbers else {
            return MeasuredBlock(data: data, topSize: .zero, bottomSize: .zero, width: self.ringDiameter)
        }
        // NSString reports a line height even for an empty label.
        let topSize = data.topText.isEmpty ? .zero : (data.topText as NSString).size(withAttributes: self.topAttrs)
        let bottomSize = data.bottomText.isEmpty ? .zero : (data.bottomText as NSString).size(withAttributes: self.bottomAttrs)
        let textWidth = max(topSize.width, bottomSize.width)
        let blockWidth = self.ringDiameter + (textWidth > 0 ? self.textGap + textWidth : 0)
        return MeasuredBlock(data: data, topSize: topSize, bottomSize: bottomSize, width: blockWidth)
    }

    private static func drawBlock(_ block: MeasuredBlock, at originX: CGFloat, baseColor: NSColor,
                                  showsNumbers: Bool, ringStyle: MenuBarRingStyle) {
        let ringColor = block.data.ringColor ?? baseColor

        let center = NSPoint(x: originX + self.ringDiameter / 2, y: self.iconHeight / 2)
        if ringStyle == .dual, let quota = block.data.quotaRings {
            let radius = (self.ringDiameter - self.dualRingLineWidth) / 2
            Self.drawRing(at: center, radius: radius, lineWidth: self.dualRingLineWidth,
                          fraction: quota.weekly, color: ringColor, progressAlpha: self.weeklyRingAlpha)
            // A reported zero keeps its track; nil means this window does not apply.
            if let fiveHour = quota.fiveHour {
                Self.drawRing(at: center, radius: radius - self.innerRingInset, lineWidth: self.dualRingLineWidth,
                              fraction: fiveHour, color: ringColor)
            }
        } else {
            Self.drawRing(at: center, radius: (self.ringDiameter - self.ringLineWidth) / 2,
                          lineWidth: self.ringLineWidth, fraction: block.data.ringFraction, color: ringColor)
        }

        // Center symbol (inside ring)
        if let symbol = block.data.centerSymbol {
            Self.drawSymbol(symbol, at: center, color: ringColor)
        }

        guard showsNumbers else { return }

        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: self.topFont,
            .foregroundColor: baseColor,
        ]
        let bottomAttrs: [NSAttributedString.Key: Any] = [
            .font: self.bottomFont,
            .foregroundColor: baseColor.withAlphaComponent(self.secondaryTextAlpha),
        ]

        let textX = originX + self.ringDiameter + self.textGap
        let textTotalHeight = block.topSize.height + block.bottomSize.height
        let textY = (self.iconHeight - textTotalHeight) / 2

        if !block.data.topText.isEmpty {
            (block.data.topText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: topAttrs)
        }
        if !block.data.bottomText.isEmpty {
            (block.data.bottomText as NSString).draw(
                at: NSPoint(x: textX, y: textY + block.topSize.height),
                withAttributes: bottomAttrs
            )
        }
    }

    private static func drawRing(at center: NSPoint, radius: CGFloat, lineWidth: CGFloat,
                                 fraction: Double, color: NSColor, progressAlpha: CGFloat = 1) {
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        color.withAlphaComponent(self.trackAlpha).setStroke()
        track.stroke()

        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0.001 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 270,
                      endAngle: 270 + 360 * clamped, clockwise: false)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.withAlphaComponent(progressAlpha).setStroke()
        arc.stroke()
    }

    // MARK: - Center symbol

    private static func drawSymbol(_ symbol: CenterSymbol, at center: NSPoint, color: NSColor) {
        color.setStroke()
        switch symbol {
        case .questionMark:
            let mark = "?" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: color]
            let size = mark.size(withAttributes: attrs)
            mark.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
        case .checkmark:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: center.x - 3.5, y: center.y + 0.5))
            path.line(to: NSPoint(x: center.x - 1, y: center.y + 3))
            path.line(to: NSPoint(x: center.x + 4, y: center.y - 3))
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .exclamation:
            // Top bar
            let top = NSBezierPath()
            top.move(to: NSPoint(x: center.x, y: center.y - 4))
            top.line(to: NSPoint(x: center.x, y: center.y - 0.5))
            top.lineWidth = 1.8
            top.lineCapStyle = .round
            top.stroke()
            // A filled circle stays round; a stroked segment becomes a capsule.
            let diameter: CGFloat = 2.2
            let dot = NSBezierPath(ovalIn: NSRect(
                x: center.x - diameter / 2, y: center.y + 2,
                width: diameter, height: diameter
            ))
            color.setFill()
            dot.fill()
        }
    }
}
