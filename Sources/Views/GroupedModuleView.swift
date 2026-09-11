import SwiftUI
import AppKit

/// Màn hình dùng chung cho Quét thông minh, Rác hệ thống, Thùng rác & Tải về, Riêng tư.
struct GroupedModuleView: View {
    @ObservedObject var store: ScanStore
    @EnvironmentObject private var settings: AppSettings
    @State private var confirming = false

    var body: some View {
        ZStack {
            switch store.phase {
            case .idle, .scanning:
                heroScreen
            case .results, .cleaning, .done:
                resultsScreen
            }

            if store.phase == .cleaning || store.phase == .done {
                CleanOverlay(store: store)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(Motion.standard, value: store.phase)
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in store.scan() }
        .confirmationDialog("Dọn \(Fmt.size(store.totalSelected))?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Dọn ngay", role: .destructive) { store.clean() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        var s = "\(store.selectedItems.count) mục sẽ bị "
        s += settings.moveToTrash ? "chuyển vào Thùng rác." : "xoá vĩnh viễn."
        if store.needsAdmin {
            s += "\nMột số mục nằm trong thư mục hệ thống, macOS sẽ hỏi mật khẩu quản trị của bạn."
        }
        return s
    }

    // MARK: - Màn hình khởi đầu

    private var heroScreen: some View {
        VStack(spacing: 0) {
            PageHeader(title: store.module.title, subtitle: store.module.subtitle)
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.top, 34)

            Spacer()

            ScanRing(mode: store.ringMode,
                     bytes: store.liveBytes,
                     caption: store.phase == .scanning
                        ? (store.statusText.isEmpty ? "Đang quét…" : store.statusText)
                        : "Sẵn sàng")

            VStack(spacing: 10) {
                if store.phase == .scanning {
                    SecondaryButton(title: "Dừng lại", systemImage: "stop.fill") { store.cancelScan() }
                } else {
                    PrimaryButton(title: "Bắt đầu quét", systemImage: "sparkles") { store.scan() }
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(.top, -18)

            Spacer()
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String {
        switch store.module {
        case .smartScan:
            return "Quét bộ nhớ đệm, nhật ký, báo cáo sự cố và Thùng rác. Mọi mục ở đây đều an toàn để xoá."
        case .systemJunk:
            return "Bao gồm cả /Library — những mục đó sẽ cần mật khẩu quản trị khi dọn."
        case .privacy:
            return "Hãy đóng trình duyệt trước khi dọn để dữ liệu không bị ghi lại ngay sau đó."
        case .trashDownloads:
            return "Xem qua danh sách trước khi dọn — trong đây có tệp cá nhân của bạn."
        default:
            return ""
        }
    }

    // MARK: - Màn hình kết quả

    private var resultsScreen: some View {
        VStack(spacing: 0) {
            PageHeader(title: store.module.title, subtitle: store.module.subtitle) {
                HStack(spacing: 8) {
                    SecondaryButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                }
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.top, 34)
            .padding(.bottom, 18)

            summaryBar
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, 14)

            if store.groups.isEmpty {
                EmptyStateView(icon: "checkmark.seal",
                               title: "Sạch sẽ rồi",
                               message: "Không còn gì để dọn ở mục này. Thử lại sau vài ngày nữa nhé.")
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.groups) { group in
                                GroupCard(group: group,
                                          onToggleGroup: { store.toggleGroup(group.id) },
                                          onToggleExpand: { store.toggleExpanded(group.id) },
                                          onToggleItem: { store.toggleItem(groupID: group.id, itemID: $0) })
                            }
                        }
                        .padding(.horizontal, Metrics.contentPadding)
                        .padding(.bottom, 104)
                    }
                    .scrollIndicators(.automatic)
                    BottomFade()
                }
            }
        }
        .overlay(alignment: .bottom) { footer }
    }

    private var summaryBar: some View {
        HStack(spacing: 18) {
            MiniRing(fraction: store.totalFound > 0
                     ? Double(store.totalSelected) / Double(store.totalFound) : 0)
            stat(title: "Tìm thấy", value: Fmt.size(store.totalFound), color: Palette.textPrimary)
            Divider().frame(height: 26).overlay(Palette.hairline)
            stat(title: "Đã chọn", value: Fmt.size(store.totalSelected), color: Palette.accent)
            Divider().frame(height: 26).overlay(Palette.hairline)
            stat(title: "Số mục", value: "\(store.selectedItems.count)", color: Palette.textPrimary)

            Spacer()

            if store.needsAdmin { AdminBadge() }

            Button("Chọn tất cả") { withAnimation(Motion.snappy) { store.selectAll(true) } }
                .buttonStyle(.link).font(.system(size: 11.5))
            Button("Bỏ chọn") { withAnimation(Motion.snappy) { store.selectAll(false) } }
                .buttonStyle(.link).font(.system(size: 11.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .cardBackground()
    }

    private func stat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(Motion.gentle, value: value)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.totalSelected > 0
                     ? "Sẽ giải phóng \(Fmt.size(store.totalSelected))"
                     : "Chưa chọn mục nào")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(settings.moveToTrash ? "Chuyển vào Thùng rác" : "Xoá vĩnh viễn")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            PrimaryButton(title: "Dọn ngay", systemImage: "sparkles",
                          isEnabled: store.totalSelected > 0) {
                if settings.confirmBeforeClean { confirming = true } else { store.clean() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 20, y: 6)
        )
        .padding(.horizontal, Metrics.contentPadding)
        .padding(.bottom, 18)
        .opacity(store.groups.isEmpty ? 0 : 1)
        .animation(Motion.standard, value: store.groups.isEmpty)
    }
}

// MARK: - Thẻ nhóm

struct GroupCard: View {
    let group: CleanGroup
    var onToggleGroup: () -> Void
    var onToggleExpand: () -> Void
    var onToggleItem: (UUID) -> Void
    var onQuitApp: (() -> Void)? = nil

    @State private var hovering = false
    private let visibleLimit = 120

    var body: some View {
        VStack(spacing: 0) {
            header
            if group.isExpanded {
                Divider().overlay(Palette.hairline)
                itemList
            }
        }
        .cardBackground()
    }

    private var header: some View {
        HStack(spacing: 12) {
            TriStateBox(state: group.selection, action: onToggleGroup)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: group.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.title).font(.cardTitle).foregroundStyle(Palette.textPrimary)
                    if group.safety != .safe { SafetyBadge(level: group.safety) }
                    if group.items.contains(where: \.requiresAdmin) { AdminBadge() }
                }
                Text(group.subtitle).font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if group.runningBundleID != nil, let onQuitApp {
                Button(action: onQuitApp) {
                    Text("Thoát app")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(Palette.warning.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Thoát ứng dụng để dữ liệu không bị ghi lại ngay sau khi dọn")
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.size(group.selectedSize))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(group.selectedSize > 0 ? Palette.textPrimary : Palette.textTertiary)
                    .contentTransition(.numericText())
                Text("\(group.items.count) mục").font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                .animation(Motion.snappy, value: group.isExpanded)
                .frame(width: 14)
        }
        .padding(14)
        .background(hovering ? Palette.textPrimary.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }

    private var itemList: some View {
        LazyVStack(spacing: 0) {
            ForEach(group.items.prefix(visibleLimit)) { item in
                ItemRow(item: item) { onToggleItem(item.id) }
            }
            if group.items.count > visibleLimit {
                Text("… và \(group.items.count - visibleLimit) mục nữa (đã tính vào tổng)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Dòng mục

struct ItemRow: View {
    let item: CleanItem
    var onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckBox(isOn: item.isSelected, action: onToggle)
                .padding(.leading, 16)

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.rowDetail)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if item.requiresAdmin {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.warning)
            }

            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Hiện trong Finder")
            }

            Text(Fmt.size(item.size))
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 74, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 34)
        .background(hovering ? Palette.accent.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}

// MARK: - Lớp phủ khi dọn

struct CleanOverlay: View {
    @ObservedObject var store: ScanStore

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ScanRing(mode: store.ringMode,
                         bytes: store.phase == .done ? (store.outcome?.freedBytes ?? 0) : store.totalSelected,
                         caption: store.statusText,
                         diameter: 190)

                if store.phase == .done, let o = store.outcome {
                    VStack(spacing: 6) {
                        Text(o.wasCancelled && o.freedBytes == 0
                             ? "Đã huỷ"
                             : "Đã giải phóng \(Fmt.size(o.freedBytes))")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(summary(o))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }

                    if !o.failures.isEmpty {
                        DisclosureGroup("\(o.failures.count) mục không xoá được") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(o.failures.prefix(30).enumerated()), id: \.offset) { _, f in
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(FileUtils.prettyPath(f.url))
                                                .font(.system(size: 11, weight: .medium))
                                            Text(f.reason).font(.system(size: 10))
                                                .foregroundStyle(Palette.textTertiary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(8)
                            }
                            .frame(maxHeight: 150)
                        }
                        .font(.system(size: 11))
                        .frame(width: 420)
                        .padding(12)
                        .cardBackground(radius: 10)
                    }

                    HStack(spacing: 10) {
                        SecondaryButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                        PrimaryButton(title: "Xong", systemImage: "checkmark") { store.reset() }
                    }
                }
            }
            .padding(40)
        }
    }

    private func summary(_ o: CleanOutcome) -> String {
        var parts: [String] = ["\(o.removedCount) mục đã được dọn"]
        if o.wasCancelled {
            parts.append("bạn đã huỷ nhập mật khẩu nên phần trong thư mục hệ thống được giữ nguyên")
        } else if o.usedAdmin {
            parts.append("có dùng quyền quản trị")
        }
        if !o.failures.isEmpty { parts.append("\(o.failures.count) mục bị bỏ qua") }
        return parts.joined(separator: " · ")
    }
}
