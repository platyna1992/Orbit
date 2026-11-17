import Darwin
import Foundation
import SwiftUI
import WidgetKit

private struct OrbitWidgetMetrics {
    let cpuPercent: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let memoryAvailable: UInt64
    let storageFree: UInt64
    let storageTotal: UInt64
    let thermalState: String
    let sampledAt: Date

    static func sample() -> OrbitWidgetMetrics {
        let cpu = CPUSampler().sample()
        let memory = memoryUsage()
        let storage = storageUsage()
        return OrbitWidgetMetrics(
            cpuPercent: cpu,
            memoryUsed: memory.used,
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            memoryAvailable: memory.available,
            storageFree: storage.free,
            storageTotal: storage.total,
            thermalState: thermalStateName(ProcessInfo.processInfo.thermalState),
            sampledAt: Date()
        )
    }

    private static func memoryUsage() -> (used: UInt64, available: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, 0) }
        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let availablePages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count) + UInt64(stats.purgeable_count)
        let available = min(total, availablePages * pageSize)
        return (total - available, available)
    }

    private static func storageUsage() -> (free: UInt64, total: UInt64) {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            return (
                UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0)),
                UInt64(max(0, values.volumeTotalCapacity ?? 0))
            )
        } catch { return (0, 0) }
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

private final class CPUSampler {
    private let previousTicksKey = "orbit.widget.previousCPUTicks"

    func sample() -> Double {
        guard let current = readTicks() else { return 0 }
        defer { save(current) }
        guard let previous = load(), previous.count == current.count else { return 0 }
        let deltas = zip(current, previous).map { $0 >= $1 ? $0 - $1 : 0 }
        let total = deltas.reduce(UInt64(0), +)
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) * 100))
    }

    private func readTicks() -> [UInt64]? {
        var processorInfo: processor_info_array_t?
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &infoCount) == KERN_SUCCESS,
              let processorInfo else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: processorInfo), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        var totals = Array(repeating: UInt64(0), count: stateCount)
        for processor in 0..<Int(processorCount) {
            for state in 0..<stateCount {
                totals[state] += UInt64(processorInfo[processor * stateCount + state])
            }
        }
        return totals
    }

    private func load() -> [UInt64]? {
        guard let data = UserDefaults.standard.data(forKey: previousTicksKey) else { return nil }
        return try? JSONDecoder().decode([UInt64].self, from: data)
    }

    private func save(_ ticks: [UInt64]) {
        guard let data = try? JSONEncoder().encode(ticks) else { return }
        UserDefaults.standard.set(data, forKey: previousTicksKey)
    }
}

private struct OrbitWidgetEntry: TimelineEntry {
    let date: Date
    let metrics: OrbitWidgetMetrics?
}

private struct OrbitWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> OrbitWidgetEntry {
        OrbitWidgetEntry(date: Date(), metrics: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OrbitWidgetEntry) -> Void) {
        completion(OrbitWidgetEntry(date: Date(), metrics: .sample()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OrbitWidgetEntry>) -> Void) {
        let metrics = OrbitWidgetMetrics.sample()
        let entry = OrbitWidgetEntry(date: metrics.sampledAt, metrics: metrics)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
    }
}

private struct OrbitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OrbitWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Color.cyan)
                Text("ORBIT").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2)
                Spacer()
                if let metrics = entry.metrics {
                    Text(metrics.thermalState.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(thermalColor(metrics.thermalState))
                }
            }

            if let metrics = entry.metrics {
                if family == .systemSmall {
                    smallMetrics(metrics)
                } else {
                    mediumMetrics(metrics)
                }
                Spacer(minLength: 0)
                Text("Updated \(metrics.sampledAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            } else {
                Spacer()
                Text("Waiting for system readings…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
        }
        .padding(14)
        .containerBackground(Color(red: 0.07, green: 0.11, blue: 0.19), for: .widget)
    }

    @ViewBuilder
    private func smallMetrics(_ metrics: OrbitWidgetMetrics) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CPU LOAD").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.48))
                Text("\(Int(metrics.cpuPercent.rounded()))%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
            }
            Divider().overlay(.white.opacity(0.14))
            HStack {
                compactMetric("MEMORY", "\(Int(memoryFraction(metrics) * 100))%")
                Spacer(minLength: 8)
                compactMetric("DISK FREE", formatBytes(metrics.storageFree))
            }
        }
    }

    @ViewBuilder
    private func mediumMetrics(_ metrics: OrbitWidgetMetrics) -> some View {
        HStack(alignment: .center, spacing: 0) {
            mediumMetric("CPU", "\(Int(metrics.cpuPercent.rounded()))%")
            Divider().overlay(.white.opacity(0.16)).padding(.horizontal, 12)
            mediumMetric("MEMORY", "\(Int(memoryFraction(metrics) * 100))%", detail: "\(formatBytes(metrics.memoryAvailable)) free")
            Divider().overlay(.white.opacity(0.16)).padding(.horizontal, 12)
            mediumMetric("DISK FREE", formatBytes(metrics.storageFree), detail: "of \(formatBytes(metrics.storageTotal))")
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func mediumMetric(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.48))
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(.system(size: 8)).foregroundStyle(.white.opacity(0.52)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memoryFraction(_ metrics: OrbitWidgetMetrics) -> Double {
        metrics.memoryTotal > 0 ? Double(metrics.memoryUsed) / Double(metrics.memoryTotal) : 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .memory)
    }

    private func thermalColor(_ state: String) -> Color {
        switch state {
        case "Nominal": return .green
        case "Fair": return .yellow
        case "Serious": return .orange
        case "Critical": return .red
        default: return .secondary
        }
    }
}

struct OrbitSystemWidget: Widget {
    let kind = "OrbitSystemWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OrbitWidgetProvider()) { entry in
            OrbitWidgetView(entry: entry)
        }
        .configurationDisplayName("Orbit Monitor")
        .description("CPU, memory, storage, and thermal state at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OrbitWidgetExtension: WidgetBundle {
    var body: some Widget {
        OrbitSystemWidget()
    }
}
