//
//  View+Platform.swift
//  Mission Planning Software
//
//  Small cross-platform wrappers so view code can stay free of #if os() noise.
//  The iOS-only modifiers (keyboard type, autocapitalization, inline nav title,
//  sheet detents) become no-ops (or sensible macOS equivalents) on macOS.
//

import SwiftUI

extension ShapeStyle where Self == AnyShapeStyle {
    /// Panel background: frosted `.ultraThinMaterial` on iOS, a cheap solid on
    /// macOS — live blur over the moving map is very costly on integrated GPUs.
    static var panel: AnyShapeStyle {
        #if os(macOS)
        AnyShapeStyle(Color.black.opacity(0.62))
        #else
        AnyShapeStyle(.ultraThinMaterial)
        #endif
    }
}

/// An EditButton on iOS (drives swipe/List edit mode); nothing on macOS, where
/// List has no edit mode. Use inside a `.toolbar { }`.
struct PlatformEditButton: ToolbarContent {
    var body: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) { EditButton() }
        #else
        ToolbarItem(placement: .automatic) { EmptyView() }
        #endif
    }
}

extension View {

    /// Inline navigation title on iOS; unchanged on macOS.
    @ViewBuilder
    func inlineNavTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Numeric (with punctuation) keyboard on iOS; no-op on macOS.
    @ViewBuilder
    func numericKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }

    /// Word-capitalized entry on iOS; no-op on macOS.
    @ViewBuilder
    func wordsCapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    /// Medium/large detents on iOS; a reasonable window size on macOS.
    @ViewBuilder
    func editorSheet() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #else
        frame(minWidth: 460, minHeight: 540)
        #endif
    }

    /// The mission menu sheet: taller first detent on iOS; window on macOS.
    @ViewBuilder
    func menuSheet() -> some View {
        #if os(iOS)
        presentationDetents([.fraction(0.7), .large])
            .presentationDragIndicator(.visible)
        #else
        frame(minWidth: 460, minHeight: 560)
        #endif
    }

    /// A trailing EditButton toolbar on iOS when `visible`; nothing on macOS.
    @ViewBuilder
    func editButtonToolbar(visible: Bool) -> some View {
        #if os(iOS)
        toolbar {
            if visible { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        }
        #else
        self
        #endif
    }
}
