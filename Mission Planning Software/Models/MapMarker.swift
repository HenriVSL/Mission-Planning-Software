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

    init(
        id: UUID = UUID(),
        emoji: String = "📍",
        name: String? = nil,
        coordinate: CLLocationCoordinate2D,
        showLabel: Bool = false
    ) {
        self.id = id
        self.emoji = emoji.isEmpty ? "📍" : emoji
        self.name = name
        self.coordinate = coordinate
        self.showLabel = showLabel
    }

    func displayName(index: Int) -> String {
        name ?? "Marker \(index)"
    }
}
