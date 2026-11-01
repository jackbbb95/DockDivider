//
//  OnboardingView.swift
//  DockDivider
//

import SwiftUI
import AppKit

/// One-time welcome sheet explaining the drag-to-Dock model and offering a few
/// starting styles. Nothing here is required to use the app; it exists so a new
/// user does not have to infer the workflow.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            steps

            Divider()

            HStack {
                Text("DockDivider never edits your Dock preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Get Started") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onDisappear {
            appState.completeOnboarding()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to DockDivider")
                    .font(.title2.weight(.semibold))
                Text("Build a divider on the left, then drag it into your Dock.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingStep(
                number: 1,
                title: "Design it",
                message: "Pick a line, dashes, a dot, a label, or a blank spacer. Colors and size update live."
            )
            OnboardingStep(
                number: 2,
                title: "Drag it into the Dock",
                message: "Drag the preview in “Drag Me to Dock” onto your Dock. DockDivider creates the app for you."
            )
            OnboardingStep(
                number: 3,
                title: "Remove it whenever you like",
                message: "Right-click the divider in the Dock, then choose Options > Remove from Dock. Clean Up… reviews leftovers."
            )
        }
    }
}

private struct OnboardingStep: View {
    let number: Int
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
