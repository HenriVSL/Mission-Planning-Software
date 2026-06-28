//
//  Waypoint.swift
//  Mission Planning Software
//
//  A single tactical target along a mission route.
//

import CoreLocation
import Foundation

struct Waypoint: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var coordinate: CLLocationCoordinate2D
    /// Trigger radius in meters used to consider this waypoint "reached".
    var activationRadius: Double

    init(
        id: UUID = UUID(),
        name: String? = nil,
        coordinate: CLLocationCoordinate2D,
        activationRadius: Double = 25
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.activationRadius = activationRadius
    }

    /// Display name, falling back to a positional label when unnamed.
    func displayName(index: Int) -> String {
        name ?? "WP \(index)"
    }

    static func == (lhs: Waypoint, rhs: Waypoint) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.activationRadius == rhs.activationRadius
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}
