import AppKit

/// Renders the menu bar gauge either as a barometer-style needle (color-coded
/// by *remaining* quota) or as a plain monochrome progress ring.
enum StatusRingImage {
    enum GaugeStyle {
        /// Turn 3: 270° arc, needle, color-coded by remaining quota.
        case needle
        /// Turn 2a: plain monochrome full ring with the percentage inside.
        case ring
    }

    struct Metric {
        let label: String
        /// Used percentage (0...100), as reported by Claude Code.
        let percentage: Double?
    }

    struct Countdown {
        let metricLabel: String
        let text: String
    }

    static func make(metrics: [Metric], isStale: Bool, countdown: Countdown? = nil, style: GaugeStyle = .needle) -> NSImage {
        let ringSize: CGFloat = 22
        let itemSpacing: CGFloat = 4
        let labelGap: CGFloat = 2
        let countdownGap: CGFloat = 1.5
        let labelAttributes = labelAttributes(isStale: isStale)
        let countdownAttributes = countdownAttributes(isStale: isStale)
        let displayLabels = metrics.map { displayLabel($0, style: style) }
        let labelWidths = displayLabels.map {
            ceil(NSAttributedString(string: $0, attributes: labelAttributes).size().width)
        }
        let countdownWidth = countdown.map {
            ceil(NSAttributedString(string: $0.text, attributes: countdownAttributes).size().width)
        } ?? 0
        let integratedCountdownIndex = countdown.flatMap { value in
            metrics.firstIndex { $0.label == value.metricLabel }
        }
        let itemWidths = metrics.indices.map { index in
            ringSize + labelGap + labelWidths[index]
                + (integratedCountdownIndex == index ? countdownGap + countdownWidth : 0)
        }
        let metricsWidth = itemWidths.reduce(0, +) + itemSpacing * CGFloat(max(0, metrics.count - 1))
        let trailingCountdown = countdown.flatMap { integratedCountdownIndex == nil ? $0 : nil }
        let trailingWidth = trailingCountdown.map { value in
            let text = value.metricLabel + value.text
            return itemSpacing + ceil(NSAttributedString(string: text, attributes: countdownAttributes).size().width)
        } ?? 0
        let width = metricsWidth + trailingWidth
        let size = NSSize(width: max(ringSize, ceil(width)), height: ringSize)

        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (index, metric) in metrics.enumerated() {
                let ringRect = NSRect(x: x, y: 0, width: ringSize, height: ringSize)
                switch style {
                case .needle:
                    drawNeedleGauge(usedPercentage: metric.percentage, in: ringRect, isStale: isStale)
                case .ring:
                    drawPlainRing(usedPercentage: metric.percentage, in: ringRect, isStale: isStale)
                }

                let label = NSAttributedString(string: displayLabels[index], attributes: labelAttributes)
                let labelSize = label.size()
                label.draw(at: NSPoint(
                    x: ringRect.maxX + labelGap,
                    y: ringRect.midY - labelSize.height / 2 + 0.3
                ))
                if integratedCountdownIndex == index, let countdown {
                    let value = NSAttributedString(string: countdown.text, attributes: countdownAttributes)
                    let valueSize = value.size()
                    value.draw(at: NSPoint(
                        x: ringRect.maxX + labelGap + labelWidths[index] + countdownGap,
                        y: ringRect.midY - valueSize.height / 2 + 0.3
                    ))
                }
                x += itemWidths[index] + itemSpacing
            }
            if let trailingCountdown {
                let text = trailingCountdown.metricLabel + trailingCountdown.text
                let value = NSAttributedString(string: text, attributes: countdownAttributes)
                let valueSize = value.size()
                value.draw(at: NSPoint(
                    x: metricsWidth + itemSpacing,
                    y: ringSize / 2 - valueSize.height / 2 + 0.3
                ))
            }
            return true
        }
        image.isTemplate = false
        let metricDescription = metrics.map { metric in
            metric.percentage.map { used in
                let remaining = max(0, min(100, 100 - used))
                return "\(metric.label) \(Int(remaining.rounded())) percent remaining"
            } ?? "\(metric.label) unavailable"
        }.joined(separator: ", ")
        image.accessibilityDescription = countdown.map {
            "\(metricDescription), \($0.metricLabel) resets in \($0.text)"
        } ?? metricDescription
        return image
    }

    /// A 270° gauge with a 90° gap centered at the bottom, like a speedometer.
    /// Empty (0% remaining) sits at the lower-left; the arc, needle, and
    /// pivot sweep *clockwise* up and over the top as remaining quota grows,
    /// ending full (100%) at the lower-right — matching the design's needle
    /// orientation. Color-coded by remaining quota.
    private static func drawNeedleGauge(usedPercentage: Double?, in rect: NSRect, isStale: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 7.6
        let startAngle: CGFloat = 5 * .pi / 4 // 225°, lower-left
        let totalSweep: CGFloat = .pi * 1.5 // 270°, swept clockwise (decreasing angle)

        context.setLineWidth(2.1)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - totalSweep, clockwise: true)
        context.strokePath()

        guard let usedPercentage else {
            context.setFillColor(NSColor.white.withAlphaComponent(0.42).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2))
            return
        }

        let remaining = max(0, min(100, 100 - usedPercentage))
        let progress = remaining / 100
        let valueColor = gaugeColor(remaining: remaining)
        context.setStrokeColor(valueColor.withAlphaComponent(isStale ? 0.5 : 1).cgColor)
        context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - totalSweep * progress, clockwise: true)
        context.strokePath()

        let needleAngle = startAngle - totalSweep * progress
        let needleColor = (remaining < 15 ? criticalNeedleColor : NSColor.white).withAlphaComponent(isStale ? 0.5 : 1)
        context.setStrokeColor(needleColor.cgColor)
        context.setLineWidth(1.3)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: center.x + 2.2 * cos(needleAngle), y: center.y + 2.2 * sin(needleAngle)))
        context.addLine(to: CGPoint(x: center.x + 8.4 * cos(needleAngle), y: center.y + 8.4 * sin(needleAngle)))
        context.strokePath()
        context.setFillColor(needleColor.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 1.3, y: center.y - 1.3, width: 2.6, height: 2.6))
    }

    /// A plain monochrome full-circle progress ring with the used percentage
    /// centered inside it — no needle, no color coding.
    private static func drawPlainRing(usedPercentage: Double?, in rect: NSRect, isStale: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 9.5
        context.setLineWidth(1.45)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.strokePath()

        guard let usedPercentage else {
            context.setFillColor(NSColor.white.withAlphaComponent(0.42).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2))
            return
        }

        let progress = max(0, min(usedPercentage / 100, 1))
        context.setStrokeColor(NSColor.white.withAlphaComponent(isStale ? 0.5 : 1).cgColor)
        context.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - (.pi * 2 * progress), clockwise: true)
        context.strokePath()
        drawCenterValue(Int(usedPercentage.rounded()), in: rect, isStale: isStale, color: .white)
    }

    private static func drawCenterValue(_ value: Int, in rect: NSRect, isStale: Bool, color: NSColor) {
        let text = String(value)
        let fontSize: CGFloat = text.count >= 3 ? 7.4 : 10.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: color.withAlphaComponent(isStale ? 0.55 : 1),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2 + 0.4
        ))
    }

    /// The needle gauge's percentage is drawn beside it, not inside — at menu
    /// bar scale the needle sweeps through the center and would collide with
    /// a digit rendered there. The plain ring has room for one inside.
    private static func displayLabel(_ metric: Metric, style: GaugeStyle) -> String {
        switch style {
        case .ring:
            return metric.label
        case .needle:
            guard let usedPercentage = metric.percentage else { return metric.label }
            let remaining = Int(max(0, min(100, 100 - usedPercentage)).rounded())
            return "\(metric.label) \(remaining)%"
        }
    }

    /// Thresholds mirror the design's legend: >50% remaining is green, then
    /// yellow (30–50%), orange (15–30%), and red below 15%.
    private static func gaugeColor(remaining: Double) -> NSColor {
        if remaining < 15 { return NSColor(red: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1) }
        if remaining < 30 { return NSColor(red: 0xfb / 255, green: 0x92 / 255, blue: 0x3c / 255, alpha: 1) }
        if remaining < 50 { return NSColor(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255, alpha: 1) }
        return NSColor(red: 0x4a / 255, green: 0xde / 255, blue: 0x80 / 255, alpha: 1)
    }

    private static var criticalNeedleColor: NSColor {
        NSColor(red: 0xf8 / 255, green: 0x71 / 255, blue: 0x71 / 255, alpha: 1)
    }

    private static func labelAttributes(isStale: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(isStale ? 0.45 : 0.78),
        ]
    }

    private static func countdownAttributes(isStale: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(isStale ? 0.45 : 0.82),
        ]
    }
}
