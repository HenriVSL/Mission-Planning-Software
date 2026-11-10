//
//  EditModeBar.swift
//  Mission Planning Software
//
//  Bottom controls shown in Edit Mode: drop a waypoint at the crosshair, or
//  finish editing and return to Navigation Mode.
//

import SwiftUI

struct EditModeBar: View {
    @Environment(MissionManager.self) private var mission
    /// Invoked when the user taps "Drop Waypoint" — drops at the map center.
    let onDrop: () -> Void
    /// Invoked when the user taps "List" — opens the waypoint list editor.
    let onOpenList: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                mission.exitEditMode()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button(action: onOpenList) {
                Label("List", systemImage: "list.bullet")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button(action: onDrop) {
                Label("Drop", systemImage: "mappin.and.ellipse")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
