# DAX measures & calculated columns — Power BI

Nguồn: view `vw_funding_report` + bảng `procedure_log`. Đổi tên bảng nếu import khác.

---

## Bảng phụ trợ

**Bảng lịch** (Modeling → New table):
```dax
Calendar = CALENDAR(DATE(2023,1,1), DATE(2023,12,31))
```
Nối `Calendar[Date]` với `vw_funding_report[process_dt]` (1 - nhiều).

**Cột phân nhóm Huy động/Dư nợ** (New column):
```dax
Nhom = IF( LEFT( TRIM(vw_funding_report[funding_code]), 2 ) = "DP", "Huy động", "Dư nợ" )
```

**Cột cờ bucket kỳ hạn** — để lọc donut/bar chỉ còn dòng lá theo kỳ hạn (New column):
```dax
La_bucket_kyhan =
IF( vw_funding_report[funding_level] = 2
    && MID(vw_funding_report[funding_code], 3, 2) = "01", 1, 0 )
```

---

## Nhóm QUY MÔ

```dax
Tong HD ty = DIVIDE( CALCULATE(SUM(vw_funding_report[balance]),
                     vw_funding_report[funding_code] = "DP"), 1e9 )

Tong DN ty = DIVIDE( CALCULATE(SUM(vw_funding_report[balance]),
                     vw_funding_report[funding_code] = "LN"), 1e9 )

LDR pct = DIVIDE(
    CALCULATE(SUM(vw_funding_report[balance]), vw_funding_report[funding_code]="LN"),
    CALCULATE(SUM(vw_funding_report[balance]), vw_funding_report[funding_code]="DP") )
```

## Nhóm SINH LỜI

```dax
LS huy dong = CALCULATE(AVERAGE(vw_funding_report[interest_rate]),
                        vw_funding_report[funding_code]="DP")

LS cho vay  = CALCULATE(AVERAGE(vw_funding_report[interest_rate]),
                        vw_funding_report[funding_code]="LN")

-- Chenh lech lai suat rong = margin toan hang (KPI chinh, de doc)
NIM spread pct = [LS cho vay] - [LS huy dong]

-- Margin FTP tung khoi = (VOF/COF - lai suat), khop cot Margin dong A/B tren Excel
Margin huy dong pct =
    CALCULATE(AVERAGE(vw_funding_report[vof_cof_rate]) - AVERAGE(vw_funding_report[interest_rate]),
              vw_funding_report[funding_code]="DP")

Margin cho vay pct =
    CALCULATE(AVERAGE(vw_funding_report[vof_cof_rate]) - AVERAGE(vw_funding_report[interest_rate]),
              vw_funding_report[funding_code]="LN")
```

## Nhóm CƠ CẤU

```dax
Ty trong KKH pct = DIVIDE(
    CALCULATE(SUM(vw_funding_report[balance]), vw_funding_report[funding_code]="DP01001"),
    CALCULATE(SUM(vw_funding_report[balance]), vw_funding_report[funding_code]="DP01") )
```

## Tiêu đề động (không mất khi bấm visual, không nhảy ra ngày ngoài dữ liệu)

```dax
Phu de bang =
"Số liệu ngày "
& FORMAT(
    CALCULATE( MAX(vw_funding_report[process_dt]), ALLSELECTED(vw_funding_report) ),
    "dd/MM/yyyy" )
& " · đơn vị: đồng · lãi suất %/năm"
```

---

## Nhóm VẬN HÀNH (từ procedure_log)

```dax
Lan chay gan nhat = MAX(procedure_log[start_time])

Trang thai job =
VAR latest = MAX(procedure_log[start_time])
VAR ok = CALCULATE( SELECTEDVALUE(procedure_log[is_successful]),
                    procedure_log[start_time] = latest )
RETURN IF( ok, "OK", "THẤT BẠI" )

-- Mau chu cho card trang thai (dung voi Font color -> Field value)
Mau trang thai =
IF( CALCULATE(SELECTEDVALUE(procedure_log[is_successful]),
              procedure_log[start_time]=MAX(procedure_log[start_time])),
    "#0F6E56", "#D03B3B" )

So lan that bai = CALCULATE( COUNTROWS(procedure_log),
                             procedure_log[is_successful] = FALSE() )

Thoi gian chay giay =
VAR latest = MAX(procedure_log[start_time])
RETURN CALCULATE(
    DATEDIFF( MIN(procedure_log[start_time]), MAX(procedure_log[end_time]), SECOND ),
    procedure_log[start_time] = latest )
```

**Cột hiển thị kết quả trong bảng log** (New column trên procedure_log):
```dax
Ket qua = IF( procedure_log[is_successful], "OK", "Lỗi" )
```

**Cột thời gian chạy từng dòng** (New column):
```dax
Thoi gian (giay) = DATEDIFF(procedure_log[start_time], procedure_log[end_time], SECOND)
```

---

## Ghi chú áp dụng

- Card tổng lấy thẳng dòng `funding_code IN ("DP","LN")` — chính xác hơn cộng dòng lá (tránh đếm trùng cả tổng lẫn lá).
- Lãi suất/margin luôn dùng **Average**, không Sum.
- Conditional formatting LDR (nền/chữ theo ngưỡng): base trên `LDR pct`, Rules: `<0.85` xanh, `0.85-0.9` vàng, `>0.9` đỏ.
- Slicer ngày phải **ngắt** (Edit interactions → None) khỏi các line chart xu hướng để chúng luôn hiện cả kỳ.
