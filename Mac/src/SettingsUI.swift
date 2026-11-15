import AppKit

private final class FeatureCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.42).cgColor
    }
    required init?(coder: NSCoder) { nil }
}

private final class WinterHeroView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let card = NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22)
        card.addClip()

        let colors = [
            NSColor(calibratedRed: 0.035, green: 0.08, blue: 0.16, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.45, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: bounds.width, y: bounds.height), options: [])
        }

        context.setFillColor(NSColor.white.withAlphaComponent(0.72).cgColor)
        for index in 0..<22 {
            let x = CGFloat((index * 71 + 17) % max(1, Int(bounds.width)))
            let y = CGFloat((index * 47 + 23) % max(1, Int(bounds.height)))
            let size = CGFloat(index.isMultiple(of: 5) ? 2 : 1)
            context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }

        let windowRect = CGRect(x: 24, y: 49, width: bounds.width * 0.54, height: 78)
        let windowShape = CGPath(roundedRect: windowRect, cornerWidth: 11, cornerHeight: 11, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: NSColor.black.withAlphaComponent(0.34).cgColor)
        context.setFillColor(NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.10, alpha: 0.94).cgColor)
        context.addPath(windowShape)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(windowShape)
        context.clip()
        context.setFillColor(NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.19, alpha: 1).cgColor)
        context.fill(CGRect(x: windowRect.minX, y: windowRect.maxY - 23, width: windowRect.width, height: 23))
        let trafficColors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (index, color) in trafficColors.enumerated() {
            context.setFillColor(color.withAlphaComponent(0.92).cgColor)
            context.fillEllipse(in: CGRect(x: windowRect.minX + 11 + CGFloat(index) * 14, y: windowRect.maxY - 16, width: 7, height: 7))
        }
        context.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: windowRect.minX + 17, y: windowRect.minY + 14, width: 74, height: 8), cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor.systemCyan.withAlphaComponent(0.28).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: windowRect.minX + 17, y: windowRect.minY + 29, width: 128, height: 7), cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
        context.restoreGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(1)
        context.addPath(windowShape)
        context.strokePath()

        let cap = CGMutablePath()
        let capLeft = windowRect.minX + 11
        let capRight = windowRect.maxX - 11
        cap.move(to: CGPoint(x: capLeft, y: windowRect.maxY))
        cap.addCurve(to: CGPoint(x: capLeft + 92, y: windowRect.maxY + 5), control1: CGPoint(x: capLeft + 28, y: windowRect.maxY + 8), control2: CGPoint(x: capLeft + 61, y: windowRect.maxY + 2))
        cap.addCurve(to: CGPoint(x: capRight, y: windowRect.maxY + 3), control1: CGPoint(x: capLeft + 145, y: windowRect.maxY + 9), control2: CGPoint(x: capRight - 42, y: windowRect.maxY + 1))
        cap.addLine(to: CGPoint(x: capRight, y: windowRect.maxY))
        cap.closeSubpath()
        context.setFillColor(NSColor(calibratedRed: 0.93, green: 0.98, blue: 1, alpha: 0.98).cgColor)
        context.addPath(cap)
        context.fillPath()

        let dock = CGRect(x: 48, y: 10, width: bounds.width - 82, height: 36)
        let dockPath = CGPath(roundedRect: dock, cornerWidth: 13, cornerHeight: 13, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 7, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        context.setFillColor(NSColor.white.withAlphaComponent(0.20).cgColor)
        context.addPath(dockPath)
        context.fillPath()
        context.restoreGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
        context.setLineWidth(1)
        context.addPath(dockPath)
        context.strokePath()

        let iconColors: [NSColor] = [.systemBlue, .systemGray, .systemPurple, .systemPink, .systemRed, .systemTeal, .systemIndigo, .systemOrange]
        for (index, color) in iconColors.enumerated() {
            let iconRect = CGRect(x: dock.minX + 18 + CGFloat(index) * 34, y: dock.minY + 7, width: 22, height: 22)
            context.setFillColor(color.withAlphaComponent(0.94).cgColor)
            context.addPath(CGPath(roundedRect: iconRect, cornerWidth: 5, cornerHeight: 5, transform: nil))
            context.fillPath()
            context.setFillColor(NSColor.white.withAlphaComponent(0.38).cgColor)
            context.fillEllipse(in: CGRect(x: iconRect.minX + 5, y: iconRect.maxY - 7, width: 3, height: 3))
        }

        let dockSnow = CGMutablePath()
        dockSnow.move(to: CGPoint(x: dock.minX + 12, y: dock.maxY))
        dockSnow.addCurve(to: CGPoint(x: dock.midX, y: dock.maxY + 4), control1: CGPoint(x: dock.minX + 105, y: dock.maxY + 7), control2: CGPoint(x: dock.midX - 65, y: dock.maxY + 1))
        dockSnow.addCurve(to: CGPoint(x: dock.maxX - 12, y: dock.maxY + 2), control1: CGPoint(x: dock.midX + 70, y: dock.maxY + 7), control2: CGPoint(x: dock.maxX - 72, y: dock.maxY))
        dockSnow.addLine(to: CGPoint(x: dock.maxX - 12, y: dock.maxY))
        dockSnow.closeSubpath()
        context.setFillColor(NSColor.white.withAlphaComponent(0.94).cgColor)
        context.addPath(dockSnow)
        context.fillPath()

        let sx = dock.maxX - 43
        let baseY = dock.maxY + 14
        drawBall(context, center: CGPoint(x: sx, y: baseY), radius: 15)
        drawBall(context, center: CGPoint(x: sx, y: baseY + 24), radius: 11)
        drawBall(context, center: CGPoint(x: sx, y: baseY + 43), radius: 8.5)
        context.setFillColor(NSColor(calibratedWhite: 0.05, alpha: 0.95).cgColor)
        context.fillEllipse(in: CGRect(x: sx - 3.8, y: baseY + 45, width: 2.4, height: 2.4))
        context.fillEllipse(in: CGRect(x: sx + 1.4, y: baseY + 45, width: 2.4, height: 2.4))
        context.setFillColor(NSColor(calibratedRed: 0.90, green: 0.14, blue: 0.18, alpha: 1).cgColor)
        context.fill(CGRect(x: sx - 7.5, y: baseY + 51, width: 15, height: 3.5))
        context.fill(CGRect(x: sx - 5.5, y: baseY + 54, width: 11, height: 8))
    }

    private func drawBall(_ context: CGContext, center: CGPoint, radius: CGFloat) {
        context.setFillColor(NSColor(calibratedRed: 0.92, green: 0.98, blue: 1, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.72).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

final class SettingsWindowController: NSWindowController {
    private let settings = SnowSettings.shared
    private let onClear: () -> Void
    private let onPlow: () -> Void

    private let enabledControl = NSSwitch(frame: .zero)
    private let styleControl = NSSegmentedControl(labels: SnowStyle.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let intensitySlider = NSSlider(value: 0.58, minValue: 0.15, maxValue: 1.0, target: nil, action: nil)
    private let frameRateSlider = NSSlider(value: 36, minValue: 20, maxValue: 60, target: nil, action: nil)
    private let windSlider = NSSlider(value: 0.08, minValue: -1.0, maxValue: 1.0, target: nil, action: nil)
    private let windowSnowControl = NSButton(checkboxWithTitle: "На верхушках окон", target: nil, action: nil)
    private let dockSnowControl = NSButton(checkboxWithTitle: "На верхней части Dock", target: nil, action: nil)
    private let groundSnowControl = NSButton(checkboxWithTitle: "Снизу рабочего стола", target: nil, action: nil)
    private let pauseFullscreenControl = NSButton(checkboxWithTitle: "Пауза в полноэкранных приложениях", target: nil, action: nil)
    private let cursorControl = NSButton(checkboxWithTitle: "Снег разлетается от курсора", target: nil, action: nil)
    private let snowmanControl = NSButton(checkboxWithTitle: "Катать снежные шары и лепить снеговика", target: nil, action: nil)
    private let intensityValue = NSTextField(labelWithString: "")
    private let frameRateValue = NSTextField(labelWithString: "")

    init(onClear: @escaping () -> Void, onPlow: @escaping () -> Void) {
        self.onClear = onClear
        self.onPlow = onPlow
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 880),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnowVibe"
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)
        buildUI()
        syncFromSettings()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let window else { return }
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        window.contentView = effect

        let icon = NSImageView(image: NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 25, weight: .semibold)
        icon.contentTintColor = .systemCyan
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36)
        ])

        let title = NSTextField(labelWithString: "SnowVibe")
        title.font = .systemFont(ofSize: 27, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Живой зимний эффект")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let header = NSStackView(views: [icon, titleStack, NSView(), enabledControl])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        enabledControl.target = self
        enabledControl.action = #selector(enabledChanged)

        let hero = WinterHeroView(frame: NSRect(x: 0, y: 0, width: 520, height: 130))
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.heightAnchor.constraint(equalToConstant: 130).isActive = true

        let snowCard = FeatureCardView()
        snowCard.translatesAutoresizingMaskIntoConstraints = false
        let snowStack = NSStackView(views: [
            sectionLabel("Вид снега", symbol: "snowflake"),
            styleControl,
            sliderHeader("Интенсивность", symbol: "cloud.snow.fill", value: intensityValue),
            intensitySlider,
            sliderHeader("Плавность", symbol: "speedometer", value: frameRateValue),
            frameRateSlider,
            sectionLabel("Ветер", symbol: "wind"),
            windRow()
        ])
        snowStack.orientation = .vertical
        snowStack.alignment = .leading
        snowStack.spacing = 9
        snowStack.translatesAutoresizingMaskIntoConstraints = false
        snowCard.addSubview(snowStack)
        NSLayoutConstraint.activate([
            snowStack.leadingAnchor.constraint(equalTo: snowCard.leadingAnchor, constant: 16),
            snowStack.trailingAnchor.constraint(equalTo: snowCard.trailingAnchor, constant: -16),
            snowStack.topAnchor.constraint(equalTo: snowCard.topAnchor, constant: 14),
            snowStack.bottomAnchor.constraint(equalTo: snowCard.bottomAnchor, constant: -14)
        ])
        for view in [styleControl, intensitySlider, frameRateSlider] {
            view.widthAnchor.constraint(equalTo: snowStack.widthAnchor).isActive = true
        }

        styleControl.segmentStyle = .rounded
        styleControl.target = self
        styleControl.action = #selector(styleChanged)
        intensitySlider.target = self
        intensitySlider.action = #selector(intensityChanged)
        intensitySlider.isContinuous = true
        frameRateSlider.target = self
        frameRateSlider.action = #selector(frameRateChanged)
        frameRateSlider.isContinuous = true
        frameRateSlider.numberOfTickMarks = 5
        frameRateSlider.allowsTickMarkValuesOnly = false
        windSlider.target = self
        windSlider.action = #selector(windChanged)
        windSlider.isContinuous = true

        let physicsCard = FeatureCardView()
        physicsCard.translatesAutoresizingMaskIntoConstraints = false
        let accumulationTitle = sectionLabel("Где копить снег", symbol: "square.stack.3d.up.fill")
        let physicsTitle = sectionLabel("Физика и игра", symbol: "sparkles")
        for control in [windowSnowControl, dockSnowControl, groundSnowControl, pauseFullscreenControl, cursorControl, snowmanControl] {
            control.font = .systemFont(ofSize: 13, weight: .medium)
        }
        windowSnowControl.target = self
        windowSnowControl.action = #selector(windowSnowChanged)
        dockSnowControl.target = self
        dockSnowControl.action = #selector(dockSnowChanged)
        groundSnowControl.target = self
        groundSnowControl.action = #selector(groundSnowChanged)
        pauseFullscreenControl.target = self
        pauseFullscreenControl.action = #selector(pauseFullscreenChanged)
        cursorControl.target = self
        cursorControl.action = #selector(cursorChanged)
        snowmanControl.target = self
        snowmanControl.action = #selector(snowmanChanged)
        let physicsStack = NSStackView(views: [
            accumulationTitle,
            windowSnowControl,
            dockSnowControl,
            groundSnowControl,
            physicsTitle,
            pauseFullscreenControl,
            cursorControl,
            snowmanControl
        ])
        physicsStack.orientation = .vertical
        physicsStack.alignment = .leading
        physicsStack.spacing = 9
        physicsStack.translatesAutoresizingMaskIntoConstraints = false
        physicsCard.addSubview(physicsStack)
        NSLayoutConstraint.activate([
            physicsStack.leadingAnchor.constraint(equalTo: physicsCard.leadingAnchor, constant: 16),
            physicsStack.trailingAnchor.constraint(equalTo: physicsCard.trailingAnchor, constant: -16),
            physicsStack.topAnchor.constraint(equalTo: physicsCard.topAnchor, constant: 14),
            physicsStack.bottomAnchor.constraint(equalTo: physicsCard.bottomAnchor, constant: -14)
        ])

        let clearButton = actionButton("Очистить весь снег", symbol: "sparkles", action: #selector(clearPressed))
        let plowButton = actionButton("Запустить снегоуборщик", symbol: "truck.box.fill", action: #selector(plowPressed))
        plowButton.bezelColor = .systemBlue
        plowButton.contentTintColor = .white
        plowButton.attributedTitle = NSAttributedString(
            string: "Запустить снегоуборщик",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ]
        )
        plowButton.toolTip = "Снегоуборщик проедет по Dock, сгребая и разбрасывая снег"
        let buttonRow = NSStackView(views: [clearButton, plowButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 10

        let hint = NSTextField(wrappingLabelWithString: "Нажми и тяни по снегу на окне или Dock. Отпусти кнопку — шар упадёт. Три шара соберут снеговика; нажатие на него разломит его.")
        hint.font = .systemFont(ofSize: 11.5, weight: .medium)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let footer = NSTextField(labelWithString: "Не читает содержимое окон · клики проходят сквозь снег")
        footer.font = .systemFont(ofSize: 10.5)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center

        let stack = NSStackView(views: [header, hero, snowCard, physicsCard, buttonRow, hint, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        for view in [header, hero, snowCard, physicsCard, buttonRow, hint, footer] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -18),
            snowCard.heightAnchor.constraint(equalToConstant: 240),
            physicsCard.heightAnchor.constraint(equalToConstant: 238),
            clearButton.heightAnchor.constraint(equalToConstant: 40),
            plowButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func sectionLabel(_ title: String, symbol: String) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .systemCyan
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    private func sliderHeader(_ title: String, symbol: String, value: NSTextField) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .systemCyan
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18)
        ])
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        value.textColor = .secondaryLabelColor
        let row = NSStackView(views: [image, label, NSView(), value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    private func windRow() -> NSView {
        let left = NSTextField(labelWithString: "←")
        let right = NSTextField(labelWithString: "→")
        left.textColor = .secondaryLabelColor
        right.textColor = .secondaryLabelColor
        let row = NSStackView(views: [left, windSlider, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func actionButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        return button
    }

    func syncFromSettings() {
        enabledControl.state = settings.enabled ? .on : .off
        styleControl.selectedSegment = settings.style.rawValue
        intensitySlider.doubleValue = settings.intensity
        frameRateSlider.doubleValue = settings.frameRate
        windSlider.doubleValue = settings.wind
        windowSnowControl.state = settings.windowSnow ? .on : .off
        dockSnowControl.state = settings.dockSnow ? .on : .off
        groundSnowControl.state = settings.groundSnow ? .on : .off
        pauseFullscreenControl.state = settings.pauseFullscreen ? .on : .off
        cursorControl.state = settings.cursorReaction ? .on : .off
        snowmanControl.state = settings.snowmanMode ? .on : .off
        intensityValue.stringValue = "\(Int(settings.intensity * 100))%"
        frameRateValue.stringValue = "\(Int(settings.frameRate.rounded())) FPS"
    }

    func show() {
        syncFromSettings()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func enabledChanged() { settings.enabled = enabledControl.state == .on }
    @objc private func styleChanged() { settings.style = SnowStyle(rawValue: styleControl.selectedSegment) ?? .crystal }
    @objc private func intensityChanged() { settings.intensity = intensitySlider.doubleValue; intensityValue.stringValue = "\(Int(settings.intensity * 100))%" }
    @objc private func frameRateChanged() {
        settings.frameRate = frameRateSlider.doubleValue.rounded()
        frameRateValue.stringValue = "\(Int(settings.frameRate)) FPS"
    }
    @objc private func windChanged() { settings.wind = windSlider.doubleValue }
    @objc private func windowSnowChanged() { settings.windowSnow = windowSnowControl.state == .on }
    @objc private func dockSnowChanged() { settings.dockSnow = dockSnowControl.state == .on }
    @objc private func groundSnowChanged() { settings.groundSnow = groundSnowControl.state == .on }
    @objc private func pauseFullscreenChanged() { settings.pauseFullscreen = pauseFullscreenControl.state == .on }
    @objc private func cursorChanged() { settings.cursorReaction = cursorControl.state == .on }
    @objc private func snowmanChanged() { settings.snowmanMode = snowmanControl.state == .on }
    @objc private func clearPressed() { onClear() }
    @objc private func plowPressed() { onPlow() }
}
