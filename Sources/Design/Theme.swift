import SwiftUI
import AppKit

// MARK: - Màu

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        // Chuỗi 8 ký tự là RRGGBBAA (alpha nằm cuối), 6 ký tự là RRGGBB.
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255
            g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255
            a = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}

// MARK: - Bảng màu theo từng mục

/// Mỗi mục có một tông màu riêng phủ kín cửa sổ. Người dùng nhận ra mình đang ở đâu
/// bằng màu nền trước cả khi đọc tiêu đề.
struct ModuleSkin {
    let deep: Color      // góc tối
    let mid: Color       // màu chủ đạo
    let glow: Color      // điểm sáng
    let gem: [Color]     // khối 3D
    /// Màu nút hành động. Cả app dùng chung một màu nhấn — màu của Quét thông minh —
    /// để nút chính ở mọi mục đều nhận ra ngay là cùng một loại hành động.
    let action: Color

    /// Xanh lá tươi: không trùng với nền của mục nào (hồng, chàm, cam, teal)
    /// nên nút chính luôn nổi, và màu này hợp nghĩa "đã sạch".
    static let appAccent = Color(hex: "#22C55E")

    static func skin(for module: CleanModule) -> ModuleSkin {
        switch module {
        case .smartScan:
            return .init(deep: Color(hex: "#37062A"), mid: Color(hex: "#B31F86"),
                         glow: Color(hex: "#F472B6"),
                         gem: [Color(hex: "#F9A8D4"), Color(hex: "#DB2777"), Color(hex: "#5C0B44")],
                         action: ModuleSkin.appAccent)
        case .uninstaller:
            return .init(deep: Color(hex: "#0C1440"), mid: Color(hex: "#3B4FD8"),
                         glow: Color(hex: "#818CF8"),
                         gem: [Color(hex: "#A5B4FC"), Color(hex: "#4F46E5"), Color(hex: "#1E1B6B")],
                         action: ModuleSkin.appAccent)
        case .startup:
            return .init(deep: Color(hex: "#2A0A46"), mid: Color(hex: "#7C3AED"),
                         glow: Color(hex: "#C4B5FD"),
                         gem: [Color(hex: "#C4B5FD"), Color(hex: "#7C3AED"), Color(hex: "#3B0F80")],
                         action: ModuleSkin.appAccent)
        case .largeOld:
            return .init(deep: Color(hex: "#3A1204"), mid: Color(hex: "#C85A1B"),
                         glow: Color(hex: "#FB923C"),
                         gem: [Color(hex: "#FDBA74"), Color(hex: "#EA580C"), Color(hex: "#5A1E08")],
                         action: ModuleSkin.appAccent)
        case .duplicates:
            return .init(deep: Color(hex: "#032B29"), mid: Color(hex: "#0E8F86"),
                         glow: Color(hex: "#2DD4BF"),
                         gem: [Color(hex: "#5EEAD4"), Color(hex: "#0D9488"), Color(hex: "#04403C")],
                         action: ModuleSkin.appAccent)
        }
    }

    /// Trang Cài đặt cũng là một trang như mọi mục khác, nên nó cũng có nền riêng.
    /// Tông xám xanh trung tính: không đụng màu của mục nào (hồng, chàm, cam, teal)
    /// nên người dùng thấy ngay mình đã rời khỏi phần quét.
    static let settings = ModuleSkin(
        deep: Color(hex: "#0A101C"), mid: Color(hex: "#2C3A56"),
        glow: Color(hex: "#93A7C9"),
        gem: [Color(hex: "#CBD5E1"), Color(hex: "#64748B"), Color(hex: "#1B2536")],
        action: ModuleSkin.appAccent)

    /// Nền cửa sổ: một lớp chéo đậm, một quầng sáng lệch về góc trên phải,
    /// và một quầng tối ở đáy trái để khối nội dung nổi lên.
    @ViewBuilder
    var background: some View {
        ZStack {
            LinearGradient(colors: [mid, deep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [glow.opacity(0.55), .clear],
                           center: UnitPoint(x: 0.86, y: 0.06),
                           startRadius: 0, endRadius: 780)
            RadialGradient(colors: [deep.opacity(0.85), .clear],
                           center: UnitPoint(x: 0.02, y: 1.05),
                           startRadius: 0, endRadius: 700)
            LinearGradient(colors: [.black.opacity(0.28), .clear],
                           startPoint: .bottom, endPoint: .center)
        }
    }
}

// MARK: - Màu dùng chung trên nền tối

enum Palette {
    static let text         = Color.white
    static let textSecond   = Color.white.opacity(0.72)
    static let textFaint    = Color.white.opacity(0.48)

    /// Thẻ kính: sáng mờ, viền mảnh, không đổ bóng cứng.
    static let glass        = Color.white.opacity(0.13)
    static let glassStrong  = Color.white.opacity(0.19)
    static let glassLine    = Color.white.opacity(0.17)
    static let glassHover   = Color.white.opacity(0.08)

    static let success      = Color(hex: "#4ADE80")
    static let warning      = Color(hex: "#FBBF24")
    static let danger       = Color(hex: "#FB7185")

    static func safetyColor(_ level: SafetyLevel) -> Color {
        switch level {
        case .safe:      return success
        case .review:    return warning
        case .sensitive: return danger
        }
    }
}

enum Metrics {
    static let cardRadius: CGFloat = 20
    static let rowRadius: CGFloat = 10
    static let sidebarWidth: CGFloat = 76
    static let sidebarExpanded: CGFloat = 252
    static let contentPadding: CGFloat = 26
    static let titleBarHeight: CGFloat = 46

    /// Khoảng cách từ đáy **tấm nền** tới nút tròn chính — cố ý ÂM: nút thò hẳn ra ngoài mép
    /// dưới của tấm nền, như nút "Scan" của CleanMyMac. Một chỗ đổi, cả chín nút đi theo.
    static let actionButtonBottom: CGFloat = -26

    /// Dải trong suốt chừa ở đáy CỬA SỔ, bên dưới tấm nền.
    ///
    /// Nút tròn vẽ vào đúng dải này. Không có nó thì nút bị cắt ngang ở mép cửa sổ — cửa sổ
    /// luôn cắt mọi thứ vẽ ra ngoài khung của nó.
    ///
    /// Đủ chỗ cho cả bướu tròn của `CardShape` (76 − 16 = 60 tính từ mép tấm nền). Hụt một
    /// chút là quầng sáng dưới nút bị mép cửa sổ cắt ngang thành một đường thẳng. Dải này trong
    /// suốt hoàn toàn và cửa sổ đã tắt bóng, nên rộng hơn cũng không ai thấy.
    static let windowBottomInset: CGFloat = 64

    /// Bo góc dưới của tấm nền. Hai góc trên để hệ thống tự bo theo khung cửa sổ.
    static let cardCornerRadius: CGFloat = 16

    /// Bán kính vùng chừa cho nút tròn thò ra khỏi tấm nền.
    ///
    /// Phải tính theo lúc nút ĐANG HOVER, không phải lúc đứng yên: (42 nút + 20 bóng + 2 lệch)
    /// × 1,06 phình ≈ 68. Để 70 là sát quá, một lần đổi bóng nữa là quầng sáng bị xén vành cung.
    static let actionButtonHalo: CGFloat = 76
}

enum Motion {
    static let standard = Animation.spring(response: 0.4, dampingFraction: 0.86)
    static let snappy   = Animation.spring(response: 0.26, dampingFraction: 0.9)
    static let gentle   = Animation.easeInOut(duration: 0.22)
    static let skin     = Animation.easeInOut(duration: 0.5)
}

extension Font {
    static let displayNumber = Font.system(size: 52, weight: .semibold, design: .rounded)
    static let heroTitle     = Font.system(size: 23, weight: .semibold)
    static let cardTitle     = Font.system(size: 15, weight: .semibold)
    static let cardNumber    = Font.system(size: 26, weight: .semibold)
    static let rowTitle      = Font.system(size: 12.5, weight: .medium)
    static let rowDetail     = Font.system(size: 10.5)
}

// MARK: - Thẻ kính

struct GlassBackground: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius
    var strength: Color = Palette.glass

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(strength)
                    // Mép trên sáng hơn một chút, như ánh sáng hắt vào cạnh kính.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .center))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.glassLine, lineWidth: 1)
            )
            // Cắt theo đúng hình, nếu không strokeBorder để lại hai vạch dọc mảnh ở hai bên.
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func glass(radius: CGFloat = Metrics.cardRadius, strength: Color = Palette.glass) -> some View {
        modifier(GlassBackground(radius: radius, strength: strength))
    }
}


/// Mỗi thẻ kết quả mượn một tông màu khác nhau, giống lưới tile nhiều màu của CleanMyMac.
enum TileGems {
    static let sets: [[Color]] = [
        [Color(hex: "#6EE7B7"), Color(hex: "#10B981"), Color(hex: "#05402A")],  // lục
        [Color(hex: "#93C5FD"), Color(hex: "#3B82F6"), Color(hex: "#132B6B")],  // lam
        [Color(hex: "#F9A8D4"), Color(hex: "#DB2777"), Color(hex: "#5C0B44")],  // hồng
        [Color(hex: "#FDBA74"), Color(hex: "#EA580C"), Color(hex: "#5A1E08")],  // cam
        [Color(hex: "#5EEAD4"), Color(hex: "#0D9488"), Color(hex: "#04403C")],  // teal
        [Color(hex: "#C4B5FD"), Color(hex: "#7C3AED"), Color(hex: "#3B0F80")],  // tím
        [Color(hex: "#FDE68A"), Color(hex: "#D97706"), Color(hex: "#4A2A03")]   // vàng
    ]

    static func gem(for index: Int) -> [Color] { sets[index % sets.count] }
}


// MARK: - Hình của tấm nền

/// Chữ nhật bo hai góc dưới, **cộng** một vòng tròn ở giữa mép dưới.
///
/// Dùng làm khuôn cắt cho cả trang. Vòng tròn chính là chỗ nút "Xong"/"Quét"/"Dọn" thò ra:
/// không có nó thì khuôn cắt xén mất nửa dưới của nút. Có nó thì mọi thứ KHÁC vẽ ra ngoài tấm
/// nền đều bị cắt — cụ thể là bóng của sidebar, thứ vốn tràn qua góc bo và loang xuống dải
/// trong suốt, làm góc dưới bên trái trông như lỗi vẽ.
struct CardShape: Shape {
    var cornerRadius: CGFloat = Metrics.cardCornerRadius
    var buttonRadius: CGFloat = Metrics.actionButtonHalo
    /// Tâm vòng tròn nằm cao hơn mép dưới chừng này — nút thò ra 26 trên tổng đường kính 84.
    var buttonCenterLift: CGFloat = 16

    /// Nút căn giữa VÙNG NỘI DUNG, mà vùng đó đã bị sidebar ăn mất 76pt bên trái — nên tâm nút
    /// nằm lệch phải nửa chừng ấy so với tâm cửa sổ. Đặt bướu tròn ở giữa cửa sổ thì nó xén mất
    /// một lưỡi liềm ở sườn nút.
    var centerOffsetX: CGFloat = Metrics.sidebarWidth / 2

    func path(in rect: CGRect) -> Path {
        var p = UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius,
                                       bottomTrailingRadius: cornerRadius,
                                       style: .continuous).path(in: rect)
        p.addEllipse(in: CGRect(x: rect.midX + centerOffsetX - buttonRadius,
                                y: rect.maxY - buttonCenterLift - buttonRadius,
                                width: buttonRadius * 2,
                                height: buttonRadius * 2))
        return p
    }
}
