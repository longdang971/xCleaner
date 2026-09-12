import SwiftUI
import AppKit

/// Mục "Khởi động cùng máy": xem thứ gì tự chạy khi bật máy, tắt thứ không cần.
///
/// Khác với các mục còn lại, ở đây hầu như không có gì để xoá — việc chính là **tắt**.
/// Nên màn này không có nút tròn "Dọn" ở đáy; mỗi hàng tự mang công tắc của nó.
struct StartupView: View {
    @ObservedObject var store: StartupStore
    @State private var confirmingRemoval: StartupScanner.Item?

    private let skin = ModuleSkin.skin(for: .startup)

    var body: some View {
        VStack(spacing: 0) {
            if store.items.isEmpty && !store.isLoading {
                startScreen
            } else if store.isLoading {
                loadingScreen
            } else {
                header.padding(.bottom, 18)
                toolbar
                    .padding(.horizontal, Metrics.contentPadding)
                    .padding(.bottom, 12)
                list
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in store.load() }
        .confirmationDialog("Xoá mục khởi động “\(confirmingRemoval?.name ?? "")”?",
                            isPresented: Binding(get: { confirmingRemoval != nil },
                                                 set: { if !$0 { confirmingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Xoá", role: .destructive) {
                if let item = confirmingRemoval { store.remove(item) }
                confirmingRemoval = nil
            }
            Button("Huỷ", role: .cancel) { confirmingRemoval = nil }
        } message: {
            Text("Tắt là đủ để nó không chạy nữa và bật lại được bất cứ lúc nào. Xoá thì app chủ có thể tạo lại tệp này ở lần cập nhật sau.")
        }
    }

    // MARK: Màn khởi đầu

    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            ModuleIntro(title: CleanModule.startup.title,
                        subtitle: "Bộ cập nhật, trình đồng bộ, helper — thứ các app cài thêm để tự chạy ngầm. Tắt bớt thì máy khởi động nhẹ hơn.",
                        icon: CleanModule.startup.icon,
                        gem: skin.gem,
                        highlights: CleanModule.startup.highlights) {
                ActionButton(title: "Mở mục Đăng nhập của macOS…",
                             systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            CircleActionButton(title: "Xem", accent: skin.action) { store.load() }
                .padding(.bottom, 22)
        }
    }

    private var loadingScreen: some View {
        VStack(spacing: 16) {
            ScanRing(mode: .scanning(store.progress), bytes: 0,
                     caption: store.statusText, diameter: 170, accent: skin.glow)
            ActionButton(title: "Dừng", systemImage: "stop.fill") { store.cancel() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Kết quả

    private var header: some View {
        HeroHeadline(title: store.activeCount == 0
                     ? "Không có gì của app tự chạy"
                     : "\(store.activeCount) mục của ứng dụng đang tự chạy",
                     subtitle: store.orphanCount > 0
                     ? "\(store.orphanCount) mục trỏ tới chương trình không còn trên máy — xoá được"
                     : "Mục của macOS được liệt kê để bạn biết, nhưng không tắt được") {
            EmptyView()
        }
        .padding(.top, 6)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Quay lại", systemImage: "chevron.left") { store.backToStart() }
            ForEach(StartupStore.Filter.allCases) { f in
                FilterChip(title: f.rawValue, isOn: store.filter == f) {
                    withAnimation(Motion.snappy) { store.filter = f }
                }
            }
            Spacer()
            SearchField(placeholder: "Lọc theo tên", text: $store.search, width: 190)
            ActionButton(title: "Đọc lại", systemImage: "arrow.clockwise") { store.load() }
        }
    }

    @ViewBuilder
    private var list: some View {
        if store.visibleItems.isEmpty {
            EmptyStateView(icon: "power",
                           title: "Không có mục nào",
                           message: "Thử đổi bộ lọc ở trên, hoặc bỏ chữ trong ô tìm kiếm.",
                           gem: skin.gem)
        } else {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.visibleItems) { item in
                            StartupRow(item: item,
                                       busy: store.working.contains(item.id),
                                       accent: skin.action,
                                       onToggle: { store.toggle(item) },
                                       onReveal: { store.revealInFinder(item) },
                                       onRemove: { confirmingRemoval = item })
                        }
                    }
                    .padding(8)
                    .padding(.bottom, store.lastError == nil ? 8 : 56)
                }
                .scrollIndicators(.never)
                .glass()
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, Metrics.contentPadding)

                if let error = store.lastError {
                    Text(error)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.black.opacity(0.82))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.warning))
                        .padding(.bottom, Metrics.contentPadding + 12)
                        .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Một hàng

private struct StartupRow: View {
    let item: StartupScanner.Item
    let busy: Bool
    let accent: Color
    let onToggle: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if item.isApple {
                        Tag(text: "macOS", color: Palette.textFaint)
                    } else if item.isOrphan {
                        Tag(text: "không còn", color: Palette.warning)
                    } else if item.isRunning {
                        Tag(text: "đang chạy", color: Palette.success)
                    }
                }
                Text(item.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textFaint)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if hovering || item.isOrphan {
                ActionButton(title: "Hiện", systemImage: "folder", height: 24, action: onReveal)
                if !item.isApple {
                    ActionButton(title: "Xoá", systemImage: "trash",
                                 height: 24, action: onRemove)
                }
            }

            if busy {
                ProgressView().controlSize(.small).tint(.white).frame(width: 42)
            } else {
                RowSwitch(isOn: !item.isDisabled,
                          accent: accent,
                          isEnabled: !item.isApple,
                          action: onToggle)
                    .help(item.isApple
                          ? "Mục của macOS — tắt là hỏng máy"
                          : (item.isDisabled ? "Đang tắt — bấm để bật lại" : "Đang bật — bấm để tắt"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
            .fill(hovering ? Color.white.opacity(0.07) : .clear))
        .opacity(item.isDisabled ? 0.62 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }

    @ViewBuilder
    private var icon: some View {
        if let id = item.bundleID, let image = AppIconProvider.icon(forBundleID: id) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: item.domain == .daemon ? "gearshape.2.fill" : "bolt.horizontal.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textSecond)
        }
    }
}

/// Nhãn nhỏ cạnh tên.
private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.18)))
    }
}

/// Công tắc cỡ hàng danh sách — cùng kiểu với công tắc trong Cài đặt, nhỏ hơn một nấc.
private struct RowSwitch: View {
    let isOn: Bool
    let accent: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? accent : Color.white.opacity(0.16))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.42 : 0.16), lineWidth: 1))
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 17, height: 17)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(.horizontal, 2.5)
                }
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(Motion.snappy, value: isOn)
    }
}
