import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var settingsTab: SettingsView.Tab = .general

    private var skin: ModuleSkin { ModuleSkin.skin(for: state.module) }

    /// Khoá của trang đang xem. Cài đặt là một trang ngang hàng với các mục quét,
    /// nên chuyển sang nó cũng đổi nền, đổi tiêu đề và chạy đúng hiệu ứng như đổi mục.
    private var pageKey: String { state.showSettings ? "settings" : state.module.rawValue }

    var body: some View {
        ZStack {
            // Nền của mọi trang vẽ chồng lên nhau, chỉ đổi độ mờ khi chuyển trang.
            // Cách này cho phép màu chuyển mượt (gradient không nội suy trực tiếp được)
            // mà vẫn rẻ vì chỉ là thay đổi opacity trên GPU.
            ZStack {
                ForEach(CleanModule.allCases) { m in
                    ModuleSkin.skin(for: m).background
                        .opacity(state.module == m && !state.showSettings ? 1 : 0)
                }
                ModuleSkin.settings.background
                    .opacity(state.showSettings ? 1 : 0)
            }
            .ignoresSafeArea()
            .animation(Motion.skin, value: pageKey)

            VStack(spacing: 0) {
                Spacer().frame(height: Metrics.titleBarHeight)
                content
            }
            .padding(.leading, Metrics.sidebarWidth)

            // Tiêu đề phải căn giữa đúng vùng nội dung, giống mọi thứ khác trong trang.
            // Căn giữa cả cửa sổ thì nó lệch khỏi tiêu đề trang đúng bằng nửa bề rộng sidebar.
            VStack {
                TitleBar(title: state.showSettings ? "Cài đặt" : state.module.title)
                Spacer()
            }
            .padding(.leading, Metrics.sidebarWidth)

            // Sidebar nằm đè lên nội dung để lúc nở ra bố cục không bị đẩy.
            HStack(spacing: 0) {
                SidebarView(selection: Binding(get: { state.module },
                                               set: { m in
                                                   state.module = m
                                                   state.showSettings = false
                                               }),
                            settingsActive: state.showSettings) {
                    withAnimation(Motion.standard) { state.showSettings = true }
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .xcOpenSettings)) { note in
            if let raw = note.object as? String,
               let t = SettingsView.Tab(rawValue: raw) { settingsTab = t }
            withAnimation(Motion.standard) { state.showSettings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcCheckUpdates)) { _ in
            settingsTab = .about
            state.requestUpdateCheck = true
            withAnimation(Motion.standard) { state.showSettings = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcSelectModule)) { note in
            guard let raw = note.object as? String,
                  let m = CleanModule(rawValue: raw) else { return }
            withAnimation(Motion.standard) {
                state.module = m
                state.showSettings = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if state.showSettings {
                SettingsView(tab: $settingsTab)
            } else {
                switch state.module {
                case .smartScan:
                    GroupedModuleView(store: state.scanStore(for: state.module), module: state.module)
                case .uninstaller:
                    UninstallerView(store: state.uninstall)
                case .startup:
                    StartupView(store: state.startup)
                case .largeOld:
                    LargeOldView(store: state.largeOld)
                case .duplicates:
                    DuplicatesView(store: state.duplicates)
                }
            }
        }
        .transition(.opacity)
        .id(pageKey)
        .animation(Motion.standard, value: pageKey)
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
