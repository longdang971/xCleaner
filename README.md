# xCleaner

Ứng dụng dọn dẹp macOS viết bằng Swift + SwiftUI.
Không sandbox, không gửi dữ liệu ra ngoài, và **không cần Apple Developer ID**.

## Cài đặt

Yêu cầu: macOS 14 (Sonoma) trở lên, máy Intel hoặc Apple Silicon.

**1. Tải bản mới nhất**

Vào [trang Releases](https://github.com/longdang971/xCleaner/releases/latest) và tải tệp
`xCleaner-<phiên bản>.zip`.

**2. Giải nén**

Bấm đúp vào tệp `.zip` vừa tải. Finder sẽ tạo ra `xCleaner.app` ngay cạnh nó.

**3. Kéo vào thư mục Ứng dụng**

Kéo `xCleaner.app` vào thư mục **Applications** (Ứng dụng). Bước này không bắt buộc về mặt
kỹ thuật, nhưng lệnh ở bước sau viết theo đường dẫn đó nên cứ để app nằm đúng chỗ cho gọn.

**4. Gỡ cờ kiểm dịch của macOS**

Mở **Terminal** (⌘ + Space, gõ `Terminal`, Enter) rồi dán đúng dòng này và nhấn Enter:

```bash
xattr -cr /Applications/xCleaner.app
```

Lệnh chạy xong không in ra gì cả — im lặng nghĩa là đã xong.

**5. Mở xCleaner**

Mở từ Launchpad hoặc thư mục Applications. Lần đầu macOS có thể hỏi xác nhận, chọn **Mở**.

### Vì sao phải chạy lệnh ở bước 4?

xCleaner ký **ad-hoc** — tức là không có chứng chỉ Apple Developer ID, vì thứ đó tốn 99 USD
mỗi năm cho một app miễn phí không sandbox. Mọi tệp tải từ Internet đều bị macOS gắn thuộc
tính `com.apple.quarantine`; gặp thuộc tính đó trên một app ký ad-hoc, Gatekeeper từ chối
thẳng và báo **"xCleaner bị hỏng và không thể mở"** — app không hỏng, chỉ là không có chữ ký
Apple công nhận. `xattr -cr` xoá các thuộc tính mở rộng đó (`-c` là xoá sạch, `-r` là làm cả
những tệp bên trong gói app), nên sau đó app mở bình thường.

Chỉ phải làm một lần cho mỗi bản tải về bằng trình duyệt. Khi cập nhật **từ trong app**
(Cài đặt ▸ Giới thiệu) thì không cần làm gì: script thay thế app tự chạy đúng lệnh `xattr -cr`
này lên bản mới trước khi mở lại.

### Gỡ cài đặt

Kéo `xCleaner.app` vào Thùng rác. Nếu muốn xoá sạch cả tuỳ chọn đã lưu:

```bash
defaults delete com.pikalong.xCleaner
```

## Ngôn ngữ thiết kế

Học theo CleanMyMac 5 nhưng dựng lại hoàn toàn bằng SwiftUI, không dùng tệp ảnh nào:

- **Nền gradient đậm phủ kín cửa sổ, mỗi mục một tông màu.** Người dùng nhận ra mình đang ở
  đâu bằng màu trước cả khi đọc tiêu đề. Nền của mọi mục vẽ chồng lên nhau và chỉ đổi độ mờ
  khi chuyển mục — gradient không nội suy trực tiếp được, còn đổi opacity thì chạy trên GPU.
- **Sidebar 72px chỉ có icon, rê chuột vào thì nở ra 206px kèm tên.** Nó đè lên nội dung chứ
  không đẩy, nên bố cục không giật. Nền phải **đục** khi nở: material của SwiftUI không làm mờ
  view anh em cùng cửa sổ, để trong suốt là chữ bên dưới hiện xuyên qua.
- **Thẻ kính mờ** (trắng 13%, viền trắng 17%, mép trên sáng hơn) nổi trên gradient.
- **Khối 3D bóng** (`GemView`): squircle thật + gradient ba chặng + highlight vai trên trái +
  ánh phản chiếu hắt ngược từ dưới + cạnh kính. Mỗi thẻ mượn một tông màu khác nhau.
- **Nút hành động tròn** dùng màu **kế cận** trên vòng màu, bão hoà hơn nền — không phải màu
  đối lập: vàng trên teal đọc ra như một cảnh báo, còn magenta trên tím thì nổi mà vẫn hài hoà.
  Màu phải đặc, pha trong suốt là nền phía sau làm nút xỉn đi ngay.
- **Ba chặng thao tác**: màn khởi đầu (khối 3D + nút tròn) → lưới thẻ tóm tắt → danh sách chi
  tiết khi bấm "Xem". Nhờ vậy màn kết quả luôn gọn dù nhóm có hàng nghìn tệp.
- **Bốn màn cùng một khung**: đang quét, đang dọn, dọn xong và lưới kết quả dùng chung con số
  lớn ở đỉnh, lưới thẻ ở giữa và nút tròn ở đáy. Đi hết một lượt, người dùng thấy các ô đổi
  nội dung tại chỗ chứ không phải bốn trang khác nhau nối đuôi.
- **Không có bước xác nhận trước khi dọn**: mọi mục đều nhìn thấy và bỏ chọn được ngay trên
  màn kết quả, nên hộp thoại hỏi lại chỉ là một cú bấm thừa. Mục có rủi ro (tự động điền,
  cookie) cố tình **không** tick sẵn.
- **Vào là thấy việc**: mục Gỡ ứng dụng và Khởi động cùng máy chỉ đọc danh sách chứ không xoá
  gì, nên chúng vào thẳng danh sách, không có màn giới thiệu và cũng không có màn chờ riêng.

## Các mục

| Mục | Việc nó làm |
|---|---|
| Quét thông minh | Quét sâu đúng như các mục chuyên biệt, nhưng chỉ tick sẵn những gì an toàn tuyệt đối |
| Rác hệ thống | Bộ nhớ đệm, nhật ký, báo cáo sự cố của người dùng và của `/Library`, rác công cụ lập trình |
| Thùng rác & Tải về | Thùng rác mọi ổ đĩa, bộ cài cũ, tệp tải lâu ngày, đính kèm thư, ảnh chụp màn hình |
| Riêng tư | Quét sâu từng trình duyệt (Safari, Chrome, Edge, Brave, Firefox, Arc, Opera, Vivaldi, Zen), chia thành 7 phần chọn riêng được |
| Gỡ ứng dụng | Xoá app cùng dữ liệu, tuỳ chọn, container, tác vụ nền, biên nhận cài đặt |
| Tệp lớn & cũ | Duyệt thư mục theo dung lượng và ngày dùng cuối |
| Tệp trùng lặp | Ba vòng lọc: kích thước → băm hai đầu → SHA-256 toàn bộ |

## Quyền quản trị mà không có Developer ID

`SMJobBless` và `SMAppService` đều đòi chứng chỉ Developer ID, nên xCleaner đi đường khác:

1. **Ưu tiên** `AuthorizationServices`: `AuthorizationCreate` với `kAuthorizationEnvironmentPrompt` và
   `kAuthorizationEnvironmentIcon` → hộp thoại mật khẩu mang **icon và tên xCleaner** cùng câu giải thích
   tiếng Việt, sau đó `AuthorizationExecuteWithPrivileges` (nạp động bằng `dlsym` vì Apple đã đánh dấu
   deprecated) chạy lệnh dưới quyền root.
2. **Dự phòng** `osascript -e 'do shell script … with administrator privileges'` — luôn có mặt trên mọi
   máy macOS, dùng khi cách thứ nhất không chạy được.

App **không bao giờ nhìn thấy mật khẩu**: hộp thoại do SecurityAgent của hệ thống hiển thị.

### Bốn lớp bảo vệ khi chạy dưới root

1. Đường dẫn **không** được nội suy vào chuỗi lệnh. Chúng được ghi ra tệp kê khai ngăn cách bằng byte NUL,
   `xargs -0` đọc lại — tên có dấu cách, nháy đơn, nháy kép hay xuống dòng đều vô hại.
2. Tệp kê khai nằm trong thư mục `0700` thuộc sở hữu người dùng, tên ngẫu nhiên, xoá ngay sau khi xong.
3. Mọi đường dẫn đi qua `SafetyGuard` hai lần — lúc lập kế hoạch và ngay trước khi ghi vào tệp kê khai.
   Danh sách cấm gồm `/System`, `/usr`, `/bin`, `/Library/Keychains`, chính thư mục nhà, gốc ổ đĩa…
   và chỉ vài nhánh được phép đụng tới.
4. Cả phiên dọn chỉ hỏi mật khẩu **một lần** vì mọi đường dẫn được gom vào một lệnh duy nhất.

## Dựng và chạy

```bash
xcodegen generate
xcodebuild -project xCleaner.xcodeproj -scheme xCleaner -configuration Debug build
```

### Công cụ khi phát triển (chỉ có trong bản Debug)

```bash
# Bộ tự kiểm tra: hàng rào an toàn, xoá thật, Thùng rác, đo dung lượng
XCLEANER_SELFTEST=1 ./xCleaner.app/Contents/MacOS/xCleaner

# Tự chụp cửa sổ (không cần cấp quyền Ghi màn hình cho Terminal)
XCLEANER_SHOT=/tmp/a.png XCLEANER_SHOT_DELAY=5 XCLEANER_SHOT_QUIT=1 \
XCLEANER_MODULE=privacy XCLEANER_SHOT_ACTION=scan \
XCLEANER_SIDEBAR=expanded XCLEANER_REVIEW=1 \
  ./xCleaner.app/Contents/MacOS/xCleaner

# Dựng sẵn màn "đã dọn xong" bằng dữ liệu giả (không quét, không xoá gì)
XCLEANER_SHOT=/tmp/b.png XCLEANER_SHOT_DELAY=4 XCLEANER_SHOT_QUIT=1 \
XCLEANER_DEMO_DONE=fail XCLEANER_DEMO_FAILURES=1 \
  ./xCleaner.app/Contents/MacOS/xCleaner

# Thử luồng xin quyền root mà không xoá gì
XCLEANER_TEST_AUTH=1 ./xCleaner.app/Contents/MacOS/xCleaner
```

### Biểu tượng

`docs/icon-source.swift` dựng icon bằng Core Graphics:

```bash
swift docs/icon-source.swift
iconutil -c icns /tmp/xCleaner.iconset -o Resources/AppIcon.icns
```

## Ghi chú kỹ thuật

- **Giữ cho mượt**: scanner gọi hàm tiến trình hàng nghìn lần mỗi giây, `ProgressThrottle` chỉ cho qua
  ~20 lần/giây nên SwiftUI không dựng lại cây view liên tục. Mỗi mục có `ScanStore` riêng để việc quét ở
  mục này không làm mục khác dựng lại. Danh sách dùng `LazyVStack` và cắt ở 120 dòng mỗi nhóm.
- **Màu**: `Color.adaptive(light, dark)` dựng `NSColor` động, một khai báo dùng cho cả hai chế độ sáng/tối.
- **Tệp cá nhân** (Tệp lớn & cũ, Tệp trùng lặp) luôn vào Thùng rác, không xoá thẳng.
- **Nhớ lựa chọn** (`SelectionMemory`): chỉ ghi lại **phần khác với mặc định**, khoá là đường dẫn
  rút gọn `~`. Nhờ vậy khi một bản sau đổi đề xuất mặc định, những mục người dùng chưa từng đụng
  tới sẽ đi theo đề xuất mới thay vì mắc kẹt ở lựa chọn cũ. Quay về đúng mặc định thì mục đó
  được xoá khỏi bộ nhớ, không tích rác vô hạn. Tắt hoặc xoá sạch trong Tuỳ chọn.
- **Quét thông minh** dùng chung bộ quét trình duyệt với mục Riêng tư, chỉ khác ở chỗ tick sẵn
  mỗi phần bộ nhớ đệm. Muốn đổi thì phải tạo `CleanItem` mới qua `reselected(_:)` chứ không sửa
  `isSelected`, vì `defaultSelected` chính là cái mốc để biết người dùng có tự tay đổi ý hay không.
- **Firefox**: không bao giờ xoá `places.sqlite` vì tệp đó chứa cả lịch sử lẫn dấu trang.
- **Chromium**: `History` an toàn để xoá, dấu trang nằm ở tệp `Bookmarks` riêng.

### Mục Riêng tư quét những gì

Bảy phần, mỗi phần chọn hoặc bỏ chọn riêng được ngay trong màn hình "Xem":

| Phần | Gồm những gì | Chọn sẵn |
|---|---|---|
| Lịch sử duyệt web | địa chỉ đã truy cập, gợi ý thanh địa chỉ, lối tắt, trang hay vào, liên kết đã xem, biểu tượng trang | ✓ |
| Danh sách tải về | danh sách tệp đã tải (tệp vẫn còn nguyên) | ✓ |
| Cookie & đăng nhập | cookie, Trust Token | ✗ |
| Tự động điền | biểu mẫu, địa chỉ, thẻ thanh toán đã lưu | ✗ (cẩn trọng) |
| Thẻ & phiên làm việc | thẻ đang mở, thẻ vừa đóng, phiên lần trước, thẻ iCloud, Session Storage | ✗ |
| Bộ nhớ đệm | cache trang, cache mã, GPU, Dawn/WebGPU, Service Worker | ✓ |
| Dữ liệu trang web | Local Storage, IndexedDB, Web SQL, File System API | ✗ |

**Mật khẩu đã lưu** (`Login Data`, `logins.json`, `key4.db`) cố tình **không** có trong danh sách:
mất mật khẩu là mất hẳn, và không ai mong một công cụ dọn rác đụng tới chúng.

Khi macOS chặn đọc thư mục Safari (chưa cấp Toàn quyền truy cập đĩa), thẻ Safari sẽ nói rõ
danh sách chưa đầy đủ và có nút mở thẳng trang cấp quyền.

## Cần cấp quyền

Vào **Cài đặt Hệ thống → Quyền riêng tư & Bảo mật → Quyền truy cập toàn bộ đĩa** và thêm xCleaner,
nếu muốn dọn dữ liệu Safari, Mail và vài thư mục được macOS bảo vệ.
