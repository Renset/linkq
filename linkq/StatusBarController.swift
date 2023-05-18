//
//  StatusBarController.swift
//  linkq
//
//  Created by Renat Notfullin on 19.05.2023.
//

import Foundation
import AppKit
import SwiftyPing
import ServiceManagement

struct Constants {
    static let pingingHost = "1.1.1.1"
    static let interval: TimeInterval = 1
    static let jitterGood = 0.02 // 20ms
    static let jitterAverage = 0.1 // 100ms
}


class StatusBarController {
    var statusItem: NSStatusItem!
    var rttBuffer: [TimeInterval] = []
    let rttBufferSize = 10
    
    init() {
        DispatchQueue.main.async {
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.startPing()
            self.setupMenu()
        }
    }
    
    func startPing() {
        let pinger = try? SwiftyPing(host: Constants.pingingHost, configuration: PingConfiguration(interval: Constants.interval, with: 5), queue: DispatchQueue.global())
        pinger?.observer = { response in
            
            let latency = response.duration
            self.rttBuffer.append(latency)
            if self.rttBuffer.count > self.rttBufferSize {
                self.rttBuffer.removeFirst()
            }
            
            DispatchQueue.main.async {
                if let jitter = self.standardDeviation() {
                    if jitter < Constants.jitterGood {
                        self.updateStatusBarIcon(quality: "good")
                    } else if jitter < Constants.jitterAverage {
                        self.updateStatusBarIcon(quality: "average")
                    } else {
                        self.updateStatusBarIcon(quality: "poor")
                    }
                } else {
                    self.updateStatusBarIcon(quality: "unknown")
                }
            }
        }
        try? pinger?.startPinging()
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
    
    func updateStatusBarIcon(quality: String) {
        DispatchQueue.main.async {
            let menuItem = self.statusItem.menu?.items.first(where: { $0.tag == 1 })
            
            switch quality {
            case "good":
                self.statusItem.button?.image = NSImage(named: "GoodConnection")
                menuItem?.title = "Connection: Good"
            case "average":
                self.statusItem.button?.image = NSImage(named: "AverageConnection")
                menuItem?.title = "Connection: Average"
            case "poor":
                self.statusItem.button?.image = NSImage(named: "PoorConnection")
                menuItem?.title = "Connection: Poor"
            default:
                self.statusItem.button?.image = NSImage(named: "UnknownConnection")
                menuItem?.title = "Connection: Unknown"
            }
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "Connection: Unknown", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)
        
        let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        statusItem.menu = menu
    }
    
    @objc func toggleStartAtLogin() {
        let identifier = "com.notfullin.linkqHelper" as CFString
        let wasEnabled = SMLoginItemSetEnabled(identifier, false)
        SMLoginItemSetEnabled(identifier, !wasEnabled)
        if let item = statusItem.menu?.item(withTitle: "Start at login") {
            item.state = wasEnabled ? .off : .on
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
}
