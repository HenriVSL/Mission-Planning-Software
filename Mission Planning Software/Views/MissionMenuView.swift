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
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var distanceToActive: Double? {
        guard let user = location.userLocation,
              let active = mission.activeWaypoint else { return nil }
        return user.distance(to: active.coordinate)
    }

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
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

                    NavigationLink {
                        MissionLibraryView()
                    } label: {
                        Label("Mission Library", systemImage: "folder")
                    }
                } footer: {
                    Text("Add or adjust waypoints, or save, load, and manage missions.")
                }

                Section("Display") {
                    Picker("Map Type", selection: $settings.mapStyle) {
                        ForEach(MapStyleOption.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Toggle("Dark Map", isOn: $settings.mapDark)
                    Toggle("Keep Screen Awake", isOn: $settings.keepAwake)
                }
            }
            .navigationTitle(mission.missionName)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .menuSheet()
    }

    private func format(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}
