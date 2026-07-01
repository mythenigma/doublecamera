import SwiftUI

/// 选择您的相机 — pick the primary (1) and secondary (2) lens, in order.
struct CameraPickerView: View {
    let cameras: [CameraOption]
    let initialPrimary: String?
    let initialSecondary: String?
    let arePairable: (_ id1: String, _ id2: String) -> Bool
    let onConfirm: (_ primary: String, _ secondary: String) -> Void
    let onClose: () -> Void

    @State private var selection: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cameras) { camera in
                        let enabled = isSelectable(camera.id)
                        tile(camera)
                            .opacity(enabled ? 1 : 0.3)
                            .overlay(alignment: .center) {
                                if !enabled {
                                    Image(systemName: "nosign")
                                        .font(.title)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .onTapGesture { if enabled { toggle(camera.id) } }
                    }
                }
                .padding(16)
            }

            confirmBar
        }
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            selection = [initialPrimary, initialSecondary].compactMap { $0 }
        }
    }

    private var header: some View {
        ZStack {
            Text("选择您的相机")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func tile(_ camera: CameraOption) -> some View {
        let index = selection.firstIndex(of: camera.id)
        let isSelected = index != nil

        return ZStack {
            LinearGradient(
                colors: [Color(white: 0.35), Color(white: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: lensSymbol(camera))
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
        }
        .aspectRatio(0.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text(camera.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.red : Color.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            selectionBadge(number: index.map { $0 + 1 })
                .padding(12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? Color.red : Color.clear, lineWidth: 3)
        }
    }

    private func selectionBadge(number: Int?) -> some View {
        ZStack {
            Circle()
                .fill(number == nil ? Color.black.opacity(0.35) : Color.red)
                .frame(width: 30, height: 30)
            if let number {
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
    }

    private var confirmBar: some View {
        Button(action: confirm) {
            Text(selection.count == 2 ? "开始" : "请选择 2 个相机 (\(selection.count)/2)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(selection.count == 2 ? Color.red : Color.gray.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(selection.count != 2)
        .padding(16)
    }

    /// A camera is selectable when nothing is chosen yet, it is already chosen,
    /// or it can run together with everything currently chosen.
    private func isSelectable(_ id: String) -> Bool {
        if selection.isEmpty || selection.contains(id) { return true }
        return selection.allSatisfy { arePairable($0, id) }
    }

    private func toggle(_ id: String) {
        if let idx = selection.firstIndex(of: id) {
            selection.remove(at: idx)
        } else if selection.count < 2 {
            selection.append(id)
        } else {
            // Replace the oldest selection to keep at most two.
            selection.removeFirst()
            selection.append(id)
        }
    }

    private func confirm() {
        guard selection.count == 2 else { return }
        onConfirm(selection[0], selection[1])
    }

    private func lensSymbol(_ camera: CameraOption) -> String {
        switch camera.deviceType {
        case .builtInUltraWideCamera: return "camera.aperture"
        case .builtInTelephotoCamera: return "camera.metering.spot"
        default: return camera.position == .front ? "person.crop.circle" : "camera"
        }
    }
}
