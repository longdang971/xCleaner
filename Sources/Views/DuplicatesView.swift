import SwiftUI
import AppKit

struct DuplicatesView: View {
    @ObservedObject var store: DuplicateStore
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Tệp trùng lặp",
                       subtitle: "So khớp nội dung từng byte, không dựa vào tên tệp") {
                HStack(spacing: 8) {
                    SecondaryButton(title: "Chọn thư mục…", systemImage: "folder") { pickRoots() }
                    if store.isScanning {
                        SecondaryButton(title: "Dừng", systemImage: "stop.fill") { store.cancel() }
                    } else {
                        SecondaryButton(title: store.sets.isEmpty ? "Quét" : "Quét lại",
                                        systemImage: "square.on.square") { store.scan() }
                    }
                }
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.top, 34)
            .padding(.bottom, 16)

            if store.isScanning {
                VStack(spacing: 14) {
                    ScanRing(mode: .scanning(store.progress), bytes: 0,
                             caption: store.statusText, diameter: 150)
                    Text("Ba vòng lọc: kích thước → băm nhanh → so từng byte")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.sets.isEmpty {
                EmptyStateView(icon: "square.on.square",
                               title: "Chưa có dữ liệu",
                               message: "Bấm Quét để tìm bản sao trong Documents, Downloads, Desktop, Pictures và Movies.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.sets) { set in
                            DuplicateCard(set: set,
                                          selected: store.selected,
                                          onToggle: { store.toggle($0, in: set) })
                        }
                    }
                    .padding(.horizontal, Metrics.contentPadding)
                    .padding(.bottom, 96)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !store.sets.isEmpty && !store.isScanning { bottomBar }
        }
        .confirmationDialog("Chuyển \(store.selected.count) bản sao vào Thùng rác?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Chuyển vào Thùng rác", role: .destructive) { store.remove() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("Mỗi nhóm luôn giữ lại ít nhất một bản.")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Có thể lấy lại \(Fmt.size(store.reclaimable))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Đã chọn \(store.selected.count) bản sao · \(Fmt.size(store.selectedSize))")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            SecondaryButton(title: "Chọn tự động", systemImage: "wand.and.stars") {
                withAnimation(Motion.snappy) { store.autoSelect() }
            }
            PrimaryButton(title: "Xoá bản sao", systemImage: "trash",
                          isEnabled: !store.selected.isEmpty) { confirming = true }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 20, y: 6))
        .padding(.horizontal, Metrics.contentPadding)
        .padding(.bottom, 18)
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
                        .font(.cardTitle).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text("\(set.files.count) bản · mỗi bản \(Fmt.size(set.size))")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.size(set.reclaimable))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.accent)
                    Text("lấy lại được").font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(14)

            Divider().overlay(Palette.hairline)

            VStack(spacing: 0) {
                ForEach(set.files, id: \.self) { url in
                    DuplicateFileRow(url: url,
                                     isSelected: selected.contains(url),
                                     onToggle: { onToggle(url) })
                }
            }
            .padding(.vertical, 4)
        }
        .cardBackground()
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

            VStack(alignment: .leading, spacing: 1) {
                Text(FileUtils.prettyPath(url))
                    .font(.system(size: 11.5))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)

            if !isSelected {
                Text("giữ lại")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.success)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.success.opacity(0.14)))
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Palette.textSecondary : .clear)
            }
            .buttonStyle(.plain).padding(.trailing, 16)
        }
        .frame(height: 30)
        .background(hovering ? Palette.accent.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}
