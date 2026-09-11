# xCleaner

Ứng dụng dọn dẹp macOS viết bằng Swift + SwiftUI, giao diện theo hướng CleanMyMac.
Không sandbox, không gửi dữ liệu ra ngoài, và **không cần Apple Developer ID**.

## Các mục

| Mục | Việc nó làm |
|---|---|
| Quét thông minh | Gom rác hệ thống + Thùng rác + bộ nhớ đệm trình duyệt, tất cả đều an toàn để xoá |
| Rác hệ thống | Bộ nhớ đệm, nhật ký, báo cáo sự cố của người dùng và của `/Library`, rác công cụ lập trình |
| Thùng rác & Tải về | Thùng rác mọi ổ đĩa, bộ cài cũ, tệp tải lâu ngày, đính kèm thư, ảnh chụp màn hình |
| Riêng tư | Cookie, lịch sử, phiên, bộ nhớ đệm của Safari, Chrome, Edge, Brave, Firefox, Arc, Opera, Vivaldi, Zen |
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
XCLEANER_MODULE=privacy XCLEANER_SHOT_ACTION=scan XCLEANER_APPEARANCE=dark \
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
- **Firefox**: không bao giờ xoá `places.sqlite` vì tệp đó chứa cả lịch sử lẫn dấu trang.
- **Chromium**: `History` an toàn để xoá, dấu trang nằm ở tệp `Bookmarks` riêng.

## Cần cấp quyền

Vào **Cài đặt Hệ thống → Quyền riêng tư & Bảo mật → Quyền truy cập toàn bộ đĩa** và thêm xCleaner,
nếu muốn dọn dữ liệu Safari, Mail và vài thư mục được macOS bảo vệ.
