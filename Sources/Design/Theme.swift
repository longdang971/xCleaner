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

    static let appAccent = Color(hex: "#A855F7")

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
