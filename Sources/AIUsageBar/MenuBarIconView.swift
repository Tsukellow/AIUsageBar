import AppKit

enum CenterSymbol {
    case checkmark
    case exclamation
}

/// Data for one service's ring + text block in the menu bar.
struct ServiceIconData {
    let ringFraction: Double
    let topText: String
    let bottomText: String
    /// Optional ring color; nil uses the default menu bar tint.
    let ringColor: NSColor?
    let centerSymbol: CenterSymbol?

    init(ringFraction: Double, topText: String, bottomText: String, ringColor: NSColor? = nil, centerSymbol: CenterSymbol? = nil) {
        self.ringFraction = ringFraction
        self.topText = topText
        self.bottomText = bottomText
        self.ringColor = ringColor
        self.centerSymbol = centerSymbol
    }
}

@MainActor
struct MenuBarIconView {
    let services: [ServiceIconData]

    // MARK: - Layout constants

    private static let ringDiameter: CGFloat = 18
    private static let ringLineWidth: CGFloat = 2.0
    private static let textGap: CGFloat = 4
    private static let sectionGap: CGFloat = 8
    private static let iconHeight: CGFloat = 22
    private static let trackAlpha: CGFloat = 0.3

    private static let topFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let bottomFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

    private static let topAttrs: [NSAttributedString.Key: Any] = [
        .font: MenuBarIconView.topFont,
        .foregroundColor: NSColor.black,
    ]
    private static let bottomAttrs: [NSAttributedString.Key: Any] = [
        .font: MenuBarIconView.bottomFont,
        .foregroundColor: NSColor.black.withAlphaComponent(0.55),
    ]

    // MARK: - Rendering

    func renderedImage() -> NSImage {
        let hasColors = self.services.contains { $0.ringColor != nil }
        let baseColor: NSColor = .white

        let blocks = self.services.map { Self.measureBlock($0) }
        let totalWidth = blocks.reduce(CGFloat(0)) { $0 + $1.width }
            + CGFloat(max(0, blocks.count - 1)) * Self.sectionGap

        let image = NSImage(
            size: NSSize(width: ceil(totalWidth), height: Self.iconHeight),
            flipped: true
        ) { _ in
            var x: CGFloat = 0
            for (i, block) in blocks.enumerated() {
                Self.drawBlock(block, at: x, baseColor: baseColor)
                x += block.width
                if i < blocks.count - 1 {
                    let sepX = x + Self.sectionGap / 2
                    let sepPath = NSBezierPath()
                    sepPath.move(to: NSPoint(x: sepX, y: Self.iconHeight * 0.2))
                    sepPath.line(to: NSPoint(x: sepX, y: Self.iconHeight * 0.8))
                    sepPath.lineWidth = 0.5
                    baseColor.withAlphaComponent(0.25).setStroke()
                    sepPath.stroke()

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

    private static func measureBlock(_ data: ServiceIconData) -> MeasuredBlock {
        let topSize = (data.topText as NSString).size(withAttributes: self.topAttrs)
        let bottomSize = (data.bottomText as NSString).size(withAttributes: self.bottomAttrs)
        let textWidth = max(topSize.width, bottomSize.width)
        let blockWidth = self.ringDiameter + self.textGap + textWidth
        return MeasuredBlock(data: data, topSize: topSize, bottomSize: bottomSize, width: blockWidth)
    }

    private static func drawBlock(_ block: MeasuredBlock, at originX: CGFloat, baseColor: NSColor) {
        let ringColor = block.data.ringColor ?? baseColor

        // Ring
        let center = NSPoint(x: originX + self.ringDiameter / 2, y: self.iconHeight / 2)
        let radius = (self.ringDiameter - self.ringLineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = self.ringLineWidth
        track.lineCapStyle = .round
        ringColor.withAlphaComponent(self.trackAlpha).setStroke()
        track.stroke()

        let clamped = min(max(block.data.ringFraction, 0), 1)
        if clamped > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 270,
                endAngle: 270 + 360 * clamped,
                clockwise: false
            )
            arc.lineWidth = self.ringLineWidth
            arc.lineCapStyle = .round
            ringColor.setStroke()
            arc.stroke()
        }

        // Center symbol (inside ring)
        if let symbol = block.data.centerSymbol {
            Self.drawSymbol(symbol, at: center, color: ringColor)
        }

        // Texts
        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: self.topFont,
            .foregroundColor: baseColor,
        ]
        let bottomAttrs: [NSAttributedString.Key: Any] = [
            .font: self.bottomFont,
            .foregroundColor: baseColor.withAlphaComponent(0.55),
        ]

        let textX = originX + self.ringDiameter + self.textGap
        let textTotalHeight = block.topSize.height + block.bottomSize.height
        let textY = (self.iconHeight - textTotalHeight) / 2

        (block.data.topText as NSString).draw(
            at: NSPoint(x: textX, y: textY),
            withAttributes: topAttrs
        )
        (block.data.bottomText as NSString).draw(
            at: NSPoint(x: textX, y: textY + block.topSize.height),
            withAttributes: bottomAttrs
        )
    }

    // MARK: - Center symbol

    private static func drawSymbol(_ symbol: CenterSymbol, at center: NSPoint, color: NSColor) {
        color.setStroke()
        switch symbol {
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
            // Bottom dot
            let dot = NSBezierPath()
            dot.move(to: NSPoint(x: center.x, y: center.y + 1.5))
            dot.line(to: NSPoint(x: center.x, y: center.y + 3))
            dot.lineWidth = 1.8
            dot.lineCapStyle = .round
            dot.stroke()
        }
    }
}
