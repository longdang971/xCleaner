import SwiftUI

// MARK: - Lưới ô co giãn

/// Lưới ô dùng cho cả lúc quét lẫn lúc dọn. Bố cục giữ nguyên như màn kết quả — cùng số ô,
/// cùng tên — nhưng ô đang xử lý **phình rộng ra** và hàng chứa nó **cao lên**, các ô còn lại
/// co lại. Xong chặng thì ô thu về và hiện số liệu.
struct StageGridView: View {
    let stages: [ScanStage]
    let activeIndex: Int?
    let stageBytes: [Int: Int64]
    /// Câu hiển thị to trong ô đang chạy, ví dụ "Đang tìm trong Nhật ký…".
    let activeHeadline: String
    /// Dòng nhỏ dưới đáy ô đang chạy — tên tệp đang xử lý.
    let activeDetail: String
    /// Khi dọn: các mục đã xong của chặng hiện tại, tick dần.
    var activeEntries: [CleanedEntry] = []
    /// Nhãn dưới số liệu của ô đã xong ("để dọn" khi quét, "đã dọn" khi dọn).
    var doneCaption: String = "để dọn"

    /// Chia ô thành hai hàng, hàng trên nhiều hơn một ô khi số lẻ.
    private var rows: [[Int]] {
        let n = stages.count
        guard n > 3 else { return [Array(0..<n)] }
        let top = Int(ceil(Double(n) / 2))
        return [Array(0..<top), Array(top..<n)]
    }

    private func rowHasActive(_ row: [Int]) -> Bool {
        guard let activeIndex else { return false }
        return row.contains(activeIndex)
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let rowCount = rows.count
            let availableH = geo.size.height - spacing * CGFloat(rowCount - 1)

            VStack(spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let isActiveRow = rowHasActive(row)
                    let h = rowCount == 1
                        ? availableH
                        : (activeIndex == nil ? availableH / 2
                                              : availableH * (isActiveRow ? 0.63 : 0.37))

                    HStack(spacing: spacing) {
                        let availableW = geo.size.width - spacing * CGFloat(row.count - 1)
                        let weights = row.map { $0 == activeIndex ? 2.4 : 1.0 }
                        let total = weights.reduce(0, +)

                        ForEach(Array(row.enumerated()), id: \.element) { pos, idx in
                            StageTile(stage: stages[idx],
                                      gem: TileGems.gem(for: idx),
                                      state: state(for: idx),
                                      headline: activeHeadline,
                                      detail: activeDetail,
                                      entries: activeEntries,
                                      doneCaption: doneCaption)
                                .frame(width: availableW * weights[pos] / total, height: h)
                        }
                    }
                    .frame(height: h)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(Motion.standard, value: activeIndex)
            .animation(Motion.standard, value: stageBytes.count)
        }
    }

    private func state(for index: Int) -> StageTile.Phase {
        if index == activeIndex { return .active }
        if let b = stageBytes[index] { return .done(b) }
        return .pending
    }
}

// MARK: - Một ô

struct StageTile: View {
    /// Không đặt tên là `State`: trùng với `@State` của SwiftUI trong cùng phạm vi.
    enum Phase: Equatable {
        case pending
        case active
        case done(Int64)
    }

    let stage: ScanStage
    let gem: [Color]
    let state: Phase
    let headline: String
    let detail: String
    var entries: [CleanedEntry] = []
    var doneCaption: String = "để dọn"

    @State private var sweep = false

    private var isActive: Bool { state == .active }

    var body: some View {
        ZStack {
            background
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isActive ? 0.28 : 0.14), lineWidth: 1)
        )
        .shadow(color: isActive ? gem[1].opacity(0.5) : .black.opacity(0.2),
                radius: isActive ? 24 : 12, y: isActive ? 10 : 5)
    }

    // MARK: Nền

    @ViewBuilder
    private var background: some View {
        switch state {
        case .active:
            ZStack {
                LinearGradient(colors: [gem[1], gem[2]],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [gem[0].opacity(0.55), .clear],
                               center: UnitPoint(x: 0.5, y: 0.35),
                               startRadius: 0, endRadius: 320)
                // Vệt sáng chạy ngang cho thấy máy đang làm việc
                LinearGradient(colors: [.clear, .white.opacity(0.16), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 200)
                    .offset(x: sweep ? 520 : -520)
                    .blur(radius: 30)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
        case .done:
            ZStack {
                gem[1].opacity(0.55)
                RadialGradient(colors: [gem[0].opacity(0.28), .clear],
                               center: UnitPoint(x: 0.9, y: 0.05),
                               startRadius: 0, endRadius: 260)
            }
        case .pending:
            Color.white.opacity(0.07)
        }
    }

    // MARK: Nội dung

    @ViewBuilder
    private var content: some View {
        switch state {
        case .active:
            activeContent
        default:
            quietContent
        }
    }

    private var activeContent: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 22)

            Spacer(minLength: 6)

            if entries.isEmpty {
                glyph(size: 118)
            } else {
                // Lúc dọn: danh sách tick dần thay cho khối 3D
                cleanedList
            }

            Spacer(minLength: 6)

            Text(detail.isEmpty ? " " : detail)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .animation(nil, value: detail)
        }
    }

    private var cleanedList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { e in
                        HStack(spacing: 9) {
                            Image(systemName: e.failed ? "exclamationmark.triangle.fill" : "checkmark")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(e.failed ? Palette.warning : .white)
                                .frame(width: 14)
                            Text(e.name)
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(Fmt.size(e.bytes))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 28)
                        .id(e.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                }
            }
            .onChange(of: entries.count) { _ in
                guard let last = entries.last else { return }
                withAnimation(Motion.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    /// Ô chưa tới hoặc đã xong: tên ở trên, số liệu ở dưới, khối 3D nhô ra góc phải.
    private var quietContent: some View {
        ZStack(alignment: .topTrailing) {
            glyph(size: 84)
                .offset(x: 32, y: -20)
                .opacity(isPending ? 0.32 : 0.55)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Text(stage.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(isPending ? 0.72 : 0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 52)   // chừa chỗ cho khối 3D ở góc

                Spacer(minLength: 4)

                if case .done(let bytes) = state {
                    Text(bytes > 0 ? Fmt.size(bytes) : "không có gì")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(bytes > 0 ? doneCaption : "đã kiểm tra")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var isPending: Bool { state == .pending }

    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        if let bid = stage.appBundleID, let icon = AppIconProvider.icon(forBundleID: bid) {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: size * 0.92, height: size * 0.92)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        } else {
            GemView(symbol: stage.icon, colors: gem, size: size, floating: isActive)
        }
    }
}

// MARK: - Màn hình đang quét

struct ScanningView: View {
    let stages: [ScanStage]
    let currentStage: Int?
    let stageBytes: [Int: Int64]
    let currentFile: String
    let totalBytes: Int64
    let skin: ModuleSkin
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 16)

            StageGridView(stages: stages,
                          activeIndex: currentStage,
                          stageBytes: stageBytes,
                          activeHeadline: headline,
                          activeDetail: currentFile)
                .padding(.horizontal, Metrics.contentPadding)

            CircleActionButton(title: "Dừng", accent: skin.action, action: onStop)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
    }

    private var headline: String {
        guard let i = currentStage, stages.indices.contains(i) else { return "Đang quét…" }
        return "Đang tìm trong \(stages[i].title)…"
    }

    private var header: some View {
        VStack(spacing: 3) {
            if totalBytes > 0 {
                let parts = Fmt.sizeParts(totalBytes)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(parts.value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(parts.unit)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("tìm được đến giờ")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            } else {
                Text("Đang quét…")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("\(min(stageBytes.count + 1, stages.count))/\(stages.count) chặng")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecond)
        }
    }
}

// MARK: - Màn hình đang dọn

struct CleaningView: View {
    let stages: [ScanStage]
    let currentStage: Int?
    let stageBytes: [Int: Int64]
    let entries: [CleanedEntry]
    let total: Int
    let doneCount: Int
    let freed: Int64
    let skin: ModuleSkin
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text("Đang dọn…")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(doneCount)/\(total) mục · đã giải phóng \(Fmt.size(freed))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecond)
                    .contentTransition(.numericText())
            }
            .padding(.bottom, 16)

            StageGridView(stages: stages,
                          activeIndex: currentStage,
                          stageBytes: stageBytes,
                          activeHeadline: headline,
                          activeDetail: "",
                          activeEntries: entries,
                          doneCaption: "đã dọn")
                .padding(.horizontal, Metrics.contentPadding)

            CircleActionButton(title: "Dừng", accent: skin.action, action: onStop)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
    }

    private var headline: String {
        guard let i = currentStage, stages.indices.contains(i) else { return "Đang dọn…" }
        return "Đang dọn \(stages[i].title)…"
    }
}
