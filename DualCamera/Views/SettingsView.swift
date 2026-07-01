import SwiftUI

/// Settings sheet reached from the capture screen's gear icon: manual
/// language picker (no system-locale auto-detection) plus a way to reach the
/// internal camera capability console for debugging.
struct SettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showConsole = false

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

                Section {
                    Button(loc.t(.settingsDeveloperConsole)) {
                        showConsole = true
                    }
                }
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
