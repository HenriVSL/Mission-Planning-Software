//
//  SelectedWaypointBar.swift
//  Mission Planning Software
//
//  Compact action bar shown in Edit Mode when a waypoint is selected on the
//  map: rename/edit details, delete, or deselect.
//

import SwiftUI

struct SelectedWaypointBar: View {
    @Environment(MissionManager.self) private var mission

    let index: Int
    let waypoint: Waypoint
    let onEdit: () -> Void
    let onMove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.yellow)
                Text("\(index)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(waypoint.displayName(index: index))
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("r \(Int(waypoint.activationRadius.rounded())) m")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.yellow)
            }

            Spacer(minLength: 8)

            Button(action: onMove) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(width: 36, height: 32)
            }

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 32)
            }

            Button {
                mission.deleteSelectedWaypoint()
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 32)
            }

            Button {
                mission.deselect()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.yellow.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        .padding(.horizontal, 12)
    }
}
