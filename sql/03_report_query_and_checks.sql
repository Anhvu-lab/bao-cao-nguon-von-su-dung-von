-- ============================================================================
-- 03. Query bao cao + cac cau kiem tra sau import
-- ============================================================================

-- ---- BAO CAO NGUON VON - SU DUNG VON tai 1 ngay ----
SELECT d.funding_name                                   AS "NGUỒN VỐN - SỬ DỤNG VỐN",
       f.avg_balance_mtd::numeric(20,0)                 AS "Số dư/dư nợ BQ",
       f.balance                                        AS "Số dư/dư nợ TĐ",
       ROUND(f.interest_rate, 2)                        AS "Lãi suất (%)",
       ROUND(f.vof_cof_rate, 2)                         AS "VOF/COF (%)",
       ROUND(f.vof_cof_rate, 2) - ROUND(f.interest_rate, 2) AS "Margin (%)",
       CASE WHEN f.acct_cnt > 0 THEN f.process_dt END   AS "Ngày số liệu"
FROM   mini_project.fact_summary_funding_daily f
JOIN   mini_project.dim_funding_structure d USING (funding_id)
WHERE  f.process_dt = DATE '2023-12-15'          -- doi ngay can xem
ORDER  BY d.sort_order;

-- ============================================================================
-- KIEM TRA SAU IMPORT
-- ============================================================================

-- 1. Dem so dong (ky vong dp=910671, ln=209082)
SELECT 'dp' AS bang, count(*) FROM mini_project.fact_dp_customer
UNION ALL
SELECT 'ln', count(*) FROM mini_project.fact_ln_customer;

-- 2. Do phu ngay (ky vong 365 ngay lien tuc, thieu=0)
SELECT 'dp' AS bang, count(DISTINCT process_dt) AS so_ngay,
       min(process_dt) AS ngay_dau, max(process_dt) AS ngay_cuoi,
       (max(process_dt)-min(process_dt))+1 - count(DISTINCT process_dt) AS so_ngay_thieu
FROM mini_project.fact_dp_customer
UNION ALL
SELECT 'ln', count(DISTINCT process_dt), min(process_dt), max(process_dt),
       (max(process_dt)-min(process_dt))+1 - count(DISTINCT process_dt)
FROM mini_project.fact_ln_customer;

-- 3. Trung khoa (process_dt, account_id) - ky vong 0 dong
SELECT process_dt, account_id, count(*)
FROM mini_project.fact_dp_customer
GROUP BY process_dt, account_id HAVING count(*) > 1;

-- 4. NULL cot trong yeu (maturity_date NULL o DP la hop le = KKH)
SELECT count(*) FILTER (WHERE process_dt    IS NULL) AS process_dt_null,
       count(*) FILTER (WHERE account_id    IS NULL) AS account_id_null,
       count(*) FILTER (WHERE interest_rate IS NULL) AS interest_null,
       count(*) FILTER (WHERE vof_rate      IS NULL) AS vof_null,
       count(*) FILTER (WHERE balance       IS NULL) AS balance_null,
       count(*) FILTER (WHERE maturity_date IS NULL) AS kkh_so_dong
FROM mini_project.fact_dp_customer;

-- 5. Doi chieu voi bao cao mau 15/12/2023
--    ky vong dp: tong_balance=7583225364658, ls_tb=3.92
--            ln: tong_balance=6647994600000, ls_tb=12.08
SELECT 'dp' AS bang, count(*) AS so_dong, sum(balance) AS tong_balance,
       round(avg(interest_rate),2) AS ls_tb
FROM mini_project.fact_dp_customer WHERE process_dt = '2023-12-15'
UNION ALL
SELECT 'ln', count(*), sum(balance), round(avg(interest_rate),2)
FROM mini_project.fact_ln_customer WHERE process_dt = '2023-12-15';
