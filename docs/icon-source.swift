// Dựng biểu tượng xCleaner (bản phẳng, hợp Liquid Glass của macOS 26/27) bằng Core Graphics.
//   swiftc -O docs/icon-source.swift -o /tmp/iconrender && /tmp/iconrender <thư mục ra>
//   iconutil -c icns <thư mục ra>/xCleaner.iconset -o Resources/AppIcon.icns
//
// Hình: nền hồng mận của Quét thông minh; ngôi sao bốn cánh trắng ở giữa, vòng quét xanh lá ôm
// quanh như vòng % của nút Quét. Chỉ dùng mảng màu phẳng xếp lớp — không tự vẽ viền, vát cạnh
// hay vệt bóng, vì hệ thống tự thêm hiệu ứng kính lên icon.

import Foundation
import CoreGraphics
import AppKit

let canvas: CGFloat = 1024
// Lưới icon macOS: thân icon 824/1024, hạ xuống một chút cho cân với bóng đổ.
let plateSize: CGFloat = 824
let plateOrigin = CGPoint(x: (canvas - plateSize) / 2, y: (canvas - plateSize) / 2 - 10)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: colors as CFArray, locations: locations)!
}

/// Squircle (superellipse) — góc mềm như icon hệ thống.
func squirclePath(rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = Double(i) / 720 * 2 * .pi
        let x = rect.midX + a * CGFloat(copysign(pow(abs(cos(t)), 2 / n), cos(t)))
        let y = rect.midY + b * CGFloat(copysign(pow(abs(sin(t)), 2 / n), sin(t)))
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Ngôi sao bốn cánh cạnh lõm.
func sparklePath(center c: CGPoint, radius r: CGFloat, waist: CGFloat = 0.22) -> CGPath {
    let p = CGMutablePath()
    let w = r * waist
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y + w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + w, y: c.y - w))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y - w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - w, y: c.y + w))
    p.closeSubpath()
    return p
}

/// Tỉ lệ pixel/canvas của cỡ đang vẽ. `CGContext.setShadow` tính offset và blur theo pixel THẬT,
/// không theo CTM — không nhân vào thì ở cỡ 128 bóng to gấp 8 lần và bị cắt thành ô vuông ở mép ảnh.
var shadowScale: CGFloat = 1

/// `small` = cỡ 16/32: bỏ sao phụ, nét dày hơn để không nát thành vệt mờ.
func drawIcon(into ctx: CGContext, small: Bool) {
    ctx.setAllowsAntialiasing(true)

    let inset: CGFloat = small ? 30 : 0
    let size = plateSize + inset * 2
    let plateRect = CGRect(x: plateOrigin.x - inset, y: plateOrigin.y - inset, width: size, height: size)
    let plate = squirclePath(rect: plateRect)

    // --- Nền: một gradient dọc nhẹ, không quầng sáng ---
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * shadowScale), blur: 24 * shadowScale,
                  color: color(0x000000, 0.22))
    ctx.addPath(plate)
    ctx.setFillColor(color(0x9A1A74))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xC0288A), color(0x7A1260)], [0, 1]),
                           start: CGPoint(x: 0, y: plateRect.maxY),
                           end: CGPoint(x: 0, y: plateRect.minY), options: [])
    ctx.restoreGState()

    let c = CGPoint(x: plateRect.midX, y: plateRect.midY)

    // --- Vòng quét: rãnh mờ + cung xanh đặc, đầu tròn ---
    let ringR = size * (small ? 0.37 : 0.355)
    let ringW = size * (small ? 0.08 : 0.05)
    ctx.saveGState()
    ctx.setLineWidth(ringW)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.addEllipse(in: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))
    ctx.strokePath()

    let start = CGFloat.pi / 2                  // đỉnh
    let end = start - CGFloat.pi * 1.5          // chạy theo chiều kim đồng hồ tới 9 giờ
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0x4ADE80))
    ctx.addArc(center: c, radius: ringR, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // --- Ngôi sao chính: 8 mặt cắt, mỗi mặt MỘT màu đặc (không gradient, không gờ sáng) —
    // vẫn đọc ra khối pha lê nhưng phẳng như icon hệ thống. Đèn từ trên-trái.
    let R = size * (small ? 0.25 : 0.225)
    let star = sparklePath(center: c, radius: R)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * shadowScale), blur: 18 * shadowScale,
                  color: color(0x3A0629, 0.35))
    ctx.addPath(star)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    if !small {
        ctx.saveGState()
        ctx.addPath(star); ctx.clip()
        let light = CGFloat.pi * 0.75
        for k in 0..<4 {
            let theta = CGFloat.pi / 2 - CGFloat(k) * .pi / 2
            for s in [-1.0, 1.0] as [CGFloat] {
                let facet = CGMutablePath()
                facet.move(to: c)
                facet.addLine(to: CGPoint(x: c.x + R * 1.1 * cos(theta), y: c.y + R * 1.1 * sin(theta)))
                let side = theta + s * .pi / 4
                facet.addLine(to: CGPoint(x: c.x + R * 1.5 * cos(side), y: c.y + R * 1.5 * sin(side)))
                facet.closeSubpath()
                let b = 0.5 + 0.5 * cos(theta + s * .pi / 8 - light)
                // Bốn nấc: trắng → hồng phấn → hồng → hồng đậm.
                let tones: [UInt32] = [0xE879B9, 0xF5A8D2, 0xFCD7EA, 0xFFFFFF]
                ctx.addPath(facet)
                ctx.setFillColor(color(tones[min(3, Int(b * 4))]))
                ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }

    guard !small else { return }

    // --- Sao phụ ---
    ctx.addPath(sparklePath(center: CGPoint(x: c.x + size * 0.19, y: c.y + size * 0.19), radius: size * 0.058))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
}

// --- Xuất ra iconset ---

let outRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp")
let outDir = outRoot.appendingPathComponent("xCleaner.iconset")
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]

for (px, name) in sizes {
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
    shadowScale = CGFloat(px) / canvas
    drawIcon(into: ctx, small: px <= 32)
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: px, height: px)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("Đã ghi \(sizes.count) tệp PNG vào \(outDir.path)")
