import SwiftUI

// MARK: - Màn hình đang quét

/// Các chặng quét vẽ thành ô: chặng đang chạy chiếm ô lớn bên trái với khối 3D và tên tệp
/// đang xử lý, các chặng khác nằm thành cột bên phải — xong thì hiện dung lượng, chưa tới thì mờ.
struct ScanningView: View {
    let stages: [ScanStage]
    let currentStage: Int?
    let stageBytes: [Int: Int64]
    let currentFile: String
    let totalBytes: Int64
    let skin: ModuleSkin
    var onStop: () -> Void

    @Namespace private var cards

    private var activeIndex: Int { currentStage ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 14) {
                activeCard
                    .frame(maxWidth: .infinity)

                if stages.count > 1 {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(Array(stages.enumerated()), id: \.element.id) { idx, stage in
                                if idx != activeIndex {
                                    SmallStageCard(stage: stage,
                                                   gem: TileGems.gem(for: idx),
                                                   bytes: stageBytes[idx],
                                                   isPending: stageBytes[idx] == nil)
                                        .matchedGeometryEffect(id: stage.id, in: cards)
                                }
                            }
                        }
                    }
                    .frame(width: 252)
                }
            }
            .padding(.horizontal, Metrics.contentPadding)

            Spacer(minLength: 16)

            CircleActionButton(title: "Dừng", accent: skin.action, action: onStop)
                .padding(.bottom, 22)
        }
        .animation(Motion.standard, value: currentStage)
        .animation(Motion.standard, value: stageBytes.count)
    }

    private var header: some View {
        VStack(spacing: 4) {
            if totalBytes > 0 {
                let parts = Fmt.sizeParts(totalBytes)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(parts.value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(parts.unit)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("tìm được đến giờ")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.leading, 2)
                }
            } else {
                Text("Đang quét…")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("\(min(stageBytes.count + 1, stages.count))/\(stages.count) chặng")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecond)
        }
    }

    @ViewBuilder
    private var activeCard: some View {
        if stages.indices.contains(activeIndex) {
            let stage = stages[activeIndex]
            ActiveStageCard(stage: stage,
                            gem: TileGems.gem(for: activeIndex),
                            currentFile: currentFile)
                .matchedGeometryEffect(id: stage.id, in: cards)
        }
    }
}

// MARK: - Ô của chặng đang chạy

struct ActiveStageCard: View {
    let stage: ScanStage
    let gem: [Color]
    let currentFile: String

    @State private var sweep = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Đang tìm trong \(stage.title)…")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 28)

            Spacer(minLength: 8)

            if let bid = stage.appBundleID, let icon = AppIconProvider.icon(forBundleID: bid) {
                Image(nsImage: icon)
                    .resizable().interpolation(.high)
                    .frame(width: 118, height: 118)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            } else {
                GemView(symbol: stage.icon, colors: gem, size: 150)
            }

            Spacer(minLength: 8)

            Text(currentFile.isEmpty ? "Đang chuẩn bị…" : currentFile)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .animation(nil, value: currentFile)   // tên tệp đổi liên tục, đừng animate
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .background {
            ZStack {
                LinearGradient(colors: [gem[1].opacity(0.95), gem[2].opacity(0.98)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [gem[0].opacity(0.45), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42),
                               startRadius: 0, endRadius: 300)
                // Vệt sáng quét ngang, gợi cảm giác máy đang lần từng chỗ
                LinearGradient(colors: [.clear, .white.opacity(0.18), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 220)
                    .offset(x: sweep ? 460 : -460)
                    .blur(radius: 26)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: gem[1].opacity(0.45), radius: 26, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }
}

// MARK: - Ô nhỏ

struct SmallStageCard: View {
    let stage: ScanStage
    let gem: [Color]
    let bytes: Int64?
    let isPending: Bool

    var body: some View {
        HStack(spacing: 11) {
            if let bid = stage.appBundleID, let icon = AppIconProvider.icon(forBundleID: bid) {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: stage.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 26)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let bytes {
                    Text(bytes > 0 ? Fmt.size(bytes) : "không có gì")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .contentTransition(.numericText())
                } else {
                    Text("đang chờ")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }

            Spacer(minLength: 4)

            if bytes != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.success)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPending ? Color.white.opacity(0.08)
                                : gem[1].opacity(0.55))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(isPending ? 0.10 : 0.20), lineWidth: 1)
        )
        .opacity(isPending ? 0.72 : 1)
    }
}

// MARK: - Màn hình đang dọn

/// Danh sách tick dần từng mục, giống lúc CleanMyMac xoá: người dùng thấy rõ máy đang làm gì
/// chứ không phải một thanh tiến trình vô nghĩa.
struct CleaningView: View {
    let entries: [CleanedEntry]
    let total: Int
    let statusText: String
    let progress: Double
    let skin: ModuleSkin
    var onStop: () -> Void

    private var freed: Int64 { entries.filter { !$0.failed }.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("Đang dọn…")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(entries.count)/\(total) mục · đã giải phóng \(Fmt.size(freed))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecond)
                    .contentTransition(.numericText())
            }
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 16) {
                list
                    .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    GemView(symbol: "sparkles", colors: TileGems.gem(for: 0), size: 108)
                    ProgressRingSmall(progress: progress, accent: skin.action)
                }
                .frame(width: 200)
                .padding(.top, 10)
            }
            .padding(.horizontal, Metrics.contentPadding)

            Spacer(minLength: 14)

            CircleActionButton(title: "Dừng", accent: skin.action, action: onStop)
                .padding(.bottom, 22)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.failed ? "exclamationmark.triangle.fill" : "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(entry.failed ? Palette.warning : Palette.success)
                                .frame(width: 16)
                            Text(entry.name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Fmt.size(entry.bytes))
                                .font(.system(size: 11.5, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .id(entry.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: 340)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Color.black.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .onChange(of: entries.count) { _ in
                guard let last = entries.last else { return }
                withAnimation(Motion.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

/// Vòng tiến trình nhỏ, dùng kèm danh sách lúc dọn.
struct ProgressRingSmall: View {
    var progress: Double
    var accent: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(LinearGradient(colors: [.white, accent],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.standard, value: progress)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(width: 86, height: 86)
    }
}
