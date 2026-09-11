import SwiftUI

/// Dải điều hướng bên trái: luôn mở rộng, mỗi mục là một hàng cao với khối biểu tượng nhỏ
/// và tên đầy đủ; mục đang chọn nằm trong một viên thuốc kính.
struct SidebarView: View {
    @Binding var selection: CleanModule

    @State private var hovered: CleanModule?
    @State private var expanded = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCLEANER_SIDEBAR"] == "expanded"
        #else
        return false
        #endif
    }()

    private var width: CGFloat { expanded ? Metrics.sidebarExpanded : Metrics.sidebarWidth }

    private let cleaning: [CleanModule] = [.smartScan, .systemJunk, .trashDownloads, .privacy]
    private let tools: [CleanModule] = [.uninstaller, .largeOld, .duplicates]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chừa chỗ cho ba nút hệ thống
            Spacer().frame(height: Metrics.titleBarHeight + 26)

            VStack(spacing: 4) {
                ForEach(cleaning) { row($0) }
            }

            Spacer().frame(height: 26)

            VStack(spacing: 4) {
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
        let isSelected = selection == m
        let skin = ModuleSkin.skin(for: m)

        return Button {
            guard selection != m else { return }
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
            .padding(.horizontal, expanded ? 16 : 8)
            .frame(height: 52)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
                        )
                } else if hovered == m {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, expanded ? 12 : 8)
        .help(expanded ? "" : m.title)
        .onHover { h in
            withAnimation(Motion.gentle) { hovered = h ? m : (hovered == m ? nil : hovered) }
        }
    }

    private var settingsRow: some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 32)
                    .frame(maxWidth: expanded ? nil : .infinity)
                if expanded {
                    Text("Tuỳ chọn")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize().transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, expanded ? 16 : 8)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
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
