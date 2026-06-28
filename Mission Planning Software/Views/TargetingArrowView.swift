//
//  TargetingArrowView.swift
//  Mission Planning Software
//
//  Custom user-location annotation: an arrow that always points at the
//  active waypoint, regardless of the device's physical heading.
//

import SwiftUI

struct TargetingArrowView: View {
    /// True bearing to the active waypoint, in degrees clockwise from north.
    let bearing: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
            Circle()
                .stroke(.green.opacity(0.85), lineWidth: 2)

            Image(systemName: "location.north.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.green)
                .rotationEffect(.degrees(bearing))
        }
        .frame(width: 46, height: 46)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        // Smooth the arrow sweep as new bearings arrive.
        .animation(.easeInOut(duration: 0.25), value: bearing)
    }
}

#Preview {
    ZStack {
        Color.gray
        TargetingArrowView(bearing: 45)
    }
    .ignoresSafeArea()
}
