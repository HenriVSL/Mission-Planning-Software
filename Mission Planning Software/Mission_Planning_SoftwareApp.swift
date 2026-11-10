//
//  Mission_Planning_SoftwareApp.swift
//  Mission Planning Software
//
//  Created by Henri Lavikainen on 28.6.2026.
//

import SwiftUI

@main
struct Mission_Planning_SoftwareApp: App {
    @State private var missionManager = MissionManager()
    @State private var locationManager = LocationManager()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(missionManager)
                .environment(locationManager)
                .environment(settings)
                .preferredColorScheme(.dark) // Default to Dark Mode for field visibility.
                #if os(macOS)
                .frame(minWidth: 700, minHeight: 500)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        #endif
    }
}
