import SwiftUI

/// Settings sheet reached from the capture screen's gear icon: manual
/// language picker (no system-locale auto-detection) plus a way to reach the
/// internal camera capability console for debugging.
struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showConsole = false
    @AppStorage(VideoCodec.storageKey) private var codecRaw = VideoCodec.hevc.rawValue

    private func codecLabel(_ codec: VideoCodec) -> String {
        codec == .hevc ? loc.t(.formatHEVC) : loc.t(.formatH264)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(loc.t(.settingsLanguageSection)) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            loc.language = language
                        } label: {
                            HStack {
                                Text(language.nativeName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if loc.language == language {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                Section(loc.t(.settingsVideoFormatSection)) {
                    ForEach(VideoCodec.allCases) { codec in
                        Button {
                            codecRaw = codec.rawValue
                        } label: {
                            HStack {
                                Text(codecLabel(codec))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if codecRaw == codec.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                // Internal capability scanner — development builds only, so
                // App Review never sees debug tooling (guideline 2.2).
                #if DEBUG
                Section {
                    Button(loc.t(.settingsDeveloperConsole)) {
                        showConsole = true
                    }
                }
                #endif
            }
            .navigationTitle(loc.t(.settingsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t(.settingsDone)) { dismiss() }
                }
            }
            .sheet(isPresented: $showConsole) { ContentView() }
        }
    }
}

#Preview {
    SettingsView()
}
