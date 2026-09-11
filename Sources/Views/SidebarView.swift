import SwiftUI

/// Dải điều hướng bên trái: luôn mở rộng, mỗi mục là một hàng cao với khối biểu tượng nhỏ
/// và tên đầy đủ; mục đang chọn nằm trong một viên thuốc kính.
struct SidebarView: View {
    @Binding var selection: CleanModule

    @State private var hovered: CleanModule?

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

            DiskUsageRing(expanded: true)
                .padding(.leading, 22)
                .padding(.bottom, 12)

            settingsRow
                .padding(.bottom, 14)
        }
        .frame(width: Metrics.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // Chỉ tối đi rất nhẹ: sidebar của CleanMyMac gần như chung nền với nội dung,
            // ranh giới đến từ viên thuốc và bóng chứ không từ một mảng màu khác.
            LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.20)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func row(_ m: CleanModule) -> some View {
        let isSelected = selection == m
        let skin = ModuleSkin.skin(for: m)

        return Button {
            guard selection != m else { return }
            withAnimation(Motion.standard) { selection = m }
        } label: {
            HStack(spacing: 14) {
                SidebarGlyph(icon: m.icon, colors: skin.gem, dimmed: !isSelected && hovered != m)

                Text(m.title)
                    .font(.system(size: 14.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.88))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
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
        .padding(.horizontal, 12)
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
                Text("Tuỳ chọn")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}

/// Khối biểu tượng nhỏ trong sidebar — cùng ngôn ngữ với các khối 3D lớn, thu về cỡ 32pt.
struct SidebarGlyph: View {
    let icon: String
    let colors: [Color]
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            Squircle()
                .fill(LinearGradient(colors: [colors[0], colors[1]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Squircle()
                .fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                     startPoint: .top, endPoint: .center))
            Squircle()
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: colors[2].opacity(0.7), radius: 2, y: 1)
        }
        .frame(width: 32, height: 32)
        .shadow(color: colors[1].opacity(dimmed ? 0.18 : 0.45), radius: 6, y: 2)
        .saturation(dimmed ? 0.65 : 1)
        .opacity(dimmed ? 0.82 : 1)
    }
}
