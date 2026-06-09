//
//  linkqApp.swift
//  linkq
//
//  Created by Renat Notfullin on 06.05.2023.
//

import SwiftUI
import AppKit


@main
struct linkqApp: App {
    @StateObject private var appState: AppState
    private let statusBarController: StatusBarController

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        statusBarController = StatusBarController(state: state)
    }
    
    var body: some Scene {
        // Settings live in the window opened from the status bar menu
        // (StatusBarController.showPreferences); this scene only satisfies App.
        Settings {
            EmptyView()
        }
    }
}
