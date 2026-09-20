# Thiết kế lại màn "dọn xong"

Ngày 20/09/2026. Trạng thái: đã chốt với người dùng qua mockup động.

## Vấn đề

Màn `.done` hiện tại (`DoneScreen` trong `Sources/Views/GroupedModuleView.swift:671`) giữ nguyên
lưới `ProgressGrid` của màn đang dọn: mỗi nhóm một thẻ, thẻ nào cũng ghi số byte nhóm đó đã dọn.
Người dùng đánh giá cách báo cáo "từng thẻ một" này trông **không chuyên nghiệp** — nó biến khoảnh
khắc kết thúc thành một bảng số liệu, trong khi thứ duy nhất người ta muốn biết lúc đó là **đã dọn
được tổng bao nhiêu**.

## Quyết định

**Bỏ hẳn lưới thẻ khỏi màn dọn xong. Không thay bằng danh sách, không giấu sau nút "Chi tiết" —
xoá hẳn.** Phần chia theo nhóm đã có ở màn kết quả trước khi dọn; nhắc lại sau khi dọn không giúp
người dùng làm gì tiếp.

Màn mới chỉ còn một khối duy nhất, căn giữa:

```
        ✓   (dấu ✓ lớn 132pt, pháo hoa nổ quanh nó)

            12,4 GB
          đã giải phóng

           ( Xong )
```

Dòng "N mục đã được dọn · có dùng quyền quản trị" cũng bỏ nốt: quyền quản trị thì người dùng vừa
tự gõ mật khẩu nên đã biết, còn số mục chỉ là cách nói khác của con số ngay phía trên. Dòng phụ
chỉ còn hiện khi có thứ người dùng **còn phải làm gì đó với nó** — tệp nằm trong Thùng rác, hoặc
việc dọn bị bỏ dở.

Vẫn giữ đúng khung chung của bốn màn (số lớn ở trên, nút tròn ở đáy, nút "Quét lại" góc trên phải),
theo thoả thuận đã có: thêm màn mới thì giữ khung này.

## Hiệu ứng (đã chọn bằng mắt trên mockup động)

Người dùng xem ba phương án (vòng sáng bung / hạt pha lê / tĩnh sang) rồi chốt **ghép B + C**, bản
**không nảy**:

| Lớp | Nội dung | Thời gian |
|---|---|---|
| Quầng sáng | Vòng sáng trắng mờ sau lưng khối số, hiện lên rồi "thở" một nhịp, đọng lại ở 45% | 0,1s → 2,9s |
| Dấu ✓ | Vòng tròn viền mảnh, nét tick vẽ từ trái sang | 0,25s → 0,70s |
| Pháo hoa | Ba chùm nổ so le **ngay quanh dấu ✓** (lệch nhau ~90pt), mỗi chùm 18 tia xoay đúng hướng bay, vừa toả ra vừa rơi xuống theo đường cong nặng dần | 0,05 / 0,45 / 0,80s, mỗi chùm 1,5s |
| Con số | Từ nhoè (blur 16) và giãn chữ (tracking 7) **tụ lại sắc nét**, đồng thời chạy số từ 0 lên tổng thật | 0,18s → 1,18s |
| Chữ & nút | "đã giải phóng" → (dòng phụ nếu có) → nút "Xong" lần lượt trượt lên hiện ra | 0,62s → 1,45s |

Con số **không nảy** (không phóng to từ 80%) — đây là điểm người dùng chọn giữa hai biến thể.

## Kiến trúc

Tách `DoneScreen` ra khỏi `GroupedModuleView.swift` (đang 33 KB, ôm cả màn khởi đầu, lưới kết quả,
trang chi tiết) sang **`Sources/Views/DoneScreen.swift`** cùng các thành phần hiệu ứng. Mỗi thành
phần là một view độc lập, tự lo một lớp hiệu ứng, nhận `progress` hoặc `trigger` từ ngoài:

- `CelebrationHalo` — quầng sáng thở. Vào: `isOn`.
- `FireworksShow` — ba chùm pháo hoa quanh dấu ✓. Vào: `trigger` (đổi là bắn lại), `colors`.
- `DrawnCheckmark` — vòng tròn + nét vẽ dần, đường kính 132pt, nét tỉ lệ theo đường kính. Vào:
  `mark` (`.check` khi xong, `.halt` — một gạch ngang trung tính — khi huỷ), `drawn`, `tint`.
- `FreedAmount` — con số tụ nét kèm đếm lên. Vào: `bytes`, `progress`. Là `View & Animatable` nên
  thân view được dựng lại mỗi khung hình, đủ để nội suy cả **chữ số**, **blur** và **tracking**
  trong cùng một animation.
- `DoneScreen` — xếp các lớp trên, bật `progress` 0 → 1 lúc `onAppear`.

`ProgressGrid` **giữ nguyên**: màn đang quét và đang dọn vẫn dùng.

## Đếm số mà không nhảy đơn vị

Nội suy byte rồi gọi `Fmt.sizeParts` mỗi khung hình sẽ làm đơn vị nhảy KB → MB → GB giữa chừng.
Thay vào đó: **lấy đơn vị và số chữ số thập phân từ giá trị cuối cùng**, rồi chỉ nội suy phần số.

`Fmt.countingValue(finalValue:fraction:)` nhận đúng chuỗi phần số mà `Fmt.sizeParts` đã sinh
(ví dụ `"12,4"`), nhân với `fraction`, và định dạng lại **đúng số chữ số thập phân đó** theo
locale hiện hành. Ở `fraction == 1` hàm trả lại nguyên chuỗi ban đầu — không có cú giật ở khung
hình cuối. Không phân tích được chuỗi (locale lạ) thì trả luôn giá trị cuối: mất hiệu ứng đếm,
không bao giờ hiện sai số.

## Tôn trọng "Giảm chuyển động"

Khi `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` bật: không pháo hoa, không thở, không
blur, không đếm số — chỉ hiện ra bằng một lần mờ dần. Cùng một cây view, khác mỗi tham số.

## Các trạng thái khác của màn này

- **Huỷ mà chưa xoá được gì** (`wasCancelled && freedBytes == 0`): "Đã huỷ", không pháo hoa, và
  dấu trong vòng tròn đổi sang `.halt` (một gạch ngang trung tính) — vẽ dấu ✓ xanh cho một việc
  vừa bị dừng là báo sai.
- **Dọn xong nhưng không giải phóng được byte nào** (`removedCount == 0 && freedBytes == 0`): hiện
  "Không có gì để dọn" thay cho con số `0 KB`, vẫn có dấu ✓ nhưng không có pháo hoa.
- **`outcome` chưa kịp về**: giữ nguyên `ScanRing` như cũ.
- Hai nhánh rìa trên xem được bằng `XCLEANER_DEMO_DONE=cancel` và `=empty` (chỉ bản Debug).

## Kiểm thử

`SelfTest` (197 phép trước đợt này) thêm mục `Fmt.countingValue`: phân số 0 / 0,5 / 1 ra đúng chuỗi, giữ
nguyên số chữ số thập phân, chuỗi không phân tích được thì trả giá trị cuối. Phần hiệu ứng kiểm
bằng mắt qua `XCLEANER_DEMO_DONE=1` + `XCLEANER_SHOT`.

## Hai điều phát hiện khi dựng, đã sửa

**Nút "Quét lại" tụt vào giữa màn.** Nó neo `.topTrailing` trên khối nội dung; hồi còn lưới thẻ
thì chính lưới kéo khối đó rộng bằng cửa sổ. Bỏ lưới đi, bề ngang co lại bằng dòng chữ dài nhất
và nút trôi theo vào trong. Phải `.frame(maxWidth: .infinity, maxHeight: .infinity)` cho khối nội
dung.

**Màu tia phải sáng hơn nền, không cùng tông với nền.** Lấy thẳng `skin.gem` thì chùm pháo hoa
hồng nổ trên nền hồng của Quét thông minh gần như tàng hình. Bảng màu tia nay là trắng + tông
sáng nhất của bộ đá quý + `glow` + xanh "đã sạch" + vàng ấm, và màu chủ đạo của mỗi chùm bỏ qua
màu trắng.
