import SwiftUI

/// Dải điều hướng bên trái: luôn mở rộng, mỗi mục là một hàng cao với khối biểu tượng nhỏ
/// và tên đầy đủ; mục đang chọn nằm trong một viên thuốc kính.
struct SidebarView: View {
    @Binding var selection: CleanModule
    /// Cài đặt là một trang như các mục quét, nên hàng của nó cũng sáng lên khi đang mở.
    var settingsActive: Bool = false
    /// Tông màu của TRANG đang xem — dải này nở ra thì đục bằng chính màu ấy.
    var skin: ModuleSkin = ModuleSkin.skin(for: .smartScan)
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
            // Nở ra thì vẫn phải ĐỤC, nếu không chữ của thẻ bên dưới hiện xuyên qua. Nhưng đục
            // bằng chính màu của trang chứ không phải bằng màu đen: bản trước phủ đen 72–82%,
            // dải này hoá ra một mảng gần như đen đặt cạnh nền hồng/chàm/cam của trang, nhìn
            // như hai app khác nhau ghép lại. Nay là đúng gradient của trang, chỉ tối hơn một
            // bậc — vẫn tách được khỏi nội dung nhờ bóng bên phải.
            ZStack {
                // Cả hai lớp đều LUÔN tồn tại, chỉ đổi độ mờ.
                //
                // `LinearGradient` không nội suy được màu: đổi màu bên trong nó, hay dựng/gỡ
                // nó bằng `if`, đều là một cú nhảy tức thì giữa chừng animation — rê chuột qua
                // lại mép sidebar là thấy nháy màu. Độ mờ thì nội suy mượt, nên chuyển động
                // bám đúng cùng nhịp với bề ngang đang co giãn.
                LinearGradient(colors: [skin.mid, skin.deep],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(expanded ? 1 : 0)
                // Tỉ lệ đậm nhạt nằm trong chính gradient, còn mức tối chung nằm ở `opacity`:
                // thu gọn 0,22 → đen 0,12 ở đỉnh và 0,22 ở đáy, nở ra 0,44 → 0,24 và 0,44.
                LinearGradient(colors: [.black.opacity(0.55), .black],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(expanded ? 0.44 : 0.22)
            }
            // Màu chạy nhanh hơn bề ngang (0,14s so với lò xo 0,4s). Cùng nhịp với bề ngang thì
            // suốt quãng dải đang nở, nền còn nửa trong suốt và chữ của thẻ phía sau lấp ló qua
            // — cũng đọc ra thành "nháy".
            .animation(.easeOut(duration: 0.14), value: expanded)
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
