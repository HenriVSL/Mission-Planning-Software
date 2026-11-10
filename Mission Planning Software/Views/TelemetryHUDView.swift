//
//  TelemetryHUDView.swift
//  Mission Planning Software
//
//  Bottom execution HUD: distance / ETA to the active waypoint plus the
//  manual Prev / Next mission-progression overrides.
//

import SwiftUI

struct TelemetryHUDView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(LocationManager.self) private var location

    /// Invoked when the user taps the central readout to open the mission menu.
    let onOpenMenu: () -> Void

    /// Straight-line distance from the user to the active waypoint.
    private var distanceToActive: Double? {
        guard let user = location.userLocation,
              let active = mission.activeWaypoint else { return nil }
        return user.distance(to: active.coordinate)
    }

    var body: some View {
        HStack(spacing: 18) {
            controlButton(
                systemName: "chevron.left",
                title: "PREV",
                enabled: mission.canRetreat,
                action: mission.retreat
            )

            Button(action: onOpenMenu) {
                VStack(spacing: 2) {
                    Text(Telemetry.distanceString(distanceToActive))
                        .font(.system(.title2, design: .rounded).monospacedDigit().bold())
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(Telemetry.etaString(distance: distanceToActive, speed: location.groundSpeed))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(.green)
                }
                .frame(minWidth: 110)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            controlButton(
                systemName: "chevron.right",
                title: "NEXT",
                enabled: mission.canAdvance,
                action: mission.advance
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.panel, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func controlButton(
        systemName: String,
        title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemName)
                    .font(.title3.bold())
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(enabled ? .white : .white.opacity(0.3))
            .frame(width: 52, height: 44)
        }
        .disabled(!enabled)
    }
}
