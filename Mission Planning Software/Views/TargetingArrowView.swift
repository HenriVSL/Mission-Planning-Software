//
//  TargetingArrowView.swift
//  Mission Planning Software
//
//  Custom user-location annotation: an arrow that always points at the
//  active waypoint, regardless of the device's physical heading.
//

import SwiftUI

struct TargetingArrowView: View {
    /// Target angle to the active waypoint, in degrees clockwise from screen-up.
    let bearing: Double

    /// Continuously accumulated rotation. Updated by the shortest signed delta on
    /// each new bearing so the arrow never spins the "long way" across the 0/360
    /// boundary (e.g. 359° → 1° rotates +2°, not −358°).
    @State private var displayedAngle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
            Circle()
                .stroke(.green.opacity(0.85), lineWidth: 2)

            Image(systemName: "location.north.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.green)
                .rotationEffect(.degrees(displayedAngle))
        }
        .frame(width: 46, height: 46)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        // Smooth the arrow sweep; always takes the short path thanks to unwrapping.
        .animation(.easeInOut(duration: 0.25), value: displayedAngle)
        .onAppear { displayedAngle = bearing }
        .onChange(of: bearing) { _, newValue in
            displayedAngle += shortestDelta(from: displayedAngle, to: newValue)
        }
    }

    /// Smallest signed rotation (−180°…180°) to get from `current` to `target`,
    /// accounting for `current` being an unbounded accumulated angle.
    private func shortestDelta(from current: Double, to target: Double) -> Double {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

#Preview {
    ZStack {
        Color.gray
        TargetingArrowView(bearing: 45)
    }
    .ignoresSafeArea()
}
