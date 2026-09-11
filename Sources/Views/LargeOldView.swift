import SwiftUI
import AppKit

struct LargeOldView: View {
    @ObservedObject var store: LargeOldStore
    @EnvironmentObject private var settings: AppSettings
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Tệp lớn & cũ",
                       subtitle: "Những tệp chiếm nhiều chỗ nhất trong thư mục nhà của bạn") {
                HStack(spacing: 8) {
                    SecondaryButton(title: "Chọn thư mục…", systemImage: "folder") { pickRoot() }
                    if store.isScanning {
                        SecondaryButton(title: "Dừng", systemImage: "stop.fill") { store.cancel() }
                    } else {
                        SecondaryButton(title: store.files.isEmpty ? "Quét" : "Quét lại",
                                        systemImage: "magnifyingglass") { store.scan() }
                    }
                }
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.top, 34)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                ForEach(LargeOldStore.Filter.allCases) { f in
                    FilterChip(title: f.rawValue, isOn: store.filter == f) {
                        withAnimation(Motion.snappy) { store.filter = f }
                    }
                }
                Spacer()
                SearchField(placeholder: "Lọc theo tên", text: $store.search).frame(width: 200)
            }
            .padding(.horizontal, Metrics.contentPadding)
            .padding(.bottom, 12)

            if store.isScanning {
                VStack(spacing: 14) {
                    ScanRing(mode: .scanning(store.progress), bytes: 0,
                             caption: store.statusText, diameter: 150)
                    Text("Đang duyệt \(store.roots.map { FileUtils.prettyPath($0) }.joined(separator: ", "))")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.files.isEmpty {
                EmptyStateView(icon: "chart.pie",
                               title: "Chưa có dữ liệu",
                               message: "Bấm Quét để tìm các tệp lớn hơn \(settings.largeMinMB) MB. Thư mục Library và node_modules được bỏ qua cho nhanh.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.visibleFiles) { f in
                            FileRow(found: f, isSelected: store.selected.contains(f.url)) {
                                store.toggle(f.url)
                            }
                        }
                    }
                    .padding(8)
                    .padding(.bottom, 80)
                }
                .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, Metrics.contentPadding)
            }
        }
        .overlay(alignment: .bottom) {
            if !store.files.isEmpty && !store.isScanning {
                bottomBar
            }
        }
        .confirmationDialog("Chuyển \(store.selected.count) tệp vào Thùng rác?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Chuyển vào Thùng rác", role: .destructive) { store.remove() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("Tệp cá nhân luôn được chuyển vào Thùng rác để bạn còn lấy lại được.")
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(store.selected.isEmpty
                 ? "\(store.visibleFiles.count) tệp · \(Fmt.size(store.files.reduce(0) { $0 + $1.size }))"
                 : "Đã chọn \(store.selected.count) tệp · \(Fmt.size(store.selectedSize))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            PrimaryButton(title: "Chuyển vào Thùng rác", systemImage: "trash",
                          isEnabled: !store.selected.isEmpty) { confirming = true }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 20, y: 6))
        .padding(.horizontal, Metrics.contentPadding + 10)
        .padding(.bottom, 26)
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

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? .white : Palette.textSecondary)
                .padding(.horizontal, 13)
                .frame(height: 26)
                .background {
                    if isOn {
                        Capsule().fill(Palette.accentGradient)
                    } else {
                        Capsule().fill(Palette.surfaceAlt)
                            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                            .brightness(hovering ? 0.03 : 0)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { h in hovering = h }
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
                    .foregroundStyle(Palette.textPrimary).lineLimit(1)
                Text(FileUtils.prettyPath(found.url.deletingLastPathComponent()))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if found.isOld {
                Text("lâu không dùng")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.warning)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.warning.opacity(0.14)))
            }

            Text(found.kind).font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 90, alignment: .trailing)

            Text(Fmt.relativeAge(found.accessed ?? found.modified))
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 100, alignment: .trailing)

            Text(Fmt.size(found.size))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 80, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([found.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Palette.textSecondary : .clear)
            }
            .buttonStyle(.plain).help("Hiện trong Finder")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
            .fill(isSelected ? Palette.accent.opacity(0.10)
                             : (hovering ? Palette.textPrimary.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { h in hovering = h }
    }
}
