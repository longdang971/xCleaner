import SwiftUI
import AppKit

struct UninstallerView: View {
    @ObservedObject var store: UninstallStore
    @EnvironmentObject private var settings: AppSettings
    @State private var confirming = false

    private let skin = ModuleSkin.skin(for: .uninstaller)

    var body: some View {
        browser
            .onAppear { if store.apps.isEmpty && !store.isLoading { store.load() } }
        .overlay {
            if let pending = store.pendingQuit {
                AppDialog(accent: ModuleSkin.appAccent,
                          primaryTitle: "Thoát \(pending.name)",
                          secondaryTitle: "Dừng",
                          onPrimary: { store.quitPendingApp() },
                          onSecondary: { store.cancelPendingQuit() }) {
                    VStack(spacing: 14) {
                        if let icon = AppIconProvider.icon(forBundleID: pending.bundleID) {
                            Image(nsImage: icon)
                                .resizable().interpolation(.high)
                                .frame(width: 62, height: 62)
                                .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
                        }
                        Text("\(pending.name) đang mở")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Thoát ứng dụng rồi xCleaner gỡ tiếp. Nếu để nguyên, app sẽ ghi lại tuỳ chọn lúc thoát và một phần tệp vừa xoá quay trở lại.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textSecond)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in store.load() }
        .animation(Motion.standard, value: store.pendingQuit)
        .confirmationDialog("Gỡ \(store.selectedApp?.name ?? "")?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Gỡ ứng dụng", role: .destructive) { store.uninstall() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text(confirmText)
        }
    }

    private var confirmText: String {
        var s = "\(store.leftovers.filter(\.isSelected).count) mục · \(Fmt.size(store.selectedLeftoverSize))"
        if store.leftovers.contains(where: { $0.isSelected && $0.requiresAdmin }) {
            s += "\nMột số tệp nằm ngoài thư mục nhà, macOS sẽ hỏi mật khẩu quản trị."
        }
        return s
    }

    private var browser: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, 14)

            HStack(spacing: 14) {
                appList.frame(width: 320)
                detail
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.bottom, Metrics.contentPadding)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            SearchField(placeholder: "Tìm ứng dụng", text: $store.search, width: 236)

            sortButton

            FilterChip(title: "App hệ thống", isOn: store.showSystemApps) {
                withAnimation(Motion.snappy) { store.showSystemApps.toggle() }
            }

            Spacer(minLength: 12)

            if store.isLoading {
                ProgressView().controlSize(.small).tint(.white)
                Text(store.statusText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textFaint)
                    .lineLimit(1)
                    .frame(maxWidth: 240, alignment: .leading)
            } else {
                Text("\(store.filteredApps.count) ứng dụng")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textFaint)

                IconToolbar(actions: [
                    .init(icon: "arrow.clockwise", help: "Đọc lại danh sách ứng dụng") {
                        store.load()
                    }
                ])
            }
        }
    }

    /// Nút sắp xếp xoay vòng qua ba tiêu chí. `Menu` của SwiftUI không nhận chiều cao mình
    /// đặt và còn nuốt luôn mũi tên trong nhãn, nên nó thấp hơn hẳn các nút bên cạnh.
    private var sortButton: some View {
        Button {
            let all = UninstallStore.Sort.allCases
            let next = (all.firstIndex(of: store.sort).map { $0 + 1 } ?? 0) % all.count
            withAnimation(Motion.snappy) { store.sort = all[next] }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(store.sort.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.12)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 2.5, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Đổi cách sắp xếp")
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.filteredApps) { app in
                    AppRow(app: app, isSelected: store.selectedApp?.url == app.url, skin: skin) {
                        withAnimation(Motion.gentle) { store.select(app) }
                    }
                }
            }
            .padding(7)
        }
        .scrollIndicators(.never)
        .glass()
    }

    @ViewBuilder
    private var detail: some View {
        if let app = store.selectedApp {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    AppIconView(url: app.url, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        Text(app.version.isEmpty ? app.id : "Phiên bản \(app.version) · \(app.id)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textSecond)
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 10) {
                            Label(Fmt.size(app.appSize), systemImage: "internaldrive")
                            if let d = app.lastUsed {
                                Label("Dùng lần cuối \(Fmt.relativeAge(d))", systemImage: "clock")
                            }
                        }
                        .font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
                    }
                    Spacer()
                }
                .padding(16)

                Divider().overlay(Color.white.opacity(0.12))

                if store.isLoadingLeftovers {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Đang tìm tệp còn sót…")
                            .font(.system(size: 12)).foregroundStyle(Palette.textSecond)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.leftovers) { item in
                                ItemRow(item: item) { store.toggle(item.id) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.never)
                }

                Divider().overlay(Color.white.opacity(0.12))

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(store.leftovers.filter(\.isSelected).count)/\(store.leftovers.count) mục · \(Fmt.size(store.selectedLeftoverSize))")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        Text(settings.moveToTrash ? "Chuyển vào Thùng rác" : "Xoá vĩnh viễn")
                            .font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
                    }
                    Spacer()
                    if store.isRemoving {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        ActionButton(title: "Gỡ ứng dụng", systemImage: "trash", kind: .prominent,
                                   isEnabled: store.leftovers.contains(where: \.isSelected)) {
                            confirming = true
                        }
                    }
                }
                .padding(14)
            }
            .glass()
        } else {
            overview.glass()
        }
    }
}

// MARK: - Bảng tổng quan khi chưa chọn app nào

extension UninstallerView {
    /// Chỗ này trước đây chỉ có một câu "chọn một ứng dụng" trên khoảng trống mênh mông.
    /// Giờ nó nói luôn máy đang có bao nhiêu app, chiếm bao nhiêu chỗ, và app nào lâu rồi
    /// không mở — chính là thứ người ta vào đây để tìm.
    var overview: some View {
        let apps = store.filteredApps
        let total = apps.reduce(Int64(0)) { $0 + $1.appSize }
        let stale = apps.filter { app in
            guard let d = app.lastUsed else { return false }
            return Date().timeIntervalSince(d) > 90 * 86_400
        }
        let byAge = apps
            .filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        // Nếu có app quá 90 ngày thì chỉ liệt kê đúng những app đó, để con số phía trên
        // và danh sách bên dưới nói cùng một chuyện.
        let oldest = stale.isEmpty ? Array(byAge.prefix(4))
                                   : Array(byAge.filter { app in stale.contains { $0.url == app.url } }
                                                .prefix(4))
        let listTitle = stale.isEmpty ? "ÍT DÙNG GẦN ĐÂY" : "LÂU RỒI KHÔNG MỞ"

        return VStack(spacing: 0) {
            HeroEmblem(icon: "shippingbox.fill", gem: skin.gem, size: 104)
                .padding(.top, 8)

            Text("Chọn một ứng dụng để gỡ")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)

            Text("xCleaner tìm mọi tệp ứng dụng đó để lại: dữ liệu, bộ nhớ đệm, tuỳ chọn, tác vụ nền và biên nhận cài đặt.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecond)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 6)

            HStack(spacing: 12) {
                statBox(value: "\(apps.count)", label: "ứng dụng")
                statBox(value: Fmt.size(total), label: "tổng dung lượng")
                statBox(value: "\(stale.count)", label: "lâu không mở")
            }
            .padding(.top, 22)
            .padding(.horizontal, 24)

            if !oldest.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(listTitle)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textFaint)
                        .padding(.bottom, 8)

                    ForEach(Array(oldest), id: \.url) { app in
                        Button {
                            withAnimation(Motion.gentle) { store.select(app) }
                        } label: {
                            HStack(spacing: 10) {
                                AppIconView(url: app.url, size: 22)
                                Text(app.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(Fmt.relativeAge(app.lastUsed))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.textSecond)
                                Text(Fmt.size(app.appSize))
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .frame(width: 72, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07)))
                .padding(.top, 20)
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textSecond)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.07)))
    }
}

private struct AppRow: View {
    let app: UninstallScanner.InstalledApp
    let isSelected: Bool
    let skin: ModuleSkin
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconView(url: app.url, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(app.lastUsed.map { "Dùng \(Fmt.relativeAge($0))" } ?? app.id)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Palette.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.size(app.appSize))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.textSecond)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [skin.gem[0].opacity(0.55),
                                                      skin.gem[1].opacity(0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                // Đường kẻ mảnh giữa các hàng; hàng đang chọn có nền riêng nên không cần.
                if !isSelected {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 1)
                        .padding(.leading, 46)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { h in hovering = h }
    }
}
