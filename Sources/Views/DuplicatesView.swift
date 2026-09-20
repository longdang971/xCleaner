import SwiftUI
import AppKit

struct DuplicatesView: View {
    @ObservedObject var store: DuplicateStore
    @State private var confirming = false

    private let skin = ModuleSkin.skin(for: .duplicates)

    var body: some View {
        VStack(spacing: 0) {
            if store.sets.isEmpty && !store.isScanning && store.hasScanned {
                emptyResult
            } else if store.sets.isEmpty && !store.isScanning {
                startScreen
            } else if store.isScanning {
                VStack(spacing: 16) {
                    ScanRing(mode: .scanning(store.progress), bytes: 0,
                             caption: store.statusText, diameter: 170, accent: skin.glow)
                    Text("Ba vòng lọc: kích thước → băm nhanh → so từng byte")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.textSecond)
                    ActionButton(title: "Dừng", systemImage: "stop.fill") { store.cancel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HeroHeadline(title: "Có thể lấy lại \(Fmt.size(store.reclaimable))",
                             subtitle: "\(store.sets.count) nhóm trùng lặp · mỗi nhóm luôn giữ lại ít nhất một bản") {
                    HStack(spacing: 8) {
                        ActionButton(title: "Quay lại", systemImage: "chevron.left") {
                            store.backToStart()
                        }
                        ActionButton(title: "Chọn tự động", systemImage: "wand.and.stars") {
                            withAnimation(Motion.snappy) { store.autoSelect() }
                        }
                        ActionButton(title: "Chọn thư mục…", systemImage: "folder") { pickRoots() }
                        ActionButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                    }
                }
                .padding(.bottom, 20)

                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.sets) { set in
                                DuplicateCard(set: set, selected: store.selected,
                                              onToggle: { store.toggle($0, in: set) })
                            }
                        }
                        .padding(.horizontal, Metrics.contentPadding)
                        .padding(.bottom, 130)
                    }
                    .scrollIndicators(.never)
                    BottomFade()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !store.sets.isEmpty && !store.isScanning { bottomBar }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcRescan)) { _ in store.scan() }
        .confirmationDialog("Chuyển \(store.selected.count) bản sao vào Thùng rác?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Chuyển vào Thùng rác", role: .destructive) { store.remove() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("Mỗi nhóm luôn giữ lại ít nhất một bản.")
        }
    }

    /// Quét xong mà không có nhóm trùng nào — nói thẳng ra thay vì quay về màn khởi đầu.
    private var emptyResult: some View {
        VStack(spacing: 18) {
            EmptyStateView(icon: "checkmark.seal",
                           title: "Không tìm thấy tệp trùng nào",
                           message: "Những thư mục vừa quét không có hai tệp nào giống hệt nhau. Thử chọn thư mục khác, hoặc hạ mốc bỏ qua trong Cài đặt ▸ Quét.",
                           gem: skin.gem)
            HStack(spacing: 10) {
                ActionButton(title: "Chọn thư mục…", systemImage: "folder") { pickRoots() }
                ActionButton(title: "Quét lại", systemImage: "arrow.clockwise") { store.scan() }
                ActionButton(title: "Quay lại", systemImage: "chevron.left") { store.backToStart() }
            }
            .padding(.bottom, 30)
        }
    }

    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            ModuleIntro(title: CleanModule.duplicates.title,
                        subtitle: "So khớp nội dung từng byte, không dựa vào tên tệp. Tìm trong Documents, Downloads, Desktop, Pictures và Movies.",
                        icon: CleanModule.duplicates.icon,
                        gem: skin.gem,
                        highlights: CleanModule.duplicates.highlights) {
                ActionButton(title: "Chọn thư mục khác…", systemImage: "folder") { pickRoots() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            CircleActionButton(title: "Quét", accent: skin.action) { store.scan() }
                .padding(.bottom, Metrics.actionButtonBottom)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text("Đã chọn \(store.selected.count) bản sao · \(Fmt.size(store.selectedSize))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.textSecond)
            CircleActionButton(title: "Xoá", accent: skin.action,
                               isEnabled: !store.selected.isEmpty) { confirming = true }
        }
        .padding(.bottom, Metrics.actionButtonBottom)
    }

    private func pickRoots() {
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

private struct DuplicateCard: View {
    let set: DuplicateScanner.DuplicateSet
    let selected: Set<URL>
    let onToggle: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: set.files[0].path))
                    .resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.files[0].lastPathComponent)
                        .font(.cardTitle).foregroundStyle(.white).lineLimit(1)
                    Text("\(set.files.count) bản · mỗi bản \(Fmt.size(set.size))")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecond)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.size(set.reclaimable))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("lấy lại được").font(.system(size: 10)).foregroundStyle(Palette.textFaint)
                }
            }
            .padding(14)

            Divider().overlay(Color.white.opacity(0.12))

            VStack(spacing: 0) {
                ForEach(set.files, id: \.self) { url in
                    DuplicateFileRow(url: url, isSelected: selected.contains(url),
                                     onToggle: { onToggle(url) })
                }
            }
            .padding(.vertical, 4)
        }
        .glass()
    }
}

private struct DuplicateFileRow: View {
    let url: URL
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            CheckBox(isOn: isSelected, action: onToggle).padding(.leading, 16)
            Text(FileUtils.prettyPath(url))
                .font(.system(size: 11.5))
                .foregroundStyle(isSelected ? .white : Palette.textSecond)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if !isSelected {
                Text("giữ lại")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.success)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.success.opacity(0.20)))
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Palette.textSecond : .clear)
            }
            .buttonStyle(.plain).padding(.trailing, 16)
        }
        .frame(height: 30)
        .background(hovering ? Color.white.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}
