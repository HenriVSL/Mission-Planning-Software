//
//  MissionLibraryView.swift
//  Mission Planning Software
//
//  Mission Library: save the current mission, start a new one, and load or
//  delete saved missions (stored as .kml files in the Documents directory).
//

import SwiftUI
import UniformTypeIdentifiers

struct MissionLibraryView: View {
    @Environment(MissionManager.self) private var mission
    @Environment(\.dismiss) private var dismiss

    @State private var files: [MissionFile] = []
    @State private var errorMessage: String?
    /// Name pending a replace-confirmation (a saved mission already uses it).
    @State private var replaceName: String?
    /// Temp KML file backing the share sheet; regenerated to stay current.
    @State private var exportURL: URL?
    @State private var showingImporter = false

    /// KML has no system UTType; it resolves to a dynamic type matched by the
    /// `.kml` extension, which is enough for the file importer to filter on.
    private let kmlType = UTType(filenameExtension: "kml") ?? .xml

    var body: some View {
        @Bindable var mission = mission

        List {
            Section {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                    TextField("Mission name", text: $mission.missionName)
                        .wordsCapitalization()
                        .submitLabel(.done)
                }
                LabeledContent("Waypoints", value: "\(mission.waypoints.count)")

                Button(action: performSave) {
                    Label("Save Mission", systemImage: "square.and.arrow.down")
                }

                if let exportURL, !mission.waypoints.isEmpty {
                    ShareLink(item: exportURL) {
                        Label("Export / Share (KML)", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    mission.newMission()
                    refresh()
                    refreshExport()
                } label: {
                    Label("New Mission", systemImage: "plus")
                }
            } header: {
                Text("Current Mission")
            } footer: {
                Text("Saving an existing name asks before replacing it. A new name saves a separate mission (rename = save under the new name, then delete the old one).")
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import KML…", systemImage: "square.and.arrow.down.on.square")
                }
            }

            Section("Saved Missions") {
                if files.isEmpty {
                    Text("No saved missions yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files) { file in
                        Button {
                            load(file)
                        } label: {
                            row(for: file)
                        }
                        .tint(.primary)
                    }
                    .onDelete(perform: deleteFiles)
                }
            }
        }
        .navigationTitle("Mission Library")
        .inlineNavTitle()
        .editButtonToolbar(visible: !files.isEmpty)
        .onAppear { refresh(); refreshExport() }
        .onChange(of: mission.missionName) { _, _ in refreshExport() }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [kmlType],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("Replace Mission?",
               isPresented: Binding(get: { replaceName != nil },
                                    set: { if !$0 { replaceName = nil } }),
               presenting: replaceName) { name in
            Button("Replace", role: .destructive) { writeSave(name: name) }
            Button("Cancel", role: .cancel) {}
        } message: { name in
            Text("A saved mission named “\(name)” already exists. Replace it?")
        }
        .alert("Something Went Wrong",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for file: MissionFile) -> some View {
        HStack {
            Image(systemName: "map")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                Text(file.modified, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if file.url == mission.currentFileURL {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        files = MissionStore.list()
    }

    /// Write the current mission to a temp KML file for the share sheet, named
    /// after the mission so the shared file has a sensible filename.
    private func refreshExport() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(MissionStore.sanitize(mission.missionName))
            .appendingPathExtension("kml")
        do {
            try Data(KMLCodec.encode(mission.currentMission).utf8).write(to: url, options: .atomic)
            if let previous = exportURL, previous != url {
                try? FileManager.default.removeItem(at: previous)
            }
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    /// Save the current mission. If a file with this name already exists, ask
    /// before replacing it; a different name simply creates another mission.
    private func performSave() {
        let name = MissionStore.sanitize(mission.missionName)
        if MissionStore.exists(name: name) {
            replaceName = name
        } else {
            writeSave(name: name)
        }
    }

    private func writeSave(name: String) {
        do {
            let url = try MissionStore.save(mission.currentMission, fileName: name)
            mission.markSaved(as: name, url: url)
            refresh()
            refreshExport()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first { importFile(url) }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(_ url: URL) {
        // Files from outside the sandbox are security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let base = url.deletingPathExtension().lastPathComponent
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "“\(base)” could not be read."
            return
        }
        guard var imported = KMLCodec.decode(data, fallbackName: base) else {
            errorMessage = "“\(base)” has no waypoints we can read."
            return
        }

        // Save a copy into the library under a non-colliding name.
        let name = MissionStore.uniqueName(base: base)
        imported.name = name
        do {
            _ = try MissionStore.save(imported, fileName: name)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ file: MissionFile) {
        guard let loaded = MissionStore.load(file.url) else {
            errorMessage = "“\(file.name)” could not be read as a valid mission."
            return
        }
        mission.load(loaded, from: file.url)
        dismiss()
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets where files.indices.contains(index) {
            let file = files[index]
            MissionStore.delete(file.url)
            if file.url == mission.currentFileURL { mission.currentFileURL = nil }
        }
        refresh()
    }
}
