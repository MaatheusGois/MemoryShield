//
//  ContentView.swift
//  Copyright © 2026 MaatheusGois. All rights reserved.
//

import SwiftUI
import Charts

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case history = "Process History"
    case settings = "Settings"
    case logs = "Logs"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .overview: return "shield.lefthalf.filled"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .logs: return "doc.text"
        }
    }
}

struct ContentView: View {
    @StateObject private var monitor = ProcessMonitor()
    @State private var selection: SidebarSection = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch selection {
                case .overview: OverviewView(monitor: monitor)
                case .history:  HistoryView(monitor: monitor)
                case .settings: SettingsView(monitor: monitor)
                case .logs:     LogsView(monitor: monitor)
                }
            }
            .frame(minWidth: 760, minHeight: 520)
            .safeAreaInset(edge: .bottom) { statusBar }
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            Section("Active Profiles") {
                Text("[Default]")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text("MemoryShield Active")
            Text("•").foregroundStyle(.secondary)
            Text("\(monitor.processes.filter { $0.isUserApp }.count) Active Processes")
            Text("•").foregroundStyle(.secondary)
            Text(String(format: "%.1f GB used", monitor.totalMemoryUsedGB))
            Spacer()
            Text("Status: Stable").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var monitor: ProcessMonitor
    @State private var thresholdText: String = ""
    @State private var sustainText: String = ""
    @State private var search: String = ""
    @State private var confirmKill: ProcessInfo?

    var filtered: [ProcessInfo] {
        let base = monitor.processes.filter { $0.isUserApp }
        guard !search.isEmpty else { return base }
        let q = search.lowercased()
        return base.filter { $0.name.lowercased().contains(q) || "\($0.id)".contains(q) }
    }

    var body: some View {
        VStack(spacing: 12) {
            controlBar
            searchField
            processTable
            activityLog
        }
        .padding(16)
        .onAppear {
            thresholdText = String(format: "%.0f", monitor.thresholdMB)
            sustainText = "\(monitor.sustainSeconds)"
        }
        .confirmationDialog(
            "Force Quit \(confirmKill?.name ?? "")?",
            isPresented: Binding(get: { confirmKill != nil },
                                 set: { if !$0 { confirmKill = nil } }),
            presenting: confirmKill
        ) { p in
            Button("Force Quit", role: .destructive) {
                monitor.kill(pid: p.id, name: p.name, reason: "manual")
                confirmKill = nil
            }
            Button("Cancel", role: .cancel) { confirmKill = nil }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Text("Threshold (MB):")
            TextField("", text: $thresholdText)
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applyThreshold)
            Text(String(format: "%.1f GB", monitor.thresholdMB / 1024.0))
                .foregroundStyle(.secondary)
            Button("Apply", action: applyThreshold)

            Spacer().frame(width: 24)

            Toggle("", isOn: $monitor.autoKill)
                .toggleStyle(.switch)
                .labelsHidden()
            Text("Enable Auto-kill: If memory exceeds threshold for")
            TextField("", text: $sustainText)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .onSubmit(applySustain)
            Stepper("", value: $monitor.sustainSeconds, in: 1...3600)
                .labelsHidden()
                .onChange(of: monitor.sustainSeconds) { _, new in
                    sustainText = "\(new)"
                }
            Text("seconds")
        }
        .font(.callout)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search processes or filter by name, PID…", text: $search)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.tint, lineWidth: 1.2))
    }

    private var processTable: some View {
        Table(filtered) {
            TableColumn("Process") { p in
                HStack(spacing: 8) {
                    Circle()
                        .fill(p.memoryMB > monitor.thresholdMB ? .red : .green)
                        .frame(width: 8, height: 8)
                    if let icon = p.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.secondary)
                    }
                    Text(p.name).lineLimit(1)
                }
            }
            TableColumn("PID") { p in Text("\(p.id)") }.width(60)
            TableColumn("Memory") { p in
                Text(formatMemory(p.memoryMB))
                    .foregroundStyle(p.memoryMB > monitor.thresholdMB ? .red : .primary)
            }.width(110)
            TableColumn("") { p in
                HStack(spacing: 6) {
                    Button("Kill") { confirmKill = p }
                        .buttonStyle(.bordered).tint(.red)
                    if monitor.whitelist.contains(p.name) {
                        Button("Unwhitelist") { monitor.removeFromWhitelist(p.name) }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Whitelist") { monitor.addToWhitelist(p.name) }
                            .buttonStyle(.bordered)
                    }
                }
            }.width(180)
            TableColumn("Memory %") { p in
                Text(String(format: "%.1f%%", p.memoryPercent))
            }.width(80)
            TableColumn("Uptime") { p in
                Text(formatUptime(p.uptime)).foregroundStyle(.secondary)
            }.width(80)
        }
    }

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Activity & Actions Log").font(.headline)
                Spacer()
                Button("View Full Log") {
                    NotificationCenter.default.post(name: .showLogs, object: nil)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if monitor.killLog.isEmpty {
                        Text("No actions yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.killLog.prefix(5)) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("[\(timeString(entry.date))]")
                                    .foregroundStyle(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                Text(entry.message).font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
        }
        .padding(.top, 4)
    }

    private func applyThreshold() {
        if let v = Double(thresholdText.replacingOccurrences(of: ",", with: ".")), v > 0 {
            monitor.thresholdMB = v
            monitor.log("User applied new threshold: \(String(format: "%.1f", v / 1024.0)) GB")
        } else {
            thresholdText = String(format: "%.0f", monitor.thresholdMB)
        }
    }

    private func applySustain() {
        if let v = Int(sustainText), v > 0 { monitor.sustainSeconds = v }
        else { sustainText = "\(monitor.sustainSeconds)" }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.2f G", mb / 1024.0) }
        return String(format: "%.0f M", mb)
    }

    private func formatUptime(_ t: TimeInterval?) -> String {
        guard let t else { return "—" }
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}

// MARK: - Logs

struct LogsView: View {
    @ObservedObject var monitor: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity Log").font(.title2).bold()
                Spacer()
                Button("Clear") { monitor.killLog.removeAll() }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if monitor.killLog.isEmpty {
                        Text("No actions yet.").foregroundStyle(.secondary).padding()
                    } else {
                        ForEach(monitor.killLog) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Text(entry.message).font(.caption)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var monitor: ProcessMonitor

    var body: some View {
        Form {
            Section("Whitelist") {
                if monitor.whitelist.isEmpty {
                    Text("No whitelisted processes.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(monitor.whitelist).sorted(), id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Remove") { monitor.removeFromWhitelist(name) }
                        }
                    }
                }
            }
            Section("Defaults") {
                LabeledContent("Threshold", value: String(format: "%.1f GB", monitor.thresholdMB / 1024.0))
                LabeledContent("Sustain", value: "\(monitor.sustainSeconds)s")
                LabeledContent("Auto-kill", value: monitor.autoKill ? "On" : "Off")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HistoryView: View {
    @ObservedObject var monitor: ProcessMonitor
    @State private var selected: String?

    private var names: [String] {
        monitor.history.keys.sorted {
            (monitor.history[$0]?.last?.memoryMB ?? 0) > (monitor.history[$1]?.last?.memoryMB ?? 0)
        }
    }

    private func icon(for name: String) -> NSImage? {
        monitor.processes.first { $0.name == name }?.icon
    }

    var body: some View {
        HSplitView {
            List(names, id: \.self, selection: $selected) { name in
                HStack(spacing: 8) {
                    if let img = icon(for: name) {
                        Image(nsImage: img).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "app.dashed").frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                    }
                    Text(name).lineLimit(1)
                    Spacer()
                    if let last = monitor.history[name]?.last {
                        Text(String(format: "%.0f MB", last.memoryMB))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(name)
            }
            .frame(minWidth: 240)

            Group {
                if let name = selected ?? names.first,
                   let samples = monitor.history[name], !samples.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if let img = icon(for: name) {
                                Image(nsImage: img).resizable().frame(width: 28, height: 28)
                            }
                            Text(name).font(.title2).bold()
                            Spacer()
                            Text(String(format: "Current: %.1f MB", samples.last?.memoryMB ?? 0))
                                .foregroundStyle(.secondary)
                        }
                        Chart(samples) { s in
                            LineMark(x: .value("Time", s.date),
                                     y: .value("Memory (MB)", s.memoryMB))
                            AreaMark(x: .value("Time", s.date),
                                     y: .value("Memory (MB)", s.memoryMB))
                                .opacity(0.15)
                        }
                        .chartYAxisLabel("MB")
                    }
                    .padding()
                } else {
                    Text("Collecting history…").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.title2).bold()
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let showLogs = Notification.Name("memoryshield.showLogs")
}

#Preview { ContentView() }
