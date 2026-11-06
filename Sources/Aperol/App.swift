// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aperol

import SwiftUI
import AppKit

@main
struct AperolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 500, height: 750)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.title = "Aperol RGB Controller"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.center()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
