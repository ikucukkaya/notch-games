import SwiftUI

struct OnboardingView: View {
    @State private var doNotShowAgain = true
    let onPlay: (Bool) -> Void
    let onDismiss: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Your desktop now has a basketball hoop.")
                    .font(.title2.weight(.bold))
                Text("A tiny break, right on your desktop.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                instruction("1", "Open the basketball in the menu bar.")
                instruction("2", "Choose Play.")
                instruction("3", "Drag the ball backward, then release.")
                instruction("esc", "Press Escape at any time to exit.")
            }
            .padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

            Toggle("Do not show again", isOn: $doNotShowAgain)

            HStack {
                Button("Not Now") {
                    onDismiss(doNotShowAgain)
                }
                Spacer()
                Button("Let’s Play") {
                    onPlay(doNotShowAgain)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 420)
    }

    private func instruction(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(symbol)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .frame(width: 28, height: 28)
                .background(.orange.opacity(0.16), in: Circle())
            Text(text)
        }
    }
}
