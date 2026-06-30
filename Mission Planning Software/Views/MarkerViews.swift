//
//  MarkerViews.swift
//  Mission Planning Software
//
//  Emoji-marker UI: the emoji entry field, the on-map chip, and the
//  markers-layer bottom bars.
//

import SwiftUI

/// A compact field that holds a single emoji (uses the system emoji keyboard).
struct EmojiField: View {
    @Binding var emoji: String

    var body: some View {
        TextField("📍", text: Binding(
            get: { emoji },
            set: { newValue in
                // Keep only the last entered grapheme (one emoji).
                if let last = newValue.last { emoji = String(last) }
            }
        ))
        .multilineTextAlignment(.center)
        .font(.title2)
        .frame(width: 52, height: 38)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
    }
}

/// On-map emoji marker: the glyph on a translucent chip, with an optional label.
struct MarkerView: View {
    let emoji: String
    let name: String?
    let showLabel: Bool
    let isSelected: Bool
    var backgroundHex: String = MarkerPalette.defaultBackground

    var body: some View {
        VStack(spacing: 2) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Color(hex: backgroundHex).opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? .yellow : .white.opacity(0.4),
                                lineWidth: isSelected ? 2.5 : 1)
                )

            if showLabel, let name, !name.isEmpty {
                Text(name)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

/// Markers-layer bottom bar (not selecting): pick the emoji and drop it.
struct MarkerEditBar: View {
    @Environment(MissionManager.self) private var mission
    let onDrop: () -> Void
    let onOpenList: () -> Void

    var body: some View {
        @Bindable var mission = mission

        VStack(spacing: 8) {
            HStack(spacing: 10) {
                barButton("Done", "checkmark", tint: .white) { mission.exitEditMode() }
                barButton("List", "list.bullet", tint: .white, action: onOpenList)
                EmojiField(emoji: $mission.currentEmoji)
                barButton("Drop", "mappin.and.ellipse", tint: .green, prominent: true, action: onDrop)
            }
            ColorSwatchRow(colors: MarkerPalette.backgrounds, selectedHex: mission.currentBackground) {
                mission.currentBackground = $0
            }
        }
        .barChrome()
    }
}

/// Action bar for the selected marker: change emoji, toggle label, delete.
struct SelectedMarkerBar: View {
    @Environment(MissionManager.self) private var mission
    let index: Int
    let marker: MapMarker
    let onMove: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                EmojiField(emoji: Binding(
                    get: { marker.emoji },
                    set: { mission.setMarkerEmoji(id: marker.id, emoji: $0) }
                ))

                Text(marker.displayName(index: index))
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                iconButton("arrow.up.and.down.and.arrow.left.and.right", color: .green, action: onMove)
                iconButton(marker.showLabel ? "tag.fill" : "tag",
                           color: marker.showLabel ? .green : .white) {
                    mission.toggleMarkerShowLabel(id: marker.id)
                }
                iconButton("trash", color: .red) { mission.deleteSelectedMarker() }
                iconButton("xmark", color: .white.opacity(0.7)) { mission.deselectMarker() }
            }

            ColorSwatchRow(colors: MarkerPalette.backgrounds, selectedHex: marker.backgroundHex) {
                mission.setMarkerBackground(id: marker.id, hex: $0)
            }
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
                .frame(width: 32, height: 30)
        }
    }
}
