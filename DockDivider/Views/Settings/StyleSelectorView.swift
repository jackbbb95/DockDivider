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

            Picker("Style", selection: Binding(
                get: { style },
                set: { newStyle in
                    guard style != newStyle else { return }
                    DispatchQueue.main.async {
                        style = newStyle
                    }
                }
            )) {
                ForEach(DividerStyle.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }
}
