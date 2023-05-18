//
//  linkqApp.swift
//  linkq
//
//  Created by Renat Notfullin on 06.05.2023.
//

import SwiftUI
import AppKit
import SwiftyPing
import ServiceManagement


@main
struct linkqApp: App {
    private let statusBarController = StatusBarController()
    
    var body: some Scene {
        Settings {
            EmptyView()
                .onAppear {
                    statusBarController.updateStatusBarIcon(quality: "unknown")
                }
        }
    }
}


