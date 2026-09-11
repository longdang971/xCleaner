import SwiftUI
import AppKit

// MARK: - Vòng quét

/// Vòng tròn trung tâm: hiển thị tiến trình quét, tổng dung lượng tìm được và trạng thái.
struct ScanRing: View {
    enum Mode: Equatable { case idle, scanning(Double), results, cleaning(Double), done }

    var mode: Mode
    var bytes: Int64
    var caption: String
    var diameter: CGFloat = 224

    @State private var spin = false
    @State private var breathe = false

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
            // Quầng sáng nền
            Circle()
                .fill(RadialGradient(colors: [Palette.accent.opacity(isBusy ? 0.26 : 0.14), .clear],
                                     center: .center, startRadius: diameter * 0.16,
                                     endRadius: diameter * 0.62))
                .frame(width: diameter * 1.5, height: diameter * 1.5)
                .opacity(breathe ? 1 : 0.55)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)

            Circle()
                .stroke(Palette.ringTrack, lineWidth: 12)
                .frame(width: diameter, height: diameter)

            // Cung tiến trình
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [Palette.accentStart, Palette.accentEnd,
                                                 Palette.accentStart],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
                .animation(Motion.standard, value: progress)

            // Vệt xoay khi đang bận
            if isBusy {
                Circle()
                    .trim(from: 0, to: 0.12)
                    .stroke(Palette.accentEnd.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: diameter + 22, height: diameter + 22)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                    .transition(.opacity)
            }

            centerContent
        }
        .frame(width: diameter * 1.5, height: diameter * 1.5)
        .onAppear { spin = true; breathe = true }
    }

    @ViewBuilder
    private var centerContent: some View {
        VStack(spacing: 4) {
            switch mode {
            case .idle:
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Palette.accentGradient)
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.success)
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

            default:
                let parts = Fmt.sizeParts(bytes)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.value)
                        .font(.displayNumber)
                        .foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text(parts.unit)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: diameter - 40)
            }
        }
        .animation(Motion.gentle, value: caption)
    }
}

// MARK: - Nút chính

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var tint: LinearGradient = Palette.accentGradient
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 38)
            .background(
                Capsule().fill(tint)
                    .brightness(pressed ? -0.06 : (hovering ? 0.05 : 0))
            )
            .shadow(color: Palette.accentStart.opacity(isEnabled ? (hovering ? 0.42 : 0.28) : 0),
                    radius: hovering ? 16 : 10, x: 0, y: hovering ? 7 : 4)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
        .animation(Motion.snappy, value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
    }
}

struct SecondaryButton: View {
    var title: String
    var systemImage: String?
    var role: ButtonRole? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .medium)) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(role == .destructive ? Palette.danger : Palette.textPrimary)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(Palette.surfaceAlt)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                    .brightness(hovering ? 0.03 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.gentle) { hovering = h } }
    }
}

// MARK: - Ô chọn ba trạng thái

struct TriStateBox: View {
    var state: CleanGroup.Selection
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(state == .none ? Palette.textTertiary.opacity(0.55) : .clear,
                                  lineWidth: 1.4)
                if state != .none {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Palette.accentGradient)
                    Image(systemName: state == .all ? "checkmark" : "minus")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .animation(Motion.snappy, value: state)
        }
        .buttonStyle(.plain)
    }
}

/// Ô chọn hai trạng thái, dùng cho từng dòng.
struct CheckBox: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        TriStateBox(state: isOn ? .all : .none, action: action)
    }
}

// MARK: - Nhãn mức an toàn

struct SafetyBadge: View {
    var level: SafetyLevel

    var body: some View {
        Text(level.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.safetyColor(level))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.safetyColor(level).opacity(0.14)))
    }
}

struct AdminBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
            Text("Cần mật khẩu").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Palette.warning)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Palette.warning.opacity(0.14)))
    }
}

// MARK: - Thanh dung lượng ổ đĩa

struct DiskUsageBar: View {
    @State private var total: Int64 = 0
    @State private var free: Int64 = 0

    private var used: Int64 { max(0, total - free) }
    private var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ổ đĩa").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(Fmt.size(free)) trống")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ringTrack)
                    Capsule()
                        .fill(ratio > 0.9 ? AnyShapeStyle(Palette.danger) : AnyShapeStyle(Palette.accentGradient))
                        .frame(width: max(4, geo.size.width * ratio))
                        .animation(Motion.standard, value: ratio)
                }
            }
            .frame(height: 6)
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in refresh() }
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
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.surfaceAlt)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? Palette.accent.opacity(0.6) : Palette.hairline,
                                  lineWidth: focused ? 1.5 : 1))
        )
        .animation(Motion.gentle, value: focused)
    }
}

// MARK: - Trạng thái rỗng

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.textTertiary.opacity(0.7))
            Text(title).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text(message).font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Biểu tượng ứng dụng

struct AppIconView: View {
    var url: URL
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

// MARK: - Tiêu đề trang

struct PageHeader: View {
    var title: String
    var subtitle: String
    var trailing: AnyView?

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.sectionTitle).foregroundStyle(Palette.textPrimary)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Vòng tròn nhỏ trong thanh tổng kết

struct MiniRing: View {
    var fraction: Double
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ringTrack, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Palette.accentGradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.standard, value: fraction)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

/// Dải mờ dần ở đáy danh sách để nội dung không bị cắt cụt ngay dưới thanh hành động.
struct BottomFade: View {
    var height: CGFloat = 72

    var body: some View {
        LinearGradient(colors: [Palette.canvas.opacity(0), Palette.canvas],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}
