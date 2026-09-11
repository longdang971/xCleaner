// Dựng biểu tượng xCleaner bằng Core Graphics rồi đóng gói thành .icns.
//   swift docs/icon-source.swift && iconutil -c icns /tmp/xCleaner.iconset -o Resources/AppIcon.icns
//
// Hình: squircle gradient xanh → tím theo phong cách macOS, trên mặt là một "tia sáng" bốn cánh
// cùng hai tia nhỏ — cùng ngôn ngữ hình với biểu tượng trong sidebar.

import Foundation
import CoreGraphics
import AppKit

let canvas: CGFloat = 1024
// Apple để nội dung icon chiếm 824/1024 và đẩy xuống 1 chút cho cân với bóng đổ.
let plateSize: CGFloat = 824
let plateOrigin = CGPoint(x: (canvas - plateSize) / 2, y: (canvas - plateSize) / 2 - 8)

/// Đường bao squircle (superellipse) — mềm hơn rounded rect thường.
func squirclePath(rect: CGRect, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * CGFloat(copysign(pow(abs(Double(ct)), 2.0 / Double(n)), Double(ct)))
        let y = cy + b * CGFloat(copysign(pow(abs(Double(st)), 2.0 / Double(n)), Double(st)))
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// Ngôi sao bốn cánh với cạnh lõm (kiểu "sparkle" của SF Symbols).
func sparklePath(center: CGPoint, radius r: CGFloat, waist: CGFloat = 0.26) -> CGPath {
    let p = CGMutablePath()
    let w = r * waist
    p.move(to: CGPoint(x: center.x, y: center.y + r))
    p.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y),
                   control: CGPoint(x: center.x + w, y: center.y + w))
    p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r),
                   control: CGPoint(x: center.x + w, y: center.y - w))
    p.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y),
                   control: CGPoint(x: center.x - w, y: center.y - w))
    p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r),
                   control: CGPoint(x: center.x - w, y: center.y + w))
    p.closeSubpath()
    return p
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(into ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let plateRect = CGRect(origin: plateOrigin, size: CGSize(width: plateSize, height: plateSize))
    let plate = squirclePath(rect: plateRect)

    // Bóng đổ dưới đế
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: color(0x0B1020, 0.34))
    ctx.addPath(plate)
    ctx.setFillColor(color(0x5E7CF5))
    ctx.fillPath()
    ctx.restoreGState()

    // Nền gradient chéo
    ctx.saveGState()
    ctx.addPath(plate); ctx.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [color(0x4C6FEF), color(0x7C5BEE), color(0xA472FF)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg,
                           start: CGPoint(x: plateRect.minX, y: plateRect.maxY),
                           end: CGPoint(x: plateRect.maxX, y: plateRect.minY),
                           options: [])

    // Quầng sáng góc trên trái cho khối có chiều sâu
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0xFFFFFF, 0.42), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: plateRect.minX + plateSize * 0.26,
                                                y: plateRect.maxY - plateSize * 0.16),
                           startRadius: 0,
                           endCenter: CGPoint(x: plateRect.minX + plateSize * 0.26,
                                              y: plateRect.maxY - plateSize * 0.16),
                           endRadius: plateSize * 0.62, options: [])

    // Vệt sáng cong phía dưới, gợi cảm giác "vừa lau xong"
    ctx.saveGState()
    let sweep = CGMutablePath()
    sweep.move(to: CGPoint(x: plateRect.minX, y: plateRect.minY + plateSize * 0.30))
    sweep.addQuadCurve(to: CGPoint(x: plateRect.maxX, y: plateRect.minY + plateSize * 0.16),
                       control: CGPoint(x: plateRect.midX, y: plateRect.minY - plateSize * 0.06))
    sweep.addLine(to: CGPoint(x: plateRect.maxX, y: plateRect.minY))
    sweep.addLine(to: CGPoint(x: plateRect.minX, y: plateRect.minY))
    sweep.closeSubpath()
    ctx.addPath(sweep)
    ctx.setFillColor(color(0x2B3A8F, 0.28))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.restoreGState()

    // Viền trong mảnh cho cạnh sắc nét
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.setStrokeColor(color(0xFFFFFF, 0.22))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // Tia sáng chính
    let c = CGPoint(x: plateRect.midX - plateSize * 0.04, y: plateRect.midY + plateSize * 0.02)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: color(0x21295C, 0.45))
    ctx.addPath(sparklePath(center: c, radius: plateSize * 0.30))
    ctx.setFillColor(color(0xFFFFFF, 0.97))
    ctx.fillPath()
    ctx.restoreGState()

    // Hai tia phụ
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0x21295C, 0.35))
    ctx.addPath(sparklePath(center: CGPoint(x: plateRect.midX + plateSize * 0.26,
                                            y: plateRect.midY + plateSize * 0.25),
                            radius: plateSize * 0.115))
    ctx.setFillColor(color(0xFFFFFF, 0.92))
    ctx.fillPath()

    ctx.addPath(sparklePath(center: CGPoint(x: plateRect.midX + plateSize * 0.22,
                                            y: plateRect.midY - plateSize * 0.22),
                            radius: plateSize * 0.075))
    ctx.setFillColor(color(0xFFFFFF, 0.8))
    ctx.fillPath()
    ctx.restoreGState()
}

// --- Xuất ra iconset ---

let outDir = URL(fileURLWithPath: "/tmp/xCleaner.iconset")
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
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    let scale = CGFloat(px) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(into: ctx)
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: px, height: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try! data.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("Đã ghi \(sizes.count) tệp PNG vào \(outDir.path)")
