import AppKit
import SwiftUI

/// Uses the source app's AppKit geometry, rings, and two-line status text.
struct MenuBarBalanceView: View {
    let title: String
    var caption: String = "DSH"
    let toppedUpPercent: Double?
    let grantedPercent: Double?
    let isStale: Bool
    let style: MenuBarStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: statusImage)
            .renderingMode(.original)
            .accessibilityLabel("DSHMeter · " + title + (isStale ? " · " + L10n.string("data.stale") : ""))
    }

    private var statusImage: NSImage {
        let textWidth = max(40, (title as NSString).size(withAttributes: [.font: titleFont]).width.rounded(.up) + 2)
        let contentWidth: CGFloat
        switch style {
        case .iconAndBalance: contentWidth = 18 + 2 + textWidth
        case .iconOnly: contentWidth = 18
        case .balanceOnly, .compactBarBelowBalance: contentWidth = textWidth
        case .horizontalBarBesideBalance, .dualBars: contentWidth = 26 + 2 + textWidth
        }
        let size = NSSize(width: contentWidth + 2 + (isStale ? 13 : 0), height: 20)
        let foreground = colorScheme == .dark ? NSColor.white : NSColor.black
        let blue = NSColor(srgbRed: 0.30, green: 0.72, blue: 1, alpha: 1)
        let image = NSImage(size: size, flipped: false) { rect in
            var x: CGFloat = 1
            switch style {
            case .iconAndBalance, .iconOnly:
                drawRings(in: NSRect(x: x, y: 1, width: 18, height: 18), foreground: foreground, blue: blue)
                if style == .iconAndBalance {
                    x += 20
                    drawTitleAndCaption(in: NSRect(x: x, y: 0, width: textWidth, height: 20), color: foreground)
                }
            case .balanceOnly:
                drawTitleAndCaption(in: NSRect(x: x, y: 0, width: textWidth, height: 20), color: foreground)
            case .horizontalBarBesideBalance:
                drawBar(toppedUpPercent, in: NSRect(x: x, y: 8.5, width: 26, height: 3), color: foreground)
                x += 28
                drawSingleTitle(in: NSRect(x: x, y: 0, width: textWidth, height: 20), color: foreground)
            case .compactBarBelowBalance:
                drawSingleTitle(in: NSRect(x: x, y: 5, width: textWidth, height: 15), color: foreground)
                drawBar(toppedUpPercent, in: NSRect(x: x, y: 1, width: textWidth, height: 3), color: foreground)
            case .dualBars:
                drawBar(toppedUpPercent, in: NSRect(x: x, y: 11.5, width: 26, height: 3), color: foreground)
                drawBar(grantedPercent, in: NSRect(x: x, y: 5.5, width: 26, height: 3), color: blue)
                x += 28
                drawSingleTitle(in: NSRect(x: x, y: 0, width: textWidth, height: 20), color: foreground)
            }
            if isStale {
                drawText("!", in: NSRect(x: rect.maxX - 12, y: 5, width: 10, height: 12),
                         font: .systemFont(ofSize: 10, weight: .bold), color: .systemOrange)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private var titleFont: NSFont { .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold) }

    private func drawTitleAndCaption(in rect: NSRect, color: NSColor) {
        drawText(title, in: NSRect(x: rect.minX, y: rect.height - 12, width: rect.width, height: 12),
                 font: titleFont, color: color)
        drawText(caption, in: NSRect(x: rect.minX, y: 0, width: rect.width, height: 9),
                 font: .systemFont(ofSize: 6.5, weight: .medium), color: color)
    }

    private func drawSingleTitle(in rect: NSRect, color: NSColor) {
        drawText(title, in: NSRect(x: rect.minX, y: rect.midY - 6.75, width: rect.width, height: 13.5),
                 font: titleFont, color: color)
    }

    private func drawRings(in rect: NSRect, foreground: NSColor, blue: NSColor) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius: CGFloat = 7.5
        let innerRadius: CGFloat = 4.7
        drawRing(center: center, radius: outerRadius, lineWidth: 3, value: nil,
                 color: foreground.withAlphaComponent(0.22))
        guard let toppedUpPercent else {
            drawText("?", in: rect, font: .systemFont(ofSize: 8, weight: .semibold), color: .secondaryLabelColor)
            return
        }
        drawRing(center: center, radius: outerRadius, lineWidth: 3, value: toppedUpPercent, color: foreground)
        guard let grantedPercent else { return }
        drawRing(center: center, radius: innerRadius, lineWidth: 2, value: nil, color: blue.withAlphaComponent(0.22))
        drawRing(center: center, radius: innerRadius, lineWidth: 2, value: grantedPercent, color: blue)
    }

    private func drawRing(center: NSPoint, radius: CGFloat, lineWidth: CGFloat, value: Double?, color: NSColor) {
        let path = NSBezierPath()
        if let value {
            let fraction = CGFloat(min(100, max(0, value))) / 100
            guard fraction > 0 else { return }
            path.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
            path.lineCapStyle = .round
        } else {
            path.appendOval(in: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private func drawBar(_ value: Double?, in rect: NSRect, color: NSColor) {
        let radius = rect.height / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.withAlphaComponent(0.22).setFill()
        track.fill()
        guard let value else { return }
        let fraction = CGFloat(min(100, max(0, value))) / 100
        guard fraction > 0 else { return }
        let progress = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY,
                                   width: max(rect.height, rect.width * fraction), height: rect.height),
                                   xRadius: radius, yRadius: radius)
        color.setFill()
        progress.fill()
    }

    private func drawText(_ value: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        (value as NSString).draw(in: rect, withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }
}
