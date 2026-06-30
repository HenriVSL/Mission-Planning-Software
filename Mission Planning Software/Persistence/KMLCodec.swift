//
//  KMLCodec.swift
//  Mission Planning Software
//
//  Encodes a Mission to a KML string and parses KML back into a Mission.
//  Navigation waypoints are <Point> placemarks (in a "Waypoints" folder); TLS
//  areas are <Polygon> placemarks (in a "TLS" folder) carrying a <Style> for
//  interoperable rendering. Custom attributes (activationRadius, color, filled)
//  round-trip through <ExtendedData>. Parsing uses Foundation's XMLParser.
//

import CoreLocation
import Foundation

nonisolated enum KMLCodec {

    // MARK: - Encoding

    static func encode(_ mission: Mission) -> String {
        var kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
        <name>\(escape(mission.name))</name>
        <Folder>
        <name>Waypoints</name>
        """

        for (index, waypoint) in mission.waypoints.enumerated() {
            let name = waypoint.name ?? "WP \(index)"
            kml += """

            <Placemark>
            <name>\(escape(name))</name>
            <ExtendedData>
            <Data name="featureType"><value>waypoint</value></Data>
            <Data name="activationRadius"><value>\(waypoint.activationRadius)</value></Data>
            </ExtendedData>
            <Point><coordinates>\(coord(waypoint.coordinate))</coordinates></Point>
            </Placemark>
            """
        }

        kml += "\n</Folder>"

        if !mission.areas.isEmpty {
            kml += "\n<Folder>\n<name>TLS</name>"
            for (index, area) in mission.areas.enumerated() {
                kml += encodeArea(area, index: index)
            }
            kml += "\n</Folder>"
        }

        if !mission.markers.isEmpty {
            kml += "\n<Folder>\n<name>Markers</name>"
            for (index, marker) in mission.markers.enumerated() {
                kml += encodeMarker(marker, index: index)
            }
            kml += "\n</Folder>"
        }

        kml += "\n</Document>\n</kml>\n"
        return kml
    }

    private static func encodeMarker(_ marker: MapMarker, index: Int) -> String {
        let name = marker.name ?? "Marker \(index)"
        return """

        <Placemark>
        <name>\(escape(name))</name>
        <ExtendedData>
        <Data name="featureType"><value>marker</value></Data>
        <Data name="emoji"><value>\(escape(marker.emoji))</value></Data>
        <Data name="showLabel"><value>\(marker.showLabel ? 1 : 0)</value></Data>
        <Data name="background"><value>\(marker.backgroundHex)</value></Data>
        </ExtendedData>
        <Point><coordinates>\(coord(marker.coordinate))</coordinates></Point>
        </Placemark>
        """
    }

    private static func encodeArea(_ area: TLSArea, index: Int) -> String {
        let name = area.name ?? "TLS \(index)"
        let lineColor = kmlColor(rgbHex: area.colorHex, alpha: 0xFF)
        let fillColor = kmlColor(rgbHex: area.colorHex, alpha: area.filled ? 0x4D : 0x00)

        // Closed coordinate ring (repeat the first vertex at the end).
        var ringCoords = area.vertices.map(coord)
        if let first = area.vertices.first { ringCoords.append(coord(first)) }
        let ring = ringCoords.joined(separator: " ")

        return """

        <Style id="tls-\(index)">
        <LineStyle><color>\(lineColor)</color><width>3</width></LineStyle>
        <PolyStyle><color>\(fillColor)</color><fill>\(area.filled ? 1 : 0)</fill></PolyStyle>
        </Style>
        <Placemark>
        <name>\(escape(name))</name>
        <styleUrl>#tls-\(index)</styleUrl>
        <ExtendedData>
        <Data name="featureType"><value>tls</value></Data>
        <Data name="color"><value>\(area.colorHex)</value></Data>
        <Data name="filled"><value>\(area.filled ? 1 : 0)</value></Data>
        <Data name="showLabel"><value>\(area.showLabel ? 1 : 0)</value></Data>
        </ExtendedData>
        <Polygon><outerBoundaryIs><LinearRing><coordinates>\(ring)</coordinates></LinearRing></outerBoundaryIs></Polygon>
        </Placemark>
        """
    }

    /// KML coordinate order is "lon,lat,alt".
    private static func coord(_ c: CLLocationCoordinate2D) -> String {
        "\(c.longitude),\(c.latitude),0"
    }

    /// RGB hex ("RRGGBB") + alpha byte -> KML "aabbggrr" (KML reverses byte order).
    private static func kmlColor(rgbHex: String, alpha: Int) -> String {
        let s = rgbHex.count >= 6 ? rgbHex.uppercased() : "FF3B30"
        let rr = s.prefix(2)
        let gg = s.dropFirst(2).prefix(2)
        let bb = s.dropFirst(4).prefix(2)
        return (String(format: "%02x", alpha & 0xFF) + bb + gg + rr).lowercased()
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Decoding

    /// Parse KML data into a Mission. Returns nil if it has no readable features.
    static func decode(_ data: Data, fallbackName: String) -> Mission? {
        KMLParserDelegate().parse(data, fallbackName: fallbackName)
    }
}

/// SAX-style KML parser. `nonisolated` so its synchronous XMLParserDelegate
/// callbacks don't collide with the project's default MainActor isolation.
private nonisolated final class KMLParserDelegate: NSObject, XMLParserDelegate {

    private enum Geometry { case none, point, polygon }

    private var documentName: String?
    private var waypoints: [Waypoint] = []
    private var areas: [TLSArea] = []
    private var markers: [MapMarker] = []

    private var insidePlacemark = false
    private var geometry: Geometry = .none
    private var placemarkName: String?
    private var placemarkCoordinates: String?
    private var placemarkRadius: Double?
    private var placemarkColor: String?
    private var placemarkFilled: Bool?
    private var placemarkShowLabel: Bool?
    private var placemarkFeatureType: String?
    private var placemarkEmoji: String?
    private var placemarkBackground: String?

    private var currentDataName: String?
    private var buffer = ""

    func parse(_ data: Data, fallbackName: String) -> Mission? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(),
              !(waypoints.isEmpty && areas.isEmpty && markers.isEmpty) else { return nil }
        return Mission(name: documentName ?? fallbackName,
                       waypoints: waypoints, areas: areas, markers: markers)
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        buffer = ""
        switch elementName {
        case "Placemark":
            insidePlacemark = true
            geometry = .none
            placemarkName = nil
            placemarkCoordinates = nil
            placemarkRadius = nil
            placemarkColor = nil
            placemarkFilled = nil
            placemarkShowLabel = nil
            placemarkFeatureType = nil
            placemarkEmoji = nil
            placemarkBackground = nil
        case "Point":
            geometry = .point
        case "Polygon":
            geometry = .polygon
        case "Data", "SimpleData":
            currentDataName = attributeDict["name"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "name":
            if insidePlacemark {
                placemarkName = text
            } else if documentName == nil {
                documentName = text
            }
        case "coordinates":
            if insidePlacemark { placemarkCoordinates = text }
        case "value", "SimpleData":
            switch currentDataName {
            case "activationRadius": placemarkRadius = Double(text)
            case "color": if !text.isEmpty { placemarkColor = text }
            case "filled": placemarkFilled = (text == "1" || text.lowercased() == "true")
            case "showLabel": placemarkShowLabel = (text == "1" || text.lowercased() == "true")
            case "featureType": if !text.isEmpty { placemarkFeatureType = text }
            case "emoji": if !text.isEmpty { placemarkEmoji = text }
            case "background": if !text.isEmpty { placemarkBackground = text }
            default: break
            }
        case "Data":
            currentDataName = nil
        case "Placemark":
            finishPlacemark()
            insidePlacemark = false
        default:
            break
        }
        buffer = ""
    }

    private func finishPlacemark() {
        let name = (placemarkName?.isEmpty == false) ? placemarkName : nil
        switch geometry {
        case .polygon:
            var vertices = Self.parseCoordinates(placemarkCoordinates)
            // Drop the duplicated closing vertex, if present.
            if vertices.count >= 2, let first = vertices.first, let last = vertices.last,
               first.latitude == last.latitude, first.longitude == last.longitude {
                vertices.removeLast()
            }
            guard vertices.count >= 3 else { return }
            areas.append(TLSArea(
                name: name,
                vertices: vertices,
                colorHex: placemarkColor ?? TLSPalette.defaultColor,
                filled: placemarkFilled ?? false,
                showLabel: placemarkShowLabel ?? false
            ))
        case .point:
            guard let coordinate = Self.parseCoordinates(placemarkCoordinates).first else { return }
            if placemarkFeatureType == "marker" {
                markers.append(MapMarker(
                    emoji: placemarkEmoji ?? "📍",
                    name: name,
                    coordinate: coordinate,
                    showLabel: placemarkShowLabel ?? false,
                    backgroundHex: placemarkBackground ?? MarkerPalette.defaultBackground
                ))
            } else {
                waypoints.append(Waypoint(
                    name: name,
                    coordinate: coordinate,
                    activationRadius: placemarkRadius ?? 25
                ))
            }
        case .none:
            break
        }
    }

    /// Parse a KML coordinate string ("lon,lat[,alt]" tuples, whitespace separated).
    private static func parseCoordinates(_ raw: String?) -> [CLLocationCoordinate2D] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [] }
        return raw
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            .compactMap { tuple in
                let parts = tuple.split(separator: ",")
                guard parts.count >= 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
    }
}
