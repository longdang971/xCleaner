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
    /// Nhóm sẽ được dọn khi xác nhận; nil nghĩa là dọn tất cả những gì đang chọn.
    @State private var cleanScope: String?

    private var skin: ModuleSkin { ModuleSkin.skin(for: module) }

    var body: some View {
        ZStack {
            switch store.phase {
            case .scanning where !store.stages.isEmpty:
                ScanningView(stages: store.stages,
                             currentStage: store.currentStage,
                             stageBytes: store.stageBytes,
                             currentFile: store.statusText,
                             totalBytes: store.liveBytes,
                             found: store.found,
                             progress: store.progress,
                             skin: skin,
                             onStop: { store.cancelScan() })
                    .transition(.opacity)
            case .idle, .scanning:
                heroScreen
            case .cleaning:
                CleaningView(stages: store.stages,
                             currentStage: store.currentStage,
                             stageBytes: store.stageBytes,
                             entries: store.cleaned.filter { $0.stageIndex == store.currentStage },
                             total: store.cleanTotal,
                             doneCount: store.cleaned.count,
                             freed: store.cleanFreed,
                             progress: store.progress,
                             skin: skin,
                             onStop: { store.cancelClean() })
                    .transition(.opacity)

            case .done:
                DoneScreen(store: store, skin: skin).transition(.opacity)

            case .results:
                if let id = reviewing, let group = store.groups.first(where: { $0.id == id }) {
                    GroupDetailView(group: group,
                                    skin: skin,
                                    gemBase: store.groups.firstIndex(where: { $0.id == id }) ?? 0,
                                    groupSelectedSize: group.selectedSize,
                                    onBack: { withAnimation(Motion.standard) { reviewing = nil } },
                                    onToggleGroup: { store.toggleGroup(group.id) },
                                    onToggleItem: { store.toggleItem(groupID: group.id, itemID: $0) },
                                    onToggleCategory: { store.toggleCategory(groupID: group.id, category: $0) },
                                    onQuitApp: { store.quitApp(groupID: group.id) },
                                    onClean: {
                                        cleanScope = group.id
                                        if settings.confirmBeforeClean { confirming = true }
                                        else { store.clean(groupID: group.id) }
                                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                } else {
                    resultsScreen
                        .transition(.opacity)
                }
            }

        }
        .animation(Motion.standard, value: store.phase)
        // Hộp thoại phải là overlay của cả màn hình: đặt trong ZStack, lớp mờ bị ép theo
        // kích thước của chính hộp thoại và phần còn lại vẫn sáng nguyên.
        .overlay {
            if let pending = store.pendingQuit {
                AppDialog(accent: skin.action,
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
                        Text("Thoát ứng dụng rồi xCleaner dọn tiếp. Nếu để nguyên, phần dữ liệu vừa xoá có thể được ghi lại ngay sau đó.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textSecond)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .zIndex(20)
            }
        }
        .animation(Motion.standard, value: store.pendingQuit)
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in
            reviewing = nil
            store.scan()
        }
        .onChange(of: store.phase) { _ in
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCLEANER_DEMO_CLEAN"] == "1",
               store.phase == .results {
                store.debugDemoClean()
            }
            if ProcessInfo.processInfo.environment["XCLEANER_DEMO_QUIT"] == "1",
               store.phase == .results {
                store.debugShowQuitDialog()
            }
            if let want = ProcessInfo.processInfo.environment["XCLEANER_REVIEW"],
               store.phase == .results, reviewing == nil {
                reviewing = want == "1" ? store.groups.first?.id
                                        : store.groups.first(where: { $0.id == want })?.id
            }
            #endif
        }
        .confirmationDialog("Dọn \(Fmt.size(scopeSize))?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Dọn ngay", role: .destructive) {
                let scope = cleanScope
                reviewing = nil
                store.clean(groupID: scope)
            }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text(confirmMessage)
        }
    }

    /// Những mục sẽ bị xoá nếu xác nhận ngay bây giờ.
    private var scopeItems: [CleanItem] {
        if let id = cleanScope, let g = store.groups.first(where: { $0.id == id }) {
            return g.items.filter(\.isSelected)
        }
        return store.selectedItems
    }

    private var scopeSize: Int64 { scopeItems.reduce(0) { $0 + $1.size } }

    private var confirmMessage: String {
        var s = "\(scopeItems.count) mục sẽ bị "
        s += settings.moveToTrash ? "chuyển vào Thùng rác." : "xoá vĩnh viễn."
        if scopeItems.contains(where: \.requiresAdmin) {
            s += "\nMột số mục nằm trong thư mục hệ thống, macOS sẽ hỏi mật khẩu quản trị của bạn."
        }
        if scopeItems.contains(where: { $0.safety == .sensitive }) {
            s += "\nTrong đó có dữ liệu tự động điền — xoá rồi không lấy lại được."
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
                ModuleIntro(title: module.title,
                            subtitle: hint,
                            icon: module.icon,
                            gem: skin.gem,
                            highlights: module.highlights)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if store.phase != .scanning {
                CircleActionButton(title: "Quét", accent: skin.action) { store.scan() }
                    .padding(.bottom, 22)
            }
        }
    }

    private var hint: String {
        switch module {
        case .smartScan:
            return "Dọn nhanh những thứ an toàn tuyệt đối. Mọi mục tick sẵn đều có thể xoá mà không mất gì."
        case .systemJunk:
            return "Gồm cả /Library — những mục đó sẽ cần mật khẩu quản trị khi dọn."
        case .privacy:
            return "Dấu vết duyệt web của mọi trình duyệt trên máy. Nhớ thoát trình duyệt trước khi dọn."
        case .trashDownloads:
            return "Thùng rác, bộ cài cũ và tệp tải về lâu ngày. Xem qua danh sách trước khi dọn."
        default:
            return ""
        }
    }

    // MARK: - Lưới thẻ tóm tắt

    private var resultsScreen: some View {
        VStack(spacing: 0) {
            Group {
                if store.groups.isEmpty {
                    HeroHeadline(title: "Không còn gì để dọn",
                                 subtitle: "Thử lại sau vài ngày nữa nhé.") {
                        PillButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                    }
                } else {
                    ResultHeadline(selectedBytes: store.totalSelected,
                                   totalBytes: store.totalFound) {
                        EmptyView()
                    }
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
                        tileLayout
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
        .overlay(alignment: .topLeading) {
            PillButton(title: "Quay lại", systemImage: "chevron.left") { store.backToStart() }
                .padding(.leading, Metrics.contentPadding)
                .padding(.top, 6)
        }
        .overlay(alignment: .topTrailing) {
            if !store.groups.isEmpty {
                // Một nút duy nhất, đổi vai theo trạng thái: đang có mục được chọn thì nó bỏ
                // chọn, không còn mục nào thì nó chọn lại tất cả.
                let hasSelection = store.totalSelected > 0
                IconToolbar(actions: [
                    .init(icon: hasSelection ? "circle.slash" : "checkmark.circle",
                          help: hasSelection ? "Bỏ chọn tất cả" : "Chọn tất cả") {
                        withAnimation(Motion.snappy) { store.selectAll(!hasSelection) }
                    },
                    .init(icon: "arrow.clockwise", help: "Quét lại") { store.scan() }
                ])
                .padding(.trailing, Metrics.contentPadding)
                .padding(.top, 6)
            }
        }
    }

    /// Ba thẻ nhỏ ở hàng đầu rồi các thẻ rộng hơn ở dưới — bố cục của Smart Care.
    /// Dưới bốn nhóm thì chia đều cho đỡ trống trải.
    @ViewBuilder
    private var tileLayout: some View {
        let groups = store.groups
        if groups.count >= 4 {
            VStack(spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                          spacing: 14) {
                    ForEach(Array(groups.prefix(3).enumerated()), id: \.element.id) { idx, group in
                        tile(group, index: idx)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                          spacing: 14) {
                    ForEach(Array(groups.dropFirst(3).enumerated()), id: \.element.id) { idx, group in
                        tile(group, index: idx + 3)
                    }
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 14)], spacing: 14) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                    tile(group, index: idx)
                }
            }
        }
    }

    private func tile(_ group: CleanGroup, index: Int) -> some View {
        GroupTile(group: group, gem: TileGems.gem(for: index),
                  onToggle: { store.toggleGroup(group.id) },
                  onReview: { withAnimation(Motion.standard) { reviewing = group.id } },
                  onQuitApp: { store.quitApp(groupID: group.id) })
    }

    private var cleanButton: some View {
        CircleActionButton(title: "Dọn", accent: skin.action,
                           isEnabled: store.totalSelected > 0) {
            cleanScope = nil
            if settings.confirmBeforeClean { confirming = true } else { store.clean() }
        }
        .padding(.bottom, 22)
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
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer(minLength: 4)
            }

            Spacer(minLength: 10)

            // Chưa chọn gì thì đưa tổng ra, mờ hơn — hiện "0 KB" chỉ làm người dùng tưởng thẻ rỗng.
            Text(group.items.isEmpty && group.needsFullDiskAccess
                 ? "Cần quyền"
                 : Fmt.size(group.selectedSize > 0 ? group.selectedSize : group.totalSize))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(group.selectedSize > 0 ? 1 : 0.55))
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.7)

            Text(group.selectedSize > 0
                 ? "\(group.items.count) mục · \(group.subtitle)"
                 : "chưa chọn mục nào · \(group.items.count) mục · \(group.subtitle)")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)

            HStack(spacing: 6) {
                // Chỉ một nhãn: nhồi nhiều nhãn vào hàng này là nút bị nén tới mức cắt mất chữ.
                if group.needsFullDiskAccess {
                    SafetyBadge(level: .sensitive)
                } else if group.items.contains(where: \.requiresAdmin) {
                    AdminBadge()
                } else if group.safety != .safe {
                    SafetyBadge(level: group.safety)
                }
                Spacer(minLength: 4)
                if group.needsFullDiskAccess {
                    PillButton(title: "Cấp quyền", kind: .warning, action: openFullDiskAccess)
                        .fixedSize()
                } else if group.runningBundleID != nil, let onQuitApp {
                    PillButton(title: "Thoát", kind: .warning, action: onQuitApp)
                        .fixedSize()
                }
                PillButton(title: "Xem", kind: hovering ? .solid : .glass, action: onReview)
                    .fixedSize()
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(height: 200, alignment: .topLeading)
        .tileSurface(gem: gem, icon: group.icon, bundleID: group.appBundleID,
                     highlighted: hovering)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
        .onTapGesture(perform: onReview)
    }
}

// MARK: - Danh sách chi tiết của một nhóm

/// Cùng ngôn ngữ với lưới ngoài: mỗi phần là một thẻ mang màu riêng. Bên trong thẻ, các mục
/// lại chia thành cụm nhỏ theo loại dữ liệu — mười bảy dòng phẳng lì thì không ai đọc nổi.
struct GroupDetailView: View {
    let group: CleanGroup
    let skin: ModuleSkin
    let gemBase: Int
    let groupSelectedSize: Int64
    var onBack: () -> Void
    var onToggleGroup: () -> Void
    var onToggleItem: (UUID) -> Void
    var onToggleCategory: (String) -> Void
    var onQuitApp: () -> Void
    var onClean: () -> Void

    private var sections: [(title: String, items: [CleanItem], hasCategory: Bool)] {
        if group.categories.isEmpty {
            return [(group.title, group.items, false)]
        }
        return group.categories.map { ($0, group.items(in: $0), true) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 16)

            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                            PartCard(title: section.title,
                                     icon: section.hasCategory
                                        ? Self.icon(forPart: section.title) : group.icon,
                                     bundleID: group.categoryAppIDs[section.title]
                                        ?? (section.hasCategory ? nil : group.appBundleID),
                                     subtitle: section.hasCategory ? "" : group.subtitle,
                                     gem: TileGems.gem(for: gemBase + idx),
                                     items: section.items,
                                     subcategories: section.hasCategory
                                        ? group.subcategories(in: section.title) : [],
                                     selection: section.hasCategory
                                        ? group.selection(in: section.title) : group.selection,
                                     onToggleAll: {
                                         if section.hasCategory { onToggleCategory(section.title) }
                                         else { onToggleGroup() }
                                     },
                                     onToggleItem: onToggleItem)
                        }
                    }
                    .padding(.horizontal, Metrics.contentPadding)
                    .padding(.bottom, 140)
                }

                BottomFade(height: 190)
            }
        }
        .overlay(alignment: .bottom) { cleanButton }
    }

    // MARK: Đầu trang

    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    if let bid = group.appBundleID,
                       let icon = AppIconProvider.icon(forBundleID: bid) {
                        Image(nsImage: icon)
                            .resizable().interpolation(.high)
                            .frame(width: 34, height: 34)
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    }
                    Text(group.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("\(group.selectedCount)/\(group.items.count) mục · \(Fmt.size(groupSelectedSize)) trong \(Fmt.size(group.totalSize))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecond)
                    .contentTransition(.numericText())

                if group.needsFullDiskAccess || group.runningBundleID != nil {
                    noticeBar
                }
            }
            .frame(maxWidth: 640)

            HStack {
                PillButton(title: "Quay lại", systemImage: "chevron.left", action: onBack)
                Spacer()
                IconToolbar(actions: [
                    .init(icon: group.selection == .all ? "circle.slash" : "checkmark.circle",
                          help: group.selection == .all ? "Bỏ chọn tất cả" : "Chọn tất cả",
                          run: onToggleGroup)
                ])
            }
            .padding(.horizontal, Metrics.contentPadding)
        }
    }

    /// Một dải nhỏ cho lời nhắc, thay vì một nút to chiếm giữa trang.
    private var noticeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: group.needsFullDiskAccess ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
            Text(group.needsFullDiskAccess
                 ? "Một phần danh sách bị macOS chặn"
                 : "Trình duyệt đang mở — nên thoát trước khi dọn")
                .font(.system(size: 11.5, weight: .medium))

            Button(group.needsFullDiskAccess ? "Cấp quyền" : "Thoát app") {
                if group.needsFullDiskAccess { openFullDiskAccess() } else { onQuitApp() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.22)))
        }
        .foregroundStyle(.black.opacity(0.82))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.warning))
        .clipShape(Capsule())
    }

    private var cleanButton: some View {
        CircleActionButton(title: "Dọn", accent: skin.action,
                           isEnabled: groupSelectedSize > 0, action: onClean)
            .padding(.bottom, 22)
    }

    static func icon(forPart part: String) -> String {
        switch part {
        case BrowserPrivacyScanner.Part.history:   return "clock.arrow.circlepath"
        case BrowserPrivacyScanner.Part.downloads: return "arrow.down.circle.fill"
        case BrowserPrivacyScanner.Part.cookies:   return "person.badge.key.fill"
        case BrowserPrivacyScanner.Part.autofill:  return "rectangle.and.pencil.and.ellipsis"
        case BrowserPrivacyScanner.Part.sessions:  return "rectangle.on.rectangle"
        case BrowserPrivacyScanner.Part.cache:     return "shippingbox.fill"
        case BrowserPrivacyScanner.Part.siteData:  return "externaldrive.fill"
        default:                                    return "folder.fill"
        }
    }
}

// MARK: - Một phần trong nhóm

struct PartCard: View {
    let title: String
    let icon: String
    var bundleID: String? = nil
    var subtitle: String = ""
    let gem: [Color]
    let items: [CleanItem]
    var subcategories: [String] = []
    let selection: CleanGroup.Selection
    var onToggleAll: () -> Void
    var onToggleItem: (UUID) -> Void

    private let visibleLimit = 120

    private var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    private var worstSafety: SafetyLevel { items.map(\.safety).max() ?? .safe }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.16))
            body_
        }
        // Không tô màu riêng: thẻ để lộ đúng nền cửa sổ, chỉ còn đường viền và một lớp
        // sáng rất nhẹ ở đầu thẻ để tách phần tiêu đề khỏi danh sách.
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 11) {
            TriStateBox(state: selection, action: onToggleAll)

            if let bundleID, let appIcon = AppIconProvider.icon(forBundleID: bundleID) {
                Image(nsImage: appIcon)
                    .resizable().interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 22)
            }

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if worstSafety != .safe { SafetyBadge(level: worstSafety) }
            if items.contains(where: \.requiresAdmin) { AdminBadge() }

            Spacer(minLength: 6)

            Text("\(items.filter(\.isSelected).count)/\(items.count)")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.7))

            Text(selectedSize == totalSize ? Fmt.size(totalSize)
                                           : "\(Fmt.size(selectedSize)) / \(Fmt.size(totalSize))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color.white.opacity(0.07))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleAll)
    }

    private var body_: some View {
        let shown = Array(items.prefix(visibleLimit))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, item in
                ItemRow(item: item,
                        showsDivider: idx < shown.count - 1) { onToggleItem(item.id) }
            }

            if items.count > visibleLimit {
                Text("… và \(items.count - visibleLimit) mục nữa (đã tính vào tổng)")
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Một dòng

struct ItemRow: View {
    let item: CleanItem
    var showsDivider: Bool = false
    var onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckBox(isOn: item.isSelected, action: onToggle).padding(.leading, 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.rowTitle).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                if !item.detail.isEmpty {
                    Text(item.detail).font(.rowDetail)
                        .foregroundStyle(Color.white.opacity(0.72))
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
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 74, alignment: .trailing)
                .padding(.trailing, 16)
        }
        .frame(height: 42)
        .background(hovering ? Color.white.opacity(0.07) : .clear)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)
                    .padding(.leading, 42)
                    .padding(.trailing, 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}

// MARK: - Lớp phủ lúc dọn

struct DoneScreen: View {
    @ObservedObject var store: ScanStore
    let skin: ModuleSkin

    var body: some View {
        ZStack {
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


/// Mở thẳng mục Toàn quyền truy cập đĩa trong Cài đặt Hệ thống.
func openFullDiskAccess() {
    guard let url = URL(string:
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    else { return }
    NSWorkspace.shared.open(url)
}
