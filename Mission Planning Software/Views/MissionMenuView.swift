//
//  MissionMenuView.swift
//  Mission Planning Software
//
//  Sheet presented by tapping the telemetry HUD. Shows details about the
//  active target and the entry point to Edit Mode. More sections (waypoint
//  info, mission actions) will be added in later phases.
//

import CoreLocation
import SwiftUI

struct MissionMenuView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    private var distanceToActive: Double? {
        guard let user = location.userLocation,
              let active = mission.activeWaypoint else { return nil }
        return user.distance(to: active.coordinate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Active Target") {
                    if let active = mission.activeWaypoint {
                        LabeledContent("Waypoint",
                                       value: active.displayName(index: mission.currentActiveWaypointIndex))
                        LabeledContent("Distance",
                                       value: Telemetry.distanceString(distanceToActive))
                        LabeledContent("Coordinate", value: format(active.coordinate))
                        LabeledContent("Radius", value: "\(Int(active.activationRadius)) m")
                    } else {
                        Text("No active waypoint")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        mission.enterEditMode()
                        dismiss()
                    } label: {
                        Label("Edit Mission", systemImage: "pencil.and.outline")
                    }
                } footer: {
                    Text("Add, move, and adjust waypoints on the map.")
                }
            }
            .navigationTitle(mission.missionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func format(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}
