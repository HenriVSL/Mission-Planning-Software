//
//  MissionStore.swift
//  Mission Planning Software
//
//  File-based mission library. Missions are stored as .kml files in the app's
//  Documents directory; this type lists, loads, saves, and deletes them.
//

import Foundation

/// Lightweight descriptor for a saved mission file (Mission Library rows).
struct MissionFile: Identifiable {
    var id: URL { url }
    let url: URL
    let name: String
    let modified: Date
}

enum MissionStore {

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// All saved missions, newest first.
    static func list() -> [MissionFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "kml" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return MissionFile(url: url,
                                   name: url.deletingPathExtension().lastPathComponent,
                                   modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// The file URL a mission with `name` would be saved to.
    static func url(forName name: String) -> URL {
        documentsURL
            .appendingPathComponent(sanitize(name))
            .appendingPathExtension("kml")
    }

    /// Whether a saved mission already exists for `name`.
    static func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forName: name).path)
    }

    /// Write a mission to "<name>.kml" (overwriting), returning the file URL.
    @discardableResult
    static func save(_ mission: Mission, fileName: String) throws -> URL {
        let url = url(forName: fileName)
        let kml = KMLCodec.encode(mission)
        try Data(kml.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Load and parse a mission from a KML file URL.
    static func load(_ url: URL) -> Mission? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let fallback = url.deletingPathExtension().lastPathComponent
        var mission = KMLCodec.decode(data, fallbackName: fallback)
        // Prefer the file name as the library-facing mission name.
        mission?.name = fallback
        return mission
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// A sanitized base file name that doesn't collide with an existing mission
    /// (appends " 2", " 3", … as needed). Used when importing.
    static func uniqueName(base: String) -> String {
        let sanitized = sanitize(base)
        let existing = Set(list().map(\.name))
        guard existing.contains(sanitized) else { return sanitized }
        var index = 2
        while existing.contains("\(sanitized) \(index)") { index += 1 }
        return "\(sanitized) \(index)"
    }

    /// Strip path separators and trim; never returns an empty name.
    static func sanitize(_ name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Mission" : cleaned
    }
}
