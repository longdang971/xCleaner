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
            SearchField(placeholder: "Tìm ứng dụng", text: $store.search).frame(width: 210)

            Menu {
                ForEach(UninstallStore.Sort.allCases) { s in
                    Button(s.rawValue) { store.sort = s }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .semibold))
                    Text(store.sort.rawValue).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            FilterChip(title: "App hệ thống", isOn: store.showSystemApps) {
                withAnimation(Motion.snappy) { store.showSystemApps.toggle() }
            }

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small).tint(.white)
                Text(store.statusText).font(.system(size: 11)).foregroundStyle(Palette.textFaint)
                    .lineLimit(1).frame(maxWidth: 220, alignment: .leading)
            } else {
                Text(store.statusText).font(.system(size: 11)).foregroundStyle(Palette.textFaint)
                PillButton(title: "Làm mới", systemImage: "arrow.clockwise") { store.load() }
            }
        }
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
                        PillButton(title: "Gỡ ứng dụng", systemImage: "trash", kind: .solid,
                                   isEnabled: store.leftovers.contains(where: \.isSelected)) {
                            confirming = true
                        }
                    }
                }
                .padding(14)
            }
            .glass()
        } else {
            EmptyStateView(icon: "shippingbox.fill",
                           title: "Chọn một ứng dụng",
                           message: "xCleaner sẽ tìm mọi tệp mà ứng dụng đó để lại: dữ liệu, bộ nhớ đệm, tuỳ chọn, tác vụ nền và biên nhận cài đặt.",
                           gem: skin.gem)
                .glass()
        }
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
