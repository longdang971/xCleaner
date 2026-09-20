import SwiftUI
import AppKit

// MARK: - Màn hình dọn xong

/// Khoảnh khắc kết thúc chỉ có MỘT thông tin: đã giải phóng được bao nhiêu.
///
/// Bản trước bày lại lưới thẻ của màn đang dọn, mỗi nhóm một ô kèm số byte của riêng nó. Nhìn
/// như một bảng số liệu chứ không như một việc vừa xong — và phần chia theo nhóm thì người dùng
/// đã xem ở màn kết quả trước khi bấm Dọn rồi, nhắc lại không giúp họ làm gì tiếp. Nay bỏ hẳn:
/// một dấu ✓ lớn, một con số lớn, và nút "Xong".
///
/// Khung chung của bốn màn vẫn giữ: số lớn ở trên, nút tròn ở đáy. Không có nút "Quét lại":
/// quét lại ngay sau khi vừa dọn xong là việc chẳng ai làm, và nút đó cướp mất sự tĩnh lặng
/// của màn duy nhất trong app không có gì phải bấm ngoài "Xong".
struct DoneScreen: View {
    @ObservedObject var store: ScanStore
    let skin: ModuleSkin

    /// Bật một lần lúc màn hiện ra; mọi lớp hiệu ứng treo vào đây với độ trễ riêng.
    @State private var revealed = false

    /// Đổi giá trị là bắn lại pháo hoa. Bắn trong `onAppear` chứ không lúc dựng view: lúc dựng,
    /// view còn bị SwiftUI tạo đi tạo lại vài lần và pháo hoa sẽ nháy theo.
    @State private var burst = 0

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            if let o = store.outcome {
                content(o)
            } else {
                // Chỉ gặp khi phase nhảy sang .done trước lúc kết quả kịp về.
                ScanRing(mode: store.ringMode, bytes: store.totalSelected,
                         caption: store.statusText, diameter: 180, accent: skin.glow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Huỷ giữa chừng mà chưa xoá được gì thì không có con số nào để khoe.
    private func cancelledEmpty(_ o: CleanOutcome) -> Bool {
        o.wasCancelled && o.freedBytes == 0
    }

    /// Dọn xong thật nhưng không đòi lại được byte nào (mục rỗng, hoặc chỉ toàn thư mục).
    /// Vẫn là "xong", nhưng đừng khoe "0 KB đã giải phóng".
    private func nothingFreed(_ o: CleanOutcome) -> Bool {
        !o.wasCancelled && o.freedBytes == 0
    }

    /// Chỉ ăn mừng khi thật sự có gì để ăn mừng.
    private func celebrates(_ o: CleanOutcome) -> Bool {
        !cancelledEmpty(o) && !nothingFreed(o) && !reduceMotion
    }

    private func content(_ o: CleanOutcome) -> some View {
        ZStack {
            if celebrates(o) {
                CelebrationHalo(trigger: burst)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                ZStack {
                    // Pháo hoa nổ NGAY QUANH dấu ✓, không rải khắp cửa sổ: nổ ở bốn góc màn thì
                    // mắt người xem chạy theo góc màn, còn thứ đáng nhìn — dấu ✓ và con số —
                    // lại thành nền.
                    if celebrates(o) {
                        FireworksShow(colors: Self.sparkColors(skin), trigger: burst)
                    }
                    // Huỷ giữa chừng thì KHÔNG được vẽ dấu ✓ xanh: người dùng vừa dừng việc
                    // dọn, mà màn hình lại báo thành công bằng đúng ký hiệu của lúc xong xuôi.
                    DrawnCheckmark(mark: cancelledEmpty(o) ? .halt : .check,
                                   drawn: revealed,
                                   tint: cancelledEmpty(o) ? Color.white.opacity(0.55) : skin.action,
                                   size: 132)
                }
                .padding(.bottom, 30)

                headline(o)

                if let note = note(o) {
                    Text(note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecond)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                        .padding(.top, 14)
                        .modifier(RiseIn(revealed: revealed, delay: 0.76))
                }

                Spacer(minLength: 12)

                CircleActionButton(title: "Xong", accent: skin.action) { store.backToStart() }
                    .padding(.bottom, Metrics.actionButtonBottom)
                    .modifier(RiseIn(revealed: revealed, delay: 0.95))
            }
            // Phải căng hết khung, nếu không bề ngang co lại bằng dòng chữ dài nhất và khối nội
            // dung không còn nằm giữa cửa sổ.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            revealed = true
            burst += 1
        }
    }

    // MARK: Con số

    @ViewBuilder
    private func headline(_ o: CleanOutcome) -> some View {
        if cancelledEmpty(o) {
            Text("Đã huỷ")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .modifier(RiseIn(revealed: revealed, delay: 0.2))
        } else if nothingFreed(o) {
            Text("Không có gì để dọn")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .modifier(RiseIn(revealed: revealed, delay: 0.2))
        } else {
            VStack(spacing: 6) {
                FreedAmount(bytes: o.freedBytes,
                            progress: revealed ? 1 : 0,
                            reduceMotion: reduceMotion)
                    .animation(reduceMotion
                               ? .easeOut(duration: 0.35)
                               : .timingCurve(0.2, 0.75, 0.25, 1, duration: 1.0).delay(0.18),
                               value: revealed)

                Text("đã giải phóng")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .modifier(RiseIn(revealed: revealed, delay: 0.62))
            }
        }
    }

    /// Màu hạt pháo hoa phải SÁNG HƠN nền, không phải cùng tông với nền.
    ///
    /// Lần đầu lấy thẳng `skin.gem`: nền của Quét thông minh là hồng sẫm, mà `gem` của nó cũng
    /// hồng — chụp lại thì cả chùm chỉ còn là vài đốm lấm tấm không ai nhận ra. Nay chỉ mượn
    /// tông sáng nhất của bộ đá quý rồi trộn thêm trắng, xanh "đã sạch" và vàng ấm: bốn màu này
    /// nổi trên cả năm nền của app.
    private static func sparkColors(_ skin: ModuleSkin) -> [Color] {
        [.white, skin.gem.first ?? .white, skin.glow, Palette.success, Color(hex: "#FDE68A")]
    }

    /// Dòng phụ dưới con số — cố ý **chỉ hiện khi có điều người dùng cần biết**.
    ///
    /// Bản trước luôn in "N mục đã được dọn · có dùng quyền quản trị". Hai ý đó không đổi được
    /// hành vi của ai: quyền quản trị thì người dùng vừa tự gõ mật khẩu nên đã biết, còn số mục
    /// chỉ là cách nói khác của con số đã nằm ngay phía trên. Bỏ. Thứ còn giữ lại là thứ người
    /// dùng CÒN PHẢI LÀM GÌ ĐÓ với nó: tệp nằm trong Thùng rác (còn lấy lại được, và vẫn chiếm
    /// chỗ tới khi đổ rác) hoặc việc dọn đã bị bỏ dở.
    private func note(_ o: CleanOutcome) -> String? {
        if cancelledEmpty(o) { return "Bạn đã huỷ nên chưa có gì bị xoá." }
        if nothingFreed(o) { return "Không còn gì trong danh sách vừa rồi." }

        var parts: [String] = []
        if o.trashedCount > 0 {
            parts.append(o.trashedCount == o.removedCount
                         ? "Tất cả đang nằm trong Thùng rác"
                         : "\(o.trashedCount) mục nằm trong Thùng rác")
        }
        if o.wasCancelled {
            parts.append("bạn đã huỷ nhập mật khẩu nên phần trong thư mục hệ thống được giữ nguyên")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Con số tụ nét

/// Con số từ nhoè và giãn chữ **tụ lại sắc nét**, đồng thời chạy từ 0 lên giá trị thật.
///
/// Là `View & Animatable` chứ không phải một chuỗi modifier: SwiftUI dựng lại thân view này ở
/// MỖI khung hình của animation, nên cùng một lần chạy vừa nội suy được chữ số, vừa nội suy
/// blur và `tracking` — thứ mà `.animation()` trên `Text` không làm được vì chữ số là nội dung
/// chứ không phải thuộc tính.
struct FreedAmount: View, Animatable {
    let bytes: Int64
    var progress: Double
    var reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        // Chậm dần về cuối: con số dừng lại êm thay vì phanh gấp.
        let eased = 1 - pow(1 - p, 3)
        let parts = Fmt.sizeParts(bytes)
        let shown = reduceMotion ? parts.value
                                 : Fmt.countingValue(finalValue: parts.value, fraction: eased)

        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(shown)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .tracking(reduceMotion ? 0 : 7 * (1 - p))
                .foregroundStyle(.white)
            Text(parts.unit)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.84))
        }
        // Mũ 1,4 để chữ thoát khỏi vùng nhoè sớm hơn một chút so với lúc số chạy xong —
        // đọc được mặt số trong lúc nó vẫn đang nhích.
        .blur(radius: reduceMotion ? 0 : 16 * pow(1 - p, 1.4))
        .opacity(min(1, p * 3))
    }
}

// MARK: - Dấu ✓ vẽ nét

struct DrawnCheckmark: View {
    enum Mark {
        /// Dấu ✓ — việc đã xong.
        case check
        /// Một gạch ngang — việc đã dừng lại. Cùng khuôn vòng tròn, cùng cách vẽ nét, nên hai
        /// trạng thái vẫn trông là hai mặt của một màn hình chứ không phải hai thiết kế rời.
        case halt
    }

    var mark: Mark = .check
    let drawn: Bool
    let tint: Color
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            Circle()
                // Nét vẽ theo tỉ lệ đường kính: đổi `size` là cả dấu ✓ lớn lên cân đối,
                // không phải một vòng tròn to với nét mảnh như sợi tóc.
                .stroke(Color.white.opacity(0.34), lineWidth: size * 0.030)
            MarkShape(mark: mark)
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.076,
                                                 lineCap: .round, lineJoin: .round))
                .animation(.easeOut(duration: 0.5).delay(0.25), value: drawn)
        }
        .frame(width: size, height: size)
    }
}

/// Nét trong khung vuông của `DrawnCheckmark`, vẽ theo tỉ lệ nên co giãn được.
struct MarkShape: Shape {
    var mark: DrawnCheckmark.Mark = .check

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch mark {
        case .check:
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.52))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.66))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.38))
        case .halt:
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.67, y: rect.midY))
        }
        return p
    }
}

// MARK: - Pháo hoa

/// Vài chùm pháo hoa nổ so le khắp khung màn hình.
///
/// Khác một chùm hạt bung đều: mỗi tia ở đây vừa toả ra vừa **rơi xuống** theo một đường cong
/// nặng dần, và là một vệt dài xoay đúng theo hướng bay chứ không phải một ô vuông — đó là thứ
/// làm mắt đọc ra "pháo hoa" chứ không phải "confetti".
struct FireworksShow: View {
    let colors: [Color]
    let trigger: Int

    /// Sức rơi tính bằng điểm: tia đi ngang bao nhiêu cũng bị kéo xuống chừng này ở cuối đời.
    private let gravity: CGFloat = 170

    /// Sinh một lần theo vòng đời của view.
    ///
    /// Phải sinh ngay trong `init` chứ không phải trong `onAppear`. Đo ra: `onAppear` của màn cha
    /// chạy TRƯỚC khi danh sách tia kịp có phần tử, nên lúc `trigger` đổi thì chưa có tia nào tồn
    /// tại để nghe; tia dựng sau đó giữ nguyên `Flight()` ban đầu — `opacity` 0, vô hình vĩnh viễn.
    @State private var bursts: [Burst]

    init(colors: [Color], trigger: Int) {
        self.colors = colors
        self.trigger = trigger
        _bursts = State(initialValue: Self.makeBursts(colors: colors))
    }

    struct Burst: Identifiable {
        let id: Int
        /// Tâm vụ nổ, tính bằng điểm so với tâm dấu ✓.
        let center: CGSize
        let delay: Double
        let rays: [Ray]
    }

    struct Ray: Identifiable {
        let id: Int
        let angle: Double
        let distance: Double
        let length: CGFloat
        let color: Color
        /// Mỗi tia tắt lệch nhau một chút; tắt đồng loạt trông như ai đó tắt công tắc.
        let fade: Double
    }

    /// Bốn đường chuyển động của một tia, gom vào một giá trị để `keyframeAnimator` nội suy.
    struct Flight {
        var spread: Double = 0
        var drop: Double = 0
        var opacity: Double = 0
        var scale: Double = 1
    }

    var body: some View {
        ZStack {
            ForEach(bursts) { b in
                ZStack {
                    ForEach(b.rays) { ray in
                        self.ray(ray, delay: b.delay)
                    }
                }
                .offset(b.center)
            }
        }
        // Khung 1×1: chùm tia vẽ TRÀN ra ngoài khung (SwiftUI không tự cắt), nên lớp pháo hoa
        // không chiếm chỗ và không đẩy dấu ✓ lệch khỏi giữa màn.
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    private func ray(_ ray: Ray, delay: Double) -> some View {
        Capsule()
            .fill(ray.color)
            .frame(width: ray.length, height: 4)
            .shadow(color: ray.color.opacity(0.9), radius: 7)
            .rotationEffect(.radians(ray.angle))
            .keyframeAnimator(initialValue: Flight(), trigger: trigger) { view, f in
                view
                    .opacity(f.opacity)
                    .scaleEffect(f.scale)
                    .offset(x: cos(ray.angle) * ray.distance * f.spread,
                            y: sin(ray.angle) * ray.distance * f.spread + gravity * f.drop)
            } keyframes: { _ in
                // Bung nhanh rồi chậm dần — sức nổ cạn đi.
                KeyframeTrack(\.spread) {
                    LinearKeyframe(0, duration: delay)
                    CubicKeyframe(1, duration: 1.5)
                }
                // Rơi thì ngược lại: gần như đứng yên lúc đầu, nặng dần về cuối. Ba chặng tuyến
                // tính 0 → 0,12 → 0,45 → 1 xấp xỉ đường parabol mà không phải tự viết đường cong.
                KeyframeTrack(\.drop) {
                    LinearKeyframe(0, duration: delay + 0.22)
                    LinearKeyframe(0.12, duration: 0.42)
                    LinearKeyframe(0.45, duration: 0.42)
                    LinearKeyframe(1, duration: 0.44)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    LinearKeyframe(1, duration: 0.10)
                    LinearKeyframe(0.9, duration: 0.70)
                    LinearKeyframe(0, duration: 0.70 + ray.fade)
                }
                // Tia ngắn lại khi tàn, cho cảm giác cháy hết.
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: delay)
                    CubicKeyframe(0.45, duration: 1.5)
                }
            }
    }

    private static func makeBursts(colors: [Color]) -> [Burst] {
        // Ba chùm chụm quanh dấu ✓, lệch nhau vài chục điểm và nổ so le — nổ cùng chỗ cùng lúc
        // thì thành một vụ nổ to chứ không ra nhịp pháo hoa.
        let layout: [(CGSize, Double)] = [
            (CGSize(width:   0, height:  -6), 0.05),
            (CGSize(width: -92, height: -54), 0.45),
            (CGSize(width:  96, height: -34), 0.80)
        ]
        return layout.enumerated().map { index, item in
            Burst(id: index, center: item.0, delay: item.1,
                  rays: makeRays(colors: colors, seed: index))
        }
    }

    private static func makeRays(colors: [Color], seed: Int) -> [Ray] {
        let count = 18
        // Mỗi chùm một màu chủ đạo — pháo hoa thật cũng nổ ra một màu mỗi quả — nhưng chừa vài
        // tia trắng cho có điểm sáng. Bỏ qua phần tử đầu (màu trắng) khi chọn màu chủ đạo: cả
        // chùm trắng trên nền sáng màu thì nhạt thếch, đã chụp lại để đối chiếu.
        let palette = colors.count > 1 ? Array(colors.dropFirst()) : colors
        let main = palette[seed % max(1, palette.count)]
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi + Double.random(in: -0.12...0.12)
            return Ray(id: i,
                       angle: angle,
                       distance: Double.random(in: 95...185),
                       length: CGFloat.random(in: 14...24),
                       color: i % 5 == 0 ? .white : main,
                       fade: Double.random(in: 0...0.35))
        }
    }
}

// MARK: - Quầng sáng thở

/// Quầng sáng sau lưng khối số: hiện lên, thở một nhịp, rồi đọng lại mờ.
struct CelebrationHalo: View {
    let trigger: Int

    struct Breath {
        var opacity: Double = 0
        var scale: Double = 0.85
    }

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color.white.opacity(0.20), .clear],
                                 center: .center, startRadius: 0, endRadius: 190))
            .frame(width: 380, height: 380)
            .keyframeAnimator(initialValue: Breath(), trigger: trigger) { view, b in
                view.opacity(b.opacity).scaleEffect(b.scale)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.1)
                    CubicKeyframe(1, duration: 0.85)
                    CubicKeyframe(0.45, duration: 1.85)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.85, duration: 0.1)
                    CubicKeyframe(1, duration: 0.85)
                    CubicKeyframe(1.04, duration: 1.85)
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Hiện ra so le

/// Trượt lên và mờ dần hiện ra sau `delay` giây. Dùng cho chữ và nút để chúng không ập vào
/// cùng lúc với con số.
struct RiseIn: ViewModifier {
    let revealed: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 10)
            .animation(.easeOut(duration: 0.5).delay(delay), value: revealed)
    }
}
