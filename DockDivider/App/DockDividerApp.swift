//
//  DockDividerApp.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI

@main
struct DockDividerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
    }
}
