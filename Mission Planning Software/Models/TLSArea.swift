//
//  TLSArea.swift
//  Mission Planning Software
//
//  A Tactical Layer Symbol (TLS): an enclosed area drawn as a colored polygon.
//  Outline-only by default; optionally filled (e.g. a red no-go zone).
//  Stored in KML as a <Polygon> placemark.
//

import CoreLocation
import Foundation

nonisolated struct TLSArea: Identifiable {
    let id: UUID
    var name: String?
    /// Boundary vertices (open ring — the closing edge is implicit / added on export).
    var vertices: [CLLocationCoordinate2D]
    /// RGB hex string, e.g. "FF3B30".
    var colorHex: String
    /// Filled (translucent) vs outline-only.
    var filled: Bool
    /// Show this area's label in Navigation Mode (always shown while editing).
    var showLabel: Bool

    init(
        id: UUID = UUID(),
        name: String? = nil,
        vertices: [CLLocationCoordinate2D],
        colorHex: String = TLSPalette.defaultColor,
        filled: Bool = false,
        showLabel: Bool = false
    ) {
        self.id = id
        self.name = name
        self.vertices = vertices
        self.colorHex = colorHex
        self.filled = filled
        self.showLabel = showLabel
    }

    func displayName(index: Int) -> String {
        name ?? "TLS \(index)"
    }

    /// Average of the vertices — used to place the selectable label marker.
    var center: CLLocationCoordinate2D {
        guard !vertices.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let count = Double(vertices.count)
        let lat = vertices.reduce(0) { $0 + $1.latitude } / count
        let lon = vertices.reduce(0) { $0 + $1.longitude } / count
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Preset colors offered when drawing areas (stored as RGB hex, SwiftUI-free).
nonisolated enum TLSPalette {
    static let defaultColor = "FF3B30"   // red
    static let colors: [String] = [
        "FF3B30", // red
        "FF9500", // orange
        "FFCC00", // yellow
        "34C759", // green
        "0A84FF", // blue
        "AF52DE", // purple
        "FFFFFF", // white
    ]
}
