import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var settingsTab: SettingsPanel.Tab = .general

    private var skin: ModuleSkin { ModuleSkin.skin(for: state.module) }

    var body: some View {
        ZStack {
            // Nền của mọi mục vẽ chồng lên nhau, chỉ đổi độ mờ khi chuyển mục.
            // Cách này cho phép màu chuyển mượt (gradient không nội suy trực tiếp được)
            // mà vẫn rẻ vì chỉ là thay đổi opacity trên GPU.
            ZStack {
                ForEach(CleanModule.allCases) { m in
                    ModuleSkin.skin(for: m).background
                        .opacity(state.module == m ? 1 : 0)
                }
            }
            .ignoresSafeArea()
            .animation(Motion.skin, value: state.module)

            VStack(spacing: 0) {
                Spacer().frame(height: Metrics.titleBarHeight)
                content
            }
            .padding(.leading, Metrics.sidebarWidth)

            // Tiêu đề phải căn giữa đúng vùng nội dung, giống mọi thứ khác trong trang.
            // Căn giữa cả cửa sổ thì nó lệch khỏi tiêu đề trang đúng bằng nửa bề rộng sidebar.
            VStack {
                TitleBar(title: state.module.title)
                Spacer()
            }
            .padding(.leading, Metrics.sidebarWidth)

            // Sidebar nằm đè lên nội dung để lúc nở ra bố cục không bị đẩy.
            HStack(spacing: 0) {
                SidebarView(selection: $state.module) {
                    withAnimation(Motion.gentle) { state.showSettings = true }
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .overlay {
            if state.showSettings {
                SettingsPanel(tab: $settingsTab) {
                    withAnimation(Motion.gentle) { state.showSettings = false }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcOpenSettings)) { note in
            if let raw = note.object as? String,
               let t = SettingsPanel.Tab(rawValue: raw) { settingsTab = t }
            withAnimation(Motion.gentle) { state.showSettings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcSelectModule)) { note in
            guard let raw = note.object as? String,
                  let m = CleanModule(rawValue: raw) else { return }
            withAnimation(Motion.standard) { state.module = m }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch state.module {
            case .smartScan:
                GroupedModuleView(store: state.scanStore(for: state.module), module: state.module)
            case .uninstaller:
                UninstallerView(store: state.uninstall)
            case .largeOld:
                LargeOldView(store: state.largeOld)
            case .duplicates:
                DuplicatesView(store: state.duplicates)
            }
        }
        .transition(.opacity)
        .id(state.module)
        .animation(Motion.standard, value: state.module)
    }
}

/// Thanh tiêu đề tự vẽ: tên mục nằm giữa, chừa chỗ cho ba nút hệ thống bên trái.
struct TitleBar: View {
    var title: String
    var leading: AnyView?

    init(title: String, @ViewBuilder leading: () -> some View = { EmptyView() }) {
        self.title = title
        self.leading = AnyView(leading())
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecond)
            HStack {
                leading
                Spacer()
            }
            .padding(.leading, 6)
        }
        .frame(height: Metrics.titleBarHeight)
        .padding(.horizontal, 14)
    }
}
