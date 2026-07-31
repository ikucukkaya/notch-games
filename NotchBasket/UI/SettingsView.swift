import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesService
    let onGameplayPreferenceChanged: () -> Void
    let onGeometryChanged: () -> Void
    let onResetScores: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                title
                gameplaySection
                audioSection
                appearanceSection
                generalSection
            }
            .padding(24)
        }
        .frame(width: 460, height: 570)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NotchBasket Settings")
                .font(.title2.weight(.semibold))
            Text("Tune the toy without cluttering the desktop.")
                .foregroundStyle(.secondary)
        }
    }

    private var gameplaySection: some View {
        settingsGroup("Gameplay") {
            Picker("Mode", selection: $preferences.playMode) {
                ForEach(PlayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Show aim guide", isOn: $preferences.aimGuideEnabled)
                .onChange(of: preferences.aimGuideEnabled) { _, _ in onGameplayPreferenceChanged() }

            Picker("Gravity", selection: $preferences.gravityPreset) {
                ForEach(GravityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .onChange(of: preferences.gravityPreset) { _, _ in onGameplayPreferenceChanged() }

            labeledSlider(
                "Launch sensitivity",
                value: $preferences.launchSensitivity,
                range: 0.5...1.5,
                valueText: String(format: "%.1fx", preferences.launchSensitivity)
            )

            labeledSlider(
                "Hoop horizontal offset",
                value: $preferences.hoopHorizontalOffset,
                range: -180...180,
                valueText: "\(Int(preferences.hoopHorizontalOffset)) pt"
            )
            .onChange(of: preferences.hoopHorizontalOffset) { _, _ in onGeometryChanged() }

            labeledSlider(
                "Hoop height",
                value: $preferences.hoopVerticalOffset,
                range: PreferencesService.hoopVerticalOffsetRange,
                valueText: "\(Int(preferences.hoopVerticalOffset)) pt"
            )
            .onChange(of: preferences.hoopVerticalOffset) { _, _ in onGeometryChanged() }
        }
    }

    private var audioSection: some View {
        settingsGroup("Audio & Haptics") {
            Toggle("Sound effects", isOn: $preferences.soundEnabled)
                .onChange(of: preferences.soundEnabled) { _, _ in onGameplayPreferenceChanged() }
            labeledSlider(
                "Master volume",
                value: $preferences.masterVolume,
                range: 0...1,
                valueText: "\(Int(preferences.masterVolume * 100))%"
            )
            Toggle("Haptic feedback", isOn: $preferences.hapticsEnabled)
        }
    }

    private var appearanceSection: some View {
        settingsGroup("Appearance") {
            Toggle("Show score", isOn: $preferences.showScore)
                .onChange(of: preferences.showScore) { _, _ in onGameplayPreferenceChanged() }
            Toggle("Reduced visual effects", isOn: $preferences.reducedEffects)
            Toggle("Debug geometry and physics", isOn: $preferences.debugGeometry)
                .onChange(of: preferences.debugGeometry) { _, _ in onGameplayPreferenceChanged() }
        }
    }

    private var generalSection: some View {
        settingsGroup("General") {
            Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
            HStack {
                Text("Global shortcut")
                Spacer()
                Text("⌃⌥B")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            Button("Reset lifetime scores", role: .destructive) {
                preferences.resetHighScores()
                onResetScores()
            }
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 11) {
                content()
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
    }
}
