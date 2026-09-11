import SwiftUI
import AppKit

/// Màn hình dùng chung cho Quét thông minh, Rác hệ thống, Thùng rác & Tải về, Riêng tư.
///
/// Ba chặng: màn khởi đầu (khối 3D + nút tròn) → lưới thẻ tóm tắt → danh sách chi tiết của
/// một nhóm khi bấm "Xem". Cách chia này giữ màn kết quả luôn gọn dù có hàng nghìn tệp.
struct GroupedModuleView: View {
    @ObservedObject var store: ScanStore
    let module: CleanModule
    @EnvironmentObject private var settings: AppSettings

    @State private var confirming = false
    @State private var reviewing: String?

    private var skin: ModuleSkin { ModuleSkin.skin(for: module) }

    var body: some View {
        ZStack {
            switch store.phase {
            case .idle, .scanning:
                heroScreen
            case .results, .cleaning, .done:
                if let id = reviewing, let group = store.groups.first(where: { $0.id == id }) {
                    GroupDetailView(group: group,
                                    skin: skin,
                                    totalSelected: store.totalSelected,
                                    onBack: { withAnimation(Motion.standard) { reviewing = nil } },
                                    onToggleGroup: { store.toggleGroup(group.id) },
                                    onToggleItem: { store.toggleItem(groupID: group.id, itemID: $0) },
                                    onQuitApp: { store.quitApp(groupID: group.id) },
                                    onClean: {
                                        if settings.confirmBeforeClean { confirming = true }
                                        else { store.clean() }
                                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                } else {
                    resultsScreen
                        .transition(.opacity)
                }
            }

            if store.phase == .cleaning || store.phase == .done {
                CleanOverlay(store: store, skin: skin).transition(.opacity).zIndex(10)
            }
        }
        .animation(Motion.standard, value: store.phase)
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in
            reviewing = nil
            store.scan()
        }
        .onChange(of: store.phase) { _ in
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCLEANER_REVIEW"] == "1",
               store.phase == .results, reviewing == nil {
                reviewing = store.groups.first?.id
            }
            #endif
        }
        .confirmationDialog("Dọn \(Fmt.size(store.totalSelected))?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Dọn ngay", role: .destructive) { reviewing = nil; store.clean() }
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

    // MARK: - Màn khởi đầu

    private var heroScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            if store.phase == .scanning {
                ScanRing(mode: store.ringMode, bytes: store.liveBytes,
                         caption: store.statusText.isEmpty ? "Đang quét…" : store.statusText,
                         accent: skin.glow)
                    .padding(.bottom, 6)
                PillButton(title: "Dừng lại", systemImage: "stop.fill") { store.cancelScan() }
            } else {
                GemView(symbol: module.icon, colors: skin.gem, size: 148)
                    .padding(.bottom, 18)

                HeroHeadline(title: module.title, subtitle: hint) {
                    EmptyView()
                }
                .padding(.bottom, 26)

                CircleActionButton(title: "Quét", accent: skin.action) { store.scan() }
            }

            Spacer()
            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String {
        switch module {
        case .smartScan:
            return "Bộ nhớ đệm, nhật ký, báo cáo sự cố và Thùng rác.\nMọi mục tìm thấy ở đây đều an toàn để xoá."
        case .systemJunk:
            return "Gồm cả /Library — những mục đó sẽ cần mật khẩu quản trị khi dọn."
        case .privacy:
            return "Cookie, lịch sử và bộ nhớ đệm của mọi trình duyệt trên máy.\nHãy thoát trình duyệt trước khi dọn."
        case .trashDownloads:
            return "Thùng rác trên mọi ổ đĩa, bộ cài cũ và tệp tải về lâu ngày.\nXem qua danh sách trước khi dọn."
        default:
            return ""
        }
    }

    // MARK: - Lưới thẻ tóm tắt

    private var resultsScreen: some View {
        VStack(spacing: 0) {
            HeroHeadline(title: store.groups.isEmpty
                            ? "Không còn gì để dọn"
                            : "Tìm thấy \(Fmt.size(store.totalFound)) có thể dọn",
                         subtitle: store.groups.isEmpty
                            ? "Thử lại sau vài ngày nữa nhé."
                            : "Đã chọn sẵn \(Fmt.size(store.totalSelected)) trong \(store.selectedItems.count) mục.") {
                HStack(spacing: 8) {
                    PillButton(title: "Chọn tất cả") {
                        withAnimation(Motion.snappy) { store.selectAll(true) }
                    }
                    PillButton(title: "Bỏ chọn") {
                        withAnimation(Motion.snappy) { store.selectAll(false) }
                    }
                    PillButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 22)

            if store.groups.isEmpty {
                EmptyStateView(icon: "checkmark.seal",
                               title: "Máy đang sạch",
                               message: "Không tìm thấy gì ở mục này.",
                               gem: skin.gem)
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 14)],
                                  spacing: 14) {
                            ForEach(Array(store.groups.enumerated()), id: \.element.id) { idx, group in
                                GroupTile(group: group, gem: TileGems.gem(for: idx),
                                          onToggle: { store.toggleGroup(group.id) },
                                          onReview: {
                                              withAnimation(Motion.standard) { reviewing = group.id }
                                          },
                                          onQuitApp: { store.quitApp(groupID: group.id) })
                            }
                        }
                        .padding(.horizontal, Metrics.contentPadding)
                        .padding(.bottom, 132)
                    }
                    .scrollIndicators(.never)

                    BottomFade()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !store.groups.isEmpty { cleanButton }
        }
    }

    private var cleanButton: some View {
        VStack(spacing: 8) {
            Text(store.totalSelected > 0
                 ? "Sẽ giải phóng \(Fmt.size(store.totalSelected))"
                 : "Chưa chọn mục nào")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.textSecond)
                .contentTransition(.numericText())

            CircleActionButton(title: "Dọn", accent: skin.action,
                               isEnabled: store.totalSelected > 0) {
                if settings.confirmBeforeClean { confirming = true } else { store.clean() }
            }
        }
        .padding(.bottom, 18)
        .animation(Motion.gentle, value: store.totalSelected)
    }
}

// MARK: - Thẻ tóm tắt một nhóm

struct GroupTile: View {
    let group: CleanGroup
    let gem: [Color]
    var onToggle: () -> Void
    var onReview: () -> Void
    var onQuitApp: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TriStateBox(state: group.selection, action: onToggle)
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            Spacer(minLength: 10)

            Text(Fmt.size(group.selectedSize))
                .font(.cardNumber)
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("\(group.items.count) mục · \(group.subtitle)")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecond)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)

            HStack(spacing: 6) {
                if group.safety != .safe { SafetyBadge(level: group.safety) }
                if group.items.contains(where: \.requiresAdmin) { AdminBadge() }
                Spacer(minLength: 4)
                if group.runningBundleID != nil, let onQuitApp {
                    PillButton(title: "Thoát app", kind: .warning, action: onQuitApp)
                }
                PillButton(title: "Xem", kind: hovering ? .solid : .glass, action: onReview)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(height: 168, alignment: .topLeading)
        .glass(strength: hovering ? Palette.glassStrong : Palette.glass)
        .overlay(alignment: .topTrailing) {
            // Khối 3D nhô một phần ra khỏi mép thẻ — nó phải nằm trên nền kính, không bị cắt.
            GemView(symbol: group.icon, colors: gem, size: 66, floating: false)
                .offset(x: 14, y: -14)
                .allowsHitTesting(false)
        }
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
        .onTapGesture(perform: onReview)
    }
}

// MARK: - Danh sách chi tiết của một nhóm

struct GroupDetailView: View {
    let group: CleanGroup
    let skin: ModuleSkin
    let totalSelected: Int64
    var onBack: () -> Void
    var onToggleGroup: () -> Void
    var onToggleItem: (UUID) -> Void
    var onQuitApp: () -> Void
    var onClean: () -> Void

    private let visibleLimit = 300

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PillButton(title: "Quay lại", systemImage: "chevron.left", action: onBack)
                Spacer()
                Text(group.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text("\(Fmt.size(group.selectedSize)) / \(Fmt.size(group.totalSize))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecond)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TriStateBox(state: group.selection, action: onToggleGroup)
                    Text(group.subtitle).font(.system(size: 11.5)).foregroundStyle(Palette.textSecond)
                    Spacer()
                    if group.runningBundleID != nil {
                        PillButton(title: "Thoát app", kind: .warning, action: onQuitApp)
                    }
                    if group.safety != .safe { SafetyBadge(level: group.safety) }
                    if group.items.contains(where: \.requiresAdmin) { AdminBadge() }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)

                Divider().overlay(Color.white.opacity(0.12))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(group.items.prefix(visibleLimit)) { item in
                            ItemRow(item: item) { onToggleItem(item.id) }
                        }
                        if group.items.count > visibleLimit {
                            Text("… và \(group.items.count - visibleLimit) mục nữa (đã tính vào tổng)")
                                .font(.system(size: 11)).foregroundStyle(Palette.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)

                Divider().overlay(Color.white.opacity(0.12))

                HStack {
                    Text("\(group.selectedCount)/\(group.items.count) mục đã chọn ở nhóm này")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.textSecond)
                    Spacer()
                    PillButton(title: "Dọn \(Fmt.size(totalSelected))", systemImage: "sparkles",
                               kind: .solid, isEnabled: totalSelected > 0, action: onClean)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
            }
            .glass()
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.bottom, Metrics.contentPadding)
        }
    }
}

// MARK: - Một dòng

struct ItemRow: View {
    let item: CleanItem
    var onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckBox(isOn: item.isSelected, action: onToggle).padding(.leading, 16)

            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textFaint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.rowTitle).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.rowDetail).foregroundStyle(Palette.textFaint)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if item.requiresAdmin {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Palette.warning)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Palette.textSecond : .clear)
            }
            .buttonStyle(.plain).help("Hiện trong Finder")

            Text(Fmt.size(item.size))
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Palette.textSecond)
                .frame(width: 74, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 34)
        .background(hovering ? Color.white.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}

// MARK: - Lớp phủ lúc dọn

struct CleanOverlay: View {
    @ObservedObject var store: ScanStore
    let skin: ModuleSkin

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.45)).ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).opacity(0.5).ignoresSafeArea()

            VStack(spacing: 20) {
                if store.phase == .done, let o = store.outcome {
                    GemView(symbol: o.wasCancelled && o.freedBytes == 0
                            ? "exclamationmark" : "checkmark",
                            colors: skin.gem, size: 116)

                    VStack(spacing: 6) {
                        Text(o.wasCancelled && o.freedBytes == 0
                             ? "Đã huỷ"
                             : "Đã giải phóng \(Fmt.size(o.freedBytes))")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                        Text(summary(o))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textSecond)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                    }

                    if !o.failures.isEmpty {
                        failureList(o)
                    }

                    HStack(spacing: 10) {
                        PillButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                        PillButton(title: "Xong", kind: .solid) { store.reset() }
                    }
                } else {
                    ScanRing(mode: store.ringMode, bytes: store.totalSelected,
                             caption: store.statusText, diameter: 180, accent: skin.glow)
                }
            }
            .padding(40)
        }
    }

    private func failureList(_ o: CleanOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(o.failures.count) mục không xoá được")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.warning)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(o.failures.prefix(30).enumerated()), id: \.offset) { _, f in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FileUtils.prettyPath(f.url))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                            Text(f.reason).font(.system(size: 10)).foregroundStyle(Palette.textFaint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 140)
        }
        .padding(14)
        .frame(width: 460)
        .glass(radius: 14)
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
