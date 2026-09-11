import SwiftUI
import AppKit

// MARK: - Hình superellipse

/// Squircle thật (superellipse), mềm hơn `RoundedRectangle` nên khối 3D trông tròn trịa hơn.
struct Squircle: InsettableShape {
    var n: CGFloat = 4
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> Squircle {
        var s = self
        s.insetAmount += amount
        return s
    }

    func path(in rawRect: CGRect) -> Path {
        let rect = rawRect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        let a = max(0, rect.width / 2), b = max(0, rect.height / 2)
        let cx = rect.midX, cy = rect.midY
        let steps = 180
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = cx + a * CGFloat(copysign(pow(abs(Double(ct)), 2.0 / Double(n)), Double(ct)))
            let y = cy + b * CGFloat(copysign(pow(abs(Double(st)), 2.0 / Double(n)), Double(st)))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Khối 3D

/// Khối bóng loáng làm điểm nhấn thị giác cho mỗi mục — vai trò giống các vật thể 3D
/// trong CleanMyMac, nhưng dựng hoàn toàn bằng gradient nên không cần tệp ảnh nào.
struct GemView: View {
    var symbol: String
    var colors: [Color]
    var size: CGFloat = 132
    var floating: Bool = true

    @State private var lift = false

    var body: some View {
        ZStack {
            // Quầng tối phía sau để khối tách khỏi nền cùng tông màu
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.34), .clear],
                                     center: .center, startRadius: size * 0.1,
                                     endRadius: size * 0.78))
                .frame(width: size * 1.6, height: size * 1.6)
                .blur(radius: size * 0.18)

            // Bóng đổ màu hắt xuống dưới — tán rộng, nếu không sẽ lộ thành cái đế vuông
            Squircle()
                .fill(colors.last ?? .black)
                .frame(width: size * 0.80, height: size * 0.80)
                .offset(y: size * 0.17)
                .blur(radius: size * 0.26)
                .opacity(0.6)

            // Thân khối: sáng ở vai trên trái, chìm hẳn ở đáy phải
            Squircle()
                .fill(LinearGradient(colors: colors.count >= 3
                                     ? [colors[0], colors[1], colors[2]]
                                     : [colors[0], colors[min(1, colors.count - 1)]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)

            // Ánh sáng hắt vào vai trên trái
            Squircle()
                .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0.04)],
                                     center: UnitPoint(x: 0.28, y: 0.2),
                                     startRadius: 0, endRadius: size * 0.62))
                .frame(width: size, height: size)
                .blendMode(.softLight)

            // Vệt sáng cong trên đỉnh
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.55), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.62, height: size * 0.3)
                .offset(y: -size * 0.26)
                .blur(radius: size * 0.05)

            // Ánh phản chiếu hắt ngược từ dưới lên, mẹo quen thuộc để khối trông có khối lượng
            Squircle()
                .fill(RadialGradient(colors: [colors[0].opacity(0.75), .clear],
                                     center: UnitPoint(x: 0.72, y: 0.9),
                                     startRadius: 0, endRadius: size * 0.42))
                .frame(width: size, height: size)
                .blendMode(.screen)

            // Cạnh kính
            Squircle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: size * 0.014)
                .frame(width: size, height: size)

            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: (colors.last ?? .black).opacity(0.6), radius: size * 0.05, y: size * 0.02)
        }
        .frame(width: size * 1.25, height: size * 1.25)
        .offset(y: lift ? -5 : 5)
        .animation(floating ? .easeInOut(duration: 3.2).repeatForever(autoreverses: true) : nil,
                   value: lift)
        .onAppear { if floating { lift = true } }
    }
}

// MARK: - Vòng quét

struct ScanRing: View {
    enum Mode: Equatable { case idle, scanning(Double), results, cleaning(Double), done }

    var mode: Mode
    var bytes: Int64
    var caption: String
    var diameter: CGFloat = 210
    var accent: Color = .white

    @State private var spin = false

    private var progress: Double {
        switch mode {
        case .scanning(let p), .cleaning(let p): return max(0.02, min(1, p))
        case .results, .done: return 1
        case .idle: return 0
        }
    }

    private var isBusy: Bool {
        if case .scanning = mode { return true }
        if case .cleaning = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.22), .clear],
                                     center: .center, startRadius: diameter * 0.2,
                                     endRadius: diameter * 0.75))
                .frame(width: diameter * 1.7, height: diameter * 1.7)

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 10)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [.white.opacity(0.95), accent, .white.opacity(0.95)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
                .shadow(color: accent.opacity(0.6), radius: 12)
                .animation(Motion.standard, value: progress)

            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.1)
                    .stroke(Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: diameter + 20, height: diameter + 20)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
            }

            centerContent
        }
        .frame(width: diameter * 1.7, height: diameter * 1.7)
        .onAppear { spin = true }
    }

    @ViewBuilder
    private var centerContent: some View {
        VStack(spacing: 4) {
            switch mode {
            case .idle:
                EmptyView()
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                Text(caption).font(.system(size: 12.5)).foregroundStyle(Palette.textSecond)
            default:
                let parts = Fmt.sizeParts(bytes)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.value).font(.displayNumber).foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(parts.unit)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textSecond)
                }
                Text(caption)
                    .font(.system(size: 11.5)).foregroundStyle(Palette.textSecond)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: diameter - 30)
            }
        }
        .animation(Motion.gentle, value: caption)
    }
}

// MARK: - Nút

/// Nút tròn lớn nổi ở đáy màn hình — hành động chính của mỗi mục.
struct CircleActionButton: View {
    var title: String
    var accent: Color
    var isEnabled: Bool = true
    /// Có giá trị thì vẽ một vòng trắng chạy quanh nút theo tiến độ.
    var progress: Double? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Màu đặc, không pha trong suốt — nền phía sau sẽ làm nút xỉn đi.
                Circle().fill(accent)
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.30), .clear],
                                         startPoint: .top, endPoint: .center))
                Circle()
                    .fill(RadialGradient(colors: [.black.opacity(0.22), .clear],
                                         center: UnitPoint(x: 0.5, y: 1.1),
                                         startRadius: 0, endRadius: 60))
                Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .frame(width: 84, height: 84)
            .overlay {
                if let progress {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(0.004, min(1, progress)))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(Motion.standard, value: progress)
                    }
                    .frame(width: 100, height: 100)
                }
            }
            // Quầng tối đặt ở nền chứ không nằm trong ZStack: một con có kích thước cứng
            // sẽ kéo cả ZStack giãn ra theo nó, và nút phình to gấp đôi.
            .background(
                Circle()
                    .fill(RadialGradient(colors: [.black.opacity(0.42), .clear],
                                         center: .center, startRadius: 36, endRadius: 66))
                    .frame(width: 140, height: 140)
            )
            .shadow(color: accent.opacity(hovering ? 0.85 : 0.55),
                    radius: hovering ? 26 : 16, y: 6)
            .brightness(hovering ? 0.06 : 0)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }
}

struct PillButton: View {
    enum Kind { case glass, solid, warning }

    var title: String
    var systemImage: String?
    var kind: Kind = .glass
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(kind == .solid ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background {
                switch kind {
                case .glass:
                    Capsule().fill(Color.white.opacity(hovering ? 0.28 : 0.18))
                case .solid:
                    Capsule().fill(Color.white.opacity(hovering ? 1 : 0.92))
                case .warning:
                    Capsule().fill(Palette.warning.opacity(hovering ? 0.34 : 0.24))
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }
}

// MARK: - Ô chọn

/// Ô chọn riêng của xCleaner: hình tròn cho hợp với nút tròn và các khối squircle của app,
/// tô trắng đặc khi đã chọn nên nổi rõ trên mọi màu thẻ.
struct TriStateBox: View {
    var state: CleanGroup.Selection
    var action: () -> Void

    var size: CGFloat = 18
    @State private var hovering = false

    private var isOn: Bool { state != .none }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Vòng ngoài: luôn có mặt, đậm dần khi rê chuột vào
                Circle()
                    .fill(Color.white.opacity(isOn ? 1 : (hovering ? 0.18 : 0.10)))

                Circle()
                    .strokeBorder(Color.white.opacity(isOn ? 0 : (hovering ? 0.9 : 0.55)),
                                  lineWidth: 1.5)

                if isOn {
                    Image(systemName: state == .all ? "checkmark" : "minus")
                        .font(.system(size: size * 0.5, weight: .black))
                        .foregroundStyle(.black.opacity(0.78))
                        .transition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .white.opacity(isOn ? 0.35 : 0), radius: hovering ? 6 : 4)
            .contentShape(Circle())
            .animation(Motion.snappy, value: state)
            .animation(Motion.gentle, value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { h in hovering = h }
    }
}

struct CheckBox: View {
    var isOn: Bool
    var action: () -> Void
    var body: some View { TriStateBox(state: isOn ? .all : .none, action: action) }
}

// MARK: - Nhãn

struct SafetyBadge: View {
    var level: SafetyLevel
    var body: some View {
        Text(level.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 8).padding(.vertical, 2.5)
            .background(Capsule().fill(Palette.safetyColor(level)))
    }
}

struct AdminBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
            Text("Cần mật khẩu").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.black.opacity(0.82))
        .padding(.horizontal, 8).padding(.vertical, 2.5)
        .background(Capsule().fill(Palette.warning))
    }
}

// MARK: - Thanh ổ đĩa (nằm dưới sidebar)

struct DiskUsageRing: View {
    @State private var total: Int64 = 0
    @State private var free: Int64 = 0
    var expanded: Bool

    private var used: Int64 { max(0, total - free) }
    private var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 3.5)
                Circle().trim(from: 0, to: max(0.02, ratio))
                    .stroke(ratio > 0.9 ? Palette.danger : Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.standard, value: ratio)
            }
            .frame(width: 26, height: 26)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Fmt.size(free)) trống")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textSecond)
                    Text("trên \(Fmt.size(total))")
                        .font(.system(size: 10)).foregroundStyle(Palette.textFaint)
                }
                .fixedSize()
                .transition(.opacity)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in refresh() }
        .help("\(Fmt.size(free)) trống trên \(Fmt.size(total))")
    }

    private func refresh() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                        .volumeAvailableCapacityForImportantUsageKey])
        else { return }
        total = Int64(v.volumeTotalCapacity ?? 0)
        free = v.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

// MARK: - Ô tìm kiếm

struct SearchField: View {
    var placeholder: String = "Tìm kiếm"
    @Binding var text: String
    /// Bề rộng phải đặt từ bên trong. Áp `.frame(width:)` từ ngoài lên view đã bo và cắt
    /// làm viền bị vẽ lại ở kích thước khác, để lại hai vạch dọc mảnh ở hai đầu.
    var width: CGFloat? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.textFaint)
            TextField("", text: $text, prompt: Text(placeholder)
                .foregroundColor(Color.white.opacity(0.45)))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.textFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 30)
        .background(Capsule().fill(Color.white.opacity(0.13)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(focused ? 0.55 : 0.14),
                                        lineWidth: focused ? 1.4 : 1))
        .animation(Motion.gentle, value: focused)
    }
}

// MARK: - Chip lọc

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(isOn ? Color.white.opacity(0.92)
                                                 : Color.white.opacity(hovering ? 0.2 : 0.13)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0 : 0.16), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }
}

// MARK: - Trạng thái rỗng

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var gem: [Color]? = nil

    var body: some View {
        VStack(spacing: 16) {
            if let gem {
                // Cùng kiểu huy hiệu không khung như màn khởi đầu.
                HeroEmblem(icon: icon, gem: gem, size: 120)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Palette.textFaint)
            }
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text(message).font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecond)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Khác

struct AppIconView: View {
    var url: URL
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// Tiêu đề lớn căn giữa, kèm một hành động phụ ngay dưới.
struct HeroHeadline<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.heroTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecond)
                        .multilineTextAlignment(.center)
                }
            }
            trailing
        }
        .frame(maxWidth: 620)
    }
}

struct MiniRing: View {
    var fraction: Double
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 4)
            Circle().trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.standard, value: fraction)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.textSecond)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

/// Dải tối dần ở đáy danh sách, để nội dung không cắt cụt dưới thanh hành động.
struct BottomFade: View {
    var height: CGFloat = 96
    var body: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: .black.opacity(0.30), location: 0.45),
                               .init(color: .black.opacity(0.62), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}

// MARK: - Biểu tượng thật của ứng dụng

/// Tra biểu tượng của một ứng dụng theo bundle id, có nhớ lại để khỏi hỏi
/// LaunchServices mỗi lần SwiftUI dựng lại view.
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func icon(forBundleID id: String) -> NSImage? {
        lock.lock()
        if let cached = cache[id] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        lock.lock(); cache[id] = image; lock.unlock()
        return image
    }
}

/// Biểu tượng ứng dụng dùng làm hoạ tiết chìm trên thẻ; không có thì lùi về ký hiệu hệ thống.
struct GroupGlyph: View {
    var bundleID: String?
    var fallback: String
    var size: CGFloat
    var opacity: Double

    var body: some View {
        if let bundleID, let icon = AppIconProvider.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .opacity(opacity + 0.16)   // ảnh màu cần đậm hơn ký hiệu đơn sắc mới thấy rõ
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundStyle(Color.white.opacity(opacity))
        }
    }
}


// MARK: - Tiêu đề màn kết quả

/// Một con số lớn cho thứ người dùng quan tâm — dung lượng sắp được dọn — rồi mới tới ngữ cảnh.
/// Cố tình không nhắc lại dung lượng ở dòng phụ: đọc hai con số MB cạnh nhau chỉ gây phân vân.
struct ResultHeadline<Trailing: View>: View {
    var selectedBytes: Int64
    var totalBytes: Int64
    var itemCount: Int
    var groupCount: Int
    var restoredCount: Int
    @ViewBuilder var trailing: Trailing

    private var hasSelection: Bool { selectedBytes > 0 }

    var body: some View {
        VStack(spacing: 12) {
            if hasSelection {
                let parts = Fmt.sizeParts(selectedBytes)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parts.value)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(parts.unit)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("sẵn sàng dọn")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .padding(.leading, 2)
                }
            } else {
                Text("Chưa chọn mục nào")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(contextLine)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecond)
                .multilineTextAlignment(.center)

            trailing
        }
        .frame(maxWidth: 640)
        .animation(Motion.gentle, value: selectedBytes)
    }

    private var contextLine: String {
        var parts: [String] = []
        if hasSelection {
            parts.append("\(itemCount) mục trong \(groupCount) nhóm")
            let left = totalBytes - selectedBytes
            if left > 0 { parts.append("còn \(Fmt.size(left)) chưa chọn") }
        } else {
            parts.append("Tìm thấy \(Fmt.size(totalBytes)) trong \(groupCount) nhóm")
        }
        if restoredCount > 0 { parts.append("giữ lựa chọn lần trước cho \(restoredCount) mục") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Cụm nút biểu tượng ở góc

/// Vài thao tác phụ gom thành một cụm nhỏ nằm ở góc, nhường chỗ giữa cho tiêu đề.
struct IconToolbar: View {
    struct Action: Identifiable {
        let id = UUID()
        let icon: String
        let help: String
        let run: () -> Void
    }

    var actions: [Action]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                IconToolbarButton(action: action)
                if idx < actions.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 1, height: 16)
                }
            }
        }
        .background(Capsule().fill(Color.white.opacity(0.13)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .clipShape(Capsule())
    }
}

private struct IconToolbarButton: View {
    let action: IconToolbar.Action
    @State private var hovering = false

    var body: some View {
        Button(action: action.run) {
            Image(systemName: action.icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 30)
                .background(Color.white.opacity(hovering ? 0.16 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action.help)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }
}


// MARK: - Khung thẻ dùng chung

/// Nền, biểu tượng in chìm, viền và bóng của một thẻ. Thẻ kết quả, thẻ lúc quét và thẻ lúc dọn
/// đều dùng chung khung này nên ba màn hình trông như một.
struct TileSurface: ViewModifier {
    let gem: [Color]
    var icon: String? = nil
    var bundleID: String? = nil
    var highlighted: Bool = false
    var dimmed: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [gem[1].opacity(highlighted ? 0.92 : 0.82),
                                            gem[2].opacity(highlighted ? 0.78 : 0.62)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)

                    if let icon {
                        GroupGlyph(bundleID: bundleID, fallback: icon,
                                   size: bundleID == nil ? 72 : 80,
                                   opacity: highlighted ? 0.26 : 0.19)
                            .padding(.trailing, 14)
                            .padding(.top, 12)
                    }

                    LinearGradient(colors: [.clear, .black.opacity(0.30)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(highlighted ? 0.42 : 0.18),
                                  lineWidth: highlighted ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .shadow(color: highlighted ? gem[1].opacity(0.55) : .black.opacity(0.24),
                    radius: highlighted ? 22 : 16, y: 7)
            .opacity(dimmed ? 0.55 : 1)
            .saturation(dimmed ? 0.7 : 1)
    }
}

extension View {
    func tileSurface(gem: [Color], icon: String? = nil, bundleID: String? = nil,
                     highlighted: Bool = false, dimmed: Bool = false) -> some View {
        modifier(TileSurface(gem: gem, icon: icon, bundleID: bundleID,
                             highlighted: highlighted, dimmed: dimmed))
    }
}

// MARK: - Huy hiệu lớn ở màn khởi đầu

/// Biểu tượng lớn không khung: một ký hiệu tô gradient nổi trên quầng sáng, có vòng mảnh
/// và vài hạt sáng xoay quanh. Cố tình không bo thành khối vuông — như vậy trông chẳng khác
/// gì một cái icon ứng dụng phóng to.
struct HeroEmblem: View {
    let icon: String
    let gem: [Color]
    var size: CGFloat = 210

    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            // Quầng sáng nền
            Circle()
                .fill(RadialGradient(colors: [gem[0].opacity(0.5), gem[1].opacity(0.3), .clear],
                                     center: .center,
                                     startRadius: size * 0.04, endRadius: size * 0.6))
                .frame(width: size * 1.35, height: size * 1.35)
                .blur(radius: size * 0.06)
                .scaleEffect(breathe ? 1.04 : 0.97)
                .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true),
                           value: breathe)

            // Vòng mảnh cố định
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.06)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.2)
                .frame(width: size, height: size)

            // Cung sáng xoay chậm, cho biết app đang chờ chứ không đứng hình
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(LinearGradient(colors: [gem[0], .clear],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: size * 1.09, height: size * 1.09)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: spin)

            // Vài hạt sáng rải quanh
            ForEach(0..<7, id: \.self) { i in
                let angle = Double(i) / 7 * 2 * .pi
                let radius = size * (i % 2 == 0 ? 0.62 : 0.72)
                Circle()
                    .fill(Color.white.opacity(i % 3 == 0 ? 0.55 : 0.25))
                    .frame(width: i % 3 == 0 ? 5 : 3, height: i % 3 == 0 ? 5 : 3)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                    .blur(radius: i % 3 == 0 ? 0 : 0.6)
            }
            .rotationEffect(.degrees(spin ? -360 : 0))
            .animation(.linear(duration: 40).repeatForever(autoreverses: false), value: spin)

            // Ký hiệu chính
            Image(systemName: icon)
                .font(.system(size: size * 0.46, weight: .regular))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.82), gem[0]],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .white.opacity(0.35), radius: size * 0.07)
                .shadow(color: gem[2].opacity(0.8), radius: size * 0.05, y: size * 0.025)
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .onAppear { spin = true; breathe = true }
    }
}

// MARK: - Màn khởi đầu của một mục

/// Hai cột: khối 3D bên trái, bên phải là tên mục, một câu mô tả và ba việc nó sẽ làm.
struct ModuleIntro<Extra: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let gem: [Color]
    let highlights: [(icon: String, title: String)]
    @ViewBuilder var extra: Extra

    init(title: String, subtitle: String, icon: String, gem: [Color],
         highlights: [(icon: String, title: String)],
         @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.gem = gem
        self.highlights = highlights
        self.extra = extra()
    }

    var body: some View {
        HStack(spacing: 54) {
            HeroEmblem(icon: icon, gem: gem, size: 200)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecond)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360, alignment: .leading)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, h in
                        HStack(spacing: 13) {
                            ZStack {
                                Squircle()
                                    .fill(LinearGradient(colors: [gem[0], gem[1]],
                                                         startPoint: .topLeading,
                                                         endPoint: .bottomTrailing))
                                Squircle()
                                    .fill(LinearGradient(colors: [.white.opacity(0.4), .clear],
                                                         startPoint: .top, endPoint: .center))
                                Image(systemName: h.icon)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 30, height: 30)
                            .shadow(color: gem[1].opacity(0.45), radius: 6, y: 2)

                            Text(h.title)
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 26)

                extra.padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metrics.contentPadding)
    }
}
