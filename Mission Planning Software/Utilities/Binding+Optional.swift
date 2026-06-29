//
//  Binding+Optional.swift
//  Mission Planning Software
//
//  Bridges an optional String binding to a non-optional one for TextField.
//

import SwiftUI

extension Binding where Value == String? {
    /// Treats nil as "" for editing; stores "" back as nil.
    func orEmpty() -> Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
