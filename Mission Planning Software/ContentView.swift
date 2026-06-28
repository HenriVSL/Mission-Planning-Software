//
//  ContentView.swift
//  Mission Planning Software
//
//  Created by Henri Lavikainen on 28.6.2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MissionMapView()
    }
}

#Preview {
    ContentView()
        .environment(MissionManager())
        .environment(LocationManager())
        .preferredColorScheme(.dark)
}
