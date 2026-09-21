import SwiftUI
import AppKit

/// Cửa sổ nhỏ nổi lên khi người dùng tự kéo một ứng dụng vào Thùng rác.
///
/// Đây là mặt duy nhất của xCleaner mà người dùng thấy khi app đang chạy nền, nên nó phải mang
/// đúng ngôn ngữ giao diện của app (nền chàm của mục "Gỡ ứng dụng", thẻ kính, nút của app) chứ
/// không phải một hộp thoại hệ thống màu trắng.
@MainActor
enum LeftoverPanel {

    /// Mỗi lúc chỉ một cửa sổ. Hàng đợi nằm ở `SmartDeleteController`.
    private static var current: FloatingPanel?
    /// Giữ sống cái delegate bắt sự kiện đóng — `NSWindow.delegate` là tham chiếu yếu.
    private static var closer: PanelCloser?

    /// Cao theo số mục, không cố định: ba dòng mà khung cao 430 thì nửa dưới là một mảng trống.
    static func height(forItems n: Int) -> CGFloat {
        // 36 lề trên dưới + 56 phần đầu + 42 phần đáy = 134, phần còn lại là danh sách:
        // một dòng "đã ở trong Thùng rác" (44) cộng mỗi mục 44, kẹp trong [88, 320].
        let list = min(max(88, 44 + 44 * CGFloat(n)), 320)
        return 134 + list
    }

    static func show(app: TrashedApp, items: [CleanItem], onClose: @escaping () -> Void) {
        current?.close()

        let model = LeftoverPanelModel(app: app, items: items)
        let size = CGSize(width: 460, height: height(forItems: items.count))
        let panel = FloatingPanel(
            // `.nonactivatingPanel`: bảng này nổi lên giữa lúc người dùng đang làm việc khác.
            // Kích hoạt cả app là kéo luôn cửa sổ chính 1140×780 (nếu đang mở) đè lên việc họ
            // đang làm — đúng thứ họ đã bảo là không được.
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)

        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // macOS vẽ bóng theo KHUNG CHỮ NHẬT của cửa sổ chứ không theo hình dạng nội dung, nên
        // cửa sổ trong suốt bo góc mà bật bóng là có bốn góc vuông lòi ra. Bóng tự vẽ bên trong.
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }

        // Mọi đường đóng đều đi qua `windowWillClose`, kể cả khi hệ thống tự dẹp cửa sổ. Nếu
        // `dismiss` vừa `close()` vừa tự gọi `onClose` thì cú đóng do hệ thống phát ra sẽ chạy
        // vòng thứ hai ngay trong lúc cửa sổ đang đóng dở.
        var closed = false
        let finish: () -> Void = {
            guard !closed else { return }
            closed = true
            onClose()
            // Thả ở nhịp sau: `finish` đang chạy BÊN TRONG `windowWillClose` của chính cái
            // delegate này, thả ngay là rút chân thang lúc còn đứng trên đó.
            //
            // Và chỉ thả ĐÚNG cái bảng này: tới nhịp sau có thể đã có bảng mới của app kế tiếp
            // ngồi vào chỗ `current`, xoá trắng là gỡ mất delegate của nó (bảng mới đóng sẽ không
            // ai nghe, hàng đợi kẹt lại y như lỗi đã sửa ở lượt trước).
            DispatchQueue.main.async {
                guard current === panel else { return }
                current = nil
                closer = nil
            }
        }
        let dismiss: () -> Void = {
            guard !closed else { return }
            panel.close()
        }

        panel.contentView = NSHostingView(
            rootView: LeftoverPanelView(model: model, size: size, dismiss: dismiss))
        // Bảng có thể bị đóng bằng đường khác (một bảng mới đẩy nó đi, hệ thống dẹp cửa sổ...).
        // Không bắt lấy lúc ấy thì `onClose` không bao giờ chạy, và `SmartDeleteController` nằm
        // chờ mãi ở cờ `busy` — app tiếp theo bị xoá sẽ không được hỏi nữa.
        closer = PanelCloser(onClose: finish)
        panel.delegate = closer

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                         y: f.midY - size.height / 2 + f.height * 0.08))
        }
        current = panel
        // `orderFrontRegardless` chứ không `makeKeyAndOrderFront`: đưa bảng lên trên cùng mà
        // không cướp tiêu điểm của app người dùng đang dùng. Bấm vào bảng thì nó thành key.
        panel.orderFrontRegardless()
    }
}

/// Báo về khi cửa sổ đóng, bất kể đóng bằng đường nào.
private final class PanelCloser: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

/// `NSPanel` bình thường không nhận phím khi thanh tiêu đề bị ẩn.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Trạng thái

@MainActor
final class LeftoverPanelModel: ObservableObject {

    enum Phase: Equatable {
        case choosing
        case removing
    }

    let app: TrashedApp
    @Published var items: [CleanItem]
    @Published var phase: Phase = .choosing

    init(app: TrashedApp, items: [CleanItem]) {
        self.app = app
        self.items = items
    }

    var selected: [CleanItem] { items.filter(\.isSelected) }
    var totalSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    func toggle(_ item: CleanItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isSelected.toggle()
    }

    func clean(done: @escaping () -> Void) {
        let chosen = selected
        guard !chosen.isEmpty else { done(); return }
        phase = .removing

        let toTrash = UserDefaults.standard.bool(forKey: "moveToTrash")
        let prompt = "xCleaner cần quyền quản trị để dọn tàn dư của \(app.name)."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Remover.perform(
                Remover.Request(items: chosen, moveToTrash: toTrash, adminPrompt: prompt)
            ) { _, _ in }
            DispatchQueue.main.async {
                CleanLedger.shared.record(result.freedBytes)
                // Xoá xong là đóng im lặng: không màn "đã dọn", và không kéo cửa sổ chính của app
                // lên. Người dùng đang làm việc khác, xong việc thì biến mất.
                done()
            }
        }
    }
}

// MARK: - Giao diện

private struct LeftoverPanelView: View {
    @ObservedObject var model: LeftoverPanelModel
    var size: CGSize
    var dismiss: () -> Void

    private let skin = ModuleSkin.skin(for: .uninstaller)

    var body: some View {
        ZStack {
            // Lớp đục tuyệt đối dưới cùng: cửa sổ trong suốt, mà thẻ kính thì chỉ là một màng
            // trắng mờ — thiếu lớp này là nhìn xuyên thấy app phía sau.
            skin.background
            chooser
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
        .onExitCommand(perform: dismiss)
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
            footer
        }
        .padding(18)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(url: model.app.url, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Còn sót lại của \(model.app.name)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(model.items.count) mục · \(Fmt.size(model.items.reduce(0) { $0 + $1.size }))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecond)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Chính bundle: đã nằm trong Thùng rác rồi nên không tick được, chỉ để người dùng
                // biết cửa sổ này đang nói về app nào.
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textFaint)
                        .frame(width: 16)
                        .padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(model.app.name).app").font(.rowTitle)
                            .foregroundStyle(Palette.textSecond)
                        Text("Đã ở trong Thùng rác").font(.rowDetail)
                            .foregroundStyle(Palette.textFaint)
                    }
                    Spacer(minLength: 8)
                }
                .frame(height: 44)

                ForEach(model.items) { item in
                    // Dòng cuối không kẻ gạch: gạch sát mép dưới thẻ kính nhìn như thẻ bị cắt ngang.
                    ItemRow(item: item, showsDivider: item.id != model.items.last?.id) {
                        model.toggle(item)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .glass(radius: 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.selected.isEmpty
                 ? "Chưa chọn mục nào"
                 : "Đã chọn \(model.selected.count) mục · \(Fmt.size(model.totalSize))")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecond)
            Spacer(minLength: 0)
            ActionButton(title: "Đóng", isEnabled: model.phase == .choosing, action: dismiss)
            ActionButton(title: model.phase == .removing ? "Đang xoá…" : "Xoá",
                         kind: .prominent,
                         isEnabled: model.phase == .choosing && !model.selected.isEmpty) {
                model.clean(done: dismiss)
            }
        }
        .padding(.top, 14)
    }
}
