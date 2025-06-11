//
//  RambleHelperApp.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import SwiftUI

@main
struct RambleHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
