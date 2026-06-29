//
//  TLSBars.swift
//  Mission Planning Software
//
//  Edit-mode UI for the TLS (areas) layer: the colour swatch row, the
//  draw/edit/selected bottom bars, and the selectable area marker.
//

import SwiftUI

/// Horizontal row of preset colour swatches; highlights the active one.
struct ColorSwatchRow: View {
    let selectedHex: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TLSPalette.colors, id: \.self) { hex in
                Button { onSelect(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().stroke(.white,
                                            lineWidth: selectedHex.caseInsensitiveCompare(hex) == .orderedSame ? 3 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Bottom bar while drawing an area vertex-by-vertex.
struct DrawAreaBar: View {
    @Environment(MissionManager.self) private var mission
    let onAddPoint: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("\(mission.draftVertices.count) point(s) placed — need at least 3")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 10) {
                barButton("Cancel", "xmark", tint: .white) { mission.cancelDrawingArea() }
                barButton("Undo", "arrow.uturn.backward", tint: .white) { mission.undoDraftVertex() }
                    .disabled(mission.draftVertices.isEmpty)
                barButton("Add", "plus", tint: .green, action: onAddPoint)
                barButton("Finish", "checkmark", tint: .green, prominent: true) { mission.finishDrawingArea() }
                    .disabled(!mission.canFinishArea)
            }
        }
        .barChrome()
    }
}

/// Bottom bar in the areas layer when not drawing.
struct AreaEditBar: View {
    @Environment(MissionManager.self) private var mission
    let onOpenList: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            barButton("Done", "checkmark", tint: .white) { mission.exitEditMode() }
            barButton("List", "list.bullet", tint: .white, action: onOpenList)
            barButton("Draw Area", "scribble.variable", tint: .green, prominent: true) { mission.beginDrawingArea() }
        }
        .barChrome()
    }
}

/// Action bar for the selected area: colour, fill, label, edit-shape, delete.
struct SelectedAreaBar: View {
    @Environment(MissionManager.self) private var mission
    let index: Int
    let area: TLSArea
    let onEditShape: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: area.colorHex))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(.white.opacity(0.6)))
                Text(area.displayName(index: index))
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                iconButton(area.showLabel ? "tag.fill" : "tag",
                           color: area.showLabel ? .green : .white) {
                    mission.toggleAreaShowLabel(id: area.id)
                }
                iconButton(area.filled ? "drop.fill" : "drop", color: Color(hex: area.colorHex)) {
                    mission.toggleAreaFilled(id: area.id)
                }
                iconButton("hand.draw", color: .white, action: onEditShape)
                iconButton("trash", color: .red) { mission.deleteSelectedArea() }
                iconButton("xmark", color: .white.opacity(0.7)) { mission.deselectArea() }
            }

            ColorSwatchRow(selectedHex: area.colorHex) { mission.setAreaColor(id: area.id, hex: $0) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.yellow.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        .padding(.horizontal, 12)
    }

    private func iconButton(_ systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
        }
    }
}

/// Bottom bar while editing an area's vertices.
struct ShapeEditBar: View {
    @Environment(MissionManager.self) private var mission

    var body: some View {
        VStack(spacing: 6) {
            Text("Drag a corner to move · tap + to add · double-tap to remove")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            barButton("Done", "checkmark", tint: .green, prominent: true) {
                mission.endEditingAreaShape()
            }
        }
        .barChrome()
    }
}

/// Selectable label marker placed at an area's centroid (areas layer).
struct AreaMarkerView: View {
    let name: String
    let colorHex: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pentagon.fill")
                .font(.caption2)
                .foregroundStyle(Color(hex: colorHex))
            Text(name)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().stroke(isSelected ? .yellow : Color(hex: colorHex),
                                  lineWidth: isSelected ? 2.5 : 1.5))
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

// MARK: - Shared bar pieces

/// A full-width labeled bar button used by the TLS bars.
private func barButton(
    _ title: String,
    _ systemImage: String,
    tint: Color,
    prominent: Bool = false,
    action: @escaping () -> Void
) -> some View {
    let label = Label(title, systemImage: systemImage)
        .font(.system(.subheadline, design: .rounded).bold())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
    return Group {
        if prominent {
            Button(action: action) { label }.buttonStyle(.borderedProminent).tint(tint)
        } else {
            Button(action: action) { label }.buttonStyle(.bordered).tint(tint)
        }
    }
}

private extension View {
    /// Shared capsule/material chrome for the TLS bottom bars.
    func barChrome() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
}
