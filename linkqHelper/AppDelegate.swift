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
            var path = Bundle.main.bundlePath as NSString
            for _ in 1...4 {
                path = path.deletingLastPathComponent as NSString
            }
            
            let applicationPathString = path as String
            let pathURL = URL(fileURLWithPath: applicationPathString)
            NSWorkspace.shared.openApplication(at: pathURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

