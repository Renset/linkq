//
//  AppDelegate.swift
//  linkqHelper
//
//  Created by Renat Notfullin on 19.05.2023.
//

import Cocoa

//@NSApplicationMain
class HelperAppDelegate: NSObject, NSApplicationDelegate {
    
    struct Constants {
        static let mainAppBundleID = "com.notfullin.linkq"
    }


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == Constants.mainAppBundleID
        }
        
        if !isRunning {
            guard let applicationURL = mainApplicationURL() else {
                NSApp.terminate(nil)
                return
            }

            NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    private func mainApplicationURL() -> URL? {
        let helperURL = Bundle.main.bundleURL
        let embeddedAppURL = helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        if embeddedAppURL.pathExtension == "app" && FileManager.default.fileExists(atPath: embeddedAppURL.path) {
            return embeddedAppURL
        }

        let debugAppURL = helperURL
            .deletingLastPathComponent()
            .appendingPathComponent("linkq.app")

        if FileManager.default.fileExists(atPath: debugAppURL.path) {
            return debugAppURL
        }

        return nil
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
