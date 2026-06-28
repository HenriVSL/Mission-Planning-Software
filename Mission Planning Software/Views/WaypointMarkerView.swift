//
//  WaypointMarkerView.swift
//  Mission Planning Software
//
//  Map annotation for a route waypoint. The active waypoint is highlighted.
//

import SwiftUI

struct WaypointMarkerView: View {
    let index: Int
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? .green : .black.opacity(0.6))
                .overlay(
                    Circle().stroke(isActive ? .white : .white.opacity(0.7),
                                    lineWidth: isActive ? 2.5 : 1.5)
                )
            Text("\(index)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .black : .white)
        }
        .frame(width: isActive ? 30 : 24, height: isActive ? 30 : 24)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

#Preview {
    HStack(spacing: 20) {
        WaypointMarkerView(index: 0, isActive: true)
        WaypointMarkerView(index: 1, isActive: false)
    }
    .padding()
    .background(.gray)
}
