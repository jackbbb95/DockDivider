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
        Window("DockDivider", id: "main") {
            MainWindowView()
                .environmentObject(appState)
        }
        .defaultSize(width: 940, height: 700)
        .windowResizability(.contentSize)
    }
}
