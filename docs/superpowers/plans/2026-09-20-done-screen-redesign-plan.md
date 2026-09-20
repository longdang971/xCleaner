# Kế hoạch: thiết kế lại màn "dọn xong"

Spec: `docs/superpowers/specs/2026-09-20-done-screen-redesign-design.md`

## 1. `Fmt.countingValue` — test trước

- `SelfTest.testCountingValue()`: `fraction == 1` trả đúng chuỗi cuối; `fraction == 0` trả `"0,0"`
  (giữ nguyên số chữ số thập phân của chuỗi cuối); `fraction == 0.5` của `"12,4"` ra `"6,2"`;
  chuỗi không có số (`"—"`) trả lại chính nó; chuỗi số nguyên `"512"` không mọc thêm phần thập phân.
- Đăng ký vào `SelfTest.run()`.
- Viết `Fmt.countingValue(finalValue:fraction:)` trong `Sources/Core/Models.swift` cho tới khi xanh.

## 2. Tách `DoneScreen` sang `Sources/Views/DoneScreen.swift`

Di chuyển nguyên trạng `DoneScreen` (và chỉ nó) khỏi `GroupedModuleView.swift`. Không đổi hành vi
ở bước này — build lại để chắc chắn phần tách là vô hại trước khi sửa giao diện.

## 3. Bốn thành phần hiệu ứng (cùng file)

`CelebrationHalo`, `SparkBurst`, `DrawnCheckmark`, `FreedAmount` như spec mô tả. `FreedAmount`
là `View & Animatable` để nội suy được chữ số, blur và tracking trong cùng một animation.

## 4. Dựng lại thân `DoneScreen`

- Bỏ `ProgressGrid` và nhánh `EmptyStateView` bám theo nó.
- Bố cục: `Spacer` → dấu ✓ (kèm hạt) → con số → "đã giải phóng" → dòng tóm tắt → `Spacer` → nút
  "Xong"; quầng sáng nằm dưới cùng trong `ZStack`. Giữ `IconToolbar` "Quét lại".
- `progress` 0 → 1 trong `onAppear`; các lớp chữ/nút hiện ra so le bằng `delay`.
- Ba trạng thái rìa của spec: huỷ-chưa-xoá-gì, dọn-xong-0-byte, `outcome` chưa về.
- `accessibilityDisplayShouldReduceMotion` → chỉ mờ dần.

## 5. Kiểm chứng

- `XCLEANER_SELFTEST=1` xanh (137 + số phép mới).
- `XCLEANER_DEMO_DONE=1` + `XCLEANER_SHOT` chụp màn mới, xem lại bằng mắt.
- Chụp thêm `XCLEANER_DEMO_DONE=fail` (trạng thái huỷ) để chắc nhánh rìa không vỡ.
