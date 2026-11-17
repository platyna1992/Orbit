import AppKit
import Darwin
import Foundation
import IOKit

@main
struct OrbitApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var widgetPanel: NSPanel?
    private var widgetButton: NSButton!
    private var widgetCPU: NSTextField!
    private var widgetMemory: NSTextField!
    private var widgetStorage: NSTextField!
    private var widgetThermal: NSTextField!
    private var timer: Timer?
    private var previousTicks: [UInt64]?
    private var cpuHistory = Array(repeating: 0.0, count: 48)
    private var memoryHistory = Array(repeating: 0.0, count: 48)
    private var cpuValue: NSTextField!
    private var memoryValue: NSTextField!
    private var memoryDetail: NSTextField!
    private var memoryAvailable: NSTextField!
    private var storageValue: NSTextField!
    private var storageDetail: NSTextField!
    private var storageBar: NSView!
    private var storageTrack: NSView!
    private var storageWidthConstraint: NSLayoutConstraint?
    private var thermalValue: NSTextField!
    private var thermalDetail: NSTextField!
    private var cpuChart: SparklineView!
    private var memoryChart: SparklineView!
    private var updatedValue: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if sender === widgetPanel { widgetButton.title = "Widget" }
        return false
    }

    private func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 760, height: 560)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Orbit"
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 700, height: 510)
        window.center()

        let material = NSVisualEffectView(frame: rect)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 16
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 1
        material.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        window.contentView = material

        let appTitle = label("ORBIT", size: 11, weight: .bold, color: white(0.76))
        let mark = OrbitMarkView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([mark.widthAnchor.constraint(equalToConstant: 24), mark.heightAnchor.constraint(equalToConstant: 24)])
        let brand = horizontal([mark, appTitle], spacing: 8)
        updatedValue = label("LIVE · UPDATING", size: 10, weight: .medium, color: white(0.45))
        widgetButton = NSButton(title: "Widget", target: self, action: #selector(toggleWidgetPanel(_:)))
        widgetButton.bezelStyle = .rounded
        widgetButton.controlSize = .small
        widgetButton.font = .systemFont(ofSize: 10, weight: .medium)
        let top = horizontal([brand, spacer(), widgetButton, updatedValue], spacing: 10)
        top.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 0, right: 24)

        let pageTitle = label("System overview", size: 25, weight: .semibold, color: .white)
        let subtitle = label("Live performance at a glance", size: 12, weight: .regular, color: white(0.56))
        let header = vertical([pageTitle, subtitle], spacing: 4)

        cpuChart = SparklineView(color: NSColor(calibratedRed: 0.26, green: 0.83, blue: 0.96, alpha: 1))
        cpuValue = label("0%", size: 36, weight: .semibold, color: .white)
        let cpuCard = makeCard(title: "PROCESSOR", subtitle: "Apple silicon · total load", icon: "cpu", tint: cpuChart.color)
        cpuCard.addArrangedSubview(cpuValue)
        cpuChart.heightAnchor.constraint(equalToConstant: 43).isActive = true
        cpuCard.addArrangedSubview(cpuChart)
        cpuCard.addArrangedSubview(label("USAGE HISTORY · LAST 72 SECONDS", size: 9, weight: .medium, color: white(0.43)))

        memoryChart = SparklineView(color: NSColor(calibratedRed: 0.70, green: 0.51, blue: 0.96, alpha: 1))
        memoryValue = label("0%", size: 36, weight: .semibold, color: .white)
        memoryDetail = label("0 B used", size: 10, weight: .medium, color: white(0.53))
        memoryAvailable = label("0 B", size: 10, weight: .semibold, color: NSColor.systemGreen)
        let memoryCard = makeCard(title: "MEMORY", subtitle: "Unified memory", icon: "memorychip", tint: memoryChart.color)
        memoryCard.addArrangedSubview(memoryValue)
        memoryCard.addArrangedSubview(memoryDetail)
        memoryChart.heightAnchor.constraint(equalToConstant: 31).isActive = true
        memoryCard.addArrangedSubview(memoryChart)
        memoryCard.addArrangedSubview(horizontal([label("AVAILABLE", size: 9, weight: .medium, color: white(0.43)), spacer(), memoryAvailable], spacing: 6))

        storageValue = label("0 B FREE", size: 27, weight: .semibold, color: .white)
        storageDetail = label("0 B used · 0 B total", size: 10, weight: .medium, color: white(0.53))
        storageBar = NSView()
        storageBar.wantsLayer = true
        storageBar.layer?.backgroundColor = NSColor.systemOrange.cgColor
        storageBar.layer?.cornerRadius = 3
        storageTrack = NSView()
        storageTrack.wantsLayer = true
        storageTrack.layer?.backgroundColor = white(0.12).cgColor
        storageTrack.layer?.cornerRadius = 3
        storageTrack.addSubview(storageBar)
        storageBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([storageBar.leadingAnchor.constraint(equalTo: storageTrack.leadingAnchor), storageBar.topAnchor.constraint(equalTo: storageTrack.topAnchor), storageBar.bottomAnchor.constraint(equalTo: storageTrack.bottomAnchor)])
        storageTrack.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let storageCard = makeCard(title: "STORAGE", subtitle: "Home volume · available space", icon: "internaldrive", tint: .systemOrange)
        storageCard.addArrangedSubview(storageValue)
        storageCard.addArrangedSubview(storageTrack)
        storageCard.addArrangedSubview(storageDetail)
        storageCard.addArrangedSubview(NSView())

        let thermalCard = makeCard(title: "THERMAL STATE", subtitle: "System-wide conditions", icon: "thermometer.medium", tint: .systemTeal)
        thermalValue = label("Nominal", size: 25, weight: .semibold, color: NSColor.systemGreen)
        thermalDetail = label("Within normal limits", size: 10, weight: .regular, color: white(0.56))
        thermalCard.addArrangedSubview(label("CURRENT STATUS", size: 9, weight: .bold, color: white(0.43)))
        thermalCard.addArrangedSubview(thermalValue)
        thermalCard.addArrangedSubview(thermalDetail)
        thermalCard.addArrangedSubview(label("Overall system heat status, not CPU/GPU temperatures.", size: 9, weight: .regular, color: white(0.48)))

        let grid = NSGridView(views: [[cpuCard, memoryCard], [storageCard, thermalCard]])
        grid.rowSpacing = 13
        grid.columnSpacing = 13
        for row in 0..<2 {
            for col in 0..<2 {
                grid.cell(atColumnIndex: col, rowIndex: row).xPlacement = .fill
                grid.cell(atColumnIndex: col, rowIndex: row).yPlacement = .fill
            }
        }

        let note = label("CPU and memory refresh every 1.5 seconds · storage reports available home-volume capacity", size: 10, weight: .regular, color: white(0.46))
        let content = vertical([top, header, grid, note], spacing: 20)
        content.edgeInsets = NSEdgeInsets(top: 51, left: 22, bottom: 20, right: 22)
        material.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: material.bottomAnchor)
        ])
        for card in [cpuCard, memoryCard, storageCard, thermalCard] {
            card.heightAnchor.constraint(equalToConstant: 174).isActive = true
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleWidgetPanel(_ sender: Any?) {
        if let widgetPanel, widgetPanel.isVisible {
            widgetPanel.orderOut(nil)
            widgetButton.title = "Widget"
            return
        }
        if widgetPanel == nil { buildWidgetPanel() }
        widgetPanel?.orderFrontRegardless()
        widgetButton.title = "Hide Widget"
    }

    private func buildWidgetPanel() {
        let size = NSSize(width: 292, height: 206)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Orbit Widget"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.minSize = size
        panel.maxSize = size
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 1
        material.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        panel.contentView = material

        let mark = OrbitMarkView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([mark.widthAnchor.constraint(equalToConstant: 20), mark.heightAnchor.constraint(equalToConstant: 20)])
        let brand = horizontal([mark, label("ORBIT · LIVE", size: 10, weight: .bold, color: white(0.72))], spacing: 7)
        let separator = NSBox()
        separator.boxType = .separator

        widgetCPU = label("—", size: 14, weight: .semibold, color: .white)
        widgetMemory = label("—", size: 14, weight: .semibold, color: .white)
        widgetStorage = label("—", size: 14, weight: .semibold, color: .white)
        widgetThermal = label("Nominal", size: 10, weight: .medium, color: .systemGreen)
        let rows = vertical([
            horizontal([label("CPU LOAD", size: 9, weight: .medium, color: white(0.48)), spacer(), widgetCPU], spacing: 8),
            horizontal([label("MEMORY", size: 9, weight: .medium, color: white(0.48)), spacer(), widgetMemory], spacing: 8),
            horizontal([label("STORAGE FREE", size: 9, weight: .medium, color: white(0.48)), spacer(), widgetStorage], spacing: 8),
            horizontal([label("THERMAL STATE", size: 9, weight: .medium, color: white(0.48)), spacer(), widgetThermal], spacing: 8)
        ], spacing: 11)
        let stack = vertical([brand, separator, rows], spacing: 13)
        material.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: material.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: material.bottomAnchor, constant: -14)
        ])
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        panel.setFrameOrigin(NSPoint(x: screenFrame.maxX - size.width - 24, y: screenFrame.maxY - size.height - 36))
        widgetPanel = panel
    }

    private func refresh() {
        let cpu = cpuUsage()
        let (used, total, available) = memoryUsage()
        let (diskUsed, diskTotal, diskFree) = storageUsage()
        cpuHistory.append(cpu)
        memoryHistory.append(total > 0 ? Double(used) / Double(total) * 100 : 0)
        if cpuHistory.count > 48 { cpuHistory.removeFirst(cpuHistory.count - 48) }
        if memoryHistory.count > 48 { memoryHistory.removeFirst(memoryHistory.count - 48) }
        cpuChart.values = cpuHistory
        memoryChart.values = memoryHistory
        cpuValue.stringValue = String(format: "%.0f%%", cpu)
        memoryValue.stringValue = String(format: "%.0f%%", total > 0 ? Double(used) / Double(total) * 100 : 0)
        memoryDetail.stringValue = "\(format(used)) used of \(format(total))"
        memoryAvailable.stringValue = format(available)
        storageValue.stringValue = "\(format(diskFree)) FREE"
        storageDetail.stringValue = "\(format(diskUsed)) used · \(format(diskTotal)) total"
        if diskTotal > 0 {
            let ratio = min(1, Double(diskUsed) / Double(diskTotal))
            storageWidthConstraint?.isActive = false
            storageWidthConstraint = storageBar.widthAnchor.constraint(equalTo: storageTrack.widthAnchor, multiplier: max(0.01, ratio))
            storageWidthConstraint?.isActive = true
        }
        updatedValue.stringValue = "LIVE · \(Date.now.formatted(date: .omitted, time: .shortened))"
        let (thermalName, thermalDescription, thermalColor) = thermalPresentation()
        thermalValue.stringValue = thermalName
        thermalValue.textColor = thermalColor
        thermalDetail.stringValue = thermalDescription
        if let widgetCPU, let widgetMemory, let widgetStorage, let widgetThermal {
            widgetCPU.stringValue = String(format: "%.0f%%", cpu)
            widgetMemory.stringValue = "\(format(used)) / \(format(total))"
            widgetStorage.stringValue = format(diskFree)
            widgetThermal.stringValue = thermalName
            widgetThermal.textColor = thermalColor
        }
    }

    private func thermalPresentation() -> (String, String, NSColor) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return ("Nominal", "Within normal limits", .systemGreen)
        case .fair: return ("Fair", "Slightly elevated", .systemYellow)
        case .serious: return ("Serious", "High · performance may be reduced", .systemOrange)
        case .critical: return ("Critical", "System needs to cool down", .systemRed)
        @unknown default: return ("Unknown", "Thermal status unavailable", .secondaryLabelColor)
        }
    }

    private func cpuUsage() -> Double {
        var info: processor_info_array_t?
        var processors: natural_t = 0
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processors, &info, &count) == KERN_SUCCESS, let info else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var ticks = Array(repeating: UInt64(0), count: Int(CPU_STATE_MAX))
        for processor in 0..<Int(processors) {
            for state in 0..<Int(CPU_STATE_MAX) { ticks[state] += UInt64(info[processor * Int(CPU_STATE_MAX) + state]) }
        }
        defer { previousTicks = ticks }
        guard let old = previousTicks else { return 0 }
        let changes = zip(ticks, old).map { $0 >= $1 ? $0 - $1 : 0 }
        let total = changes.reduce(UInt64(0), +)
        return total > 0 ? Double(total - changes[Int(CPU_STATE_IDLE)]) / Double(total) * 100 : 0
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64, available: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total, 0) }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        let availablePages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count) + UInt64(stats.purgeable_count)
        let available = min(total, availablePages * page)
        return (total - available, total, available)
    }

    private func storageUsage() -> (UInt64, UInt64, UInt64) {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            return (total > free ? total - free : 0, total, free)
        } catch { return (0, 0, 0) }
    }

    private func makeCard(title: String, subtitle: String, icon: String, tint: NSColor) -> NSStackView {
        let card = NSStackView()
        card.orientation = .vertical
        card.alignment = .leading
        card.distribution = .fill
        card.spacing = 8
        card.edgeInsets = NSEdgeInsets(top: 13, left: 14, bottom: 12, right: 14)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
        card.layer?.cornerRadius = 14
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        let symbol = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: title) ?? NSImage())
        symbol.contentTintColor = tint
        let heading = horizontal([symbol, vertical([label(title, size: 9, weight: .bold, color: white(0.84)), label(subtitle, size: 9, weight: .regular, color: white(0.46))], spacing: 3)], spacing: 8)
        heading.heightAnchor.constraint(equalToConstant: 28).isActive = true
        card.addArrangedSubview(heading)
        return card
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    private func spacer() -> NSView { NSView() }
    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = spacing
        return stack
    }
    private func horizontal(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = spacing
        return stack
    }
    private func white(_ alpha: CGFloat) -> NSColor { NSColor.white.withAlphaComponent(alpha) }
    private func format(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .memory) }
}

final class SparklineView: NSView {
    var color: NSColor
    var values: [Double] = [] { didSet { needsDisplay = true } }
    init(color: NSColor) { self.color = color; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1, let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds.insetBy(dx: 0, dy: 3)
        for mark in 1...3 {
            let y = bounds.minY + bounds.height * CGFloat(mark) / 4
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            context.setLineWidth(0.6)
            context.setLineDash(phase: 0, lengths: [3, 4])
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y))
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])
        let points = values.enumerated().map { idx, value in
            CGPoint(x: bounds.minX + bounds.width * CGFloat(idx) / CGFloat(values.count - 1), y: bounds.minY + bounds.height * CGFloat(min(100, max(0, value))) / 100)
        }
        let line = CGMutablePath()
        line.move(to: points[0])
        for point in points.dropFirst() { line.addLine(to: point) }
        let fill = CGMutablePath()
        fill.addPath(line)
        fill.addLine(to: CGPoint(x: points.last!.x, y: bounds.minY))
        fill.addLine(to: CGPoint(x: points[0].x, y: bounds.minY))
        fill.closeSubpath()
        context.addPath(fill)
        context.setFillColor(color.withAlphaComponent(0.16).cgColor)
        context.fillPath()
        context.addPath(line)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.7)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }
}

/// Three restrained, open orbital rings rendered with native vector paths.
final class OrbitMarkView: NSView {
    private let accent = NSColor(calibratedRed: 0.38, green: 0.82, blue: 0.96, alpha: 1)

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radii = [side * 0.21, side * 0.34, side * 0.47]
        let gapCenters: [CGFloat] = [25, 145, 265]
        for (index, radius) in radii.enumerated() {
            let halfGap: CGFloat = 8
            let start = gapCenters[index] + halfGap
            let end = gapCenters[index] + 360 - halfGap
            let path = NSBezierPath()
            path.lineWidth = max(0.9, side * 0.045)
            path.lineCapStyle = .round
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            accent.withAlphaComponent(0.68 + CGFloat(index) * 0.1).setStroke()
            path.stroke()
        }
        let dot = side * 0.12
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)).fill()
    }
}
