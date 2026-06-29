//
//  Color+Hex.swift
//  Mission Planning Software
//
//  Bridges the model's RGB hex strings (e.g. "FF3B30") to SwiftUI Color.
//

import SwiftUI

extension Color {
    /// Create a Color from a 6-digit RGB hex string (with or without leading '#').
    /// Falls back to red on malformed input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .red
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
