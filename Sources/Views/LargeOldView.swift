import SwiftUI
import AppKit

struct LargeOldView: View {
    @ObservedObject var store: LargeOldStore
    @EnvironmentObject private var settings: AppSettings
    @State private var confirming = false

    private let skin = ModuleSkin.skin(for: .largeOld)

    var body: some View {
        VStack(spacing: 0) {
            if store.files.isEmpty && !store.isScanning && store.hasScanned {
                emptyResult
            } else if store.files.isEmpty && !store.isScanning {
                startScreen
            } else {
                toolbar
                    .padding(.horizontal, Metrics.contentPadding)
                    .padding(.bottom, 12)
                body_
            }
        }
        .overlay(alignment: .bottom) {
            if !store.files.isEmpty && !store.isScanning { bottomBar }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in store.scan() }
        .confirmationDialog("Chuyển \(store.selected.count) tệp vào Thùng rác?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Chuyển vào Thùng rác", role: .destructive) { store.remove() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("Tệp cá nhân luôn được chuyển vào Thùng rác để bạn còn lấy lại được.")
        }
    }

    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            ModuleIntro(title: CleanModule.largeOld.title,
                        subtitle: "Tìm các tệp từ \(settings.largeMinMB) MB trở lên trong thư mục nhà. Library và node_modules được bỏ qua cho nhanh.",
                        icon: CleanModule.largeOld.icon,
                        gem: skin.gem,
                        highlights: CleanModule.largeOld.highlights) {
                ActionButton(title: "Chọn thư mục khác…", systemImage: "folder") { pickRoot() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            CircleActionButton(title: "Quét", accent: skin.action) { store.scan() }
                .padding(.bottom, Metrics.actionButtonBottom)
        }
    }

    /// Quét xong mà không có gì: phải nói ra, chứ ném người dùng về màn khởi đầu thì họ
    /// tưởng cái nút không ăn.
    private var emptyResult: some View {
        VStack(spacing: 18) {
            EmptyStateView(icon: "checkmark.seal",
                           title: "Không có tệp nào lớn hơn \(settings.largeMinMB) MB",
                           message: "Thử hạ mốc trong Cài đặt ▸ Quét, hoặc chọn thư mục khác để tìm.",
                           gem: skin.gem)
            HStack(spacing: 10) {
                ActionButton(title: "Chọn thư mục…", systemImage: "folder") { pickRoot() }
                ActionButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                ActionButton(title: "Quay lại", systemImage: "chevron.left") { store.backToStart() }
            }
            .padding(.bottom, 30)
        }
    }

    @ViewBuilder
    private var body_: some View {
        if store.isScanning {
            VStack(spacing: 16) {
                ScanRing(mode: .scanning(store.progress), bytes: 0,
                         caption: store.statusText, diameter: 170, accent: skin.glow)
                ActionButton(title: "Dừng", systemImage: "stop.fill") { store.cancel() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.visibleFiles) { f in
                            FileRow(found: f, isSelected: store.selected.contains(f.url)) {
                                store.toggle(f.url)
                            }
                        }
                    }
                    .padding(8)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.never)
                .glass()
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, Metrics.contentPadding)

                BottomFade(height: 120).padding(.bottom, Metrics.contentPadding)
                    .allowsHitTesting(false)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Quay lại", systemImage: "chevron.left") { store.backToStart() }
            ForEach(LargeOldStore.Filter.allCases) { f in
                FilterChip(title: f.rawValue, isOn: store.filter == f) {
                    withAnimation(Motion.snappy) { store.filter = f }
                }
            }
            Spacer()
            SearchField(placeholder: "Lọc theo tên", text: $store.search, width: 190)
            ActionButton(title: "Chọn thư mục…", systemImage: "folder") { pickRoot() }
            ActionButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text(store.selected.isEmpty
                 ? "\(store.visibleFiles.count) tệp · \(Fmt.size(store.files.reduce(0) { $0 + $1.size }))"
                 : "Đã chọn \(store.selected.count) tệp · \(Fmt.size(store.selectedSize))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.textSecond)
            CircleActionButton(title: "Xoá", accent: skin.action,
                               isEnabled: !store.selected.isEmpty) { confirming = true }
        }
        .padding(.bottom, Metrics.actionButtonBottom)
    }

    private func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Quét"
        panel.directoryURL = FileUtils.home
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            store.roots = panel.urls
            store.scan()
        }
    }
}

private struct FileRow: View {
    let found: LargeOldScanner.Found
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckBox(isOn: isSelected, action: onToggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: found.url.path))
                .resizable().frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(found.url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                Text(FileUtils.prettyPath(found.url.deletingLastPathComponent()))
                    .font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if found.isOld {
                Text("lâu không dùng")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.warning)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.warning.opacity(0.20)))
            }

            Text(found.kind).font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
                .frame(width: 86, alignment: .trailing)
            Text(Fmt.relativeAge(found.lastTouched))
                .font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
                .frame(width: 96, alignment: .trailing)
            Text(Fmt.size(found.size))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 78, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([found.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Palette.textSecond : .clear)
            }
            .buttonStyle(.plain).help("Hiện trong Finder")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.16)
                             : (hovering ? Color.white.opacity(0.07) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}
