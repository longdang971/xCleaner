import SwiftUI
import AppKit

/// Cài đặt là một trang bình thường của app, không phải hộp thoại.
///
/// Cảnh `Settings` của SwiftUI mở ra một cửa sổ hệ thống màu sáng, lạc hẳn với phần
/// còn lại của app. Bản trước thay nó bằng một tấm phủ lên nội dung, nhưng như vậy
/// Cài đặt vẫn là "cửa sổ trong cửa sổ". Giờ nó dùng đúng bố cục của các mục quét:
/// nền riêng, tiêu đề lớn, hàng chip lọc, rồi danh sách thẻ kính.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppState
    @Binding var tab: Tab
    @StateObject private var updates = UpdateController()

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
        var subtitle: String {
            switch self {
            case .general:  return "Cách xCleaner xoá và những gì nó nhớ về lựa chọn của bạn"
            case .scanning: return "Các mốc mà mỗi mục dùng khi đi tìm tệp"
            case .about:    return "Phiên bản và nguyên tắc làm việc của app"
            }
        }
    }

    @State private var rememberedCount = 0

    private var accent: Color { ModuleSkin.appAccent }

    var body: some View {
        VStack(spacing: 0) {
            HeroHeadline(title: "Cài đặt", subtitle: tab.subtitle) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases) { t in
                        FilterChip(title: t.title, isOn: tab == t) {
                            withAnimation(Motion.snappy) { tab = t }
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 22)

            ScrollView {
                Group {
                    switch tab {
                    case .general:  general
                    case .scanning: scanning
                    case .about:    about
                    }
                }
                // Cột hẹp hơn cửa sổ: một hàng công tắc kéo dài cả nghìn điểm thì
                // cái công tắc trôi tít sang bên kia màn hình, chẳng còn dính gì với nhãn.
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, 40)
                .id(tab)
                .transition(.opacity)
            }
            .scrollIndicators(.never)
        }
        .animation(Motion.gentle, value: tab)
        .onAppear {
            rememberedCount = SelectionMemory.shared.count
            if app.requestUpdateCheck { app.requestUpdateCheck = false; updates.check() }
        }
        .onChange(of: app.requestUpdateCheck) { want in
            guard want else { return }
            app.requestUpdateCheck = false
            tab = .about
            updates.check()
        }
    }

    // MARK: Chung

    private var general: some View {
        VStack(spacing: 14) {
            SettingCard {
                SettingToggle(
                    title: "Chuyển vào Thùng rác thay vì xoá vĩnh viễn",
                    detail: "Bật thì dung lượng chỉ thực sự được giải phóng sau khi bạn đổ Thùng rác. Tệp trong thư mục hệ thống vẫn bị xoá thẳng vì Thùng rác không nhận tệp của root.",
                    isOn: $settings.moveToTrash, accent: accent)
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
                    ActionButton(title: "Quên hết", isEnabled: rememberedCount > 0) {
                        SelectionMemory.shared.forgetAll()
                        rememberedCount = 0
                    }
                }
            }

            SettingCard {
                SettingToggle(
                    title: "Dọn tàn dư khi tôi xoá ứng dụng",
                    detail: "Khi bạn kéo một ứng dụng vào Thùng rác, xCleaner hiện một cửa sổ nhỏ liệt kê những tệp app đó để lại để dọn luôn. Để làm được việc này, xCleaner ở lại chạy nền sau khi bạn đóng cửa sổ — không có icon ở Dock.",
                    isOn: $settings.smartDelete, accent: accent)
            }
            .onChange(of: settings.smartDelete) {
                SmartDeleteController.shared.applySetting()
            }

            // Cấp rồi thì thẻ này biến mất: nó là một việc phải làm, không phải một tuỳ chọn để
            // xem lại. Còn đó mà không bấm được gì thì người dùng tưởng mình chưa cấp xong.
            if !app.hasFullDiskAccess {
              SettingCard {
                SettingRow(title: "Toàn quyền truy cập đĩa",
                           detail: "Cấp quyền này để xCleaner đọc được Thùng rác, dữ liệu Safari, Mail và danh sách mở gần đây của các app. Sau khi cấp, thoát hẳn rồi mở lại app.") {
                    ActionButton(title: "Mở Cài đặt…", systemImage: "arrow.up.forward.app") {
                        // Dùng chung một đường dẫn với các chỗ khác trong app: bảng Cài đặt
                        // hệ thống đã đổi định danh ở macOS 13, chuỗi cũ mở ra trang khác.
                        openFullDiskAccess()
                    }
                }
              }
            }
        }
        .animation(Motion.gentle, value: app.hasFullDiskAccess)
        .onAppear { app.refreshFullDiskAccess() }
    }

    // MARK: Quét

    private var scanning: some View {
        VStack(spacing: 14) {
            SettingCard {
                SettingStepper(title: "Tệp tải về coi là cũ sau",
                               detail: "Tệp trong thư mục Tải về lâu hơn mốc này sẽ được đề nghị dọn.",
                               value: $settings.oldDownloadDays,
                               range: 7...365, step: 7, unit: "ngày", accent: accent)
                SettingDivider()
                SettingStepper(title: "Tệp lớn tính từ",
                               detail: "Mục Tệp lớn & cũ bỏ qua mọi tệp nhỏ hơn mốc này.",
                               value: $settings.largeMinMB,
                               range: 10...2000, step: 10, unit: "MB", accent: accent)
                SettingDivider()
                SettingStepper(title: "Bỏ qua tệp trùng nhỏ hơn",
                               detail: "Đặt mốc cao hơn thì quét trùng lặp nhanh hơn nhiều vì bớt được rất nhiều tệp vụn.",
                               value: $settings.duplicateMinMB,
                               range: 1...500, step: 1, unit: "MB", accent: accent)
            }
        }
    }

    // MARK: Giới thiệu

    private var about: some View {
        VStack(spacing: 18) {
            // Cùng huy hiệu lớn như màn khởi đầu của mỗi mục, chỉ nhỏ hơn một nấc.
            // Tô màu của Quét thông minh chứ không phải xám của trang: đây là chỗ duy nhất
            // nói về chính app, nên nó mang màu nhận diện của app.
            HeroEmblem(icon: "wand.and.sparkles",
                       gem: ModuleSkin.skin(for: .smartScan).gem, size: 120)

            VStack(spacing: 4) {
                Text("xCleaner")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text("Phiên bản \(updates.currentVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textFaint)
            }

            SettingCard {
                UpdateRow(updates: updates, accent: accent)
            }

            SettingCard {
                VStack(alignment: .leading, spacing: 12) {
                    AboutPoint(icon: "wifi.slash",
                               title: "Không có gì rời khỏi máy",
                               detail: "App chỉ ra mạng đúng một lần: khi bạn bấm kiểm tra cập nhật. Không có máy chủ nào nhận dữ liệu của bạn.")
                    AboutPoint(icon: "checkmark.shield.fill",
                               title: "Mọi đường dẫn đều qua hàng rào kiểm tra",
                               detail: "Thư mục nhà, thư mục hệ thống và các mục thiết yếu được đối chiếu trước khi bất cứ thứ gì bị xoá.")
                    AboutPoint(icon: "lock.fill",
                               title: "Thư mục hệ thống cần mật khẩu",
                               detail: "Phần nằm ngoài thư mục nhà chỉ bị đụng tới sau khi bạn nhập mật khẩu quản trị.")
                }
                .padding(16)
            }
        }
        .padding(.top, 4)
    }
}

/// Hàng "Kiểm tra cập nhật" trong tab Giới thiệu.
///
/// Một hàng duy nhất đổi vai theo trạng thái, thay vì mở thêm cửa sổ: app này vốn đã bỏ hộp
/// thoại để mọi thứ nằm trong cùng một cửa sổ.
private struct UpdateRow: View {
    @ObservedObject var updates: UpdateController
    var accent: Color

    var body: some View {
        SettingRow(title: title, detail: detail) {
            trailing
        }
    }

    private var title: String {
        switch updates.phase {
        case .idle:                return "Kiểm tra cập nhật"
        case .checking:            return "Đang hỏi GitHub…"
        case .upToDate:            return "Bạn đang dùng bản mới nhất"
        case .available(let tag):  return "Đã có bản \(tag)"
        case .downloading:         return "Đang tải bản mới…"
        case .readyToRestart:      return "Sắp khởi động lại để cài"
        case .failed:              return "Không kiểm tra được"
        }
    }

    private var detail: String {
        switch updates.phase {
        case .idle:
            return "Bản mới được tải thẳng từ trang phát hành của kho mã, không qua máy chủ nào khác."
        case .checking:
            return "Đang xem trang phát hành mới nhất."
        case .upToDate:
            var s = "Phiên bản \(updates.currentVersion) là bản mới nhất đang có."
            if let at = updates.lastChecked {
                s += " Kiểm lúc \(Fmt.time(at))."
            }
            return s
        case .available:
            guard let r = updates.release else { return "" }
            var s = "Bạn đang dùng \(updates.currentVersion)."
            if r.sizeBytes > 0 { s += " Gói tải về \(Fmt.size(r.sizeBytes))." }
            let notes = UpdateService.plainText(r.notes)
            if !notes.isEmpty {
                s += "\n" + notes.split(separator: "\n").prefix(4).joined(separator: "\n")
            }
            return s
        case .downloading(let p):
            return "Đã tải \(Int(p * 100))%."
        case .readyToRestart:
            return "xCleaner sẽ tự đóng rồi mở lại ở bản mới."
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch updates.phase {
        case .checking, .downloading:
            ProgressView().controlSize(.small).tint(.white)
        case .available:
            HStack(spacing: 8) {
                ActionButton(title: "Xem trang phát hành", systemImage: "arrow.up.forward.app") {
                    updates.openReleasesPage()
                }
                ActionButton(title: "Cài bản mới", systemImage: "arrow.down.circle",
                             kind: .prominent, accent: accent) {
                    updates.downloadAndInstall()
                }
            }
        case .readyToRestart:
            EmptyView()
        default:
            ActionButton(title: "Kiểm tra", systemImage: "arrow.clockwise") { updates.check() }
        }
    }
}

// MARK: - Mảnh ghép của trang Cài đặt

/// Khối bo tròn gom vài hàng liên quan. Dùng đúng thẻ kính của các màn kết quả
/// nên trang này nằm cùng một hệ với phần còn lại của app.
private struct SettingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .glass()
    }
}

private struct SettingDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

/// Hàng tiêu chuẩn: tên và mô tả bên trái, thứ điều khiển bên phải.
private struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textFaint)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing.padding(.top, 1)
        }
        .padding(16)
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

/// Một điều cam kết ở tab Giới thiệu: ký hiệu nhỏ, tên, rồi một câu giải thích.
private struct AboutPoint: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textFaint)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.24)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(enabled ? Palette.text : Palette.textFaint.opacity(0.5))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 0.16 : 0.05)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
