import SwiftUI
import AppKit

struct UninstallerView: View {
    @ObservedObject var store: UninstallStore
    @EnvironmentObject private var settings: AppSettings
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Gỡ ứng dụng",
                       subtitle: "Xoá app cùng toàn bộ tệp nó để lại trong hệ thống") {
                SecondaryButton(title: "Làm mới", systemImage: "arrow.clockwise") { store.load() }
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.top, 34)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                SearchField(placeholder: "Tìm ứng dụng", text: $store.search)
                    .frame(width: 220)
                Picker("", selection: $store.sort) {
                    ForEach(UninstallStore.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).frame(width: 150).labelsHidden()
                Toggle("Hiện app hệ thống", isOn: $store.showSystemApps)
                    .toggleStyle(.checkbox).font(.system(size: 11.5))
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.small)
                    Text(store.statusText).font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1).frame(maxWidth: 200, alignment: .leading)
                } else {
                    Text(store.statusText).font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.bottom, 12)

            HStack(spacing: 14) {
                appList.frame(width: 330)
                detail
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.bottom, Metrics.contentPadding)
        }
        .onAppear { if store.apps.isEmpty { store.load() } }
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

    // MARK: Danh sách app

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.filteredApps) { app in
                    AppRow(app: app, isSelected: store.selectedApp?.url == app.url) {
                        withAnimation(Motion.gentle) { store.select(app) }
                    }
                }
            }
            .padding(6)
        }
        .cardBackground()
    }

    // MARK: Chi tiết

    @ViewBuilder
    private var detail: some View {
        if let app = store.selectedApp {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    AppIconView(url: app.url, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(app.version.isEmpty ? app.id : "Phiên bản \(app.version) · \(app.id)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 8) {
                            Label(Fmt.size(app.appSize), systemImage: "internaldrive")
                            if let d = app.lastUsed {
                                Label("Dùng lần cuối \(Fmt.relativeAge(d))", systemImage: "clock")
                            }
                        }
                        .font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(16)

                Divider().overlay(Palette.hairline)

                if store.isLoadingLeftovers {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Đang tìm tệp còn sót…").font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
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
                }

                Divider().overlay(Palette.hairline)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(store.leftovers.filter(\.isSelected).count)/\(store.leftovers.count) mục · \(Fmt.size(store.selectedLeftoverSize))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(settings.moveToTrash ? "Chuyển vào Thùng rác" : "Xoá vĩnh viễn")
                            .font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if store.isRemoving {
                        ProgressView().controlSize(.small)
                    } else {
                        PrimaryButton(title: "Gỡ ứng dụng", systemImage: "trash",
                                      tint: LinearGradient(colors: [Palette.danger,
                                                                    Palette.danger.opacity(0.8)],
                                                           startPoint: .topLeading,
                                                           endPoint: .bottomTrailing),
                                      isEnabled: store.leftovers.contains(where: \.isSelected)) {
                            confirming = true
                        }
                    }
                }
                .padding(14)
            }
            .cardBackground()
        } else {
            EmptyStateView(icon: "shippingbox",
                           title: "Chọn một ứng dụng",
                           message: "xCleaner sẽ tìm mọi tệp mà ứng dụng đó để lại: dữ liệu, bộ nhớ đệm, tuỳ chọn, tác vụ nền và biên nhận cài đặt.")
                .cardBackground()
        }
    }
}

private struct AppRow: View {
    let app: UninstallScanner.InstalledApp
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconView(url: app.url, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                        .lineLimit(1)
                    Text(app.lastUsed.map { "Dùng \(Fmt.relativeAge($0))" } ?? app.id)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(Fmt.size(app.appSize))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.accentGradient)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in hovering = h }
    }
}
