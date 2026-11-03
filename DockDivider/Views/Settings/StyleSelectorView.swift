//
//  StyleSelectorView.swift
//  DockDivider
//
//  Created by Jack Bogle on 10/27/26.
//

import SwiftUI

struct StyleSelectorView: View {
    @Binding var style: DividerStyle

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.headline)

            Picker("Style", selection: $style.deferred()) {
                ForEach(DividerStyle.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("style-picker")
            .frame(maxWidth: .infinity)
        }
    }
}
