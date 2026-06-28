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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(missionManager)
                .environment(locationManager)
                .preferredColorScheme(.dark) // Default to Dark Mode for field visibility.
        }
    }
}
