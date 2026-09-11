import SwiftUI
import AppKit

// MARK: - Màu động theo giao diện sáng/tối

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
    /// Một màu duy nhất tự đổi giá trị khi người dùng chuyển sáng/tối — không cần `@Environment`.
    static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

enum Palette {
    // Nền
    static let canvas      = Color.adaptive("#F4F5F9", "#101219")
    static let surface     = Color.adaptive("#FFFFFF", "#191C25")
    static let surfaceAlt  = Color.adaptive("#F8F9FC", "#1F2330")
    static let sidebar     = Color.adaptive("#EBECF2", "#0C0E14")
    static let hairline    = Color.adaptive("#00000012", "#FFFFFF14")

    // Chữ
    static let textPrimary   = Color.adaptive("#14161C", "#F2F4FA")
    static let textSecondary = Color.adaptive("#5C6070", "#9AA0B4")
    static let textTertiary  = Color.adaptive("#8A8F9E", "#6B7186")

    // Nhấn
    static let accent      = Color.adaptive("#4D6FF0", "#6D8BFF")
    static let accentStart = Color.adaptive("#4C6FEF", "#5E7CF5")
    static let accentEnd   = Color.adaptive("#9B5DE5", "#A472FF")

    static let success     = Color.adaptive("#17B26A", "#32D583")
    static let warning     = Color.adaptive("#DC8B12", "#FDB022")
    static let danger      = Color.adaptive("#D92D20", "#F97066")

    // Vòng quét
    static let ringTrack = Color.adaptive("#E3E6F0", "#232735")

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [Color.adaptive("#3D5AF1", "#2B3A8F"),
                                Color.adaptive("#7B4BE0", "#5B2E9E")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func safetyColor(_ level: SafetyLevel) -> Color {
        switch level {
        case .safe:      return success
        case .review:    return warning
        case .sensitive: return danger
        }
    }
}

enum Metrics {
    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 9
    static let sidebarWidth: CGFloat = 232
    static let contentPadding: CGFloat = 28
}

enum Motion {
    /// Dùng cho mọi thay đổi bố cục: đủ nhanh để không thấy chậm, đủ mềm để không giật.
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let snappy   = Animation.spring(response: 0.26, dampingFraction: 0.9)
    static let gentle   = Animation.easeInOut(duration: 0.22)
}

// MARK: - Kiểu chữ

extension Font {
    static let displayNumber = Font.system(size: 54, weight: .semibold, design: .rounded)
    static let cardTitle     = Font.system(size: 14, weight: .semibold)
    static let rowTitle      = Font.system(size: 13, weight: .medium)
    static let rowDetail     = Font.system(size: 11, weight: .regular)
    static let sectionTitle  = Font.system(size: 26, weight: .bold)
}

// MARK: - Nền mờ kiểu macOS

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        v.isEmphasized = emphasized
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.isEmphasized = emphasized
    }
}

// MARK: - Thẻ

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func cardBackground(radius: CGFloat = Metrics.cardRadius) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    /// Ẩn/hiện mềm mà không làm nhảy bố cục.
    func fadeIn(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0).animation(Motion.gentle, value: visible)
    }
}
