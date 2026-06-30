//
//  MapMarker.swift
//  Mission Planning Software
//
//  A free-form emoji marker placed on the map (e.g. 🚑 here). Not a navigation
//  waypoint — purely an informational icon. Stored in KML as a <Point> tagged
//  featureType=marker, with the emoji in <ExtendedData>.
//

import CoreLocation
import Foundation

nonisolated struct MapMarker: Identifiable {
    let id: UUID
    /// A single emoji grapheme.
    var emoji: String
    var name: String?
    var coordinate: CLLocationCoordinate2D
    /// Show the name label under the emoji.
    var showLabel: Bool
    /// RGB hex of the chip background behind the emoji.
    var backgroundHex: String

    init(
        id: UUID = UUID(),
        emoji: String = "📍",
        name: String? = nil,
        coordinate: CLLocationCoordinate2D,
        showLabel: Bool = false,
        backgroundHex: String = MarkerPalette.defaultBackground
    ) {
        self.id = id
        self.emoji = emoji.isEmpty ? "📍" : emoji
        self.name = name
        self.coordinate = coordinate
        self.showLabel = showLabel
        self.backgroundHex = backgroundHex
    }

    func displayName(index: Int) -> String {
        name ?? "Marker \(index)"
    }
}

/// Preset background colors for marker chips (black default + tactical colors).
nonisolated enum MarkerPalette {
    static let defaultBackground = "000000"
    static let backgrounds: [String] = [
        "000000", // black
        "FFFFFF", // white
        "FF3B30", // red
        "FF9500", // orange
        "FFCC00", // yellow
        "34C759", // green
        "0A84FF", // blue
        "AF52DE", // purple
    ]
}
