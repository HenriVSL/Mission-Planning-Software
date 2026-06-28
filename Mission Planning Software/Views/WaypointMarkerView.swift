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
    var isSelected: Bool = false

    private var diameter: CGFloat { isActive ? 30 : 24 }

    var body: some View {
        ZStack {
            // Selection halo (Edit Mode).
            if isSelected {
                Circle()
                    .stroke(.yellow, lineWidth: 3)
                    .frame(width: diameter + 12, height: diameter + 12)
            }

            Circle()
                .fill(isActive ? .green : .black.opacity(0.6))
                .overlay(
                    Circle().stroke(isActive ? .white : .white.opacity(0.7),
                                    lineWidth: isActive ? 2.5 : 1.5)
                )
                .frame(width: diameter, height: diameter)

            Text("\(index)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .black : .white)
        }
        .frame(width: diameter + 12, height: diameter + 12)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

#Preview {
    HStack(spacing: 20) {
        WaypointMarkerView(index: 0, isActive: true)
        WaypointMarkerView(index: 1, isActive: false)
        WaypointMarkerView(index: 2, isActive: false, isSelected: true)
    }
    .padding()
    .background(.gray)
}
