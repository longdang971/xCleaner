import SwiftUI
import AppKit

/// Bảng tuỳ chọn nằm ngay trong cửa sổ chính.
///
/// Cảnh `Settings` của SwiftUI mở ra một cửa sổ hệ thống màu sáng, lạc hẳn với phần
/// còn lại của app, nên xCleaner tự vẽ bảng này và phủ lên nội dung như một hộp thoại.
struct SettingsPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var tab: Tab
    var onClose: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case general, scanning, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "Chung"
            case .scanning: return "Quét"
            case .about: return "Giới thiệu"
            }
        }
        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .scanning: return "magnifyingglass"
            case .about: return "info.circle"
            }
        }
    }

    @State private var rememberedCount = 0
    @Namespace private var tabPill

    private var accent: Color { ModuleSkin.appAccent }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.12))
                ScrollView {
                    Group {
                        switch tab {
                        case .general:  general
                        case .scanning: scanning
                        case .about:    about
                        }
                    }
                    .padding(22)
                }
                .scrollIndicators(.never)
            }
            .frame(width: 560, height: 520)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: "#151A24").opacity(0.98))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear { rememberedCount = SelectionMemory.shared.count }
    }

    // MARK: Đầu bảng

    private var header: some View {
        HStack(spacing: 12) {
            Text("Cài đặt")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.text)

            Spacer(minLength: 0)

            // Ba thẻ dạng viên thuốc, viên sáng trượt sang mục được chọn.
            HStack(spacing: 2) {
                ForEach(Tab.allCases) { t in
                    Button { withAnimation(Motion.snappy) { tab = t } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.icon).font(.system(size: 10.5, weight: .semibold))
                            Text(t.title).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(tab == t ? Palette.text : Palette.textFaint)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background {
                            if tab == t {
                                Capsule().fill(Color.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "tab", in: tabPill)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.24)))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textSecond)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    // MARK: Chung

    private var general: some View {
        VStack(spacing: 12) {
            SettingCard {
                SettingToggle(
                    title: "Chuyển vào Thùng rác thay vì xoá vĩnh viễn",
                    detail: "Bật thì dung lượng chỉ thực sự được giải phóng sau khi bạn đổ Thùng rác. Tệp trong thư mục hệ thống vẫn bị xoá thẳng vì Thùng rác không nhận tệp của root.",
                    isOn: $settings.moveToTrash, accent: accent)
                SettingDivider()
                SettingToggle(
                    title: "Hỏi lại trước khi dọn",
                    detail: "Hiện hộp xác nhận kèm số mục và dung lượng trước mỗi lần xoá.",
                    isOn: $settings.confirmBeforeClean, accent: accent)
            }

            SettingCard {
                SettingToggle(
                    title: "Ghi nhớ lựa chọn của tôi",
                    detail: "Mục bạn tự tay bỏ chọn hoặc chọn thêm sẽ giữ nguyên ở lần quét sau. Chỉ phần khác với đề xuất mặc định được ghi lại.",
                    isOn: $settings.rememberChoices, accent: accent)
                SettingDivider()
                SettingRow(title: "Đang nhớ \(rememberedCount) mục",
                           detail: rememberedCount == 0
                            ? "Chưa có lựa chọn nào khác với đề xuất mặc định."
                            : "Quên hết để mọi mục quay lại trạng thái xCleaner đề xuất.") {
                    PillButton(title: "Quên hết", isEnabled: rememberedCount > 0) {
                        SelectionMemory.shared.forgetAll()
                        rememberedCount = 0
                    }
                }
            }

            SettingCard {
                SettingRow(title: "Toàn quyền truy cập đĩa",
                           detail: "Cấp quyền này để xCleaner đọc được Thùng rác, dữ liệu Safari, Mail và danh sách mở gần đây của các app. Sau khi cấp, thoát hẳn rồi mở lại app.") {
                    PillButton(title: "Mở Cài đặt…", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
            }
        }
    }

    // MARK: Quét

    private var scanning: some View {
        VStack(spacing: 12) {
            SettingCard {
                SettingStepper(title: "Tệp tải về coi là cũ sau",
                               detail: "Tệp trong thư mục Tải về lâu hơn mốc này sẽ được đề nghị dọn.",
                               value: $settings.oldDownloadDays,
                               range: 7...365, step: 7, unit: "ngày", accent: accent)
            }
            SettingCard {
                SettingStepper(title: "Tệp lớn tính từ",
                               detail: "Mục Tệp lớn & cũ bỏ qua mọi tệp nhỏ hơn mốc này.",
                               value: $settings.largeMinMB,
                               range: 10...2000, step: 10, unit: "MB", accent: accent)
            }
            SettingCard {
                SettingStepper(title: "Bỏ qua tệp trùng nhỏ hơn",
                               detail: "Đặt mốc cao hơn thì quét trùng lặp nhanh hơn nhiều vì bớt được rất nhiều tệp vụn.",
                               value: $settings.duplicateMinMB,
                               range: 1...500, step: 1, unit: "MB", accent: accent)
            }
        }
    }

    // MARK: Giới thiệu

    private var about: some View {
        VStack(spacing: 14) {
            HeroEmblem(icon: "wand.and.sparkles",
                       gem: ModuleSkin.skin(for: .smartScan).gem,
                       size: 92)
                .padding(.top, 10)

            Text("xCleaner")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.text)

            Text("Phiên bản \((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0")")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textFaint)

            Text("Ứng dụng không gửi bất cứ dữ liệu nào ra ngoài máy. Mọi thao tác xoá đều đi qua một hàng rào kiểm tra đường dẫn, và thư mục hệ thống chỉ bị đụng tới sau khi bạn nhập mật khẩu quản trị.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecond)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 22)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Mảnh ghép của bảng tuỳ chọn

/// Khối bo tròn gom vài hàng liên quan, cùng kiểu với thẻ kết quả nhưng nhạt hơn.
private struct SettingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.09))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// Hàng tiêu chuẩn: tên và mô tả bên trái, thứ điều khiển bên phải.
private struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textFaint)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing.padding(.top, 1)
        }
        .padding(14)
    }
}

private struct SettingToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool
    var accent: Color

    var body: some View {
        SettingRow(title: title, detail: detail) {
            AccentSwitch(isOn: $isOn, accent: accent)
        }
    }
}

/// Công tắc tự vẽ. `Toggle(.switch)` của hệ thống không nhận `tint` một cách đáng tin
/// trên nền tối tuỳ biến, bật lên vẫn ra màu xám nhạt thay vì màu accent của app.
private struct AccentSwitch: View {
    @Binding var isOn: Bool
    var accent: Color

    var body: some View {
        Button { withAnimation(Motion.snappy) { isOn.toggle() } } label: {
            Capsule()
                .fill(isOn ? accent : Color.white.opacity(0.16))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.42 : 0.16), lineWidth: 1))
                .frame(width: 42, height: 25)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 19, height: 19)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(.horizontal, 3)
                }
                .shadow(color: isOn ? accent.opacity(0.5) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Bộ tăng giảm tự vẽ: hai nút tròn kẹp lấy con số.
/// `Stepper` của hệ thống mang mũi tên kiểu Aqua, lạc hẳn với phần còn lại của app.
private struct SettingStepper: View {
    var title: String
    var detail: String?
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var unit: String
    var accent: Color

    var body: some View {
        SettingRow(title: title, detail: detail) {
            HStack(spacing: 4) {
                button("minus", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }
                Text("\(value) \(unit)")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .frame(minWidth: 66)
                button("plus", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.24)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Palette.text : Palette.textFaint.opacity(0.5))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.13 : 0.05)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
