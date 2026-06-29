//
//  MoveModeBar.swift
//  Mission Planning Software
//
//  Bottom controls while repositioning a waypoint via the center reticle:
//  cancel (restore original position) or drop it at the crosshair.
//

import SwiftUI

struct MoveModeBar: View {
    let onCancel: () -> Void
    let onDrop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button(action: onDrop) {
                Label("Drop Here", systemImage: "mappin.and.ellipse")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.green.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
