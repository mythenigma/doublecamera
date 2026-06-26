import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Camera Capability Console")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Project shell is ready. Camera scanning and capture controls will appear here.")
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("DualCamera")
        }
    }
}

#Preview {
    ContentView()
}
