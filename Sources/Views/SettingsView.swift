import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            general.tabItem { Label("Chung", systemImage: "gearshape") }
            scanning.tabItem { Label("Quét", systemImage: "magnifyingglass") }
            about.tabItem { Label("Giới thiệu", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 330)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Chuyển vào Thùng rác thay vì xoá vĩnh viễn", isOn: $settings.moveToTrash)
                Text("Bật tuỳ chọn này thì dung lượng chỉ thực sự được giải phóng sau khi bạn đổ Thùng rác. Tệp nằm trong thư mục hệ thống luôn bị xoá thẳng vì Thùng rác không nhận tệp của root.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Section {
                Toggle("Hỏi lại trước khi dọn", isOn: $settings.confirmBeforeClean)
            }
            Section {
                HStack {
                    Text("Quyền truy cập toàn bộ đĩa")
                    Spacer()
                    Button("Mở Cài đặt Hệ thống…") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
                Text("Cấp quyền này để xCleaner đọc được dữ liệu Safari, Mail và một vài thư mục được macOS bảo vệ.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
        .formStyle(.grouped)
    }

    private var scanning: some View {
        Form {
            Section("Tệp tải về") {
                Stepper("Coi là cũ sau \(settings.oldDownloadDays) ngày",
                        value: $settings.oldDownloadDays, in: 7...365, step: 7)
            }
            Section("Tệp lớn") {
                Stepper("Chỉ hiện tệp từ \(settings.largeMinMB) MB trở lên",
                        value: $settings.largeMinMB, in: 10...2000, step: 10)
            }
            Section("Tệp trùng lặp") {
                Stepper("Bỏ qua tệp nhỏ hơn \(settings.duplicateMinMB) MB",
                        value: $settings.duplicateMinMB, in: 1...500, step: 1)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.accentGradient)
                    .frame(width: 64, height: 64)
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text("xCleaner").font(.system(size: 20, weight: .bold))
            Text("Phiên bản \((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0")")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            Text("Ứng dụng không gửi bất cứ dữ liệu nào ra ngoài máy. Mọi thao tác xoá đều đi qua một hàng rào kiểm tra đường dẫn, và thư mục hệ thống chỉ bị đụng tới sau khi bạn nhập mật khẩu quản trị.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
