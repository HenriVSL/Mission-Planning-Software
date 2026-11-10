//
//  AreaListView.swift
//  Mission Planning Software
//
//  Edit-mode list of TLS areas: rename, recolour, toggle fill, locate, delete.
//

import SwiftUI

struct AreaListView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(\.dismiss) private var dismiss

    /// Recenter the map on an area (provided by the map view).
    let onLocate: (TLSArea) -> Void

    var body: some View {
        @Bindable var mission = mission

        NavigationStack {
            Group {
                if mission.areas.isEmpty {
                    ContentUnavailableView(
                        "No Areas",
                        systemImage: "pentagon",
                        description: Text("Draw an area on the map to get started.")
                    )
                } else {
                    List {
                        ForEach($mission.areas) { $area in
                            row(for: $area)
                        }
                        .onDelete { mission.deleteAreas(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle("Areas")
            .inlineNavTitle()
            .toolbar {
                if !mission.areas.isEmpty { PlatformEditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .editorSheet()
    }

    @ViewBuilder
    private func row(for area: Binding<TLSArea>) -> some View {
        let value = area.wrappedValue
        let index = mission.indexOfArea(value.id) ?? 0

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: value.colorHex))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.secondary.opacity(0.4)))
                TextField("Name", text: area.name.orEmpty())
                    .wordsCapitalization()
                Spacer()
                Text("#\(index)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ColorSwatchRow(selectedHex: value.colorHex) { hex in
                area.wrappedValue.colorHex = hex
            }

            Toggle("Filled", isOn: area.filled)
                .font(.subheadline)
            Toggle("Show label in Navigation", isOn: area.showLabel)
                .font(.subheadline)

            Button {
                onLocate(value)
                dismiss()
            } label: {
                Label("Show on map", systemImage: "scope")
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: value.colorHex))
        }
        .padding(.vertical, 4)
    }
}
