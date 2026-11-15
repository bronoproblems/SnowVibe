import AppKit
import CoreGraphics
import QuartzCore

enum SnowStyle: Int, CaseIterable {
    case crystal
    case fluffy
    case blizzard
    case sparkle

    var title: String {
        switch self {
        case .crystal: return "Снежинки"
        case .fluffy: return "Пушистый"
        case .blizzard: return "Метель"
        case .sparkle: return "Искры"
        }
    }

    var speed: ClosedRange<CGFloat> {
        switch self {
        case .crystal: return 38...82
        case .fluffy: return 22...52
        case .blizzard: return 105...185
        case .sparkle: return 32...72
        }
    }

    var size: ClosedRange<CGFloat> {
        switch self {
        case .crystal: return 4.5...9.5
        case .fluffy: return 5.5...12.5
        case .blizzard: return 2.0...5.0
        case .sparkle: return 2.5...6.0
        }
    }
}

enum SnowPreferenceMigration {
    static let legacyDomain = "local.snowgarden.desktop"

    static let registeredDefaults: [String: Any] = [
        "enabled": true,
        "intensity": 0.58,
        "wind": 0.08,
        "frameRate": 36.0,
        "style": SnowStyle.crystal.rawValue,
        "windowSnow": true,
        "dockSnow": true,
        "groundSnow": true,
        "pauseFullscreen": true,
        "cursorReaction": true,
        "snowmanMode": true
    ]

    static func prepare(defaults: UserDefaults, currentDomain: String, legacyDomain: String = legacyDomain) {
        if defaults.persistentDomain(forName: currentDomain) == nil,
           let legacy = defaults.persistentDomain(forName: legacyDomain) {
            defaults.setPersistentDomain(legacy, forName: currentDomain)
        }

        var persisted = defaults.persistentDomain(forName: currentDomain) ?? [:]
        var version = persisted["settingsVersion"] as? Int ?? 0

        func setIfMissing(_ key: String, _ value: Any) {
            guard persisted[key] == nil else { return }
            persisted[key] = value
        }

        if version < 2 {
            setIfMissing("intensity", 0.58)
            setIfMissing("wind", 0.08)
            setIfMissing("style", SnowStyle.crystal.rawValue)
            setIfMissing("surfaceSnow", true)
            setIfMissing("cursorReaction", true)
            setIfMissing("snowmanMode", true)
            version = 2
        }
        if version < 3 {
            setIfMissing("frameRate", 36.0)
            version = 3
        }
        if version < 4 {
            let oldSurfaceSetting = persisted["surfaceSnow"] as? Bool ?? true
            setIfMissing("windowSnow", oldSurfaceSetting)
            setIfMissing("dockSnow", oldSurfaceSetting)
            setIfMissing("groundSnow", oldSurfaceSetting)
            version = 4
        }
        if version < 5 {
            setIfMissing("pauseFullscreen", true)
            version = 5
        }
        persisted["settingsVersion"] = version
        defaults.setPersistentDomain(persisted, forName: currentDomain)
        defaults.register(defaults: registeredDefaults)
    }

    static func boundedDouble(
        _ defaults: UserDefaults,
        key: String,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        let value = number.doubleValue
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

final class SnowSettings {
    static let shared = SnowSettings()

    private let defaults = UserDefaults.standard
    var didChange: (() -> Void)?

    var enabled: Bool { didSet { save("enabled", enabled) } }
    var intensity: Double { didSet { save("intensity", intensity) } }
    var wind: Double { didSet { save("wind", wind) } }
    var frameRate: Double { didSet { save("frameRate", frameRate) } }
    var style: SnowStyle { didSet { save("style", style.rawValue) } }
    var windowSnow: Bool { didSet { save("windowSnow", windowSnow) } }
    var dockSnow: Bool { didSet { save("dockSnow", dockSnow) } }
    var groundSnow: Bool { didSet { save("groundSnow", groundSnow) } }
    var pauseFullscreen: Bool { didSet { save("pauseFullscreen", pauseFullscreen) } }
    var cursorReaction: Bool { didSet { save("cursorReaction", cursorReaction) } }
    var snowmanMode: Bool { didSet { save("snowmanMode", snowmanMode) } }

    private init() {
        let domain = Bundle.main.bundleIdentifier ?? "local.snowvibe.desktop"
        SnowPreferenceMigration.prepare(defaults: defaults, currentDomain: domain)
        enabled = defaults.bool(forKey: "enabled")
        intensity = SnowPreferenceMigration.boundedDouble(defaults, key: "intensity", fallback: 0.58, range: 0.15...1.0)
        wind = SnowPreferenceMigration.boundedDouble(defaults, key: "wind", fallback: 0.08, range: -1.0...1.0)
        frameRate = SnowPreferenceMigration.boundedDouble(defaults, key: "frameRate", fallback: 36, range: 20...60)
        style = SnowStyle(rawValue: defaults.integer(forKey: "style")) ?? .crystal
        windowSnow = defaults.bool(forKey: "windowSnow")
        dockSnow = defaults.bool(forKey: "dockSnow")
        groundSnow = defaults.bool(forKey: "groundSnow")
        pauseFullscreen = defaults.bool(forKey: "pauseFullscreen")
        cursorReaction = defaults.bool(forKey: "cursorReaction")
        snowmanMode = defaults.bool(forKey: "snowmanMode")

        let environment = ProcessInfo.processInfo.environment
        if let value = environment["SNOWVIBE_TEST_ENABLED"] {
            enabled = value != "0"
        }
        if let value = environment["SNOWVIBE_TEST_INTENSITY"].flatMap(Double.init), value.isFinite {
            intensity = min(1, max(0.15, value))
        }
        if let value = environment["SNOWVIBE_TEST_FPS"].flatMap(Double.init), value.isFinite {
            frameRate = min(60, max(20, value))
        }
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        didChange?()
    }
}

enum WindowOcclusion {
    private static let excludedOwners = Set(["Window Server", "Control Center", "SystemUIServer", "Notification Center"])

    static func isVisibleRegularWindow(alpha: CGFloat, layer: Int, owner: String) -> Bool {
        alpha > 0.02 && layer == 0 && !excludedOwners.contains(owner)
    }

    static func coversFullscreen(_ rect: CGRect, within bounds: CGRect) -> Bool {
        let tolerance = max(2, min(bounds.width, bounds.height) * 0.005)
        return rect.minX <= bounds.minX + tolerance &&
            rect.minY <= bounds.minY + tolerance &&
            rect.maxX >= bounds.maxX - tolerance &&
            rect.maxY >= bounds.maxY - tolerance
    }

    static func coversFullscreen(
        _ rect: CGRect,
        within bounds: CGRect,
        companionRects: [CGRect]
    ) -> Bool {
        if coversFullscreen(rect, within: bounds) { return true }

        let tolerance = max(2, min(bounds.width, bounds.height) * 0.005)
        let maximumChromeHeight = max(80, bounds.height * 0.08)
        guard rect.minX <= bounds.minX + tolerance,
              rect.maxX >= bounds.maxX - tolerance,
              rect.minY <= bounds.minY + tolerance,
              rect.maxY < bounds.maxY - tolerance,
              bounds.maxY - rect.maxY <= maximumChromeHeight
        else { return false }

        return companionRects.contains { companion in
            companion.minX <= bounds.minX + tolerance &&
                companion.maxX >= bounds.maxX - tolerance &&
                companion.maxY >= bounds.maxY - tolerance &&
                companion.minY <= rect.maxY + tolerance &&
                companion.height <= maximumChromeHeight &&
                companion.height >= 2
        }
    }

    static func exposedRanges(for rect: CGRect, occludedBy frontRects: [CGRect]) -> [ClosedRange<CGFloat>] {
        let cornerInset = min(16, max(10, rect.width * 0.018))
        let safeLeft = rect.minX + cornerInset
        let safeRight = rect.maxX - cornerInset
        guard safeRight > safeLeft else { return [] }
        var ranges: [ClosedRange<CGFloat>] = [safeLeft...safeRight]
        let snowBandBottom = rect.maxY - 1
        let snowBandTop = rect.maxY + 34

        for front in frontRects where front.maxY > snowBandBottom && front.minY < snowBandTop {
            let cutLow = max(safeLeft, front.minX - 1.5)
            let cutHigh = min(safeRight, front.maxX + 1.5)
            guard cutHigh - cutLow > 0.5 else { continue }

            var next: [ClosedRange<CGFloat>] = []
            for range in ranges {
                if cutHigh <= range.lowerBound || cutLow >= range.upperBound {
                    next.append(range)
                    continue
                }
                if cutLow - range.lowerBound > 0.5 {
                    next.append(range.lowerBound...cutLow)
                }
                if range.upperBound - cutHigh > 0.5 {
                    next.append(cutHigh...range.upperBound)
                }
            }
            ranges = next
            if ranges.isEmpty { break }
        }
        return ranges
    }
}

private extension ClosedRange where Bound == CGFloat {
    func random() -> CGFloat { CGFloat.random(in: self) }
}

private struct WindowSnapshot {
    let id: Int
    let owner: String
    let layer: Int
    let quartzRect: CGRect
    let alpha: CGFloat
}

private final class WindowSnapshotProvider {
    static let shared = WindowSnapshotProvider()
    private let queue = DispatchQueue(label: "local.snowvibe.window-scan", qos: .utility)
    private let lock = NSLock()
    private var cached: [WindowSnapshot] = []
    private var lastRequest: CFTimeInterval = 0
    private var refreshInProgress = false
    private var suspiciousEmptyReads = 0

    func snapshots(now: CFTimeInterval) -> [WindowSnapshot] {
        lock.lock()
        let result = cached
        let shouldRefresh = now - lastRequest >= 0.42 && !refreshInProgress
        if shouldRefresh {
            lastRequest = now
            refreshInProgress = true
        }
        lock.unlock()

        if shouldRefresh {
            queue.async { [weak self] in
                guard let self else { return }
                let fresh = self.readSnapshots()
                self.lock.lock()
                if fresh.isEmpty, !self.cached.isEmpty {
                    self.suspiciousEmptyReads += 1
                    if self.suspiciousEmptyReads >= 4 {
                        self.cached = fresh
                        self.suspiciousEmptyReads = 0
                    }
                } else {
                    self.cached = fresh
                    self.suspiciousEmptyReads = 0
                }
                self.refreshInProgress = false
                self.lock.unlock()
            }
        }
        return result
    }

    private func readSnapshots() -> [WindowSnapshot] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawList.compactMap { item in
            guard
                let number = item[kCGWindowNumber as String] as? NSNumber,
                let owner = item[kCGWindowOwnerName as String] as? String,
                let layer = item[kCGWindowLayer as String] as? NSNumber,
                let boundsDictionary = item[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: boundsDictionary)
            else { return nil }
            let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return WindowSnapshot(
                id: number.intValue,
                owner: owner,
                layer: layer.intValue,
                quartzRect: rect,
                alpha: CGFloat(alpha)
            )
        }
    }
}

private final class SnowSurface {
    let id: Int
    var rect: CGRect
    var pile: [CGFloat]
    var lastSeen: CFTimeInterval
    var missingSince: CFTimeInterval?
    var exposedRanges: [ClosedRange<CGFloat>]
    var suspendedUntil: CFTimeInterval = 0

    init(id: Int, rect: CGRect, now: CFTimeInterval) {
        self.id = id
        self.rect = rect
        self.pile = Array(repeating: 0, count: max(3, Int(rect.width / 7) + 1))
        self.lastSeen = now
        self.exposedRanges = [rect.minX...rect.maxX]
    }

    func resize(to newRect: CGRect) {
        let oldPile = pile
        rect = newRect
        let newCount = max(3, Int(newRect.width / 7) + 1)
        guard newCount != oldPile.count else { return }
        pile = (0..<newCount).map { index in
            guard oldPile.count > 1 else { return 0 }
            let source = min(oldPile.count - 1, Int(CGFloat(index) / CGFloat(newCount - 1) * CGFloat(oldPile.count - 1)))
            return oldPile[source]
        }
    }

    func height(at x: CGFloat) -> CGFloat {
        guard rect.width > 0, pile.count > 1 else { return 0 }
        let p = min(CGFloat(pile.count - 1), max(0, (x - rect.minX) / rect.width * CGFloat(pile.count - 1)))
        let low = Int(p)
        let high = min(pile.count - 1, low + 1)
        let t = p - CGFloat(low)
        return pile[low] * (1 - t) + pile[high] * t
    }

    func add(at x: CGFloat, amount: CGFloat) {
        guard rect.width > 0, !pile.isEmpty else { return }
        let center = min(pile.count - 1, max(0, Int((x - rect.minX) / rect.width * CGFloat(pile.count - 1))))
        for offset in -2...2 {
            let index = center + offset
            guard pile.indices.contains(index) else { continue }
            let weight: CGFloat = offset == 0 ? 1 : (abs(offset) == 1 ? 0.56 : 0.22)
            pile[index] = min(30, pile[index] + amount * weight)
        }
    }

    func smooth() {
        guard pile.count > 2 else { return }
        var next = pile
        for index in 1..<(pile.count - 1) {
            let average = (pile[index - 1] + pile[index] * 2 + pile[index + 1]) / 4
            next[index] = pile[index] * 0.95 + average * 0.05
        }
        pile = next
    }

    var hasSnow: Bool { pile.contains { $0 > 0.12 } }
    func isExposed(at x: CGFloat) -> Bool { exposedRanges.contains { $0.contains(x) } }
    func isActive(at now: CFTimeInterval) -> Bool { missingSince == nil && now >= suspendedUntil }
    func clear() { pile = Array(repeating: 0, count: pile.count) }
}

private struct Snowflake {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var size: CGFloat
    var phase: CGFloat
    var spin: CGFloat
    var opacity: CGFloat
}

private struct FallingClump {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var size: CGFloat
    var rotation: CGFloat
    var life: CGFloat
    var canSettle: Bool
    var settleDelay: CGFloat
}

private struct SnowBall {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var radius: CGFloat
    var targetRadius: CGFloat
    var rotation: CGFloat
    var active: Bool
    var stable: Bool
}

final class SnowView: NSView {
    private enum CollisionTarget {
        case window(SnowSurface)
        case dock
        case ground
    }

    private let screenFrame: CGRect
    private var flakes: [Snowflake] = []
    private var falling: [FallingClump] = []
    private var surfaces: [Int: SnowSurface] = [:]
    private var groundPile: [CGFloat] = []
    private var dockRect: CGRect = .zero
    private var dockPile: [CGFloat] = []
    private var timer: Timer?
    private var configuredFrameRate: Double = 0
    private var previousTime = CACurrentMediaTime()
    private var currentTime = CACurrentMediaTime()
    private var lastSurfaceScan: CFTimeInterval = 0
    private var gustPhase = CGFloat.random(in: 0...(2 * .pi))
    private var smoothingClock: CGFloat = 0
    private var fullscreenPaused = false
    private let diagnosticsEnabled = ProcessInfo.processInfo.environment["SNOWVIBE_DIAGNOSTICS"] == "1"
    private var diagnosticsStart = CACurrentMediaTime()
    private var diagnosticTicks = 0
    private var diagnosticDraws = 0
    private var diagnosticDeltaTotal: CFTimeInterval = 0
    private var diagnosticMaxDelta: CFTimeInterval = 0

    private static let fallingClumpPath: CGPath = {
        let path = CGMutablePath()
        let points = 7
        for index in 0..<points {
            let angle = CGFloat(index) / CGFloat(points) * 2 * .pi
            let radius: CGFloat = index.isMultiple(of: 2) ? 1 : 0.72
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }()

    private var plowX: CGFloat?
    private var plowLoad: CGFloat = 0
    private var plowSprayClock: CGFloat = 0

    private var balls: [SnowBall] = []
    private var activeBallIndex: Int?
    private var pendingPointerDown: CGPoint?
    private var pendingBallIndex: Int?
    private var lastDragPoint: CGPoint?
    private var lastDragTime: CFTimeInterval = 0
    private var snowmanComplete = false
    private var snowmanBorn: CFTimeInterval = 0

    init(frame frameRect: NSRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsScale = 1.0
        layer?.drawsAsynchronously = false
        canDrawConcurrently = false
        rebuildGroundPile()
        configureTimer(force: true)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    deinit { timer?.invalidate() }

    func settingsDidChange() {
        let settings = SnowSettings.shared
        if !settings.enabled { flakes.removeAll(keepingCapacity: true) }
        if !settings.enabled || !settings.snowmanMode {
            pendingPointerDown = nil
            pendingBallIndex = nil
            activeBallIndex = nil
            lastDragPoint = nil
            for index in balls.indices { balls[index].active = false }
        }
        if !settings.windowSnow { surfaces.values.forEach { $0.clear() } }
        if !settings.dockSnow {
            dockPile = Array(repeating: 0, count: dockPile.count)
            plowX = nil
        }
        if !settings.groundSnow { groundPile = Array(repeating: 0, count: groundPile.count) }
        if !settings.pauseFullscreen { fullscreenPaused = false }
        configureTimer()
        needsDisplay = true
    }

    private func configureTimer(force: Bool = false) {
        guard SnowSettings.shared.enabled else {
            stopAnimation()
            return
        }
        let fps = fullscreenPaused ? 4 : min(60, max(20, SnowSettings.shared.frameRate.rounded()))
        guard force || timer == nil || abs(fps - configuredFrameRate) >= 0.5 else { return }
        timer?.invalidate()
        configuredFrameRate = fps
        previousTime = CACurrentMediaTime()
        let next = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
        next.tolerance = min(0.004, 1.0 / fps * 0.12)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    func clearSnow() {
        groundPile = Array(repeating: 0, count: groundPile.count)
        dockPile = Array(repeating: 0, count: dockPile.count)
        surfaces.values.forEach { $0.clear() }
        falling.removeAll()
        balls.removeAll()
        activeBallIndex = nil
        pendingPointerDown = nil
        pendingBallIndex = nil
        lastDragPoint = nil
        plowX = nil
        plowLoad = 0
        plowSprayClock = 0
        snowmanComplete = false
        needsDisplay = true
    }

    func summonPlow() {
        guard SnowSettings.shared.enabled, SnowSettings.shared.dockSnow, dockRect.width > 0, plowX == nil else { return }
        plowX = dockRect.minX - 150
        plowLoad = 0
        plowSprayClock = 0
    }

    func handlePointerDown(globalPoint: CGPoint) {
        guard SnowSettings.shared.enabled, SnowSettings.shared.snowmanMode, !fullscreenPaused else { return }
        let point = CGPoint(x: globalPoint.x - screenFrame.minX, y: globalPoint.y - screenFrame.minY)
        guard bounds.contains(point) else { return }

        if snowmanComplete, balls.contains(where: { hypot(point.x - $0.x, point.y - $0.y) <= $0.radius + 8 }) {
            breakSnowman(at: point)
            return
        }

        if let ballIndex = balls.indices.first(where: {
            hypot(point.x - balls[$0].x, point.y - balls[$0].y) <= balls[$0].radius + 6
        }) {
            pendingPointerDown = point
            pendingBallIndex = ballIndex
            lastDragPoint = point
            lastDragTime = CACurrentMediaTime()
            return
        }

        if rollingSurface(at: point) != nil, balls.count < 3 {
            pendingPointerDown = point
            pendingBallIndex = nil
            lastDragPoint = point
            lastDragTime = CACurrentMediaTime()
        }
    }

    func handlePointerDragged(globalPoint: CGPoint) {
        guard SnowSettings.shared.enabled, SnowSettings.shared.snowmanMode, !fullscreenPaused, let down = pendingPointerDown else { return }
        let point = CGPoint(x: globalPoint.x - screenFrame.minX, y: globalPoint.y - screenFrame.minY)
        let totalDrag = hypot(point.x - down.x, point.y - down.y)
        let now = CACurrentMediaTime()

        if activeBallIndex == nil, totalDrag >= 8 {
            if let existing = pendingBallIndex, balls.indices.contains(existing) {
                balls[existing].active = true
                balls[existing].stable = false
                activeBallIndex = existing
            } else {
                let targets: [CGFloat] = [44, 33, 24]
                let stage = min(2, balls.count)
                balls.append(SnowBall(
                    x: point.x,
                    y: max(point.y, dockRect.maxY + 9),
                    vx: 0,
                    vy: 0,
                    radius: 9,
                    targetRadius: targets[stage],
                    rotation: 0,
                    active: true,
                    stable: false
                ))
                activeBallIndex = balls.count - 1
            }
        }

        if let active = activeBallIndex, balls.indices.contains(active) {
            let previous = lastDragPoint ?? point
            let movement = hypot(point.x - previous.x, point.y - previous.y)
            balls[active].x = point.x
            balls[active].y = point.y
            balls[active].rotation += movement / max(8, balls[active].radius)
            if rollingSurface(at: point) != nil {
                balls[active].radius = min(balls[active].targetRadius, balls[active].radius + movement * 0.065)
                carveSnow(at: point, radius: balls[active].radius)
            }
        }
        lastDragPoint = point
        lastDragTime = now
    }

    func handlePointerUp(globalPoint: CGPoint) {
        let point = CGPoint(x: globalPoint.x - screenFrame.minX, y: globalPoint.y - screenFrame.minY)
        if let active = activeBallIndex, balls.indices.contains(active) {
            let previous = lastDragPoint ?? point
            let elapsed = max(0.016, CACurrentMediaTime() - lastDragTime)
            balls[active].active = false
            balls[active].stable = false
            balls[active].vx = (point.x - previous.x) / CGFloat(elapsed) * 0.22
            balls[active].vy = max(8, (point.y - previous.y) / CGFloat(elapsed) * 0.18)
        }
        activeBallIndex = nil
        pendingPointerDown = nil
        pendingBallIndex = nil
        lastDragPoint = nil
    }

    private func rollingSurface(at point: CGPoint) -> CollisionTarget? {
        var nearest: (CollisionTarget, CGFloat)?
        for surface in surfaces.values where
            SnowSettings.shared.windowSnow && surface.isActive(at: currentTime) &&
            surface.isExposed(at: point.x) &&
            point.x >= surface.rect.minX && point.x <= surface.rect.maxX {
            let top = surface.rect.maxY + surface.height(at: point.x)
            let distance = abs(point.y - top)
            if point.y >= top - 15, point.y <= top + 52, distance < (nearest?.1 ?? .greatestFiniteMagnitude) {
                nearest = (.window(surface), distance)
            }
        }
        if SnowSettings.shared.dockSnow, dockRect.width > 0, point.x >= dockRect.minX, point.x <= dockRect.maxX {
            let top = dockRect.maxY + dockHeight(at: point.x)
            let distance = abs(point.y - top)
            if point.y >= top - 15, point.y <= top + 52, distance < (nearest?.1 ?? .greatestFiniteMagnitude) {
                nearest = (.dock, distance)
            }
        }
        return nearest?.0
    }

    private func carveSnow(at point: CGPoint, radius: CGFloat) {
        guard let source = rollingSurface(at: point) else { return }
        switch source {
        case .window(let surface):
            guard surface.rect.width > 0, !surface.pile.isEmpty else { return }
            let center = Int((point.x - surface.rect.minX) / surface.rect.width * CGFloat(surface.pile.count - 1))
            let bins = max(2, Int(radius / 7))
            for index in (center - bins)...(center + bins) where surface.pile.indices.contains(index) {
                surface.pile[index] = max(0, surface.pile[index] - 0.42)
            }
        case .dock:
            carveDockSnow(at: point.x, radius: radius)
        case .ground:
            break
        }
    }

    private func rebuildGroundPile() {
        groundPile = Array(repeating: 0, count: max(3, Int(bounds.width / 7) + 1))
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        currentTime = now
        let rawDelta = now - previousTime
        let dt = CGFloat(min(0.05, max(0.001, rawDelta)))
        previousTime = now
        if diagnosticsEnabled {
            diagnosticTicks += 1
            diagnosticDeltaTotal += rawDelta
            diagnosticMaxDelta = max(diagnosticMaxDelta, rawDelta)
        }
        refreshSurfaces(now: now)
        if fullscreenPaused {
            needsDisplay = true
            return
        }
        update(delta: dt, now: now)
        needsDisplay = true
    }

    private func refreshSurfaces(now: CFTimeInterval) {
        guard now - lastSurfaceScan >= 0.16 else { return }
        lastSurfaceScan = now
        let snapshots = WindowSnapshotProvider.shared.snapshots(now: now)
        let mainTop = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        func localRect(for snapshot: WindowSnapshot) -> CGRect {
            let quartz = snapshot.quartzRect
            return CGRect(
                x: quartz.minX,
                y: mainTop - quartz.maxY,
                width: quartz.width,
                height: quartz.height
            ).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        }
        let regularRectsByOwner = Dictionary(grouping: snapshots.filter {
            WindowOcclusion.isVisibleRegularWindow(alpha: $0.alpha, layer: $0.layer, owner: $0.owner)
        }, by: \.owner).mapValues { ownerSnapshots in
            ownerSnapshots.map(localRect)
        }
        var seen = Set<Int>()
        var dockCandidates: [CGRect] = []
        var frontWindowRects: [CGRect] = []
        var fullscreenWindowDetected = false
        for snapshot in snapshots where snapshot.alpha > 0.02 {
            let appRect = localRect(for: snapshot)

            if snapshot.owner == "Dock" {
                let clipped = appRect.intersection(bounds)
                if !clipped.isNull,
                   clipped.width > 24, clipped.height > 24,
                   ((clipped.width > 180 && clipped.height < 220 && clipped.minY < bounds.height * 0.28) ||
                    (clipped.height > 180 && clipped.width < 220 &&
                    (clipped.minX < 1 || clipped.maxX >= bounds.maxX - 1))) {
                    dockCandidates.append(clipped)
                }
                continue
            }

            guard WindowOcclusion.isVisibleRegularWindow(
                alpha: snapshot.alpha,
                layer: snapshot.layer,
                owner: snapshot.owner
            ) else { continue }
            let clipped = appRect.intersection(bounds)
            guard !clipped.isNull, clipped.width > 120, clipped.height > 55 else { continue }
            guard clipped.maxY > 36, clipped.minY < bounds.height - 20 else { continue }

            if snapshot.owner != "SnowVibe", WindowOcclusion.coversFullscreen(
                clipped,
                within: bounds,
                companionRects: regularRectsByOwner[snapshot.owner] ?? []
            ) {
                fullscreenWindowDetected = true
            }

            if snapshot.owner == "SnowVibe" {
                frontWindowRects.append(clipped)
                continue
            }
            let exposed = WindowOcclusion.exposedRanges(for: clipped, occludedBy: frontWindowRects)
            seen.insert(snapshot.id)

            if let surface = surfaces[snapshot.id] {
                surface.lastSeen = now
                surface.missingSince = nil
                let dx = clipped.minX - surface.rect.minX
                let dy = clipped.minY - surface.rect.minY
                let sizeChange = abs(clipped.width - surface.rect.width) + abs(clipped.height - surface.rect.height)
                if hypot(dx, dy) > 2.0 || sizeChange > 3.0 {
                    releaseSnow(from: surface, velocity: CGPoint(x: dx * 9, y: dy * 9))
                    surface.suspendedUntil = now + 0.62
                }
                surface.resize(to: clipped)
                surface.exposedRanges = exposed
            } else {
                let surface = SnowSurface(id: snapshot.id, rect: clipped, now: now)
                surface.exposedRanges = exposed
                surfaces[snapshot.id] = surface
            }
            frontWindowRects.append(clipped)
        }

        let disappeared = surfaces.keys.filter { !seen.contains($0) }
        for id in disappeared {
            guard let surface = surfaces[id] else { continue }
            if surface.missingSince == nil {
                surface.missingSince = now
                releaseSnow(from: surface, velocity: CGPoint(x: CGFloat.random(in: -28...28), y: -105))
            }
            guard now - (surface.missingSince ?? now) >= 0.95 else { continue }
            surfaces.removeValue(forKey: id)
        }

        if let detectedDock = dockCandidates.max(by: { $0.width < $1.width }) {
            updateDockRect(detectedDock)
        } else {
            dockRect = .zero
            dockPile.removeAll(keepingCapacity: true)
            plowX = nil
        }

        let shouldPause = SnowSettings.shared.pauseFullscreen && fullscreenWindowDetected
        if shouldPause != fullscreenPaused {
            fullscreenPaused = shouldPause
            if shouldPause {
                pendingPointerDown = nil
                pendingBallIndex = nil
                activeBallIndex = nil
                lastDragPoint = nil
                for index in balls.indices {
                    balls[index].active = false
                }
            }
            configureTimer(force: true)
        }
    }

    private func updateDockRect(_ newRect: CGRect) {
        guard newRect.width > 0 else { return }
        if dockRect.width > 0, hypot(newRect.minX - dockRect.minX, newRect.maxY - dockRect.maxY) > 8 {
            releaseDockSnow()
        }
        let old = dockPile
        dockRect = newRect
        let count = max(3, Int(newRect.width / 6) + 1)
        if count != old.count {
            dockPile = (0..<count).map { index in
                guard old.count > 1 else { return 0 }
                let source = min(old.count - 1, Int(CGFloat(index) / CGFloat(count - 1) * CGFloat(old.count - 1)))
                return old[source]
            }
        }
    }

    private func releaseSnow(from surface: SnowSurface, velocity: CGPoint) {
        guard surface.hasSnow else { return }
        let particleLimit = 110
        var budget = max(0, particleLimit - falling.count)
        let strideAmount = max(1, surface.pile.count / 22)
        for index in Swift.stride(from: 0, to: surface.pile.count, by: strideAmount) {
            guard budget > 0 else { break }
            let height = surface.pile[index]
            guard height > 0.35 else { continue }
            let x = surface.rect.minX + CGFloat(index) / CGFloat(max(1, surface.pile.count - 1)) * surface.rect.width
            let pieces = min(2, max(1, Int(height / 6)))
            for _ in 0..<pieces {
                guard budget > 0 else { break }
                falling.append(FallingClump(
                    x: x + CGFloat.random(in: -5...5),
                    y: surface.rect.maxY + CGFloat.random(in: 0...height),
                    vx: velocity.x + CGFloat.random(in: -30...30),
                    vy: velocity.y + CGFloat.random(in: -15...45),
                    size: CGFloat.random(in: 2.5...7.5),
                    rotation: CGFloat.random(in: 0...(2 * .pi)),
                    life: 8,
                    canSettle: true,
                    settleDelay: 0.42
                ))
                budget -= 1
            }
        }
        surface.clear()
    }

    private func releaseDockSnow() {
        guard dockPile.contains(where: { $0 > 0.4 }) else { return }
        for index in Swift.stride(from: 0, to: dockPile.count, by: 2) where dockPile[index] > 0.4 {
            let x = dockRect.minX + CGFloat(index) / CGFloat(max(1, dockPile.count - 1)) * dockRect.width
            falling.append(FallingClump(
                x: x,
                y: dockRect.maxY + dockPile[index],
                vx: CGFloat.random(in: -30...30),
                vy: CGFloat.random(in: -10...35),
                size: CGFloat.random(in: 3...7),
                rotation: CGFloat.random(in: 0...(2 * .pi)),
                life: 7,
                canSettle: true,
                settleDelay: 0.35
            ))
        }
        dockPile = Array(repeating: 0, count: dockPile.count)
    }

    private func targetFlakeCount() -> Int {
        let base = bounds.width * bounds.height / 9_600
        let boost: CGFloat = SnowSettings.shared.style == .blizzard ? 1.45 : 1
        let calculated = max(18, Int(base * CGFloat(SnowSettings.shared.intensity) * boost))
        let cap: Int
        switch SnowSettings.shared.style {
        case .crystal: cap = 56
        case .fluffy: cap = 60
        case .blizzard: cap = 76
        case .sparkle: cap = 64
        }
        return min(cap, calculated)
    }

    private func makeFlake(startAtTop: Bool = true) -> Snowflake {
        let style = SnowSettings.shared.style
        return Snowflake(
            x: CGFloat.random(in: -50...(bounds.width + 50)),
            y: startAtTop ? bounds.height + CGFloat.random(in: 0...150) : CGFloat.random(in: 0...bounds.height),
            vx: CGFloat.random(in: -10...10),
            vy: style.speed.random(),
            size: style.size.random(),
            phase: CGFloat.random(in: 0...(2 * .pi)),
            spin: CGFloat.random(in: -1.4...1.4),
            opacity: CGFloat.random(in: 0.56...0.98)
        )
    }

    private func update(delta dt: CGFloat, now: CFTimeInterval) {
        let settings = SnowSettings.shared
        guard settings.enabled else { return }

        updateFlakes(delta: dt)
        updateFallingSnow(delta: dt)
        updateSnowballs(delta: dt, now: now)
        updatePlow(delta: dt)

        if falling.count > 110 {
            falling.removeFirst(falling.count - 110)
        }

        smoothingClock += dt
        if smoothingClock >= 0.12 {
            smoothingClock = 0
            surfaces.values.forEach { $0.smooth() }
            smooth(&dockPile)
            smooth(&groundPile)
        }
    }

    private func updateFlakes(delta dt: CGFloat) {
        let settings = SnowSettings.shared
        let wanted = targetFlakeCount()
        if flakes.count < wanted {
            for _ in 0..<min(6, wanted - flakes.count) {
                flakes.append(makeFlake(startAtTop: flakes.count > wanted / 3))
            }
        } else if flakes.count > wanted {
            flakes.removeLast(min(5, flakes.count - wanted))
        }

        gustPhase += dt * 0.36
        let wind = CGFloat(settings.wind) * 86 + sin(gustPhase) * 11
        let mouse = localMouse()

        for index in flakes.indices.reversed() {
            let oldY = flakes[index].y
            flakes[index].phase += dt * (0.9 + abs(flakes[index].spin))
            var dx = flakes[index].vx + wind + sin(flakes[index].phase) * 13
            var dy = -flakes[index].vy

            if settings.cursorReaction {
                let mx = flakes[index].x - mouse.x
                let my = flakes[index].y - mouse.y
                let d2 = mx * mx + my * my
                if d2 < 10_500, d2 > 4 {
                    let distance = sqrt(d2)
                    let force = max(0, 102 - distance) * 4.1
                    dx += mx / distance * force
                    dy += my / distance * force
                }
            }

            flakes[index].x += dx * dt
            flakes[index].y += dy * dt
            if flakes[index].x > bounds.width + 65 { flakes[index].x = -55 }
            if flakes[index].x < -65 { flakes[index].x = bounds.width + 55 }

            if let collision = collision(at: flakes[index].x, from: oldY, to: flakes[index].y, radius: flakes[index].size * 0.45) {
                deposit(on: collision.0, x: flakes[index].x, amount: max(0.18, flakes[index].size * 0.05))
                flakes[index] = makeFlake()
            } else if flakes[index].y < -80 {
                flakes[index] = makeFlake()
            }
        }
    }

    private func updateFallingSnow(delta dt: CGFloat) {
        for index in falling.indices.reversed() {
            let oldY = falling[index].y
            falling[index].life -= dt
            falling[index].settleDelay = max(0, falling[index].settleDelay - dt)
            falling[index].vy -= 980 * dt
            falling[index].x += falling[index].vx * dt
            falling[index].y += falling[index].vy * dt
            falling[index].rotation += dt * 2.2
            falling[index].vx *= pow(0.985, dt * 30)

            if falling[index].canSettle, falling[index].settleDelay <= 0,
               let hit = collision(at: falling[index].x, from: oldY, to: falling[index].y, radius: falling[index].size * 0.5) {
                deposit(on: hit.0, x: falling[index].x, amount: falling[index].size * 0.18)
                falling.remove(at: index)
            } else if falling[index].life <= 0 || falling[index].y < -100 {
                falling.remove(at: index)
            }
        }
    }

    private func collision(at x: CGFloat, from oldY: CGFloat, to newY: CGFloat, radius: CGFloat) -> (CollisionTarget, CGFloat)? {
        var best: (CollisionTarget, CGFloat)?
        let settings = SnowSettings.shared

        if settings.windowSnow {
            for surface in surfaces.values where
                surface.isActive(at: currentTime) &&
                surface.isExposed(at: x) &&
                x >= surface.rect.minX && x <= surface.rect.maxX {
                let level = surface.rect.maxY + surface.height(at: x) + radius
                if oldY >= level, newY <= level, level > (best?.1 ?? -.greatestFiniteMagnitude) {
                    best = (.window(surface), level)
                }
            }
        }

        if settings.dockSnow, dockRect.width > 0, x >= dockRect.minX, x <= dockRect.maxX {
            let level = dockRect.maxY + dockHeight(at: x) + radius
            if oldY >= level, newY <= level, level > (best?.1 ?? -.greatestFiniteMagnitude) {
                best = (.dock, level)
            }
        }

        if settings.groundSnow {
            let ground = groundHeight(at: x) + radius
            if oldY >= ground, newY <= ground, ground > (best?.1 ?? -.greatestFiniteMagnitude) {
                best = (.ground, ground)
            }
        }
        return best
    }

    private func deposit(on target: CollisionTarget, x: CGFloat, amount: CGFloat) {
        switch target {
        case .window(let surface): surface.add(at: x, amount: amount)
        case .dock: add(to: &dockPile, range: dockRect, x: x, amount: amount, limit: 38)
        case .ground: add(to: &groundPile, range: bounds, x: x, amount: amount, limit: 88)
        }
    }

    private func add(to pile: inout [CGFloat], range: CGRect, x: CGFloat, amount: CGFloat, limit: CGFloat) {
        guard range.width > 0, !pile.isEmpty else { return }
        let center = min(pile.count - 1, max(0, Int((x - range.minX) / range.width * CGFloat(pile.count - 1))))
        for offset in -2...2 {
            let index = center + offset
            guard pile.indices.contains(index) else { continue }
            let weight: CGFloat = offset == 0 ? 1 : (abs(offset) == 1 ? 0.58 : 0.24)
            pile[index] = min(limit, pile[index] + amount * weight)
        }
    }

    private func smooth(_ pile: inout [CGFloat]) {
        guard pile.count > 2 else { return }
        var next = pile
        for index in 1..<(pile.count - 1) {
            let average = (pile[index - 1] + pile[index] * 2 + pile[index + 1]) / 4
            next[index] = pile[index] * 0.95 + average * 0.05
        }
        pile = next
    }

    private func height(in pile: [CGFloat], range: CGRect, at x: CGFloat) -> CGFloat {
        guard range.width > 0, pile.count > 1 else { return 0 }
        let p = min(CGFloat(pile.count - 1), max(0, (x - range.minX) / range.width * CGFloat(pile.count - 1)))
        let low = Int(p)
        let high = min(pile.count - 1, low + 1)
        let t = p - CGFloat(low)
        return pile[low] * (1 - t) + pile[high] * t
    }

    private func dockHeight(at x: CGFloat) -> CGFloat { height(in: dockPile, range: dockRect, at: x) }
    private func groundHeight(at x: CGFloat) -> CGFloat { height(in: groundPile, range: bounds, at: x) }

    private func localMouse() -> CGPoint {
        let global = NSEvent.mouseLocation
        let windowPoint = window?.convertPoint(fromScreen: global) ?? .zero
        return convert(windowPoint, from: nil)
    }

    private func updateSnowballs(delta dt: CGFloat, now: CFTimeInterval) {
        if !SnowSettings.shared.snowmanMode {
            activeBallIndex = nil
            pendingPointerDown = nil
            pendingBallIndex = nil
            lastDragPoint = nil
            for index in balls.indices { balls[index].active = false }
        }
        updateSettledBalls(delta: dt, now: now)
    }

    private func carveDockSnow(at x: CGFloat, radius: CGFloat) {
        guard dockRect.width > 0, !dockPile.isEmpty else { return }
        let center = Int((x - dockRect.minX) / dockRect.width * CGFloat(dockPile.count - 1))
        let bins = max(2, Int(radius / 6))
        for index in (center - bins)...(center + bins) where dockPile.indices.contains(index) {
            dockPile[index] = max(0, dockPile[index] - 0.35)
        }
    }

    private func updateSettledBalls(delta dt: CGFloat, now: CFTimeInterval) {
        for index in balls.indices where !balls[index].active {
            let floor = supportHeight(forBallAt: index)
            if balls[index].stable {
                if abs(balls[index].y - floor) <= 3 {
                    balls[index].y = floor
                    continue
                }
                balls[index].stable = false
                if snowmanComplete { snowmanComplete = false }
            }

            balls[index].vy -= 430 * dt
            balls[index].x += balls[index].vx * dt
            balls[index].y += balls[index].vy * dt
            balls[index].vx *= pow(0.965, dt * 30)

            if balls[index].y <= floor {
                balls[index].y = floor
                balls[index].vy = 0
                balls[index].vx *= 0.55
                balls[index].stable = abs(balls[index].vx) < 7
            }
        }
        tryCompleteSnowman(now: now)
    }

    private func supportHeight(forBallAt index: Int) -> CGFloat {
        guard balls.indices.contains(index) else { return 0 }
        let ball = balls[index]
        var floor = groundHeight(at: ball.x) + ball.radius
        if SnowSettings.shared.dockSnow, dockRect.width > 0, ball.x >= dockRect.minX, ball.x <= dockRect.maxX, dockRect.maxY < ball.y + 4 {
            floor = max(floor, dockRect.maxY + dockHeight(at: ball.x) + ball.radius)
        }
        for surface in surfaces.values where
            SnowSettings.shared.windowSnow && surface.isActive(at: currentTime) &&
            surface.isExposed(at: ball.x) &&
            ball.x >= surface.rect.minX && ball.x <= surface.rect.maxX &&
            surface.rect.maxY < ball.y + 4 {
            floor = max(floor, surface.rect.maxY + surface.height(at: ball.x) + ball.radius)
        }
        for other in balls.indices where other != index && balls[other].stable {
            let horizontal = abs(ball.x - balls[other].x)
            if horizontal < (ball.radius + balls[other].radius) * 0.72, balls[other].y < ball.y {
                let vertical = sqrt(max(0, pow(ball.radius + balls[other].radius - 2, 2) - horizontal * horizontal))
                floor = max(floor, balls[other].y + vertical)
            }
        }
        return floor
    }

    private func tryCompleteSnowman(now: CFTimeInterval) {
        guard !snowmanComplete, balls.count >= 3 else { return }
        let candidates = Array(balls.indices.prefix(3)).sorted { balls[$0].radius > balls[$1].radius }
        guard candidates.allSatisfy({ balls[$0].stable }) else { return }
        let xs = candidates.map { balls[$0].x }
        guard (xs.max() ?? 0) - (xs.min() ?? 0) < 100 else { return }

        let baseIndex = candidates[0]
        let middleIndex = candidates[1]
        let headIndex = candidates[2]
        let x = xs.reduce(0, +) / CGFloat(xs.count)
        var baseFloor = groundHeight(at: x)
        if SnowSettings.shared.dockSnow, dockRect.width > 0,
           x >= dockRect.minX, x <= dockRect.maxX,
           dockRect.maxY < balls[baseIndex].y + 8 {
            baseFloor = max(baseFloor, dockRect.maxY + dockHeight(at: x))
        }
        for surface in surfaces.values where
            SnowSettings.shared.windowSnow && surface.isActive(at: currentTime) &&
            surface.isExposed(at: x) &&
            x >= surface.rect.minX && x <= surface.rect.maxX &&
            surface.rect.maxY < balls[baseIndex].y + 8 {
            baseFloor = max(baseFloor, surface.rect.maxY + surface.height(at: x))
        }
        balls[baseIndex].x = x
        balls[baseIndex].y = baseFloor + balls[baseIndex].radius
        balls[middleIndex].x = x
        balls[middleIndex].y = balls[baseIndex].y + balls[baseIndex].radius + balls[middleIndex].radius - 4
        balls[headIndex].x = x
        balls[headIndex].y = balls[middleIndex].y + balls[middleIndex].radius + balls[headIndex].radius - 3
        snowmanComplete = true
        snowmanBorn = now
    }

    private func breakSnowman(at point: CGPoint) {
        guard snowmanComplete else { return }
        snowmanComplete = false
        activeBallIndex = nil
        for index in balls.indices {
            let direction: CGFloat = balls[index].x < point.x ? -1 : 1
            balls[index].active = false
            balls[index].stable = false
            balls[index].vx = direction * CGFloat.random(in: 55...125)
            balls[index].vy = CGFloat.random(in: 95...175)
        }
        for _ in 0..<24 {
            falling.append(FallingClump(
                x: point.x + CGFloat.random(in: -35...35),
                y: point.y + CGFloat.random(in: -30...45),
                vx: CGFloat.random(in: -120...120),
                vy: CGFloat.random(in: 30...160),
                size: CGFloat.random(in: 2.5...6.5),
                rotation: CGFloat.random(in: 0...(2 * .pi)),
                life: 3.5,
                canSettle: true,
                settleDelay: 0.30
            ))
        }
    }

    private func shatterBall(at index: Int) {
        guard balls.indices.contains(index) else { return }
        let ball = balls[index]
        for _ in 0..<14 {
            falling.append(FallingClump(
                x: ball.x + CGFloat.random(in: -ball.radius...ball.radius),
                y: ball.y + CGFloat.random(in: -ball.radius...ball.radius),
                vx: CGFloat.random(in: 55...180),
                vy: CGFloat.random(in: 35...155),
                size: CGFloat.random(in: 2.5...7),
                rotation: CGFloat.random(in: 0...(2 * .pi)),
                life: 1.7,
                canSettle: false,
                settleDelay: 0
            ))
        }
        balls.remove(at: index)
        activeBallIndex = nil
        pendingBallIndex = nil
        snowmanComplete = false
    }

    private func updatePlow(delta dt: CGFloat) {
        guard var x = plowX else { return }
        x += dt * 215
        plowX = x
        plowSprayClock += dt

        let bladeX = x + 59
        let hitBalls = balls.indices.filter {
            abs(balls[$0].x - bladeX) <= balls[$0].radius + 21 &&
            balls[$0].y <= dockRect.maxY + 190
        }.sorted(by: >)
        for index in hitBalls { shatterBall(at: index) }

        if dockRect.width > 0, !dockPile.isEmpty {
            let bladeStart = x + 45
            let bladeEnd = x + 72
            let start = max(0, Int((bladeStart - dockRect.minX) / dockRect.width * CGFloat(dockPile.count - 1)))
            let end = min(dockPile.count - 1, Int((bladeEnd - dockRect.minX) / dockRect.width * CGFloat(dockPile.count - 1)))
            if end >= start {
                for index in start...end {
                    let removed = min(dockPile[index], dt * 34)
                    dockPile[index] -= removed
                    plowLoad = min(54, plowLoad + removed * 0.20)
                }
            }
        }

        if plowLoad > 1, plowSprayClock > 0.055 {
            plowSprayClock = 0
            plowLoad *= 0.985
            for _ in 0..<2 {
                falling.append(FallingClump(
                    x: x + 69,
                    y: dockRect.maxY + 20 + CGFloat.random(in: 0...plowLoad),
                    vx: CGFloat.random(in: 65...130),
                    vy: CGFloat.random(in: 45...125),
                    size: CGFloat.random(in: 2.5...6.5),
                    rotation: CGFloat.random(in: 0...(2 * .pi)),
                    life: 1.8,
                    canSettle: false,
                    settleDelay: 0
                ))
            }
        }

        if x > dockRect.maxX + 120 {
            plowX = nil
            plowLoad = 0
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if diagnosticsEnabled {
            diagnosticDraws += 1
            reportDiagnosticsIfNeeded(now: CACurrentMediaTime())
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if fullscreenPaused {
            context.clear(bounds)
            return
        }
        drawPile(context, pile: groundPile, range: bounds, baseline: 0, maxHeight: 90)
        for surface in surfaces.values where surface.hasSnow && currentTime >= surface.suspendedUntil {
            drawPile(
                context,
                pile: surface.pile,
                range: surface.rect,
                baseline: surface.rect.maxY,
                maxHeight: 32,
                visibleRanges: surface.exposedRanges
            )
        }
        drawPile(context, pile: dockPile, range: dockRect, baseline: dockRect.maxY, maxHeight: 40)
        drawFlakes(context)
        drawFalling(context)
        drawSnowballs(context)
        if let x = plowX { drawPlow(context, x: x) }
    }

    private func reportDiagnosticsIfNeeded(now: CFTimeInterval) {
        let elapsed = now - diagnosticsStart
        guard elapsed >= 5 else { return }
        let averageDelta = diagnosticTicks > 0 ? diagnosticDeltaTotal / Double(diagnosticTicks) : 0
        let fields: [String: Any] = [
            "elapsed": elapsed,
            "targetFPS": configuredFrameRate,
            "tickFPS": Double(diagnosticTicks) / elapsed,
            "drawFPS": Double(diagnosticDraws) / elapsed,
            "averageDeltaMs": averageDelta * 1000,
            "maxDeltaMs": diagnosticMaxDelta * 1000,
            "flakes": flakes.count,
            "falling": falling.count,
            "surfaces": surfaces.count,
            "fullscreenPaused": fullscreenPaused,
            "screenWidth": bounds.width,
            "screenHeight": bounds.height
        ]
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            fputs("SNOWVIBE_METRICS \(json)\n", stderr)
            fflush(stderr)
        }
        diagnosticsStart = now
        diagnosticTicks = 0
        diagnosticDraws = 0
        diagnosticDeltaTotal = 0
        diagnosticMaxDelta = 0
    }

    private func drawPile(
        _ context: CGContext,
        pile: [CGFloat],
        range: CGRect,
        baseline: CGFloat,
        maxHeight: CGFloat,
        visibleRanges: [ClosedRange<CGFloat>]? = nil
    ) {
        guard pile.count > 1, pile.contains(where: { $0 > 0.2 }) else { return }
        if let visibleRanges, visibleRanges.isEmpty { return }

        let fillPath = CGMutablePath()
        let topPath = CGMutablePath()
        var runStart: Int?

        func xPosition(_ index: Int) -> CGFloat {
            range.minX + CGFloat(index) / CGFloat(pile.count - 1) * range.width
        }
        func renderedHeight(_ index: Int) -> CGFloat {
            let rawHeight = pile[index]
            let texture = sin(CGFloat(index) * 1.73) * min(1.6, rawHeight * 0.16)
            return min(maxHeight, max(3.2, rawHeight + texture))
        }
        func appendRun(from start: Int, through end: Int) {
            let left = xPosition(max(0, start - 1))
            let right = xPosition(min(pile.count - 1, end + 1))
            fillPath.move(to: CGPoint(x: left, y: baseline))
            topPath.move(to: CGPoint(x: xPosition(start), y: baseline + renderedHeight(start)))
            for index in start...end {
                let point = CGPoint(x: xPosition(index), y: baseline + renderedHeight(index))
                fillPath.addLine(to: point)
                if index != start { topPath.addLine(to: point) }
            }
            fillPath.addLine(to: CGPoint(x: right, y: baseline))
            fillPath.closeSubpath()
        }

        for index in 0...pile.count {
            let snowy = index < pile.count && pile[index] > 0.18
            if snowy, runStart == nil {
                runStart = index
            } else if !snowy, let start = runStart {
                appendRun(from: start, through: index - 1)
                runStart = nil
            }
        }

        context.saveGState()
        if let visibleRanges {
            let clipPath = CGMutablePath()
            for visible in visibleRanges {
                clipPath.addRect(CGRect(
                    x: visible.lowerBound,
                    y: baseline - 1,
                    width: max(0, visible.upperBound - visible.lowerBound),
                    height: maxHeight + 3
                ))
            }
            context.addPath(clipPath)
            context.clip()
        }

        context.saveGState()
        context.addPath(fillPath)
        context.clip()
        let colors = [
            NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.73, green: 0.88, blue: 0.98, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: range.midX, y: baseline + maxHeight),
                end: CGPoint(x: range.midX, y: baseline),
                options: []
            )
        }
        context.restoreGState()

        context.addPath(topPath)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.82).cgColor)
        context.setLineWidth(1.1)
        context.strokePath()
        context.restoreGState()
    }

    private func drawFlakes(_ context: CGContext) {
        for flake in flakes {
            switch SnowSettings.shared.style {
            case .crystal: drawCrystal(context, flake: flake)
            case .fluffy: drawFluffy(context, flake: flake)
            case .blizzard: drawBlizzardFlake(context, flake: flake)
            case .sparkle: drawSparkle(context, flake: flake)
            }
        }
    }

    private func drawCrystal(_ context: CGContext, flake: Snowflake) {
        context.saveGState()
        context.translateBy(x: flake.x, y: flake.y)
        context.rotate(by: flake.phase * flake.spin * 0.35)
        context.setStrokeColor(NSColor.white.withAlphaComponent(flake.opacity).cgColor)
        context.setLineWidth(max(0.65, flake.size * 0.10))
        context.setLineCap(.round)
        for arm in 0..<6 {
            context.saveGState()
            context.rotate(by: CGFloat(arm) * .pi / 3)
            context.move(to: .zero)
            context.addLine(to: CGPoint(x: 0, y: flake.size))
            let branchY = flake.size * 0.56
            let branch = flake.size * 0.28
            context.move(to: CGPoint(x: 0, y: branchY))
            context.addLine(to: CGPoint(x: -branch, y: branchY + branch))
            context.move(to: CGPoint(x: 0, y: branchY))
            context.addLine(to: CGPoint(x: branch, y: branchY + branch))
            context.strokePath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawFluffy(_ context: CGContext, flake: Snowflake) {
        context.saveGState()
        let lobes = 5
        for index in 0..<lobes {
            let angle = CGFloat(index) / CGFloat(lobes) * 2 * .pi + flake.phase * 0.15
            let radius = flake.size * 0.30
            let cx = flake.x + cos(angle) * flake.size * 0.28
            let cy = flake.y + sin(angle) * flake.size * 0.28
            context.setFillColor(NSColor.white.withAlphaComponent(flake.opacity * 0.68).cgColor)
            context.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }
        context.setFillColor(NSColor.white.withAlphaComponent(flake.opacity * 0.92).cgColor)
        context.fillEllipse(in: CGRect(x: flake.x - flake.size * 0.30, y: flake.y - flake.size * 0.30, width: flake.size * 0.60, height: flake.size * 0.60))
        context.restoreGState()
    }

    private func drawBlizzardFlake(_ context: CGContext, flake: Snowflake) {
        context.saveGState()
        context.translateBy(x: flake.x, y: flake.y)
        context.rotate(by: -.pi / 5)
        context.setFillColor(NSColor.white.withAlphaComponent(flake.opacity * 0.82).cgColor)
        context.fillEllipse(in: CGRect(x: -flake.size * 1.5, y: -flake.size * 0.34, width: flake.size * 3, height: flake.size * 0.68))
        context.restoreGState()
    }

    private func drawSparkle(_ context: CGContext, flake: Snowflake) {
        context.saveGState()
        context.translateBy(x: flake.x, y: flake.y)
        context.rotate(by: flake.phase * 0.4)
        context.setStrokeColor(NSColor(calibratedRed: 0.72, green: 0.92, blue: 1, alpha: flake.opacity).cgColor)
        context.setLineWidth(max(0.75, flake.size * 0.18))
        context.setLineCap(.round)
        for angle in stride(from: CGFloat(0), to: CGFloat.pi, by: CGFloat.pi / 4) {
            context.move(to: CGPoint(x: cos(angle) * -flake.size, y: sin(angle) * -flake.size))
            context.addLine(to: CGPoint(x: cos(angle) * flake.size, y: sin(angle) * flake.size))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawFalling(_ context: CGContext) {
        for clump in falling {
            context.saveGState()
            context.translateBy(x: clump.x, y: clump.y)
            context.rotate(by: clump.rotation)
            context.scaleBy(x: clump.size, y: clump.size)
            context.setFillColor(NSColor.white.withAlphaComponent(min(0.92, clump.life)).cgColor)
            context.addPath(Self.fallingClumpPath)
            context.fillPath()
            context.restoreGState()
        }
    }

    private func drawSnowballs(_ context: CGContext) {
        let now = CACurrentMediaTime()
        for (index, ball) in balls.enumerated() {
            let wobble: CGFloat = snowmanComplete ? sin(CGFloat(now - snowmanBorn) * 2.3 + CGFloat(index)) * 0.025 : 0
            context.saveGState()
            context.translateBy(x: ball.x, y: ball.y)
            context.rotate(by: ball.active ? ball.rotation : wobble)
            drawSnowBallBody(context, radius: ball.radius)
            context.restoreGState()
        }
        if snowmanComplete { drawSnowmanDetails(context, now: now) }
    }

    private func drawSnowBallBody(_ context: CGContext, radius: CGFloat) {
        let colors = [
            NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.99).cgColor,
            NSColor(calibratedRed: 0.72, green: 0.88, blue: 0.98, alpha: 0.96).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.saveGState()
            context.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: -radius * 0.34, y: radius * 0.38),
                startRadius: 1,
                endCenter: CGPoint(x: radius * 0.15, y: -radius * 0.18),
                endRadius: radius * 1.35,
                options: []
            )
            context.restoreGState()
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.82).cgColor)
        context.setLineWidth(1.2)
        context.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    }

    private func drawSnowmanDetails(_ context: CGContext, now: CFTimeInterval) {
        let sorted = Array(balls.indices.prefix(3)).sorted { balls[$0].radius > balls[$1].radius }
        guard sorted.count == 3 else { return }
        let base = balls[sorted[0]]
        let middle = balls[sorted[1]]
        let head = balls[sorted[2]]
        let bob = sin(CGFloat(now - snowmanBorn) * 2.6) * 1.8

        context.saveGState()
        context.setStrokeColor(NSColor(calibratedRed: 0.24, green: 0.13, blue: 0.08, alpha: 0.95).cgColor)
        context.setLineWidth(3.2)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: middle.x - middle.radius * 0.75, y: middle.y + 4))
        context.addLine(to: CGPoint(x: middle.x - middle.radius - 24, y: middle.y + 18 + bob))
        context.move(to: CGPoint(x: middle.x + middle.radius * 0.75, y: middle.y + 4))
        context.addLine(to: CGPoint(x: middle.x + middle.radius + 24, y: middle.y + 23 - bob))
        context.strokePath()

        context.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 0.95).cgColor)
        let eyeR = max(2.2, head.radius * 0.10)
        context.fillEllipse(in: CGRect(x: head.x - head.radius * 0.36 - eyeR, y: head.y + head.radius * 0.19, width: eyeR * 2, height: eyeR * 2))
        context.fillEllipse(in: CGRect(x: head.x + head.radius * 0.36 - eyeR, y: head.y + head.radius * 0.19, width: eyeR * 2, height: eyeR * 2))

        context.setStrokeColor(NSColor(calibratedWhite: 0.10, alpha: 0.95).cgColor)
        context.setLineWidth(2.4)
        context.addArc(center: CGPoint(x: head.x, y: head.y - head.radius * 0.02), radius: head.radius * 0.38, startAngle: .pi * 1.12, endAngle: .pi * 1.88, clockwise: false)
        context.strokePath()

        context.setFillColor(NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.07, alpha: 1).cgColor)
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: head.x - 2, y: head.y + head.radius * 0.04))
        nose.addLine(to: CGPoint(x: head.x + head.radius * 0.86, y: head.y - 1))
        nose.addLine(to: CGPoint(x: head.x - 2, y: head.y - head.radius * 0.10))
        nose.closeSubpath()
        context.addPath(nose)
        context.fillPath()

        context.setFillColor(NSColor(calibratedRed: 0.83, green: 0.12, blue: 0.18, alpha: 0.98).cgColor)
        let hatY = head.y + head.radius * 0.76 + bob
        context.fill(CGRect(x: head.x - head.radius * 0.70, y: hatY, width: head.radius * 1.4, height: head.radius * 0.25))
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: head.x - head.radius * 0.52, y: hatY + head.radius * 0.20))
        hat.addCurve(
            to: CGPoint(x: head.x + head.radius * 0.30, y: hatY + head.radius * 1.00),
            control1: CGPoint(x: head.x - head.radius * 0.50, y: hatY + head.radius * 0.78),
            control2: CGPoint(x: head.x - head.radius * 0.03, y: hatY + head.radius * 1.02)
        )
        hat.addLine(to: CGPoint(x: head.x + head.radius * 0.56, y: hatY + head.radius * 0.18))
        hat.closeSubpath()
        context.addPath(hat)
        context.fillPath()
        context.fillEllipse(in: CGRect(x: head.x + head.radius * 0.18, y: hatY + head.radius * 0.84, width: head.radius * 0.36, height: head.radius * 0.36))

        for y in [middle.y + 8, middle.y - 7, base.y + 9] {
            context.setFillColor(NSColor(calibratedWhite: 0.10, alpha: 0.9).cgColor)
            context.fillEllipse(in: CGRect(x: middle.x - 3, y: y - 3, width: 6, height: 6))
        }
        context.restoreGState()
    }

    private func drawPlow(_ context: CGContext, x: CGFloat) {
        let top = dockRect.maxY + dockHeight(at: x)
        let y = top + 11
        let wheelSpin = x / 11
        context.saveGState()
        context.translateBy(x: x, y: y)
        context.scaleBy(x: 0.68, y: 0.68)
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: NSColor.black.withAlphaComponent(0.32).cgColor)

        if plowLoad > 1 {
            context.setFillColor(NSColor(calibratedRed: 0.91, green: 0.97, blue: 1, alpha: 0.96).cgColor)
            let load = min(42, plowLoad)
            context.fillEllipse(in: CGRect(x: 76, y: -2, width: 34 + load, height: 17 + load * 0.30))
            context.fillEllipse(in: CGRect(x: 90, y: 5, width: 27 + load * 0.55, height: 14 + load * 0.22))
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.24).cgColor)
        context.fillEllipse(in: CGRect(x: -72, y: -7, width: 144, height: 15))
        context.setFillColor(NSColor(calibratedWhite: 0.10, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: -68, y: 7, width: 124, height: 14), cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.fillPath()

        let hopper = CGMutablePath()
        hopper.move(to: CGPoint(x: -64, y: 20))
        hopper.addLine(to: CGPoint(x: -12, y: 20))
        hopper.addLine(to: CGPoint(x: -7, y: 50))
        hopper.addLine(to: CGPoint(x: -57, y: 58))
        hopper.closeSubpath()
        context.setFillColor(NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.38, alpha: 1).cgColor)
        context.addPath(hopper)
        context.fillPath()
        context.setStrokeColor(NSColor(calibratedRed: 0.24, green: 0.49, blue: 0.62, alpha: 1).cgColor)
        context.setLineWidth(1.2)
        context.addPath(hopper)
        context.strokePath()
        context.setFillColor(NSColor(calibratedRed: 0.98, green: 0.53, blue: 0.05, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: -61, y: 53, width: 55, height: 7), cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()

        let cab = CGMutablePath()
        cab.move(to: CGPoint(x: -8, y: 18))
        cab.addLine(to: CGPoint(x: 51, y: 18))
        cab.addLine(to: CGPoint(x: 51, y: 39))
        cab.addLine(to: CGPoint(x: 37, y: 61))
        cab.addLine(to: CGPoint(x: 7, y: 61))
        cab.addLine(to: CGPoint(x: -8, y: 44))
        cab.closeSubpath()
        context.setFillColor(NSColor(calibratedRed: 0.98, green: 0.47, blue: 0.035, alpha: 1).cgColor)
        context.addPath(cab)
        context.fillPath()
        context.setStrokeColor(NSColor(calibratedRed: 0.67, green: 0.22, blue: 0.025, alpha: 0.9).cgColor)
        context.setLineWidth(1.4)
        context.addPath(cab)
        context.strokePath()

        let windowPath = CGMutablePath()
        windowPath.move(to: CGPoint(x: 8, y: 45))
        windowPath.addLine(to: CGPoint(x: 34, y: 45))
        windowPath.addLine(to: CGPoint(x: 28, y: 57))
        windowPath.addLine(to: CGPoint(x: 8, y: 57))
        windowPath.closeSubpath()
        context.setFillColor(NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.63, alpha: 0.98).cgColor)
        context.addPath(windowPath)
        context.fillPath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.addPath(windowPath)
        context.strokePath()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        context.move(to: CGPoint(x: 3, y: 20))
        context.addLine(to: CGPoint(x: 3, y: 60))
        context.strokePath()

        context.setFillColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
        context.fill(CGRect(x: 47, y: 17, width: 12, height: 7))
        context.setFillColor(NSColor(calibratedRed: 1, green: 0.92, blue: 0.48, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: 46, y: 31, width: 8, height: 7))
        context.setStrokeColor(NSColor(calibratedWhite: 0.22, alpha: 1).cgColor)
        context.setLineWidth(4)
        context.move(to: CGPoint(x: -13, y: 56))
        context.addLine(to: CGPoint(x: -13, y: 68))
        context.strokePath()
        let flashOn = Int(CACurrentMediaTime() * 5).isMultiple(of: 2)
        context.setFillColor((flashOn ? NSColor.systemYellow : NSColor.systemOrange).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 13, y: 63, width: 14, height: 9), cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()

        for wheelX in [-43 as CGFloat, 31] {
            context.saveGState()
            context.translateBy(x: wheelX, y: 9)
            context.rotate(by: wheelSpin)
            context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: -16, y: -16, width: 32, height: 32))
            context.setFillColor(NSColor(calibratedWhite: 0.48, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: -9, y: -9, width: 18, height: 18))
            context.setStrokeColor(NSColor(calibratedWhite: 0.18, alpha: 1).cgColor)
            context.setLineWidth(1.8)
            for angle in stride(from: CGFloat(0), to: 2 * .pi, by: .pi / 2) {
                context.move(to: .zero)
                context.addLine(to: CGPoint(x: cos(angle) * 8, y: sin(angle) * 8))
            }
            context.strokePath()
            context.setFillColor(NSColor(calibratedRed: 0.98, green: 0.48, blue: 0.04, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: -3, y: -3, width: 6, height: 6))
            context.restoreGState()
        }

        context.setStrokeColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
        context.setLineWidth(4)
        context.move(to: CGPoint(x: 48, y: 17))
        context.addLine(to: CGPoint(x: 73, y: 11))
        context.move(to: CGPoint(x: 48, y: 28))
        context.addLine(to: CGPoint(x: 72, y: 25))
        context.strokePath()

        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 68, y: -3))
        blade.addCurve(
            to: CGPoint(x: 104, y: 3),
            control1: CGPoint(x: 80, y: -5),
            control2: CGPoint(x: 96, y: -3)
        )
        blade.addLine(to: CGPoint(x: 96, y: 39))
        blade.addCurve(
            to: CGPoint(x: 70, y: 30),
            control1: CGPoint(x: 86, y: 38),
            control2: CGPoint(x: 76, y: 34)
        )
        blade.closeSubpath()
        context.setFillColor(NSColor(calibratedRed: 0.85, green: 0.13, blue: 0.09, alpha: 1).cgColor)
        context.addPath(blade)
        context.fillPath()
        context.setStrokeColor(NSColor(calibratedWhite: 0.82, alpha: 0.92).cgColor)
        context.setLineWidth(2)
        context.addPath(blade)
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.72).cgColor)
        context.setLineWidth(3)
        context.move(to: CGPoint(x: 73, y: 19))
        context.addLine(to: CGPoint(x: 99, y: 22))
        context.strokePath()
        context.restoreGState()
    }
}
