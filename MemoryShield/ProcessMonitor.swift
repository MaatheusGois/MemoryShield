//
//  ProcessMonitor.swift
//  Copyright © 2026 MaatheusGois. All rights reserved.
//

import Foundation
import AppKit
import Combine
import OSLog

private let logger = Logger(subsystem: "com.maatheusgois.MemoryShield", category: "monitor")

struct ProcessInfo: Identifiable {
    let id: pid_t
    let name: String
    let memoryMB: Double
    let memoryPercent: Double
    let uptime: TimeInterval?
    let icon: NSImage?
    let isUserApp: Bool
    let overThresholdSeconds: TimeInterval
}

struct MemorySample: Identifiable {
    let id = UUID()
    let date: Date
    let memoryMB: Double
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published var processes: [ProcessInfo] = []
    @Published var thresholdMB: Double {
        didSet { UserDefaults.standard.set(thresholdMB, forKey: "thresholdMB") }
    }
    @Published var autoKill: Bool {
        didSet { UserDefaults.standard.set(autoKill, forKey: "autoKill") }
    }
    @Published var sustainSeconds: Int {
        didSet { UserDefaults.standard.set(sustainSeconds, forKey: "sustainSeconds") }
    }
    @Published var killLog: [LogEntry] = []
    @Published var totalMemoryUsedGB: Double = 0
    @Published var history: [String: [MemorySample]] = [:]
    private let historyLimit = 180
    @Published var whitelist: Set<String> {
        didSet { UserDefaults.standard.set(Array(whitelist), forKey: "whitelist") }
    }

    private var timer: Timer?
    private var overThresholdSince: [pid_t: Date] = [:]
    private let totalRAMBytes: UInt64

    init() {
        let stored = UserDefaults.standard.double(forKey: "thresholdMB")
        self.thresholdMB = stored > 0 ? stored : 100 * 1024
        if UserDefaults.standard.object(forKey: "autoKill") == nil {
            self.autoKill = true
        } else {
            self.autoKill = UserDefaults.standard.bool(forKey: "autoKill")
        }
        let sustain = UserDefaults.standard.integer(forKey: "sustainSeconds")
        self.sustainSeconds = sustain > 0 ? sustain : 5
        self.whitelist = Set(UserDefaults.standard.stringArray(forKey: "whitelist") ?? [])
        self.totalRAMBytes = Foundation.ProcessInfo.processInfo.physicalMemory
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let snapshot = snapshotProcesses()
        self.processes = snapshot.sorted { $0.memoryMB > $1.memoryMB }
        self.totalMemoryUsedGB = snapshot.reduce(0) { $0 + $1.memoryMB } / 1024.0
        recordHistory(snapshot)

        if autoKill {
            for p in snapshot
            where p.memoryMB > thresholdMB
                && !whitelist.contains(p.name)
                && p.overThresholdSeconds >= Double(sustainSeconds) {
                kill(pid: p.id, name: p.name, reason: "auto: exceeded \(Int(thresholdMB)) MB for \(Int(p.overThresholdSeconds))s")
            }
        }
    }

    func kill(pid: pid_t, name: String, reason: String) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let ok = app.forceTerminate()
            log("\(ok ? "Killed" : "Failed to kill") \"\(name)\" (PID \(pid)) — \(reason)")
        } else {
            let r = Darwin.kill(pid, SIGKILL)
            log("\(r == 0 ? "Killed" : "Failed to kill") \"\(name)\" (PID \(pid)) via SIGKILL — \(reason)")
        }
    }

    func addToWhitelist(_ name: String) {
        whitelist.insert(name)
        log("Whitelisted \"\(name)\"")
    }

    func removeFromWhitelist(_ name: String) {
        whitelist.remove(name)
        log("Removed \"\(name)\" from whitelist")
    }

    func log(_ msg: String) {
        killLog.insert(LogEntry(date: Date(), message: msg), at: 0)
        if killLog.count > 500 { killLog.removeLast(killLog.count - 500) }
        logger.notice("\(msg, privacy: .public)")
    }

    private func snapshotProcesses() -> [ProcessInfo] {
        let rssByPID = Self.readRSSMap()
        let apps = NSWorkspace.shared.runningApplications
        let now = Date()
        var results: [ProcessInfo] = []
        let totalMB = Double(totalRAMBytes) / 1024.0 / 1024.0
        var currentlyOver: Set<pid_t> = []

        for app in apps {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            let rssKB = rssByPID[pid] ?? 0
            let memMB = Double(rssKB) / 1024.0
            let name = app.localizedName
                ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                ?? "PID \(pid)"
            let uptime = app.launchDate.map { now.timeIntervalSince($0) }
            let pct = totalMB > 0 ? (memMB / totalMB) * 100 : 0
            let over = trackOver(pid: pid, isOver: memMB > thresholdMB, now: now)
            if memMB > thresholdMB { currentlyOver.insert(pid) }
            results.append(ProcessInfo(
                id: pid, name: name, memoryMB: memMB,
                memoryPercent: pct, uptime: uptime,
                icon: app.icon, isUserApp: true,
                overThresholdSeconds: over
            ))
        }

        let appPIDs = Set(apps.map { $0.processIdentifier })
        let commByPID = Self.readCommMap()
        for (pid, rssKB) in rssByPID where !appPIDs.contains(pid) {
            let memMB = Double(rssKB) / 1024.0
            let name = commByPID[pid] ?? "pid \(pid)"
            let pct = totalMB > 0 ? (memMB / totalMB) * 100 : 0
            let over = trackOver(pid: pid, isOver: memMB > thresholdMB, now: now)
            if memMB > thresholdMB { currentlyOver.insert(pid) }
            results.append(ProcessInfo(
                id: pid, name: name, memoryMB: memMB,
                memoryPercent: pct, uptime: nil,
                icon: Self.iconForPID(pid), isUserApp: false,
                overThresholdSeconds: over
            ))
        }

        // Clean up trackers for processes no longer over threshold.
        overThresholdSince = overThresholdSince.filter { currentlyOver.contains($0.key) }
        return results
    }

    private func recordHistory(_ snapshot: [ProcessInfo]) {
        let now = Date()
        var seen = Set<String>()
        for p in snapshot where p.isUserApp {
            seen.insert(p.name)
            var arr = history[p.name] ?? []
            arr.append(MemorySample(date: now, memoryMB: p.memoryMB))
            if arr.count > historyLimit { arr.removeFirst(arr.count - historyLimit) }
            history[p.name] = arr
        }
        // Drop history for processes that have been gone for a while (keep last samples briefly).
        for key in history.keys where !seen.contains(key) {
            if let last = history[key]?.last?.date, now.timeIntervalSince(last) > 120 {
                history.removeValue(forKey: key)
            }
        }
    }

    private func trackOver(pid: pid_t, isOver: Bool, now: Date) -> TimeInterval {
        if isOver {
            if let since = overThresholdSince[pid] {
                return now.timeIntervalSince(since)
            } else {
                overThresholdSince[pid] = now
                return 0
            }
        } else {
            overThresholdSince[pid] = nil
            return 0
        }
    }

    private static func readRSSMap() -> [pid_t: Int] {
        var map: [pid_t: Int] = [:]
        guard let out = runPS(args: ["-axo", "pid=,rss="]) else { return map }
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, let pid = pid_t(parts[0]), let rss = Int(parts[1]) {
                map[pid] = rss
            }
        }
        return map
    }

    private static func readCommMap() -> [pid_t: String] {
        var map: [pid_t: String] = [:]
        guard let out = runPS(args: ["-axo", "pid=,comm="]) else { return map }
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2, let pid = pid_t(parts[0]) {
                map[pid] = (String(parts[1]) as NSString).lastPathComponent
            }
        }
        return map
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func iconForPID(_ pid: pid_t) -> NSImage? {
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return nil }
        let path = String(cString: buf)
        // Walk up to the enclosing .app bundle, if any.
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                let key = url.path
                if let cached = iconCache[key] { return cached }
                let icon = NSWorkspace.shared.icon(forFile: key)
                iconCache[key] = icon
                return icon
            }
            url.deleteLastPathComponent()
        }
        let key = path
        if let cached = iconCache[key] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconCache[key] = icon
        return icon
    }

    private static func runPS(args: [String]) -> String? {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch {
            logger.error("ps \(args.joined(separator: " "), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
