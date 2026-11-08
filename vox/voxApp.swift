//
//  voxApp.swift
//  vox
//
//  Created by Pedro Planel on 01/11/26.
//

import SwiftUI

@main
struct voxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Janela de Settings - acessa speechService via appDelegate
        Settings {
            SettingsView()
                .environmentObject(appDelegate.speechService)
                .environmentObject(appDelegate.executor)
        }
    }
}

