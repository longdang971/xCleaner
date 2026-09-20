import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var settingsTab: SettingsView.Tab = .general

    /// Dải trong suốt ở đáy cửa sổ. Về 0 khi toàn màn hình: ở đó không có desktop nào phía sau
    /// để nhìn xuyên xuống, dải trống chỉ thành một vệt đen dưới đáy.
    @State private var bottomInset: CGFloat = Metrics.windowBottomInset

    /// 1 = trang mới dâng từ dưới lên (đi xuống danh sách), −1 = đổ từ trên xuống (đi lên).
    @State private var pageDirection: CGFloat = 1

    /// Nút tròn của trang đang xem, do chính trang khai báo qua `bottomAction(_:)`.
    @State private var action: BottomAction?

    private var skin: ModuleSkin { ModuleSkin.skin(for: state.module) }

    /// Tông màu của trang đang xem. Khác `skin` ở chỗ trang Cài đặt có tông riêng.
    private var pageSkin: ModuleSkin { state.showSettings ? .settings : skin }

    /// Khoá của trang đang xem. Cài đặt là một trang ngang hàng với các mục quét,
    /// nên chuyển sang nó cũng đổi nền, đổi tiêu đề và chạy đúng hiệu ứng như đổi mục.
    private var pageKey: String { state.showSettings ? "settings" : state.module.rawValue }

    var body: some View {
        ZStack {
            // Nền của mọi trang vẽ chồng lên nhau, chỉ đổi độ mờ khi chuyển trang.
            // Cách này cho phép màu chuyển mượt (gradient không nội suy trực tiếp được)
            // mà vẫn rẻ vì chỉ là thay đổi opacity trên GPU.
            ZStack {
                // Lớp đục tuyệt đối dưới cùng. Nền các trang chồng mờ lên nhau lúc đổi màu, và
                // giữa chừng tổng độ đục tụt xuống dưới 1 — hồi cửa sổ còn đục thì không ai
                // thấy, từ lúc cửa sổ trong suốt thì nhìn xuyên xuống cả app nằm sau xCleaner.
                Color(hex: "#101219")
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
                    // `id` để SwiftUI coi mỗi trang là một view KHÁC — không có nó thì nó chỉ
                    // thay nội dung tại chỗ và chẳng có gì để trượt.
                    .id(pageKey)
                    .transition(.pageSwap(direction: pageDirection))
            }
            // Khuôn đứng yên, trang trượt qua nó. Phải cắt TRƯỚC khi cộng lề trái, vì khuôn có
            // bướu tròn ở giữa mép dưới và "giữa" ở đây là giữa VÙNG NỘI DUNG chứ không phải
            // giữa cửa sổ.
            .clipShape(PageClip())
            .onPreferenceChange(BottomActionKey.self) { self.action = $0 }
            .padding(.leading, Metrics.sidebarWidth)

            // Nút chính nằm NGOÀI lớp bị đẩy, nên nó đứng yên suốt cú chuyển trang và chỉ đổi
            // chữ với đổi màu — giống nút Scan của CleanMyMac. Nằm trong lớp bị đẩy thì nó
            // trượt đi theo trang, và giữa chừng có hai nút cùng hiện.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let action {
                    CircleActionButton(title: action.title,
                                       accent: pageSkin.action,
                                       isEnabled: action.isEnabled,
                                       progress: action.progress,
                                       action: action.action)
                        .padding(.bottom, Metrics.actionButtonBottom)
                        .transition(.opacity)
                }
            }
            .padding(.leading, Metrics.sidebarWidth)
            .animation(Motion.gentle, value: action)

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
                                               set: { go(to: $0, settings: false) }),
                            settingsActive: state.showSettings,
                            skin: pageSkin) {
                    go(to: nil, settings: true)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Cắt CẢ TRANG theo hình tấm nền, không chỉ riêng lớp nền. Sidebar là anh em cùng
        // ZStack với lớp nền chứ không nằm trong nó, nên nếu chỉ cắt lớp nền thì hộp tối của
        // sidebar vẫn vuông góc ở đáy và bóng của nó loang xuống dải trong suốt — đúng chỗ góc
        // dưới bên trái nhìn như lỗi vẽ. Bướu tròn trong `CardShape` chừa đường cho nút thò ra.
        .clipShape(CardShape())
        // Cả trang co lên, chừa dải trong suốt ở đáy cho nút tròn thò xuống. `padding` KHÔNG
        // cắt nội dung, nên nút vẽ tràn vào dải này vẫn hiện trọn vẹn.
        .padding(.bottom, bottomInset)
        // Phải nằm NGOÀI `clipShape`. Để bên trong thì khuôn cắt lấy theo vùng an toàn — vùng
        // đã trừ mất dải thanh tiêu đề — nên đỉnh app bị xén một dải trong suốt, ba nút đèn
        // giao thông nổi trên nền trắng của thứ phía sau.
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            bottomInset = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            bottomInset = Metrics.windowBottomInset
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .xcOpenSettings)) { note in
            if let raw = note.object as? String,
               let t = SettingsView.Tab(rawValue: raw) { settingsTab = t }
            go(to: nil, settings: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcCheckUpdates)) { _ in
            settingsTab = .about
            state.requestUpdateCheck = true
            go(to: nil, settings: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .xcSelectModule)) { note in
            guard let raw = note.object as? String,
                  let m = CleanModule(rawValue: raw) else { return }
            go(to: m, settings: false)
        }
    }

    /// Đổi trang, và ghi lại hướng đi để cú đẩy chạy đúng chiều.
    ///
    /// Thứ tự lấy theo đúng thứ tự mục trên sidebar; Cài đặt nằm cuối cùng vì nó ở đáy sidebar.
    private func go(to module: CleanModule?, settings: Bool) {
        func order(_ module: CleanModule, _ settings: Bool) -> Int {
            settings ? CleanModule.allCases.count
                     : (CleanModule.allCases.firstIndex(of: module) ?? 0)
        }
        let from = order(state.module, state.showSettings)
        let to = order(module ?? state.module, settings)
        guard from != to else { return }
        pageDirection = to > from ? 1 : -1
        // Lò xo tắt dần hoàn toàn (damping 1): còn nảy thì hai trang vẫn khít nhau, nhưng cú
        // dừng bị dội lại một nhịp, đọc ra thành "khựng" đúng như người dùng phàn nàn.
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) {
            if let module { state.module = module }
            state.showSettings = settings
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
        // KHÔNG đặt `.transition`/`.id`/`.animation` ở đây. Ba dòng ấy sót lại từ bản cũ và
        // chính chúng nuốt mất cú đẩy: lớp trong nhận diện thay trang trước, xử lý bằng một
        // cú mờ dần, nên lớp ngoài chẳng còn gì để đẩy — trang cũ biến mất rồi trang mới hiện
        // ra. Việc gán danh tính và hiệu ứng nay nằm hết ở chỗ gọi trong `body`.
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
