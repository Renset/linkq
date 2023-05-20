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
        print("Helper app launched.")
        
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains {
            $0.bundleIdentifier == Constants.mainAppBundleID
        }
        
        if !isRunning {
            print("Main app not running. Attempting to launch main app...")
            var path = Bundle.main.bundlePath as NSString
            for _ in 1...4 {
                path = path.deletingLastPathComponent as NSString
            }
            
            let applicationPathString = path as String
            let pathURL = URL(fileURLWithPath: applicationPathString)
            print("pathURL: \(pathURL)")
            let success = NSWorkspace.shared.openApplication(at: pathURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            print("Launch success: \(success)")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

