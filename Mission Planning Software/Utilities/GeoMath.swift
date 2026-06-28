//
//  GeoMath.swift
//  Mission Planning Software
//
//  Great-circle geometry helpers and telemetry formatting.
//

import CoreLocation
import Foundation

extension CLLocationCoordinate2D {

    /// Initial true bearing (forward azimuth) from `self` to `destination`, in
    /// degrees clockwise from true north (0–360). Derived from the spherical
    /// law applied to the Haversine model of the Earth.
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude.radians
        let lat2 = destination.latitude.radians
        let deltaLon = (destination.longitude - longitude).radians

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x).degrees

        // Normalize into 0..<360.
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Straight-line (great-circle) distance to `destination`, in meters.
    func distance(to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return a.distance(from: b)
    }

    /// The coordinate reached by travelling `distanceMeters` from `self` along
    /// `bearingDegrees` (clockwise from true north). Used to place handles on a
    /// circle of a given radius around a center point.
    func coordinate(bearingDegrees: Double, distanceMeters: CLLocationDistance) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distanceMeters / earthRadius
        let bearing = (bearingDegrees * .pi / 180)
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angularDistance)
                        + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1),
                                cos(angularDistance) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                      longitude: lon2 * 180 / .pi)
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

// MARK: - Telemetry formatting

enum Telemetry {

    /// Formats a distance in meters for the HUD, switching to km past 1000 m.
    static func distanceString(_ meters: CLLocationDistance?) -> String {
        guard let meters, meters.isFinite else { return "—" }
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.2f km", meters / 1000)
    }

    /// Estimated time to target given a straight-line distance and current
    /// ground speed (m/s). Returns "—" when speed is unusable (stationary / no fix).
    static func etaString(distance meters: CLLocationDistance?, speed: CLLocationSpeed?) -> String {
        guard let meters, let speed, speed > 0.3, meters.isFinite else { return "—" }
        let seconds = Int((meters / speed).rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
