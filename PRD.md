# PRD — Hệ thống Báo cáo Nguồn vốn - Sử dụng vốn

*Product Requirements Document · phiên bản 1.0*

---

## 1. Mục tiêu

Xây dựng hệ thống tự động tạo báo cáo cân đối vốn (huy động - cho vay) của ngân hàng theo ngày, thay cho quy trình tính thủ công trên Excel. Hệ thống phải: tính đúng 33 chỉ tiêu, chạy lại được cho ngày cũ, ghi log vận hành, và cung cấp dashboard trực quan.

## 2. Phạm vi

**Trong phạm vi:** thiết kế CSDL (dim/fact), ETL bằng stored procedure, query báo cáo, dashboard Power BI, kiểm soát chất lượng dữ liệu.

**Ngoài phạm vi:** thu thập dữ liệu từ core banking (giả định đã có 2 file CSV nguồn), phân quyền người dùng, hạ tầng triển khai production.

## 3. Đối tượng sử dụng

| Người dùng | Nhu cầu |
|---|---|
| Lãnh đạo / ALM | Xem nhanh quy mô vốn, LDR, biên lãi, xu hướng |
| Phòng nguồn vốn | Phân tích cơ cấu kỳ hạn/loại hình để điều chỉnh lãi suất |
| Vận hành dữ liệu | Giám sát job chạy đúng/lỗi, độ tươi dữ liệu |

## 4. Yêu cầu chức năng

| # | Yêu cầu | Đầu ra |
|---|---|---|
| FR1 | Định nghĩa thuật ngữ nghiệp vụ, thiết kế bảng dim/fact | `dim_funding_structure`, 2 bảng fact input |
| FR2 | Import dữ liệu từ 2 file CSV vào CSDL | Bảng `fact_dp_customer`, `fact_ln_customer` |
| FR3 | Bảng dimension tiêu chí báo cáo (data-driven) | `dim_funding_structure` (33 chỉ tiêu + unknown) |
| FR4 | Bảng fact tổng hợp theo ngày | `fact_summary_funding_daily` |
| FR5 | Procedure đổ dữ liệu thống kê theo chỉ tiêu | `fact_summary_funding_daily_prc` |
| FR5a | Cho phép chạy backdate (param ngày, xóa + tính lại) | — |
| FR5b | Ghi log start/end/is_successful/error vào bảng log | `procedure_log` |
| FR5c | Bắt exception, ghi lỗi vào log | — |
| FR5d | Procedure viết theo template chuẩn | — |
| FR6 | Query truy vấn theo format sheet "Report Query" | Query báo cáo |
| FR7 | Đề xuất index tăng tốc procedure | Index trên bảng input |

## 5. Yêu cầu phi chức năng

- **Chính xác:** số liệu khớp 100% với báo cáo Excel mẫu (ngày 15/12/2023).
- **Hiệu năng:** procedure chạy < 1 giây/ngày.
- **Chạy lại an toàn (idempotent):** chạy nhiều lần cùng một ngày không nhân đôi dữ liệu.
- **Toàn vẹn dữ liệu:** PK chống trùng, FK ràng buộc chỉ tiêu, chốt chặn dữ liệu chưa phân loại.

## 6. Quy tắc nghiệp vụ (đã kiểm chứng)

| Chỉ tiêu | Định nghĩa |
|---|---|
| Số dư TĐ | `SUM(balance)` tại ngày báo cáo |
| Số dư BQ | Trung bình tổng số dư theo ngày, lũy kế đầu tháng → ngày báo cáo (MTD) |
| Lãi suất / VOF / COF | Trung bình cộng đơn giản theo tài khoản, tại ngày báo cáo |
| Margin | VOF/COF − lãi suất |
| Phân loại kỳ hạn (DP) | `maturity_date − open_date` (ngày): KKH (null), 1-24, 25-165, 166-195, 196-225, 226-345, 346-375, 376-405, 406-705, còn lại |
| Phân loại (LN) | Nợ QH (`day_past_due>0`) → CCSTK / VND-USD (account_type) → ngắn ≤365 / trung ≤1825 / dài ≤3650 / ≤5475 / còn lại |
| Loại hình | DP theo `account_type`, LN theo `customer_type` (Business/Individual) |

## 7. Tiêu chí nghiệm thu

- [x] 33/33 chỉ tiêu ngày 15/12/2023 khớp báo cáo Excel gốc.
- [x] Chạy backdate: xóa + tính lại đúng, không nhân đôi.
- [x] Log ghi đủ start/end/is_successful/error cho mọi lần chạy.
- [x] Gọi ngày không có dữ liệu → báo lỗi, ghi log, không tạo dòng rác.
- [x] Dashboard Power BI hiển thị đúng số liệu, tương tác được.

## 8. Rủi ro & giả định

- Cột HSRR (hệ số rủi ro) không có trong dữ liệu nguồn → 5 dòng HSRR = 0 (placeholder).
- Bản ghi tất toán sớm có thể bị ghi đè `maturity_date` → xử lý bằng nhánh phân loại "vét".
- Bản hiện tại chưa partition bảng fact; nếu dữ liệu tăng nhiều năm, cân nhắc partition theo tháng.
