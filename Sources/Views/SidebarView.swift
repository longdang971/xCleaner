import SwiftUI

/// Dải icon hẹp bên trái. Rê chuột vào thì nở ra kèm tên từng mục rồi thu lại khi chuột rời đi,
/// nên vừa gọn khi không dùng tới, vừa đọc được khi cần chọn.
struct SidebarView: View {
    @Binding var selection: CleanModule

    @State private var expanded = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCLEANER_SIDEBAR"] == "expanded"
        #else
        return false
        #endif
    }()
    @State private var hovered: CleanModule?

    private let cleaning: [CleanModule] = [.smartScan, .systemJunk, .trashDownloads, .privacy]
    private let tools: [CleanModule] = [.uninstaller, .largeOld, .duplicates]

    private var width: CGFloat { expanded ? Metrics.sidebarExpanded : Metrics.sidebarWidth }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
                .padding(.top, Metrics.titleBarHeight + 10)
                .padding(.bottom, 26)

            group(cleaning, label: "DỌN DẸP")
            group(tools, label: "TIỆN ÍCH").padding(.top, 14)

            Spacer(minLength: 10)

            DiskUsageRing(expanded: expanded)
                .padding(.leading, 23)
                .padding(.bottom, 10)

            settingsButton
                .padding(.bottom, 16)
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                Color.black.opacity(expanded ? 0.82 : 0.18)
                LinearGradient(colors: [.white.opacity(expanded ? 0.05 : 0), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            if expanded {
                Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1).ignoresSafeArea()
            }
        }
        .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 24, x: 6)
        .onHover { inside in
            withAnimation(Motion.standard) { expanded = inside }
            if !inside { hovered = nil }
        }
        .animation(Motion.standard, value: expanded)
    }

    // MARK: Thành phần

    private var logo: some View {
        HStack(spacing: 10) {
            ZStack {
                Squircle()
                    .fill(LinearGradient(colors: [Color(hex: "#A78BFA"), Color(hex: "#6D28D9")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Squircle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .shadow(color: Color(hex: "#6D28D9").opacity(0.6), radius: 10, y: 3)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("xCleaner").font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Phiên bản \(appVersion)")
                        .font(.system(size: 10)).foregroundStyle(Palette.textFaint)
                }
                .fixedSize()
                .transition(.opacity)
            }
        }
        .padding(.leading, 22)
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    private func group(_ modules: [CleanModule], label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(expanded ? label : " ")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Palette.textFaint)
                .padding(.leading, 22)
                .padding(.bottom, 3)
                .opacity(expanded ? 1 : 0)
                .frame(height: 12)

            ForEach(modules) { row($0) }
        }
    }

    private func row(_ m: CleanModule) -> some View {
        let isSelected = selection == m
        let skin = ModuleSkin.skin(for: m)

        return Button {
            guard selection != m else { return }
            withAnimation(Motion.standard) { selection = m }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        Squircle()
                            .fill(LinearGradient(colors: [skin.gem[0].opacity(0.95),
                                                          skin.gem[1].opacity(0.95)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Squircle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    } else if hovered == m {
                        Squircle().fill(Color.white.opacity(0.14))
                    }
                    Image(systemName: m.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? .white : Palette.textSecond)
                }
                .frame(width: 34, height: 34)
                .shadow(color: isSelected ? skin.gem[1].opacity(0.55) : .clear, radius: 9, y: 3)

                if expanded {
                    Text(m.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : Palette.textSecond)
                        .fixedSize()
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 19)
            .padding(.trailing, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "" : m.title)
        .onHover { h in
            withAnimation(Motion.gentle) { hovered = h ? m : (hovered == m ? nil : hovered) }
        }
    }

    private var settingsButton: some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textSecond)
                    .frame(width: 34, height: 26)
                if expanded {
                    Text("Tuỳ chọn").font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecond)
                        .fixedSize().transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 19)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "" : "Tuỳ chọn")
    }
}
