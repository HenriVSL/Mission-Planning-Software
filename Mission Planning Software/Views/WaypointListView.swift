//
//  WaypointListView.swift
//  Mission Planning Software
//
//  Edit Mode waypoint list. Each row expands to reveal editable fields
//  (name / latitude / longitude / radius). Swipe or use the Edit button to
//  delete; tap "Show on map" to recenter the map on a waypoint.
//

import CoreLocation
import SwiftUI

struct WaypointListView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(\.dismiss) private var dismiss

    /// Recenter the map on a waypoint (provided by the map view).
    let onLocate: (Waypoint) -> Void
    /// Begin repositioning a waypoint via the center reticle (provided by map).
    let onMove: (Waypoint) -> Void

    /// Rows currently expanded for editing.
    @State private var expanded: Set<Waypoint.ID> = []

    var body: some View {
        @Bindable var mission = mission

        NavigationStack {
            Group {
                if mission.waypoints.isEmpty {
                    ContentUnavailableView(
                        "No Waypoints",
                        systemImage: "mappin.slash",
                        description: Text("Drop a waypoint on the map to get started.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach($mission.waypoints) { $waypoint in
                                row(for: $waypoint)
                                    .id(waypoint.id)
                            }
                            .onDelete { mission.deleteWaypoints(atOffsets: $0) }
                        }
                        .onAppear {
                            if let focus = mission.selectedWaypointID {
                                expanded.insert(focus)
                                proxy.scrollTo(focus, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Waypoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(for waypoint: Binding<Waypoint>) -> some View {
        let id = waypoint.wrappedValue.id
        let index = mission.index(of: id) ?? 0
        let isActive = index == mission.currentActiveWaypointIndex

        DisclosureGroup(isExpanded: expandedBinding(for: id)) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField("Name") {
                    TextField("Name", text: waypoint.name.orEmpty())
                        .textInputAutocapitalization(.words)
                }
                HStack(spacing: 12) {
                    LabeledField("Latitude") {
                        TextField("Latitude", value: waypoint.coordinate.latitude, format: .number.precision(.fractionLength(0...6)))
                            .keyboardType(.numbersAndPunctuation)
                    }
                    LabeledField("Longitude") {
                        TextField("Longitude", value: waypoint.coordinate.longitude, format: .number.precision(.fractionLength(0...6)))
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
                LabeledField("Activation radius (m)") {
                    TextField("Radius", value: waypoint.activationRadius, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.numbersAndPunctuation)
                }

                HStack(spacing: 10) {
                    Button {
                        onLocate(waypoint.wrappedValue)
                        dismiss()
                    } label: {
                        Label("Show on map", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button {
                        onMove(waypoint.wrappedValue)
                        dismiss()
                    } label: {
                        Label("Move on map", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(isActive ? .green : .secondary.opacity(0.4))
                    Text("\(index)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? .black : .primary)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(waypoint.wrappedValue.displayName(index: index))
                        .font(.body.weight(.medium))
                    Text(String(format: "%.5f, %.5f",
                                waypoint.wrappedValue.coordinate.latitude,
                                waypoint.wrappedValue.coordinate.longitude))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func expandedBinding(for id: Waypoint.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

/// Small labeled field wrapper for consistent editing rows.
struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}
