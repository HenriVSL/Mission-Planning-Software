//
//  CrosshairView.swift
//  Mission Planning Software
//
//  Static center reticle shown in Edit Mode. The map pans beneath it; the
//  coordinate at its center is where a new waypoint is dropped.
//

import SwiftUI

struct CrosshairView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.green.opacity(0.9), lineWidth: 2)
                .frame(width: 46, height: 46)

            // Cross hairs
            Rectangle().fill(.green).frame(width: 2, height: 14)
            Rectangle().fill(.green).frame(width: 14, height: 2)

            // Center dot
            Circle().fill(.green).frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
        .allowsHitTesting(false) // never intercept map gestures
    }
}

#Preview {
    ZStack {
        Color.gray
        CrosshairView()
    }
    .ignoresSafeArea()
}
