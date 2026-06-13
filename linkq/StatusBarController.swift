//
//  StatusBarController.swift
//  linkq
//
//  Created by Renat Notfullin on 19.05.2023.
//

import AppKit
import AppUpdater
import SwiftyPing
import ServiceManagement
import Network
import Security
import CryptoKit
import SwiftUI
import Combine

struct Constants {
    static let githubUrl = "https://github.com/Renset/linkq"
    static let supportAuthorUrl = "https://buymeacoffee.com/renset1"
    static let pingingHost = "1.1.1.1"
    static let loginItemIdentifier = "com.notfullin.linkqHelper"
    static let wiFiTurboEnabledKey = "wiFiTurboEnabled"
    static let privilegedHelperDigestKey = "privilegedHelperDigest"
    static let startAtLoginKey = "startAtLoginState"
    static let historyKey = "qualityHistory"
    static let settingsGraphWindowKey = "settingsGraphWindow"
    static let lastNotifiedReleaseKey = "lastNotifiedRelease"
    static let updateNotificationKind = "linkq.update.available"
    static let wiFiTurboWarningAcceptedKey = "wiFiTurboWarningAccepted"
    static let probeModeKey = "probeMode"
    static let targetHostKey = "targetHost"
    static let tcpPortKey = "tcpPort"
    static let interval: TimeInterval = 1
    static let pingOffline = 1.5
    static let pingPoor = 0.35
    static let pingVerySlow = 1.2
    static let goodJitterRatio = 0.10
    static let goodJitterMax: TimeInterval = 0.05
    static let averageJitterRatio = 0.25
    static let averageJitterMax: TimeInterval = 0.15
    static let menuHistoryWindow: TimeInterval = 5 * 60
    static let historyRetentionWindow: TimeInterval = 24 * 60 * 60
    static let historySaveInterval: TimeInterval = 60
    static let historyPruneInterval: TimeInterval = 60
    static let settingsGraphRefreshInterval: TimeInterval = 5
    static let historyGraphMaxVisiblePoints = 180
    static let maxMissedPings = 3
    static let menuWidth: CGFloat = 300
    static let menuLeadingPadding: CGFloat = 18
    static let menuTrailingPadding: CGFloat = 18
}

struct JitterThresholds {
    let good: TimeInterval
    let average: TimeInterval

    init(averageLatency: TimeInterval) {
        good = min(averageLatency * Constants.goodJitterRatio, Constants.goodJitterMax)
        average = min(averageLatency * Constants.averageJitterRatio, Constants.averageJitterMax)
    }
}

enum ProbeMode: String, CaseIterable, Identifiable, Codable {
    case icmp = "ICMP"
    case tcp = "TCP"

    var id: String {
        rawValue
    }
}

enum HistoryGraphWindow: String, CaseIterable, Identifiable, Codable {
    case tenMinutes
    case oneHour
    case oneDay

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tenMinutes:
            return "10 min"
        case .oneHour:
            return "1 hour"
        case .oneDay:
            return "24 hours"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .tenMinutes:
            return 10 * 60
        case .oneHour:
            return 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        }
    }
}

enum ConnectionQuality: String, Codable {
    case good
    case average
    case poor
    case offline
    case unknown

    var menuTitle: String {
        switch self {
        case .good:
            return "Good connection"
        case .average:
            return "Average connection"
        case .poor:
            return "Poor connection"
        case .offline:
            return "Offline"
        case .unknown:
            return "Unknown connection status"
        }
    }

    var assetName: String {
        switch self {
        case .good:
            return "GoodConnection"
        case .average:
            return "AverageConnection"
        case .poor:
            return "PoorConnection"
        case .offline:
            return "OfflineConnection"
        case .unknown:
            return "UnknownConnection"
        }
    }

    var score: Double {
        switch self {
        case .good:
            return 1.0
        case .average:
            return 0.66
        case .poor:
            return 0.33
        case .offline:
            return 0.04
        case .unknown:
            return 0.18
        }
    }

    var severity: Int {
        switch self {
        case .good:
            return 0
        case .average:
            return 1
        case .poor:
            return 2
        case .offline:
            return 3
        case .unknown:
            return 4
        }
    }

    /// Stable codes for the binary history file; never renumber existing cases.
    var storageCode: UInt8 {
        switch self {
        case .good:
            return 0
        case .average:
            return 1
        case .poor:
            return 2
        case .offline:
            return 3
        case .unknown:
            return 4
        }
    }

    init?(storageCode: UInt8) {
        switch storageCode {
        case 0:
            self = .good
        case 1:
            self = .average
        case 2:
            self = .poor
        case 3:
            self = .offline
        case 4:
            self = .unknown
        default:
            return nil
        }
    }

    var tint: Color {
        switch self {
        case .good:
            return .green
        case .average:
            return .yellow
        case .poor:
            return .orange
        case .offline:
            return .red
        case .unknown:
            return .secondary
        }
    }

    var menuPillForeground: Color {
        switch self {
        case .average:
            return .black.opacity(0.82)
        case .unknown:
            return .primary
        default:
            return .white
        }
    }

    var menuPillBackground: Color {
        switch self {
        case .unknown:
            return .secondary.opacity(0.18)
        default:
            return tint
        }
    }
}

struct QualitySample: Codable {
    let date: Date
    let quality: ConnectionQuality
    let latency: TimeInterval?
}

final class AppState: ObservableObject {
    @Published var quality: ConnectionQuality = .unknown
    /// Invariant: sorted ascending by date. `loadHistory` sorts on load and `record`
    /// appends with the current time; `pruneHistory(before:)` and
    /// `QualityHistoryGraph.visibleLatencySamples(now:)` rely on this order.
    /// A backward system-clock jump can break it until the affected samples age out.
    @Published var history: [QualitySample] = []
    @Published var isWiFiTurboEnabled = UserDefaults.standard.bool(forKey: Constants.wiFiTurboEnabledKey)
    @Published var isWiFiTurboChanging = false
    @Published var wiFiTurboError: String?
    @Published var isStartAtLoginEnabled = AppState.currentStartAtLoginEnabled()
    @Published var startAtLoginError: String?
    @Published var lastLatency: TimeInterval?
    @Published var probeMode: ProbeMode = .icmp
    @Published var targetHost: String = Constants.pingingHost
    @Published var tcpPort: Int = 443
    @Published var settingsGraphWindow: HistoryGraphWindow = .tenMinutes

    private var lastHistorySaveDate = Date.distantPast
    private var lastHistoryPruneDate = Date.distantPast
    private let historySaveQueue = DispatchQueue(label: "com.notfullin.linkq.history-save", qos: .utility)

    init() {
        let defaults = UserDefaults.standard
        probeMode = ProbeMode(rawValue: defaults.string(forKey: Constants.probeModeKey) ?? ProbeMode.icmp.rawValue) ?? .icmp
        targetHost = defaults.string(forKey: Constants.targetHostKey) ?? Constants.pingingHost
        settingsGraphWindow = HistoryGraphWindow(rawValue: defaults.string(forKey: Constants.settingsGraphWindowKey) ?? HistoryGraphWindow.tenMinutes.rawValue) ?? .tenMinutes

        let savedPort = defaults.integer(forKey: Constants.tcpPortKey)
        tcpPort = savedPort > 0 ? savedPort : 443
        history = Self.loadHistory()
        lastLatency = history.last(where: { $0.latency != nil })?.latency
        quality = history.last?.quality ?? .unknown

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveHistory(async: false)
        }
    }

    func record(quality: ConnectionQuality, latency: TimeInterval?) {
        let now = Date()
        self.quality = quality
        lastLatency = latency
        history.append(QualitySample(date: now, quality: quality, latency: latency))

        if now.timeIntervalSince(lastHistoryPruneDate) >= Constants.historyPruneInterval {
            pruneHistory(before: now.addingTimeInterval(-Constants.historyRetentionWindow))
            lastHistoryPruneDate = now
        }

        if now.timeIntervalSince(lastHistorySaveDate) >= Constants.historySaveInterval {
            saveHistory()
        }
    }

    private func saveHistory(async: Bool = true) {
        lastHistorySaveDate = Date()
        let historySnapshot = history
        let work = {
            guard let fileURL = Self.historyFileURL else {
                return
            }

            let data = Self.encodeHistory(historySnapshot)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? data.write(to: fileURL, options: .atomic)) != nil else {
                return
            }

            // Drop the legacy UserDefaults copy once the binary write succeeds:
            // the JSON history exceeded the 4 MB CFPreferences value limit.
            UserDefaults.standard.removeObject(forKey: Constants.historyKey)
        }

        if async {
            historySaveQueue.async(execute: work)
        } else {
            historySaveQueue.sync(execute: work)
        }
    }

    private func pruneHistory(before cutoff: Date) {
        guard let firstRetainedIndex = history.firstIndex(where: { $0.date >= cutoff }) else {
            history.removeAll(keepingCapacity: true)
            return
        }

        if firstRetainedIndex > history.startIndex {
            history.removeSubrange(history.startIndex..<firstRetainedIndex)
        }
    }

    private static var historyFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("linkq", isDirectory: true)
            .appendingPathComponent("qualityHistory.bin")
    }

    private static func loadHistory() -> [QualitySample] {
        guard let samples = loadStoredHistory() else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-Constants.historyRetentionWindow)
        return samples
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    private static func loadStoredHistory() -> [QualitySample]? {
        if let fileURL = historyFileURL,
           let data = try? Data(contentsOf: fileURL),
           let samples = decodeHistory(data) {
            return samples
        }

        // Migration: history used to live in UserDefaults as JSON until it
        // outgrew the 4 MB CFPreferences value limit. The key is removed
        // after the first successful binary save.
        guard let legacyData = UserDefaults.standard.data(forKey: Constants.historyKey) else {
            return nil
        }

        return try? JSONDecoder().decode([QualitySample].self, from: legacyData)
    }

    // Binary history layout: a 4-byte magic ("LQH1"), then 13-byte records of
    // date (Float64 bit pattern, seconds since reference date), latency
    // (Float32 bit pattern, NaN encodes nil) and a quality code, little-endian.
    private static let historyFileMagic = Data("LQH1".utf8)
    private static let historyRecordSize = 13

    private static func encodeHistory(_ samples: [QualitySample]) -> Data {
        var data = Data(capacity: historyFileMagic.count + samples.count * historyRecordSize)
        data.append(historyFileMagic)

        for sample in samples {
            appendLittleEndianBits(sample.date.timeIntervalSinceReferenceDate.bitPattern, to: &data)
            appendLittleEndianBits(Float(sample.latency ?? .nan).bitPattern, to: &data)
            data.append(sample.quality.storageCode)
        }

        return data
    }

    private static func appendLittleEndianBits<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func decodeHistory(_ data: Data) -> [QualitySample]? {
        guard data.starts(with: historyFileMagic) else {
            return nil
        }

        let bytes = [UInt8](data.dropFirst(historyFileMagic.count))
        guard bytes.count % historyRecordSize == 0 else {
            return nil
        }

        var samples: [QualitySample] = []
        samples.reserveCapacity(bytes.count / historyRecordSize)

        var offset = 0
        while offset < bytes.count {
            var dateBits: UInt64 = 0
            for byteIndex in 0..<8 {
                dateBits |= UInt64(bytes[offset + byteIndex]) << (8 * byteIndex)
            }

            var latencyBits: UInt32 = 0
            for byteIndex in 0..<4 {
                latencyBits |= UInt32(bytes[offset + 8 + byteIndex]) << (8 * byteIndex)
            }

            let qualityCode = bytes[offset + 12]
            offset += historyRecordSize

            guard let quality = ConnectionQuality(storageCode: qualityCode) else {
                continue
            }

            let latency = Float(bitPattern: latencyBits)
            samples.append(QualitySample(
                date: Date(timeIntervalSinceReferenceDate: Double(bitPattern: dateBits)),
                quality: quality,
                latency: latency.isNaN ? nil : TimeInterval(latency)
            ))
        }

        return samples
    }

    static func currentStartAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.loginItem(identifier: Constants.loginItemIdentifier).status == .enabled
        }

        return UserDefaults.standard.integer(forKey: Constants.startAtLoginKey) == NSControl.StateValue.on.rawValue
    }
}

final class StatusBarController: NSObject, NSMenuDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var rttBuffer: [TimeInterval] = []
    let rttBufferSize = 20
    var pinger: SwiftyPing?

    private let appState: AppState
    private var updater: AppUpdater?
    private let monitor = NWPathMonitor()
    // SwiftyPing's initializer and start/stop block on internal queues without
    // a QoS; calling them from the main thread triggers priority-inversion
    // warnings, so every SwiftyPing call goes through this queue instead.
    private let pingerQueue = DispatchQueue(label: "com.notfullin.linkq.pinger", qos: .userInitiated)
    private var isStartingICMPProbe = false
    private var isPathSatisfied = false
    private var missedPingCheckTimer: Timer?
    private var lastPingDate: Date?
    private var missedPingCount = 0
    private var tcpProbeTimer: Timer?
    private var tcpProbeInFlight = false
    private var tcpConnection: NWConnection?
    private var historyMenuItem: NSMenuItem?
    private var wiFiTurboMenuItem: NSMenuItem?
    private var startAtLoginMenuItem: NSMenuItem?
    private var newVersionMenuItem: NSMenuItem?
    private var availableUpdate: Update?
    private var isCheckingForUpdates = false
    private var isInstallingUpdate = false
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var privilegedHelperConnection: NSXPCConnection?
    private var wiFiTurboOperationID: UUID?
    private var statusIconCache: [String: NSImage] = [:]
    private var currentStatusIconKey: String?
    private var appearanceObservation: NSKeyValueObservation?

    init(state: AppState) {
        appState = state
        super.init()
        NSUserNotificationCenter.default.delegate = self

        Task { @MainActor in
            self.updater = AppUpdater(owner: "Renset", repo: "linkq")
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.refreshWiFiTurboStateFromSystem()
            self.setupMenu()
            self.updateStatusBarIcon(quality: self.appState.quality)
            self.checkForUpdates()

            // The Wi-Fi turbo badge is composited with lockFocus, which bakes the
            // current appearance into the cached image, so the cache must be
            // dropped when the system switches between light and dark mode.
            self.appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.statusIconCache.removeAll()
                    self.currentStatusIconKey = nil
                    self.updateStatusBarIcon(quality: self.appState.quality)
                }
            }
        }

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handlePathUpdate(path)
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        stopPing()
    }

    private func handlePathUpdate(_ path: NWPath) {
        isPathSatisfied = path.status == .satisfied

        if isPathSatisfied {
            startPing()
        } else {
            stopPing()
            rttBuffer.removeAll()
            missedPingCount = 0
            lastPingDate = nil
            recordStatus(.offline, latency: nil)
        }
    }

    func startPing() {
        switch appState.probeMode {
        case .icmp:
            startICMPProbe()
        case .tcp:
            startTCPProbe()
        }
    }

    private func startICMPProbe() {
        guard pinger == nil, !isStartingICMPProbe, tcpProbeTimer == nil else {
            return
        }

        isStartingICMPProbe = true
        let host = appState.targetHost
        let pingerQueue = self.pingerQueue

        pingerQueue.async { [weak self] in
            let pinger = try? SwiftyPing(host: host, configuration: PingConfiguration(interval: Constants.interval, with: 5), queue: DispatchQueue.global(qos: .utility))
            pinger?.observer = { [weak self] response in
                DispatchQueue.main.async {
                    self?.handlePingResponse(latency: response.duration)
                }
            }
            try? pinger?.startPinging()

            DispatchQueue.main.async {
                guard let self else {
                    pingerQueue.async {
                        pinger?.stopPinging()
                    }
                    return
                }

                self.isStartingICMPProbe = false

                let stillWanted = self.isPathSatisfied
                    && self.appState.probeMode == .icmp
                    && self.appState.targetHost == host
                    && self.pinger == nil
                    && self.tcpProbeTimer == nil
                if stillWanted {
                    self.pinger = pinger
                } else {
                    if let pinger {
                        pingerQueue.async {
                            pinger.stopPinging()
                        }
                    }
                    // Probing was stopped or reconfigured while this pinger was
                    // starting; restart with the current configuration.
                    if self.isPathSatisfied, self.pinger == nil, self.tcpProbeTimer == nil {
                        self.startPing()
                    }
                }
            }
        }
        startMissedPingTimer()
    }

    private func startTCPProbe() {
        guard tcpProbeTimer == nil, pinger == nil else {
            return
        }

        runTCPProbe()
        tcpProbeTimer = Timer.scheduledTimer(withTimeInterval: Constants.interval, repeats: true) { [weak self] _ in
            self?.runTCPProbe()
        }
        startMissedPingTimer()
    }

    func stopPing() {
        if let pinger {
            pingerQueue.async {
                pinger.stopPinging()
            }
        }
        pinger = nil
        missedPingCheckTimer?.invalidate()
        missedPingCheckTimer = nil
        tcpProbeTimer?.invalidate()
        tcpProbeTimer = nil
        tcpConnection?.cancel()
        tcpConnection = nil
        tcpProbeInFlight = false
    }

    private func startMissedPingTimer() {
        missedPingCheckTimer?.invalidate()
        missedPingCheckTimer = Timer.scheduledTimer(withTimeInterval: Constants.interval, repeats: true) { [weak self] _ in
            self?.checkForMissedPing()
        }
    }

    private func handlePingResponse(latency: TimeInterval) {
        guard isPathSatisfied else {
            return
        }

        lastPingDate = Date()
        missedPingCount = 0
        rttBuffer.append(latency)
        if rttBuffer.count > rttBufferSize {
            rttBuffer.removeFirst()
        }

        recordStatus(quality(for: latency), latency: latency)
    }

    private func runTCPProbe() {
        guard isPathSatisfied, !tcpProbeInFlight else {
            return
        }

        tcpProbeInFlight = true
        let startedAt = Date()
        let host = NWEndpoint.Host(appState.targetHost)
        let port = NWEndpoint.Port(rawValue: UInt16(appState.tcpPort)) ?? .https
        let connection = NWConnection(host: host, port: port, using: .tcp)
        tcpConnection = connection

        let timeout = DispatchWorkItem { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self, self.tcpProbeInFlight, self.tcpConnection === connection else {
                    return
                }

                self.tcpConnection = nil
                self.tcpProbeInFlight = false
                connection?.cancel()
                self.recordProbeMiss()
            }
        }

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                let latency = Date().timeIntervalSince(startedAt)
                DispatchQueue.main.async {
                    guard let self, self.tcpConnection === connection else {
                        return
                    }

                    timeout.cancel()
                    self.tcpConnection = nil
                    self.tcpProbeInFlight = false
                    connection?.cancel()
                    self.handlePingResponse(latency: latency)
                }
            case .failed:
                DispatchQueue.main.async {
                    guard let self, self.tcpConnection === connection else {
                        return
                    }

                    timeout.cancel()
                    self.tcpConnection = nil
                    self.tcpProbeInFlight = false
                    connection?.cancel()
                    self.recordProbeMiss()
                }
            case .cancelled:
                DispatchQueue.main.async {
                    guard let self, self.tcpConnection === connection else {
                        return
                    }

                    timeout.cancel()
                    self.tcpConnection = nil
                    self.tcpProbeInFlight = false
                }
            default:
                break
            }
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Constants.pingOffline, execute: timeout)
        connection.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func checkForMissedPing() {
        guard isPathSatisfied else {
            return
        }

        guard let lastPingDate else {
            recordProbeMiss()
            return
        }

        let elapsed = Date().timeIntervalSince(lastPingDate)
        if elapsed > Constants.interval * Double(Constants.maxMissedPings) {
            recordProbeMiss()
        }
    }

    private func recordProbeMiss() {
        missedPingCount += 1
        if missedPingCount >= Constants.maxMissedPings {
            rttBuffer.removeAll()
            recordStatus(.offline, latency: nil)
        }
    }

    private func quality(for latency: TimeInterval) -> ConnectionQuality {
        if latency > Constants.pingOffline {
            return .offline
        }

        if latency > Constants.pingVerySlow {
            return .poor
        }

        guard let jitter = standardDeviation(), let averageLatency = averageLatency(), rttBuffer.count >= 3 else {
            return latency > Constants.pingPoor ? .average : .good
        }

        let thresholds = JitterThresholds(averageLatency: averageLatency)
        if jitter <= thresholds.good {
            return .good
        } else if jitter <= thresholds.average {
            return .average
        } else {
            return .poor
        }
    }

    func standardDeviation() -> TimeInterval? {
        guard !rttBuffer.isEmpty else {
            return nil
        }
        let sum = rttBuffer.reduce(0, +)
        let mean = sum / TimeInterval(rttBuffer.count)
        let squaredDifferenceSum = rttBuffer.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        return sqrt(squaredDifferenceSum / TimeInterval(rttBuffer.count))
    }

    func averageLatency() -> TimeInterval? {
        rttBuffer.average
    }

    private func recordStatus(_ quality: ConnectionQuality, latency: TimeInterval?) {
        appState.record(quality: quality, latency: latency)
        updateStatusBarIcon(quality: quality)
    }

    func updateStatusBarIcon(quality: ConnectionQuality) {
        DispatchQueue.main.async {
            let iconKey = "\(quality.assetName)-\(self.appState.isWiFiTurboEnabled)"
            guard self.currentStatusIconKey != iconKey else {
                return
            }

            let image: NSImage?
            if let cachedImage = self.statusIconCache[iconKey] {
                image = cachedImage
            } else {
                let baseImage = NSImage(named: quality.assetName)
                image = self.appState.isWiFiTurboEnabled ? self.imageWithWiFiTurboBadge(baseImage: baseImage) : baseImage
                if let image {
                    image.isTemplate = false
                    self.statusIconCache[iconKey] = image
                }
            }

            // A failed image load must not mark the key as current: that would
            // suppress retries on every following tick and leave the icon blank.
            guard let image else {
                return
            }

            self.currentStatusIconKey = iconKey
            self.statusItem.button?.image = image
        }
    }

    private func imageWithWiFiTurboBadge(baseImage: NSImage?) -> NSImage? {
        guard let baseImage else {
            return nil
        }

        let size = baseImage.size == .zero ? NSSize(width: 18, height: 18) : baseImage.size
        let output = NSImage(size: size)
        output.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)

        let badgeDiameter = max(8, min(size.width, size.height) * 0.48)
        let badgeRect = NSRect(
            x: size.width - badgeDiameter,
            y: 0,
            width: badgeDiameter,
            height: badgeDiameter
        )
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
            let inset = badgeDiameter * 0.18
            let boltRect = badgeRect.insetBy(dx: inset, dy: inset)
            bolt.withSymbolConfiguration(.init(pointSize: badgeDiameter * 0.62, weight: .bold))?
                .draw(in: boltRect, from: .zero, operation: .sourceOver, fraction: 1)
        }

        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let historyItem = NSMenuItem()
        historyMenuItem = historyItem
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        let turboItem = NSMenuItem(title: "Tweak macOS Wi-Fi", action: #selector(toggleWiFiTurboFromMenu), keyEquivalent: "")
        turboItem.target = self
        turboItem.toolTip = "Disables AWDL/LLW for more stable low ping in games, important video calls and other latency-sensitive sessions. AirDrop, AirPlay discovery and similar nearby services will not work while enabled."
        wiFiTurboMenuItem = turboItem
        updateWiFiTurboMenuItem()
        menu.addItem(turboItem)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        startAtLoginMenuItem = loginItem
        updateStartAtLoginMenuItem()
        menu.addItem(loginItem)

        let settingsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let newVersionItem = NSMenuItem(title: "Install update...", action: #selector(installLatestRelease), keyEquivalent: "")
        newVersionItem.target = self
        newVersionItem.isHidden = true
        newVersionMenuItem = newVersionItem
        menu.addItem(newVersionItem)
        
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        installMenuHistoryView()
        appState.isStartAtLoginEnabled = AppState.currentStartAtLoginEnabled()
        refreshWiFiTurboStateFromSystem()
        updateStartAtLoginMenuItem()
        updateWiFiTurboMenuItem()
    }

    func menuDidClose(_ menu: NSMenu) {
        historyMenuItem?.view = nil
    }

    private func installMenuHistoryView() {
        guard historyMenuItem?.view == nil else {
            return
        }

        let historyView = NSHostingView(rootView: MenuHistoryView(model: appState))
        historyView.setFrameSize(NSSize(width: Constants.menuWidth, height: 104))
        historyMenuItem?.view = historyView
    }

    @objc func toggleStartAtLogin() {
        setStartAtLoginEnabled(!appState.isStartAtLoginEnabled)
    }

    func setStartAtLoginEnabled(_ enabled: Bool) {
        appState.startAtLoginError = nil

        do {
            if #available(macOS 13.0, *) {
                let service = SMAppService.loginItem(identifier: Constants.loginItemIdentifier)
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } else {
                let success = SMLoginItemSetEnabled(Constants.loginItemIdentifier as CFString, enabled)
                guard success else {
                    throw StartAtLoginError()
                }
            }
        } catch {
            appState.startAtLoginError = error.localizedDescription
            updateStartAtLoginMenuItem()
            return
        }

        appState.isStartAtLoginEnabled = AppState.currentStartAtLoginEnabled()
        UserDefaults.standard.set((appState.isStartAtLoginEnabled ? NSControl.StateValue.on : .off).rawValue, forKey: Constants.startAtLoginKey)
        updateStartAtLoginMenuItem()
    }

    private func updateStartAtLoginMenuItem() {
        startAtLoginMenuItem?.state = appState.isStartAtLoginEnabled ? .on : .off
    }

    func setProbeMode(_ mode: ProbeMode) {
        guard appState.probeMode != mode else {
            return
        }

        appState.probeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Constants.probeModeKey)
        restartProbingIfNeeded()
    }

    func setTargetHost(_ host: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, appState.targetHost != trimmedHost else {
            return
        }

        appState.targetHost = trimmedHost
        UserDefaults.standard.set(trimmedHost, forKey: Constants.targetHostKey)
        restartProbingIfNeeded()
    }

    func setTCPPort(_ port: Int) {
        let boundedPort = min(max(port, 1), 65535)
        guard appState.tcpPort != boundedPort else {
            return
        }

        appState.tcpPort = boundedPort
        UserDefaults.standard.set(boundedPort, forKey: Constants.tcpPortKey)
        restartProbingIfNeeded()
    }

    func setSettingsGraphWindow(_ window: HistoryGraphWindow) {
        guard appState.settingsGraphWindow != window else {
            return
        }

        UserDefaults.standard.set(window.rawValue, forKey: Constants.settingsGraphWindowKey)

        // The segmented picker invokes its binding's setter inside the SwiftUI
        // view-update pass; publishing there triggers "Publishing changes from
        // within view updates", so the mutation is deferred to the next cycle.
        DispatchQueue.main.async {
            self.appState.settingsGraphWindow = window
        }
    }

    private func restartProbingIfNeeded() {
        guard isPathSatisfied else {
            return
        }

        stopPing()
        rttBuffer.removeAll()
        missedPingCount = 0
        lastPingDate = nil
        startPing()
    }

    @objc func toggleWiFiTurboFromMenu() {
        setWiFiTurboEnabled(!appState.isWiFiTurboEnabled)
    }

    func setWiFiTurboEnabled(_ enabled: Bool) {
        guard !appState.isWiFiTurboChanging else {
            return
        }

        guard !enabled || shouldEnableWiFiTurboAfterWarning() else {
            return
        }

        let operationID = UUID()
        wiFiTurboOperationID = operationID
        appState.isWiFiTurboChanging = true
        appState.wiFiTurboError = nil
        updateWiFiTurboMenuItem()

        if enabled && (!Self.isPrivilegedHelperRegistered || Self.isPrivilegedHelperUpdateAvailable) {
            installPrivilegedHelperThenSet(enabled, operationID: operationID)
        } else if Self.isPrivilegedHelperRegistered {
            setWiFiTurboWithPrivilegedHelper(enabled, operationID: operationID, shouldRetryInstall: enabled)
        } else {
            finishWiFiTurboChange(
                .failure(WiFiTurboError(message: "Privileged helper is not installed. Enable Tweak macOS Wi-Fi once to install it.")),
                operationID: operationID
            )
        }
    }

    private func updateWiFiTurboMenuItem() {
        wiFiTurboMenuItem?.state = appState.isWiFiTurboEnabled ? .on : .off
        wiFiTurboMenuItem?.isEnabled = !appState.isWiFiTurboChanging
        wiFiTurboMenuItem?.title = appState.isWiFiTurboChanging ? "Tweak macOS Wi-Fi..." : "Tweak macOS Wi-Fi"
    }

    private func shouldEnableWiFiTurboAfterWarning() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Constants.wiFiTurboWarningAcceptedKey) else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Tweak macOS Wi-Fi disables nearby Apple services"
        alert.informativeText = "This can make ping more stable for games, important video calls and other latency-sensitive sessions by disabling AWDL and LLW. While it is enabled, AirDrop, AirPlay discovery, Apple Watch unlock and similar nearby services may stop working. Turn Tweak macOS Wi-Fi off when you want those features back."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        defaults.set(true, forKey: Constants.wiFiTurboWarningAcceptedKey)
        return true
    }

    private func refreshWiFiTurboStateFromSystem() {
        guard let isEnabled = Self.currentWiFiTurboState() else {
            return
        }

        appState.isWiFiTurboEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Constants.wiFiTurboEnabledKey)
        updateStatusBarIcon(quality: appState.quality)
    }

    private func checkForUpdates() {
        guard !isCheckingForUpdates, let updater else {
            return
        }

        isCheckingForUpdates = true
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let update = try await updater.check()
                await MainActor.run {
                    self.isCheckingForUpdates = false
                    guard let update else {
                        self.availableUpdate = nil
                        self.newVersionMenuItem?.isHidden = true
                        return
                    }

                    self.availableUpdate = update
                    let version = self.versionLabel(for: update)
                    self.newVersionMenuItem?.title = "Install linkq \(version)..."
                    self.newVersionMenuItem?.isHidden = false
                    self.notifyAboutNewVersionIfNeeded(update)
                }
            } catch {
                await MainActor.run {
                    self.isCheckingForUpdates = false
                }
                NSLog("linkq update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func versionLabel(for update: Update) -> String {
        let assetName = update.assetName
        let basename = (assetName as NSString).deletingPathExtension
        let prefix = "linkq-"

        guard basename.hasPrefix(prefix) else {
            return assetName
        }

        let version = String(basename.dropFirst(prefix.count))
        if version.hasSuffix(".tar") {
            return String(version.dropLast(".tar".count))
        }

        return version
    }

    private func notifyAboutNewVersionIfNeeded(_ update: Update) {
        let version = versionLabel(for: update)
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Constants.lastNotifiedReleaseKey) != update.assetName else {
            return
        }

        let notification = NSUserNotification()
        notification.title = "linkq update available"
        notification.informativeText = "Version \(version) is ready to install."
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.userInfo = ["kind": Constants.updateNotificationKind]
        NSUserNotificationCenter.default.deliver(notification)
        defaults.set(update.assetName, forKey: Constants.lastNotifiedReleaseKey)
    }

    private func installPrivilegedHelperThenSet(_ enabled: Bool, operationID: UUID) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.blessPrivilegedHelper()
            DispatchQueue.main.async {
                guard self.wiFiTurboOperationID == operationID else {
                    return
                }

                switch result {
                case .success:
                    self.setWiFiTurboWithPrivilegedHelper(enabled, operationID: operationID, shouldRetryInstall: false)
                case .failure(let error):
                    self.finishWiFiTurboChange(.failure(error), operationID: operationID)
                }
            }
        }
    }

    private func setWiFiTurboWithPrivilegedHelper(_ enabled: Bool, operationID: UUID, shouldRetryInstall: Bool) {
        privilegedHelperConnection?.invalidate()

        let connection = NSXPCConnection(
            machServiceName: PrivilegedHelperConstants.label,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LinkQPrivilegedHelperProtocol.self)
        privilegedHelperConnection = connection

        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard self?.privilegedHelperConnection === connection else {
                    return
                }
                self?.privilegedHelperConnection = nil
            }
        }
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.handlePrivilegedHelperConnectionFailure(
                    error,
                    enabled: enabled,
                    operationID: operationID,
                    shouldRetryInstall: shouldRetryInstall
                )
            }
        } as? LinkQPrivilegedHelperProtocol

        guard let proxy else {
            handlePrivilegedHelperConnectionFailure(
                WiFiTurboError(message: "Could not connect to privileged helper."),
                enabled: enabled,
                operationID: operationID,
                shouldRetryInstall: shouldRetryInstall
            )
            return
        }

        proxy.setWiFiTurboEnabled(enabled) { [weak self] success, message in
            DispatchQueue.main.async {
                if success {
                    self?.finishWiFiTurboChange(.success(enabled), operationID: operationID)
                } else {
                    self?.finishWiFiTurboChange(.failure(WiFiTurboError(message: message ?? "Could not change Wi-Fi turbo mode.")), operationID: operationID)
                }
            }
        }
    }

    private func handlePrivilegedHelperConnectionFailure(_ error: Error, enabled: Bool, operationID: UUID, shouldRetryInstall: Bool) {
        guard wiFiTurboOperationID == operationID else {
            return
        }

        privilegedHelperConnection?.invalidate()
        privilegedHelperConnection = nil

        if shouldRetryInstall {
            installPrivilegedHelperThenSet(enabled, operationID: operationID)
        } else {
            finishWiFiTurboChange(.failure(error), operationID: operationID)
        }
    }

    private func finishWiFiTurboChange(_ result: Result<Bool, Error>, operationID: UUID) {
        guard wiFiTurboOperationID == operationID else {
            return
        }

        wiFiTurboOperationID = nil
        privilegedHelperConnection?.invalidate()
        privilegedHelperConnection = nil
        appState.isWiFiTurboChanging = false

        switch result {
        case .success(let enabled):
            appState.isWiFiTurboEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: Constants.wiFiTurboEnabledKey)
            updateStatusBarIcon(quality: appState.quality)
        case .failure(let error):
            appState.wiFiTurboError = error.localizedDescription
            refreshWiFiTurboStateFromSystem()
        }

        updateWiFiTurboMenuItem()
    }

    private static var bundledPrivilegedHelperURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchServices")
            .appendingPathComponent(PrivilegedHelperConstants.label)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var isPrivilegedHelperRegistered: Bool {
        guard let job = SMJobCopyDictionary(kSMDomainSystemLaunchd, PrivilegedHelperConstants.label as CFString) else {
            return false
        }

        _ = job.takeRetainedValue()
        return true
    }

    private static var bundledPrivilegedHelperDigest: String? {
        guard let bundledPrivilegedHelperURL else {
            return nil
        }

        return fileDigest(at: bundledPrivilegedHelperURL)
    }

    private static var isPrivilegedHelperUpdateAvailable: Bool {
        guard let bundledDigest = bundledPrivilegedHelperDigest else {
            return false
        }

        return UserDefaults.standard.string(forKey: Constants.privilegedHelperDigestKey) != bundledDigest
    }

    private static func blessPrivilegedHelper() -> Result<Void, Error> {
        var authorizationRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authorizationRef)
        guard status == errAuthorizationSuccess, let authorizationRef else {
            return .failure(PrivilegedHelperInstallError(status: status, message: "Could not create authorization."))
        }
        defer {
            AuthorizationFree(authorizationRef, [])
        }

        status = kSMRightBlessPrivilegedHelper.withCString { rightName in
            var item = AuthorizationItem(
                name: rightName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
                return AuthorizationCopyRights(authorizationRef, &rights, nil, flags, nil)
            }
        }
        guard status == errAuthorizationSuccess else {
            return .failure(PrivilegedHelperInstallError(status: status, message: "Authorization was not granted."))
        }

        removeExistingPrivilegedHelperIfNeeded(authorizationRef)

        var unmanagedError: Unmanaged<CFError>?
        guard SMJobBless(kSMDomainSystemLaunchd, PrivilegedHelperConstants.label as CFString, authorizationRef, &unmanagedError) else {
            let error = unmanagedError?.takeRetainedValue()
            return .failure(PrivilegedHelperInstallError(
                status: errAuthorizationInternal,
                message: "Could not install privileged helper.",
                underlyingError: error
            ))
        }

        if let bundledDigest = bundledPrivilegedHelperDigest {
            UserDefaults.standard.set(bundledDigest, forKey: Constants.privilegedHelperDigestKey)
        }

        return .success(())
    }

    private static func removeExistingPrivilegedHelperIfNeeded(_ authorizationRef: AuthorizationRef) {
        guard isPrivilegedHelperRegistered else {
            return
        }

        var unmanagedError: Unmanaged<CFError>?
        SMJobRemove(kSMDomainSystemLaunchd, PrivilegedHelperConstants.label as CFString, authorizationRef, true, &unmanagedError)
        unmanagedError?.release()
    }

    private static func fileDigest(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func currentWiFiTurboState() -> Bool? {
        guard
            let awdlIsDown = isInterfaceDown("awdl0"),
            let llwIsDown = isInterfaceDown("llw0")
        else {
            return nil
        }

        return awdlIsDown && llwIsDown
    }

    private static func isInterfaceDown(_ name: String) -> Bool? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0 else {
            return nil
        }
        defer {
            freeifaddrs(addressList)
        }

        var current = addressList
        while let interface = current {
            if String(cString: interface.pointee.ifa_name) == name {
                return interface.pointee.ifa_flags & UInt32(IFF_UP) == 0
            }
            current = interface.pointee.ifa_next
        }

        return nil
    }

    @objc func showPreferences() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView(
                model: appState,
                setWiFiTurboEnabled: setWiFiTurboEnabled,
                setStartAtLoginEnabled: setStartAtLoginEnabled,
                setProbeMode: setProbeMode,
                setTargetHost: setTargetHost,
                setTCPPort: setTCPPort,
                setSettingsGraphWindow: setSettingsGraphWindow
            ))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "linkq Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            hostingController.view.layoutSubtreeIfNeeded()
            window.setContentSize(hostingController.view.fittingSize)
            window.contentMinSize = hostingController.view.fittingSize
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout() {
        if aboutWindow == nil {
            let hostingController = NSHostingController(rootView: AboutView(
                openGithub: openGithubReleases,
                openSupportAuthor: openSupportAuthor
            ))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "About linkq"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            aboutWindow = window
        }

        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openGithubReleases() {
        if let url = URL(string: Constants.githubUrl) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func installLatestRelease() {
        Task { [weak self] in
            await self?.installAvailableUpdate()
        }
    }

    @objc func openSupportAuthor() {
        if let url = URL(string: Constants.supportAuthorUrl) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === settingsWindow {
            settingsWindow?.delegate = nil
            settingsWindow = nil
        } else if window === aboutWindow {
            aboutWindow?.delegate = nil
            aboutWindow = nil
        }
    }

    @MainActor
    private func installAvailableUpdate() async {
        guard !isInstallingUpdate else {
            return
        }

        isInstallingUpdate = true
        defer {
            isInstallingUpdate = false
        }

        do {
            guard let updater else {
                showUpdateAlert(message: "Could not check for updates.", informativeText: "The updater is not ready yet. Please try again in a moment.")
                return
            }

            let update: Update
            if let availableUpdate {
                update = availableUpdate
            } else if let checkedUpdate = try await updater.check() {
                availableUpdate = checkedUpdate
                update = checkedUpdate
            } else {
                showUpdateAlert(message: "linkq is up to date.", informativeText: "No newer release is available right now.")
                return
            }

            let version = versionLabel(for: update)
            guard confirmUpdateInstallation(version: version) else {
                return
            }

            try await update.installAndRelaunch()
        } catch {
            showUpdateAlert(message: "Could not install the update.", informativeText: error.localizedDescription)
        }
    }

    @MainActor
    private func confirmUpdateInstallation(version: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install linkq \(version)?"
        alert.informativeText = "linkq will quit, install the update, and relaunch."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func showUpdateAlert(message: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        guard notification.userInfo?["kind"] as? String == Constants.updateNotificationKind else {
            return
        }

        installLatestRelease()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        true
    }
}

private struct WiFiTurboError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct PrivilegedHelperInstallError: LocalizedError {
    let status: OSStatus
    let message: String
    let underlyingError: CFError?

    init(status: OSStatus, message: String, underlyingError: CFError? = nil) {
        self.status = status
        self.message = message
        self.underlyingError = underlyingError
    }

    var errorDescription: String? {
        guard let underlyingError else {
            return "\(message) (OSStatus \(status))"
        }

        let domain = CFErrorGetDomain(underlyingError) as String
        let code = CFErrorGetCode(underlyingError)
        let description = CFErrorCopyDescription(underlyingError) as String
        let userInfo = (CFErrorCopyUserInfo(underlyingError) as NSDictionary) as? [String: Any] ?? [:]
        let details = userInfo
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")

        if details.isEmpty {
            return "\(message) \(description) (\(domain) \(code))"
        }

        return "\(message) \(description) (\(domain) \(code): \(details))"
    }
}

private struct StartAtLoginError: LocalizedError {
    var errorDescription: String? {
        "Could not change Start at login setting."
    }
}

private final class SettingsHistoryGraphModel: ObservableObject {
    @Published private(set) var samples: [QualitySample]
    @Published private(set) var window: TimeInterval

    private var isActive = true
    private var lastRefreshDate = Date.distantPast

    init(samples: [QualitySample], window: TimeInterval) {
        self.samples = Self.graphSnapshot(from: samples, window: window)
        self.window = window
    }

    func sync(samples: [QualitySample], window: TimeInterval, force: Bool = false) {
        guard isActive || force else {
            return
        }

        let now = Date()
        let windowChanged = self.window != window
        guard force || windowChanged || now.timeIntervalSince(lastRefreshDate) >= Constants.settingsGraphRefreshInterval else {
            return
        }

        self.samples = Self.graphSnapshot(from: samples, window: window)
        self.window = window
        lastRefreshDate = now
    }

    func setActive(_ active: Bool, samples: [QualitySample], window: TimeInterval) {
        guard isActive != active else {
            if active {
                sync(samples: samples, window: window, force: true)
            }
            return
        }

        isActive = active
        if active {
            sync(samples: samples, window: window, force: true)
        } else {
            self.samples.removeAll(keepingCapacity: false)
            self.window = window
        }
    }

    private struct BucketAccumulator {
        var quality: ConnectionQuality?
        var latencySum: TimeInterval = 0
        var latencyCount = 0

        mutating func add(_ sample: QualitySample) {
            if let currentQuality = quality {
                if sample.quality.severity > currentQuality.severity {
                    quality = sample.quality
                }
            } else {
                quality = sample.quality
            }

            if let latency = sample.latency {
                latencySum += latency
                latencyCount += 1
            }
        }

        func sample(for bucket: Int, bucketSize: TimeInterval) -> QualitySample? {
            guard latencyCount > 0 else {
                return nil
            }

            return QualitySample(
                date: Date(timeIntervalSinceReferenceDate: bucketSize * (TimeInterval(bucket) + 0.5)),
                quality: quality ?? .unknown,
                latency: latencySum / TimeInterval(latencyCount)
            )
        }
    }

    private static func graphSnapshot(from samples: [QualitySample], window: TimeInterval) -> [QualitySample] {
        guard window >= HistoryGraphWindow.oneDay.interval else {
            return visibleSnapshot(from: samples, window: window)
        }

        return aggregatedSnapshot(from: samples, window: window)
    }

    private static func visibleSnapshot(from samples: [QualitySample], window: TimeInterval) -> [QualitySample] {
        let cutoff = Date().addingTimeInterval(-window)
        let expectedSampleCount = Int(window / Constants.interval) + 1
        var snapshot: [QualitySample] = []
        snapshot.reserveCapacity(min(samples.count, expectedSampleCount))

        for sample in samples.reversed() {
            guard sample.date >= cutoff else {
                break
            }
            snapshot.append(sample)
        }

        snapshot.reverse()
        return snapshot
    }

    private static func aggregatedSnapshot(from samples: [QualitySample], window: TimeInterval) -> [QualitySample] {
        let cutoff = Date().addingTimeInterval(-window)
        let bucketSize = window / TimeInterval(Constants.historyGraphMaxVisiblePoints)
        var buckets: [Int: BucketAccumulator] = [:]
        buckets.reserveCapacity(Constants.historyGraphMaxVisiblePoints + 1)

        for sample in samples.reversed() {
            guard sample.date >= cutoff else {
                break
            }

            let bucket = Int(sample.date.timeIntervalSinceReferenceDate / bucketSize)
            buckets[bucket, default: BucketAccumulator()].add(sample)
        }

        var snapshot: [QualitySample] = []
        snapshot.reserveCapacity(min(buckets.count, Constants.historyGraphMaxVisiblePoints + 1))
        for bucket in buckets.keys.sorted() {
            if let sample = buckets[bucket]?.sample(for: bucket, bucketSize: bucketSize) {
                snapshot.append(sample)
            }
        }

        if snapshot.count > Constants.historyGraphMaxVisiblePoints {
            return Array(snapshot.suffix(Constants.historyGraphMaxVisiblePoints))
        }

        return snapshot
    }
}

struct MenuHistoryView: View {
    @ObservedObject var model: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 5 minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.quality.menuTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.quality.menuPillForeground)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(model.quality.menuPillBackground, in: Capsule())
            }

            QualityHistoryGraph(samples: model.history, window: Constants.menuHistoryWindow)
                .frame(height: 62)
        }
        .padding(.leading, Constants.menuLeadingPadding)
        .padding(.trailing, Constants.menuTrailingPadding)
        .padding(.vertical, 10)
        .frame(width: Constants.menuWidth)
    }
}

struct QualityHistoryGraph: View {
    let samples: [QualitySample]
    let window: TimeInterval
    private let maxVisiblePoints = Constants.historyGraphMaxVisiblePoints
    private let averageAxisRatio: CGFloat = 0.66

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawGrid(in: context, size: size)
                drawHistory(in: context, size: size)
            }

            if samples.count < 2 {
                Text("Collecting")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
        }
        .background(
            LinearGradient(colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(.rect(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .accessibilityLabel("Network quality history")
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize) {
        var grid = Path()
        for index in 1...3 {
            let y = size.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.primary.opacity(0.08)), lineWidth: 1)
    }

    private func drawHistory(in context: GraphicsContext, size: CGSize) {
        let now = Date()
        let visibleSamples = aggregatedSamples(now: now)

        guard visibleSamples.count > 1 else {
            let thresholds = JitterThresholds(averageLatency: 0.1)
            drawQualityBands(in: context, size: size, thresholds: thresholds, maxDeviation: Constants.averageJitterMax, logBase: max(thresholds.good * 0.5, 0.001))
            drawPlaceholderLine(in: context, size: size)
            return
        }

        let latencies = visibleSamples.compactMap(\.latency)
        guard let baselineLatency = latencies.median else {
            return
        }

        let thresholds = JitterThresholds(averageLatency: baselineLatency)
        let maxDeviation = max(thresholds.average * 1.35, latencies.map { abs($0 - baselineLatency) }.max() ?? thresholds.average)
        let logBase = max(thresholds.good * 0.5, 0.001)

        drawQualityBands(in: context, size: size, thresholds: thresholds, maxDeviation: maxDeviation, logBase: logBase)
        drawAverageLine(in: context, size: size)

        var path = Path()
        let axisY = size.height * averageAxisRatio
        let positiveScale = axisY * 0.92
        let negativeScale = (size.height - axisY) * 0.78
        // Offline samples and periods when the app was not running leave holes
        // in the data; connecting across them would draw misleading straight
        // segments spanning hours, so the line breaks at any gap noticeably
        // larger than the expected sample spacing.
        let expectedSpacing = max(Constants.interval, window / TimeInterval(maxVisiblePoints))
        let gapThreshold = expectedSpacing * 2 + Constants.interval * Double(Constants.maxMissedPings)
        var previousDate: Date?
        for sample in visibleSamples {
            guard let latency = sample.latency else {
                continue
            }

            let age = now.timeIntervalSince(sample.date)
            let x = size.width * (1 - CGFloat(age / window))
            let deviation = max(-maxDeviation, min(maxDeviation, latency - baselineLatency))
            let scale = deviation >= 0 ? positiveScale : negativeScale
            let y = axisY - CGFloat(logarithmicRatio(for: deviation, maxDeviation: maxDeviation, base: logBase)) * scale
            let point = CGPoint(x: x, y: y)

            if let previousDate, sample.date.timeIntervalSince(previousDate) <= gapThreshold {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            previousDate = sample.date
        }

        context.stroke(path, with: .linearGradient(
            Gradient(colors: [.green.opacity(0.95), .yellow.opacity(0.95), .red.opacity(0.95)]),
            startPoint: CGPoint(x: 0, y: size.height * averageAxisRatio),
            endPoint: CGPoint(x: 0, y: 0)
        ), lineWidth: 2.5)
    }

    private func aggregatedSamples(now: Date) -> [QualitySample] {
        let visibleSamples = visibleLatencySamples(now: now)

        guard window >= HistoryGraphWindow.oneDay.interval, visibleSamples.count > maxVisiblePoints else {
            return visibleSamples
        }

        // Buckets are anchored to absolute time, not to `now`: a moving grid
        // regroups samples on every redraw and makes the line shape flicker.
        let bucketSize = window / TimeInterval(maxVisiblePoints)
        var buckets: [Int: [QualitySample]] = [:]
        for sample in visibleSamples {
            let bucket = Int(sample.date.timeIntervalSinceReferenceDate / bucketSize)
            buckets[bucket, default: []].append(sample)
        }

        return buckets.keys.sorted().compactMap { bucket in
            guard let bucketSamples = buckets[bucket], !bucketSamples.isEmpty else {
                return nil
            }

            let latencies = bucketSamples.compactMap(\.latency)
            guard let averageLatency = latencies.average else {
                return nil
            }

            let date = Date(timeIntervalSinceReferenceDate: bucketSize * (TimeInterval(bucket) + 0.5))
            return QualitySample(date: date, quality: quality(for: bucketSamples), latency: averageLatency)
        }
    }

    private func visibleLatencySamples(now: Date) -> [QualitySample] {
        let cutoff = now.addingTimeInterval(-window)
        var visibleSamples: [QualitySample] = []
        let expectedSampleCount = Int(window / Constants.interval) + 1
        visibleSamples.reserveCapacity(min(samples.count, expectedSampleCount))

        for sample in samples.reversed() {
            guard sample.date >= cutoff else {
                break
            }

            if sample.latency != nil {
                visibleSamples.append(sample)
            }
        }

        return visibleSamples.reversed()
    }

    private func quality(for samples: [QualitySample]) -> ConnectionQuality {
        samples.max { first, second in
            first.quality.severity < second.quality.severity
        }?.quality ?? .unknown
    }

    private func logarithmicRatio(for deviation: TimeInterval, maxDeviation: TimeInterval, base: TimeInterval) -> Double {
        guard maxDeviation > 0, base > 0 else {
            return 0
        }

        let sign = deviation < 0 ? -1.0 : 1.0
        let magnitude = min(abs(deviation), maxDeviation)
        return sign * log1p(magnitude / base) / log1p(maxDeviation / base)
    }

    private func logarithmicMagnitudeRatio(for value: TimeInterval, maxDeviation: TimeInterval, base: TimeInterval) -> CGFloat {
        guard value > 0, maxDeviation > 0, base > 0 else {
            return 0
        }

        return CGFloat(log1p(min(value, maxDeviation) / base) / log1p(maxDeviation / base))
    }

    private func drawQualityBands(in context: GraphicsContext, size: CGSize, thresholds: JitterThresholds, maxDeviation: TimeInterval, logBase: TimeInterval) {
        let center = size.height * averageAxisRatio
        let positiveScale = center * 0.92
        let negativeScale = (size.height - center) * 0.78
        let goodRatio = logarithmicMagnitudeRatio(for: thresholds.good, maxDeviation: maxDeviation, base: logBase)
        let averageRatio = logarithmicMagnitudeRatio(for: thresholds.average, maxDeviation: maxDeviation, base: logBase)
        let goodTopHeight = positiveScale * goodRatio
        let goodBottomHeight = negativeScale * goodRatio
        let averageTopHeight = max(0, positiveScale * (averageRatio - goodRatio))
        let averageBottomHeight = max(0, negativeScale * (averageRatio - goodRatio))

        let poorTop = CGRect(x: 0, y: 0, width: size.width, height: max(0, center - goodTopHeight - averageTopHeight))
        let averageTop = CGRect(x: 0, y: poorTop.maxY, width: size.width, height: averageTopHeight)
        let good = CGRect(x: 0, y: center - goodTopHeight, width: size.width, height: goodTopHeight + goodBottomHeight)
        let averageBottom = CGRect(x: 0, y: good.maxY, width: size.width, height: averageBottomHeight)
        let poorBottom = CGRect(x: 0, y: averageBottom.maxY, width: size.width, height: max(0, size.height - averageBottom.maxY))

        context.fill(Path(poorTop), with: .color(.red.opacity(0.08)))
        context.fill(Path(averageTop), with: .color(.yellow.opacity(0.10)))
        context.fill(Path(good), with: .color(.green.opacity(0.12)))
        context.fill(Path(averageBottom), with: .color(.yellow.opacity(0.10)))
        context.fill(Path(poorBottom), with: .color(.red.opacity(0.08)))
    }

    private func drawAverageLine(in context: GraphicsContext, size: CGSize) {
        var path = Path()
        let y = size.height * averageAxisRatio
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(.primary.opacity(0.24)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }

    private func drawPlaceholderLine(in context: GraphicsContext, size: CGSize) {
        var path = Path()
        let y = size.height * 0.55
        path.move(to: CGPoint(x: 0, y: y))
        path.addCurve(
            to: CGPoint(x: size.width, y: y - 6),
            control1: CGPoint(x: size.width * 0.25, y: y - 10),
            control2: CGPoint(x: size.width * 0.7, y: y + 8)
        )
        context.stroke(path, with: .color(.secondary.opacity(0.28)), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppState
    let setWiFiTurboEnabled: (Bool) -> Void
    let setStartAtLoginEnabled: (Bool) -> Void
    let setProbeMode: (ProbeMode) -> Void
    let setTargetHost: (String) -> Void
    let setTCPPort: (Int) -> Void
    let setSettingsGraphWindow: (HistoryGraphWindow) -> Void
    @StateObject private var graphModel: SettingsHistoryGraphModel
    @State private var draftTargetHost: String
    @State private var draftTCPPort: String

    init(
        model: AppState,
        setWiFiTurboEnabled: @escaping (Bool) -> Void,
        setStartAtLoginEnabled: @escaping (Bool) -> Void,
        setProbeMode: @escaping (ProbeMode) -> Void,
        setTargetHost: @escaping (String) -> Void,
        setTCPPort: @escaping (Int) -> Void,
        setSettingsGraphWindow: @escaping (HistoryGraphWindow) -> Void
    ) {
        self.model = model
        self.setWiFiTurboEnabled = setWiFiTurboEnabled
        self.setStartAtLoginEnabled = setStartAtLoginEnabled
        self.setProbeMode = setProbeMode
        self.setTargetHost = setTargetHost
        self.setTCPPort = setTCPPort
        self.setSettingsGraphWindow = setSettingsGraphWindow
        _graphModel = StateObject(wrappedValue: SettingsHistoryGraphModel(
            samples: model.history,
            window: model.settingsGraphWindow.interval
        ))
        _draftTargetHost = State(initialValue: model.targetHost)
        _draftTCPPort = State(initialValue: String(model.tcpPort))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            statusSection
            probeSection
            turboSection
            generalSection
            if let error = model.wiFiTurboError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.startAtLoginError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSImage(named: model.quality.assetName) ?? NSImage())
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("linkq")
                    .font(.title3.weight(.semibold))
                Text("Network quality monitor")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection")
                .font(.headline)
            HStack {
                Text(model.quality.menuTitle)
                    .foregroundStyle(model.quality.tint)
                    .font(.body.weight(.medium))
                Spacer()
                if let latency = model.lastLatency {
                    Text(String(format: "%.0f ms", latency * 1000))
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Range", selection: Binding(
                get: { model.settingsGraphWindow },
                set: { window in
                    setSettingsGraphWindow(window)
                    DispatchQueue.main.async {
                        graphModel.sync(samples: model.history, window: window.interval, force: true)
                    }
                }
            )) {
                ForEach(HistoryGraphWindow.allCases) { window in
                    Text(window.title).tag(window)
                }
            }
            .pickerStyle(.segmented)

            QualityHistoryGraph(samples: graphModel.samples, window: graphModel.window)
                .frame(height: 64)
                .onAppear {
                    graphModel.setActive(true, samples: model.history, window: model.settingsGraphWindow.interval)
                }
                .onDisappear {
                    graphModel.setActive(false, samples: [], window: model.settingsGraphWindow.interval)
                }
                .onReceive(model.$history) { history in
                    graphModel.sync(samples: history, window: model.settingsGraphWindow.interval)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
                    graphModel.setActive(false, samples: [], window: model.settingsGraphWindow.interval)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
                    graphModel.setActive(true, samples: model.history, window: model.settingsGraphWindow.interval)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
                    graphModel.setActive(false, samples: [], window: model.settingsGraphWindow.interval)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
                    graphModel.setActive(true, samples: model.history, window: model.settingsGraphWindow.interval)
                }
        }
    }

    private var turboSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.isWiFiTurboEnabled },
                set: { setWiFiTurboEnabled($0) }
            )) {
                Text("Tweak macOS Wi-Fi")
                    .font(.headline)
            }
            .disabled(model.isWiFiTurboChanging)

            Text("Disables AWDL and LLW for more stable low ping in games, important video calls and other latency-sensitive sessions. AirDrop, AirPlay discovery and similar nearby services will not work while this is enabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var probeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Probe")
                .font(.headline)

            Picker("Mode", selection: Binding(
                get: { model.probeMode },
                set: { setProbeMode($0) }
            )) {
                ForEach(ProbeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                TextField("Target", text: $draftTargetHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyProbeSettings)

                TextField("Port", text: $draftTCPPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    .disabled(model.probeMode == .icmp)
                    .onSubmit(applyProbeSettings)

                Button("Apply", action: applyProbeSettings)
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { model.isStartAtLoginEnabled },
                set: { setStartAtLoginEnabled($0) }
            )) {
                Text("Start at login")
            }
        }
    }

    private func applyProbeSettings() {
        setTargetHost(draftTargetHost)

        if let port = Int(draftTCPPort) {
            setTCPPort(port)
            draftTCPPort = String(min(max(port, 1), 65535))
        } else {
            draftTCPPort = String(model.tcpPort)
        }
    }
}

struct AboutView: View {
    let openGithub: () -> Void
    let openSupportAuthor: () -> Void

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return "Version unknown"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("linkq")
                    .font(.title2.weight(.semibold))
                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("renset ©")
                Text("MIT License")
            }
            .font(.body)

            HStack(spacing: 10) {
                Button("Open GitHub page", action: openGithub)
                Button("Support author", action: openSupportAuthor)
            }
        }
        .padding(24)
        .frame(width: 320, height: 190)
    }
}

private extension Array where Element == TimeInterval {
    var average: TimeInterval? {
        guard !isEmpty else {
            return nil
        }

        return reduce(0, +) / TimeInterval(count)
    }

    var median: TimeInterval? {
        guard !isEmpty else {
            return nil
        }

        let sortedValues = sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }

        return sortedValues[middle]
    }
}
