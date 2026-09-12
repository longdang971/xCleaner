import SwiftUI

/// Dải điều hướng bên trái: luôn mở rộng, mỗi mục là một hàng cao với khối biểu tượng nhỏ
/// và tên đầy đủ; mục đang chọn nằm trong một viên thuốc kính.
struct SidebarView: View {
    @Binding var selection: CleanModule
    /// Cài đặt là một trang như các mục quét, nên hàng của nó cũng sáng lên khi đang mở.
    var settingsActive: Bool = false
    var onOpenSettings: () -> Void = {}

    @State private var hovered: CleanModule?
    @State private var settingsHovered = false
    @State private var expanded = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCLEANER_SIDEBAR"] == "expanded"
        #else
        return false
        #endif
    }()

    private var width: CGFloat { expanded ? Metrics.sidebarExpanded : Metrics.sidebarWidth }

    private let cleaning: [CleanModule] = [.smartScan]
    private let tools: [CleanModule] = [.uninstaller, .startup, .largeOld, .duplicates]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chừa chỗ cho ba nút hệ thống
            Spacer().frame(height: Metrics.titleBarHeight + 26)

            // Một cụm liền: khoảng cách giữa Quét thông minh và ba mục dưới bằng đúng
            // khoảng cách giữa chúng với nhau.
            VStack(spacing: 4) {
                ForEach(cleaning) { row($0) }
                ForEach(tools) { row($0) }
            }

            Spacer(minLength: 16)

            DiskUsageRing(expanded: expanded)
                .padding(.leading, expanded ? 26 : 24)
                .padding(.bottom, 12)

            settingsRow
                .padding(.bottom, 14)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // Thu gọn thì gần như chung nền với nội dung; nở ra thì phải đục hẳn,
            // nếu không chữ của thẻ bên dưới sẽ hiện xuyên qua.
            LinearGradient(colors: [.black.opacity(expanded ? 0.72 : 0.12),
                                    .black.opacity(expanded ? 0.82 : 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 24, x: 6)
        .onHover { inside in
            withAnimation(Motion.standard) { expanded = inside }
            if !inside { hovered = nil }
        }
    }

    private func row(_ m: CleanModule) -> some View {
        let isSelected = selection == m && !settingsActive
        let skin = ModuleSkin.skin(for: m)

        return Button {
            guard !isSelected else { return }
            withAnimation(Motion.standard) { selection = m }
        } label: {
            HStack(spacing: expanded ? 14 : 0) {
                SidebarGlyph(icon: m.icon, colors: skin.gem,
                             active: isSelected, hovering: hovered == m)
                    .frame(maxWidth: expanded ? nil : .infinity)

                if expanded {
                    Text(m.title)
                        .font(.system(size: 14.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : Color.white.opacity(0.88))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }

                if expanded { Spacer(minLength: 0) }
            }
            .padding(.horizontal, expanded ? 16 : 6)
            .frame(height: 46)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
                        )
                } else if hovered == m {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, expanded ? 12 : 14)
        .help(expanded ? "" : m.title)
        .onHover { h in
            withAnimation(Motion.gentle) { hovered = h ? m : (hovered == m ? nil : hovered) }
        }
    }

    /// Cùng hình dạng, cùng chiều cao, cùng viên thuốc chọn như các mục ở trên —
    /// chỉ khác chỗ đứng: nó nằm dưới đáy, tách khỏi cụm quét.
    private var settingsRow: some View {
        Button {
            guard !settingsActive else { return }
            onOpenSettings()
        } label: {
            HStack(spacing: expanded ? 14 : 0) {
                SidebarGlyph(icon: "gearshape", colors: ModuleSkin.settings.gem,
                             active: settingsActive, hovering: settingsHovered)
                    .frame(maxWidth: expanded ? nil : .infinity)

                if expanded {
                    Text("Cài đặt")
                        .font(.system(size: 14.5, weight: settingsActive ? .semibold : .regular))
                        .foregroundStyle(settingsActive ? .white : Color.white.opacity(0.88))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, expanded ? 16 : 6)
            .frame(height: 46)
            .background {
                if settingsActive {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
                        )
                } else if settingsHovered {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, expanded ? 12 : 14)
        .help(expanded ? "" : "Cài đặt")
        .onHover { h in withAnimation(Motion.gentle) { settingsHovered = h } }
    }
}

/// Biểu tượng trong sidebar: luôn là ký hiệu trơn, không khối, không viền.
/// Mục đang chọn thì chính ký hiệu được tô màu của mục đó.
struct SidebarGlyph: View {
    let icon: String
    let colors: [Color]
    var active: Bool = false
    var hovering: Bool = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: active ? 17 : 15.5, weight: active ? .semibold : .medium))
            .foregroundStyle(active
                             ? AnyShapeStyle(LinearGradient(colors: [colors[0], colors[1]],
                                                            startPoint: .top,
                                                            endPoint: .bottom))
                             : AnyShapeStyle(Color.white.opacity(hovering ? 0.95 : 0.66)))
            .shadow(color: active ? colors[1].opacity(0.6) : .clear, radius: 7)
            .frame(width: 32, height: 32)
            .animation(Motion.gentle, value: active)
    }
}
