//
//  MarkerListView.swift
//  Mission Planning Software
//
//  Edit-mode list of emoji markers: change emoji, rename, edit coordinate,
//  toggle label, locate, delete.
//

import CoreLocation
import SwiftUI

struct MarkerListView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(\.dismiss) private var dismiss

    /// Recenter the map on a marker (provided by the map view).
    let onLocate: (MapMarker) -> Void

    var body: some View {
        @Bindable var mission = mission

        NavigationStack {
            Group {
                if mission.markers.isEmpty {
                    ContentUnavailableView(
                        "No Markers",
                        systemImage: "mappin.slash",
                        description: Text("Drop an emoji marker on the map to get started.")
                    )
                } else {
                    List {
                        ForEach($mission.markers) { $marker in
                            row(for: $marker)
                        }
                        .onDelete { mission.deleteMarkers(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !mission.markers.isEmpty { ToolbarItem(placement: .topBarLeading) { EditButton() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(for marker: Binding<MapMarker>) -> some View {
        let index = mission.indexOfMarker(marker.wrappedValue.id) ?? 0

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                EmojiField(emoji: marker.emoji)
                    .fixedSize()
                TextField("Name", text: marker.name.orEmpty())
                    .textInputAutocapitalization(.words)
                Spacer()
                Text("#\(index)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                LabeledField("Latitude") {
                    TextField("Latitude", value: marker.coordinate.latitude, format: .number.precision(.fractionLength(0...6)))
                        .keyboardType(.numbersAndPunctuation)
                }
                LabeledField("Longitude") {
                    TextField("Longitude", value: marker.coordinate.longitude, format: .number.precision(.fractionLength(0...6)))
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorSwatchRow(colors: MarkerPalette.backgrounds,
                               selectedHex: marker.wrappedValue.backgroundHex) { hex in
                    marker.wrappedValue.backgroundHex = hex
                }
            }

            Toggle("Show label on map", isOn: marker.showLabel)
                .font(.subheadline)

            Button {
                onLocate(marker.wrappedValue)
                dismiss()
            } label: {
                Label("Show on map", systemImage: "scope")
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
        .padding(.vertical, 4)
    }
}
