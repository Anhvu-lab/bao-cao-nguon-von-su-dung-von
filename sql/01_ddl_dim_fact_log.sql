-- ============================================================================
-- 01. DDL: dim_funding_structure + 2 bang fact input + fact summary + log
-- Schema: mini_project
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS dim_funding_structure CASCADE;

-- B1: Dung bang cau truc von (DIM)
CREATE TABLE dim_funding_structure (
    funding_id        serial       PRIMARY KEY,
    funding_code      varchar(30)  NOT NULL UNIQUE,
    funding_name      varchar(255) NOT NULL,
    funding_parent_id int          REFERENCES dim_funding_structure(funding_id),
    funding_level     int          NOT NULL,
    sort_order        int          NOT NULL,
    rec_created_dt    timestamp    NOT NULL DEFAULT now(),
    rec_updated_dt    timestamp    NOT NULL DEFAULT now()
);

-- Trigger: tu dong cap nhat rec_updated_dt moi lan UPDATE
CREATE OR REPLACE FUNCTION fn_set_rec_updated_dt() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.rec_updated_dt = now();
    RETURN NEW;
END $$;

CREATE TRIGGER trg_dim_funding_structure_upd
BEFORE UPDATE ON dim_funding_structure
FOR EACH ROW EXECUTE FUNCTION fn_set_rec_updated_dt();

-- B1.1: seed dim theo thu tu cha -> con (khong vi pham FK)
INSERT INTO dim_funding_structure
      (funding_id, funding_code, funding_name, funding_parent_id, funding_level, sort_order)
VALUES
-- lv0: section
(1,  'DP',       'A. Nguồn vốn',                            NULL, 0, 1000000),
(2,  'LN',       'B. Sử dụng vốn',                          NULL, 0, 2000000),
-- lv1: nhom chi tieu
(3,  'DP01',     'I/ Tiền gửi TCKT & DC: Theo kỳ hạn',      1, 1, 1010000),
(4,  'DP02',     'II/ Tiền gửi TCKT & DC: Theo loại hình',  1, 1, 1020000),
(5,  'LN01',     'I/ Dư nợ TCKT & DC: Theo kỳ hạn',         2, 1, 2010000),
(6,  'LN02',     'II/ Dư nợ TCKT & DC: Theo loại hình',     2, 1, 2020000),
-- lv2: A.I theo ky han
(7,  'DP01001',  'a. KKH',              3, 2, 1010100),
(8,  'DP01002',  'b. 1-3W',             3, 2, 1010101),
(9,  'DP01003',  'c. 1-5 tháng',        3, 2, 1010102),
(10, 'DP01004',  'd. 6 tháng',          3, 2, 1010103),
(11, 'DP01005',  'e. 7 tháng',          3, 2, 1010104),
(12, 'DP01006',  'f. 8-11 tháng',       3, 2, 1010105),
(13, 'DP01007',  'g. 12 tháng',         3, 2, 1010106),
(14, 'DP01008',  'h. 13 tháng',         3, 2, 1010107),
(15, 'DP01009',  'i. 14-23 tháng',      3, 2, 1010108),
(16, 'DP010010', 'j. 24 đến 36 tháng',  3, 2, 1010109),
-- A.II theo loai hinh
(17, 'DP02001',  'a. Doanh nghiệp',     4, 2, 1020100),
(18, 'DP02002',  'b. Cá nhân',          4, 2, 1020101),
-- B.I theo ky han
(19, 'LN01001',  'a. Nợ QH',                          5, 2, 2010100),
(20, 'LN01002',  'b. CV CCSTK',                        5, 2, 2010101),
(21, 'LN01003',  'c. CV VNĐ lãi suất USD',             5, 2, 2010102),
(22, 'LN01004',  'd. CV ngắn hạn',                     5, 2, 2010103),
(23, 'LN01005',  'e. CV trung hạn',                    5, 2, 2010104),
(24, 'LN01006',  'f. CV dài hạn <= 120T',              5, 2, 2010105),
(25, 'LN01007',  'g. CV dài hạn <= 180T',              5, 2, 2010106),
(26, 'LN01008',  'h. CV dài hạn > 180T',               5, 2, 2010107),
(27, 'LN01009',  'i. CV ngắn hạn, HSRR ≥ 120%',        5, 2, 2010108),
(28, 'LN010010', 'j. CV trung hạn, HSRR ≥ 120%',       5, 2, 2010109),
(29, 'LN010011', 'k. CV dài hạn ≤ 120T, HSRR ≥ 120%',  5, 2, 2010110),
(30, 'LN010012', 'm. CV dài hạn ≤ 180T, HSRR ≥ 120%',  5, 2, 2010111),
(31, 'LN010013', 'l. CV dài hạn > 180T, HSRR ≥ 120%',  5, 2, 2010112),
-- B.II theo loai hinh
(32, 'LN02001',  'a. Doanh nghiệp',  6, 2, 2020100),
(33, 'LN02002',  'b. Cá nhân',       6, 2, 2020101);   -- <-- dau ; bat buoc

-- Keo sequence ve max(id) de INSERT sau nay khong bi duplicate key
SELECT setval(pg_get_serial_sequence('dim_funding_structure','funding_id'),
              (SELECT max(funding_id) FROM dim_funding_structure));

COMMIT;

-- ============================================================================
-- B2: Bang FACT input (chi tiet so du moi ngay theo tai khoan)
-- ============================================================================

-- B2.1: Fact tien gui
DROP TABLE IF EXISTS fact_dp_customer;
CREATE TABLE fact_dp_customer (
    day_key int4 GENERATED ALWAYS AS (
        (extract(year  from process_dt)*10000
       + extract(month from process_dt)*100
       + extract(day   from process_dt))::int4) STORED,     -- YYYYMMDD
    process_dt    date         NOT NULL,
    account_id    int8         NOT NULL,
    account_type  varchar(50),
    customer_id   int8         NOT NULL,
    customer_type varchar(50),
    interest_rate numeric(6,2),
    vof_rate      numeric(6,2),
    balance       int8,
    open_date     date,
    maturity_date date,
    close_date    date,
    funding_id    int4         NOT NULL DEFAULT -1
                  REFERENCES dim_funding_structure(funding_id),
    CONSTRAINT pk_fact_dp_customer PRIMARY KEY (process_dt, account_id)
);

-- B2.2: Fact cho vay
DROP TABLE IF EXISTS fact_ln_customer;
CREATE TABLE fact_ln_customer (
    day_key int4 GENERATED ALWAYS AS (
        (extract(year  from process_dt)*10000
       + extract(month from process_dt)*100
       + extract(day   from process_dt))::int4) STORED,
    process_dt    date         NOT NULL,
    account_id    int8         NOT NULL,
    account_type  varchar(50),
    customer_id   int8         NOT NULL,
    customer_type varchar(50),
    interest_rate numeric(6,2),
    cof_rate      numeric(6,2),
    balance       int8,
    day_past_due  int4         NOT NULL DEFAULT 0,    -- so ngay qua han -> No QH
    open_date     date,
    maturity_date date,
    close_date    date,
    funding_id    int4         NOT NULL DEFAULT -1
                  REFERENCES dim_funding_structure(funding_id),
    CONSTRAINT pk_fact_ln_customer PRIMARY KEY (process_dt, account_id)
);

-- Index ho tro group by chi tieu sau khi gan funding_id
CREATE INDEX ix_fact_dp_funding ON fact_dp_customer (funding_id, process_dt);
CREATE INDEX ix_fact_ln_funding ON fact_ln_customer (funding_id, process_dt);

-- Unknown member (-1) cho funding_id chua phan loai
INSERT INTO mini_project.dim_funding_structure
      (funding_id, funding_code, funding_name, funding_parent_id, funding_level, sort_order)
VALUES (-1, 'UNKNOWN', 'Chưa phân loại', NULL, -1, -1)
ON CONFLICT (funding_id) DO NOTHING;

-- ============================================================================
-- B3: Bang FACT tong hop (ket qua bao cao theo ngay) + bang LOG
-- ============================================================================

DROP TABLE IF EXISTS fact_summary_funding_daily;
CREATE TABLE fact_summary_funding_daily (
    day_key int4 GENERATED ALWAYS AS (
        (extract(year  from process_dt)*10000
       + extract(month from process_dt)*100
       + extract(day   from process_dt))::int4) STORED,
    process_dt        date          NOT NULL,
    funding_id        int4          NOT NULL REFERENCES dim_funding_structure(funding_id),
    balance           int8          NOT NULL DEFAULT 0,   -- so du/du no thoi diem (TD)
    avg_balance_mtd   numeric(20,2) NOT NULL DEFAULT 0,   -- BQ luy ke dau thang -> process_dt
    acct_cnt          int4          NOT NULL DEFAULT 0,   -- so tai khoan tai ngay
    interest_rate     numeric(12,6) NOT NULL DEFAULT 0,   -- lai suat TB cong don gian
    vof_cof_rate      numeric(12,6) NOT NULL DEFAULT 0,   -- VOF (DP) / COF (LN)
    margin            numeric(12,6) NOT NULL DEFAULT 0,   -- vof_cof - interest
    rec_created_dt    timestamp     NOT NULL DEFAULT now(),
    CONSTRAINT pk_fact_summary_funding_daily PRIMARY KEY (process_dt, funding_id)
);

CREATE TABLE IF NOT EXISTS mini_project.procedure_log (
    log_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    procedure_name varchar(50)  NOT NULL,
    start_time     timestamp    NOT NULL,
    end_time       timestamp,
    is_successful  boolean,
    error_log      text,
    rec_created_dt timestamp    NOT NULL DEFAULT now()
);
