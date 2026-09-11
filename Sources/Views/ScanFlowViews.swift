import SwiftUI

// MARK: - Thẻ trong lúc quét / dọn

/// Cùng khung, cùng màu, cùng chỗ đặt chữ như thẻ ở màn kết quả — chỉ khác phần số liệu:
/// đang chạy thì hiện thứ đang xử lý, xong thì hiện dung lượng, chưa tới thì mờ đi.
struct ProgressTile: View {
    enum Phase: Equatable {
        case pending
        case running
        case done(Int64)
    }

    let stage: ScanStage
    let gem: [Color]
    let phase: Phase
    /// Dòng chạy khi đang xử lý: tên tệp đang quét hoặc mục vừa dọn xong.
    var detail: String = ""
    /// Những mục vừa tìm thấy (hoặc vừa dọn xong) để thẻ đang chạy có nội dung.
    var entries: [CleanedEntry] = []
    /// Nhãn dưới số liệu của thẻ đã xong.
    var doneCaption: String = "để dọn"
    /// Câu hiện khi thẻ đang chạy.
    var runningTitle: String = "Đang quét…"

    private var isRunning: Bool { phase == .running }
    private var isPending: Bool { phase == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                statusMark
                Text(stage.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer(minLength: 4)
            }

            Spacer(minLength: 10)

            switch phase {
            case .done(let bytes):
                Text(bytes > 0 ? Fmt.size(bytes) : "không có gì")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(bytes > 0 ? doneCaption : "đã kiểm tra")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .padding(.top, 1)

            case .running:
                Text(runningTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, entries.isEmpty ? 0 : 10)

                if !entries.isEmpty {
                    // Liệt kê những gì vừa tìm được: thẻ phình to mà chỉ có hai dòng chữ
                    // thì trông trống hoác.
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(entries.suffix(5)) { e in
                            HStack(spacing: 8) {
                                Text(e.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.95))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(Fmt.size(e.bytes))
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
                        }
                    }
                    .animation(Motion.snappy, value: entries.count)
                }

                Text(detail.isEmpty ? " " : detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.top, entries.isEmpty ? 2 : 10)
                    .animation(nil, value: detail)

            case .pending:
                Text("đang chờ")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tileSurface(gem: gem, icon: stage.icon, bundleID: stage.appBundleID,
                     highlighted: isRunning, dimmed: isPending)
    }

    @ViewBuilder
    private var statusMark: some View {
        switch phase {
        case .done:
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.black.opacity(0.78))
            }
            .frame(width: 18, height: 18)
        case .running:
            SpinnerMark()
        case .pending:
            Circle()
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                .frame(width: 18, height: 18)
        }
    }
}

/// Vòng xoay nhỏ, cùng cỡ với ô chọn để thẻ không bị nhảy chữ khi đổi trạng thái.
struct SpinnerMark: View {
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.68)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .frame(width: 18, height: 18)
            .onAppear { spin = true }
    }
}

// MARK: - Lưới thẻ

/// Cùng bố cục với lưới kết quả: ba thẻ hàng đầu, phần còn lại hai thẻ mỗi hàng.
struct ProgressGrid: View {
    let stages: [ScanStage]
    let activeIndex: Int?
    let stageBytes: [Int: Int64]
    let detail: String
    var entries: [CleanedEntry] = []
    var doneCaption: String = "để dọn"
    var runningTitle: String = "Đang quét…"

    private let spacing: CGFloat = 14

    /// Hai hàng như lưới kết quả; hàng trên nhiều hơn một thẻ khi số thẻ lẻ.
    private var rows: [[Int]] {
        let n = stages.count
        guard n > 3 else { return [Array(0..<n)] }
        let top = Int(ceil(Double(n) / 2))
        return [Array(0..<top), Array(top..<n)]
    }

    var body: some View {
        GeometryReader { geo in
            let rowCount = rows.count
            let availableH = geo.size.height - spacing * CGFloat(rowCount - 1)

            VStack(spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let hasActive = activeIndex.map(row.contains) ?? false
                    // Hàng đang có thẻ chạy thì cao lên, hàng kia nhường chỗ.
                    let h = rowCount == 1
                        ? availableH
                        : (activeIndex == nil ? availableH / 2
                                              : availableH * (hasActive ? 0.60 : 0.40))
                    let availableW = geo.size.width - spacing * CGFloat(row.count - 1)
                    let weights = row.map { $0 == activeIndex ? 2.0 : 1.0 }
                    let totalWeight = weights.reduce(0, +)

                    HStack(spacing: spacing) {
                        ForEach(Array(row.enumerated()), id: \.element) { pos, idx in
                            tile(stages[idx], idx)
                                .frame(width: availableW * weights[pos] / totalWeight, height: h)
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

    private func tile(_ stage: ScanStage, _ index: Int) -> some View {
        ProgressTile(stage: stage,
                     gem: TileGems.gem(for: index),
                     phase: phase(for: index),
                     detail: index == activeIndex ? detail : "",
                     entries: index == activeIndex ? entries : [],
                     doneCaption: doneCaption,
                     runningTitle: runningTitle)
    }

    private func phase(for index: Int) -> ProgressTile.Phase {
        if index == activeIndex { return .running }
        if let b = stageBytes[index] { return .done(b) }
        return .pending
    }
}

// MARK: - Màn hình đang quét

struct ScanningView: View {
    let stages: [ScanStage]
    let currentStage: Int?
    let stageBytes: [Int: Int64]
    let currentFile: String
    let totalBytes: Int64
    let found: [CleanedEntry]
    let progress: Double
    let skin: ModuleSkin
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 22)

            ProgressGrid(stages: stages,
                         activeIndex: currentStage,
                         stageBytes: stageBytes,
                         detail: currentFile,
                         entries: found)
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, 18)

            CircleActionButton(title: "Dừng", accent: skin.action,
                               progress: progress, action: onStop)
                .padding(.bottom, 22)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            if totalBytes > 0 {
                let parts = Fmt.sizeParts(totalBytes)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(parts.value)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(parts.unit)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("tìm được đến giờ")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .padding(.leading, 2)
                }
            } else {
                Text("Đang quét…")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
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
    let progress: Double
    let skin: ModuleSkin
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 22)

            ProgressGrid(stages: stages,
                         activeIndex: currentStage,
                         stageBytes: stageBytes,
                         detail: "",
                         entries: entries,
                         doneCaption: "đã dọn",
                         runningTitle: "Đang dọn…")
                .padding(.horizontal, Metrics.contentPadding)
                .padding(.bottom, 18)

            CircleActionButton(title: "Dừng", accent: skin.action,
                               progress: progress, action: onStop)
                .padding(.bottom, 22)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            let parts = Fmt.sizeParts(freed)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(freed > 0 ? parts.value : "0")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(freed > 0 ? parts.unit : "KB")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                Text("đã giải phóng")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.leading, 2)
            }
            Text("\(doneCount)/\(total) mục")
                .font(.system(size: 12.5)).foregroundStyle(Palette.textSecond)
                .contentTransition(.numericText())
        }
    }
}
