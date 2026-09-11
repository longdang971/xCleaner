import SwiftUI

struct SidebarView: View {
    @Binding var selection: CleanModule
    @Namespace private var pill
    @State private var hovered: CleanModule?

    private let cleaning: [CleanModule] = [.smartScan, .systemJunk, .trashDownloads, .privacy]
    private let tools: [CleanModule] = [.uninstaller, .largeOld, .duplicates]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 44)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)

            section("DỌN DẸP", cleaning)
            section("TIỆN ÍCH", tools).padding(.top, 16)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                DiskUsageBar()
                HStack(spacing: 8) {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Label("Tuỳ chọn", systemImage: "gearshape")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Vibrancy cho có chiều sâu, nhưng phủ thêm màu của bảng màu lên trên:
        // nếu không, khi app ở chế độ tối mà hệ thống đang sáng, lớp mờ sẽ kéo nền sáng qua.
        .background {
            ZStack {
                VisualEffectBackground(material: .sidebar)
                Palette.sidebar.opacity(0.62)
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accentGradient)
                    .frame(width: 30, height: 30)
                    .shadow(color: Palette.accentStart.opacity(0.4), radius: 8, y: 3)
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("xCleaner").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Phiên bản \(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    private func section(_ title: String, _ modules: [CleanModule]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

            ForEach(modules) { m in
                row(m)
            }
        }
    }

    private func row(_ m: CleanModule) -> some View {
        let isSelected = selection == m
        return Button {
            guard selection != m else { return }
            withAnimation(Motion.standard) { selection = m }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: m.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : Palette.textSecondary)
                Text(m.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.accentGradient)
                        .matchedGeometryEffect(id: "pill", in: pill)
                        .shadow(color: Palette.accentStart.opacity(0.35), radius: 8, y: 3)
                } else if hovered == m {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.textPrimary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .onHover { h in withAnimation(Motion.gentle) { hovered = h ? m : (hovered == m ? nil : hovered) } }
    }
}
