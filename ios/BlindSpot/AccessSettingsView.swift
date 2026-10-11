import SwiftUI

struct AccessSettingsView: View {
    @AppStorage("blindspot.spokenDirections") private var spokenDirections = true
    @AppStorage("blindspot.haptics") private var haptics = true
    @AppStorage("blindspot.largeText") private var largeText = false
    @AppStorage("blindspot.highContrast") private var highContrast = false

    var body: some View {
        Form {
            Section("Guidance") {
                Toggle("Spoken directions", isOn: $spokenDirections)
                    .accessibilityHint("Reads route directions aloud.")
                Toggle("Haptic cues", isOn: $haptics)
                    .accessibilityHint("Uses taps for route landmarks and possible nearby surfaces.")
            } footer: {
                Text("Spoken navigation uses Apple's on-device speech synthesizer. A future voice service can replace it.")
            }

            Section("Display") {
                Toggle("Larger text", isOn: $largeText)
                Toggle("High contrast", isOn: $highContrast)
            } footer: {
                Text("These settings are saved on this device. VoiceOver and system accessibility settings remain available.")
            }

            Section("Privacy and safety") {
                Label("Room scans are stored locally", systemImage: "iphone.and.arrow.forward")
                Text("Camera access is used while you scan or navigate. BlindSpot does not upload maps.")
                    .font(.body)
                Text("This prototype is not safety-certified. Continue using your mobility aid and stop whenever ARKit tracking is uncertain.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle("Access settings")
    }
}

struct BlindSpotButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? Color(red: 0.08, green: 0.38, blue: 0.30) : Color(uiColor: .secondarySystemBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .accessibilityAddTraits(.isButton)
    }
}
