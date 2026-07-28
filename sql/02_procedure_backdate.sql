-- ============================================================================
-- 02. PROCEDURE tong hop bao cao (chay hang ngay, ho tro backdate)
-- Nguoi tao: van_pham  |  Muc dich: tong hop chi tieu nguon von / su dung von
-- Luong: xac dinh ngay -> chan input -> gan funding_id -> xoa (backdate)
--        -> insert chi tieu la + loai hinh -> level 1/0 + dong 0 -> log
-- ============================================================================

CREATE OR REPLACE PROCEDURE mini_project.fact_summary_funding_daily_prc(vDate date DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    vProcess_dt        date;
    vDay_key           int;
    vBeginMonth_Daykey int;
    vStartTime         timestamp := clock_timestamp();
    vCnt               bigint;
    vErrMsg            text;
    vErrDetail         text;
    vErrContext        text;
BEGIN   -- khoi chinh (khong co exception)
    BEGIN   -- khoi con (buoc 1 -> 5c)

    -- Buoc 1: xac dinh ngay xu ly
    IF vDate IS NULL THEN
        vProcess_dt := current_date - 1;
    ELSE
        vProcess_dt := vDate;
    END IF;

    vDay_key           := extract(year  from vProcess_dt)::int * 10000
                        + extract(month from vProcess_dt)::int * 100
                        + extract(day   from vProcess_dt)::int;
    vBeginMonth_Daykey := extract(year  from vProcess_dt)::int * 10000
                        + extract(month from vProcess_dt)::int * 100 + 1;

    -- Buoc 1b: co du lieu input tai ngay chay chua?
    IF NOT EXISTS (SELECT 1 FROM mini_project.fact_dp_customer WHERE day_key = vDay_key)
       AND NOT EXISTS (SELECT 1 FROM mini_project.fact_ln_customer WHERE day_key = vDay_key) THEN
        RAISE EXCEPTION 'khong co du lieu input tai ngay % (day_key %)', vProcess_dt, vDay_key;
    END IF;

    -- Gan phan loai funding_id (chi dong -1 trong cua so BQ)
    UPDATE mini_project.fact_dp_customer f
    SET funding_id = d.funding_id
    FROM mini_project.dim_funding_structure d
    WHERE f.day_key BETWEEN vBeginMonth_Daykey AND vDay_key
      AND f.funding_id = -1
      AND d.funding_code = CASE
            WHEN f.maturity_date IS NULL                           THEN 'DP01001' -- KKH
            WHEN f.maturity_date - f.open_date BETWEEN 1   AND 24   THEN 'DP01002' -- 1-3W
            WHEN f.maturity_date - f.open_date BETWEEN 25  AND 165  THEN 'DP01003' -- 1-5T
            WHEN f.maturity_date - f.open_date BETWEEN 166 AND 195  THEN 'DP01004' -- 6T
            WHEN f.maturity_date - f.open_date BETWEEN 196 AND 225  THEN 'DP01005' -- 7T
            WHEN f.maturity_date - f.open_date BETWEEN 226 AND 345  THEN 'DP01006' -- 8-11T
            WHEN f.maturity_date - f.open_date BETWEEN 346 AND 375  THEN 'DP01007' -- 12T
            WHEN f.maturity_date - f.open_date BETWEEN 376 AND 405  THEN 'DP01008' -- 13T
            WHEN f.maturity_date - f.open_date BETWEEN 406 AND 705  THEN 'DP01009' -- 14-23T
            ELSE 'DP010010'                                                        -- 24-36T
          END;

    UPDATE mini_project.fact_ln_customer f
    SET funding_id = d.funding_id
    FROM mini_project.dim_funding_structure d
    WHERE f.day_key BETWEEN vBeginMonth_Daykey AND vDay_key
      AND f.funding_id = -1
      AND d.funding_code = CASE
            WHEN f.day_past_due > 0                    THEN 'LN01001' -- No QH
            WHEN f.account_type = 'CV CCSTK'           THEN 'LN01002'
            WHEN f.account_type = 'CV VND LS USD'      THEN 'LN01003'
            WHEN f.maturity_date - f.open_date <= 365  THEN 'LN01004' -- ngan han
            WHEN f.maturity_date - f.open_date <= 1825 THEN 'LN01005' -- trung han
            WHEN f.maturity_date - f.open_date <= 3650 THEN 'LN01006' -- dai <=120T
            WHEN f.maturity_date - f.open_date <= 5475 THEN 'LN01007' -- dai <=180T
            ELSE 'LN01008'                                            -- dai >180T
          END;

    -- Chot chan: sau khi gan van con -1 la du lieu bat thuong
    SELECT count(*) INTO vCnt
    FROM (
        SELECT 1 FROM mini_project.fact_dp_customer
         WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key AND funding_id = -1
        UNION ALL
        SELECT 1 FROM mini_project.fact_ln_customer
         WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key AND funding_id = -1
    ) t;
    IF vCnt > 0 THEN
        RAISE EXCEPTION 'Sau khi gan van con % dong funding_id = -1 trong [% .. %] - kiem tra rule phan loai',
                        vCnt, vBeginMonth_Daykey, vDay_key;
    END IF;

    -- Buoc 2: backdate - xoa du lieu ngay chay
    DELETE FROM mini_project.fact_summary_funding_daily WHERE process_dt = vProcess_dt;

    -- Buoc 3 & 4: insert chi tieu nguon von + su dung von (day_key generated tu sinh)
    INSERT INTO mini_project.fact_summary_funding_daily
        (process_dt, funding_id, balance, avg_balance_mtd, acct_cnt, interest_rate, vof_cof_rate, margin)
    -- nguon von: tien gui theo ky han
    SELECT x.process_dt, x.funding_id, x.balance, COALESCE(y.avg_balance_mtd,0), x.acct_cnt,
           x.interest_rate, x.vof_cof_rate, x.vof_cof_rate - x.interest_rate
    FROM (
        SELECT vProcess_dt AS process_dt, funding_id,
               sum(balance) AS balance, count(*) AS acct_cnt,
               round(avg(interest_rate)::numeric,6) AS interest_rate,
               round(avg(vof_rate)::numeric,6)      AS vof_cof_rate
        FROM mini_project.fact_dp_customer WHERE day_key = vDay_key GROUP BY funding_id
    ) x
    LEFT JOIN (
        SELECT funding_id, round(avg(total_balance)::numeric,2) AS avg_balance_mtd
        FROM (SELECT day_key, funding_id, sum(balance) AS total_balance
              FROM mini_project.fact_dp_customer
              WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key GROUP BY day_key, funding_id) t
        GROUP BY funding_id
    ) y ON x.funding_id = y.funding_id
    UNION ALL
    -- nguon von: tien gui theo loai khach hang
    SELECT x.process_dt, x.funding_id, x.balance, COALESCE(y.avg_balance_mtd,0), x.acct_cnt,
           x.interest_rate, x.vof_cof_rate, x.vof_cof_rate - x.interest_rate
    FROM (
        SELECT vProcess_dt AS process_dt,
               CASE WHEN account_type = 'Business'
                    THEN (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='DP02001')
                    ELSE (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='DP02002')
               END AS funding_id,
               sum(balance) AS balance, count(*) AS acct_cnt,
               round(avg(interest_rate)::numeric,6) AS interest_rate,
               round(avg(vof_rate)::numeric,6)      AS vof_cof_rate
        FROM mini_project.fact_dp_customer WHERE day_key = vDay_key GROUP BY 2
    ) x
    LEFT JOIN (
        SELECT funding_id, round(avg(total_balance)::numeric,2) AS avg_balance_mtd
        FROM (SELECT day_key,
                     CASE WHEN account_type = 'Business'
                          THEN (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='DP02001')
                          ELSE (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='DP02002')
                     END AS funding_id,
                     sum(balance) AS total_balance
              FROM mini_project.fact_dp_customer
              WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key GROUP BY 1,2) t
        GROUP BY funding_id
    ) y ON x.funding_id = y.funding_id
    UNION ALL
    -- su dung von: tien vay theo category
    SELECT x.process_dt, x.funding_id, x.balance, COALESCE(y.avg_balance_mtd,0), x.acct_cnt,
           x.interest_rate, x.vof_cof_rate, x.vof_cof_rate - x.interest_rate
    FROM (
        SELECT vProcess_dt AS process_dt, funding_id,
               sum(balance) AS balance, count(*) AS acct_cnt,
               round(avg(interest_rate)::numeric,6) AS interest_rate,
               round(avg(cof_rate)::numeric,6)      AS vof_cof_rate
        FROM mini_project.fact_ln_customer WHERE day_key = vDay_key GROUP BY funding_id
    ) x
    LEFT JOIN (
        SELECT funding_id, round(avg(total_balance)::numeric,2) AS avg_balance_mtd
        FROM (SELECT day_key, funding_id, sum(balance) AS total_balance
              FROM mini_project.fact_ln_customer
              WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key GROUP BY day_key, funding_id) t
        GROUP BY funding_id
    ) y ON x.funding_id = y.funding_id
    UNION ALL
    -- su dung von: tien vay theo loai KH
    SELECT x.process_dt, x.funding_id, x.balance, COALESCE(y.avg_balance_mtd,0), x.acct_cnt,
           x.interest_rate, x.vof_cof_rate, x.vof_cof_rate - x.interest_rate
    FROM (
        SELECT vProcess_dt AS process_dt,
               CASE WHEN customer_type = 'Business'
                    THEN (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='LN02001')
                    ELSE (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='LN02002')
               END AS funding_id,
               sum(balance) AS balance, count(*) AS acct_cnt,
               round(avg(interest_rate)::numeric,6) AS interest_rate,
               round(avg(cof_rate)::numeric,6)      AS vof_cof_rate
        FROM mini_project.fact_ln_customer WHERE day_key = vDay_key GROUP BY 2
    ) x
    LEFT JOIN (
        SELECT funding_id, round(avg(total_balance)::numeric,2) AS avg_balance_mtd
        FROM (SELECT day_key,
                     CASE WHEN customer_type = 'Business'
                          THEN (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='LN02001')
                          ELSE (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='LN02002')
                     END AS funding_id,
                     sum(balance) AS total_balance
              FROM mini_project.fact_ln_customer
              WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key GROUP BY 1,2) t
        GROUP BY funding_id
    ) y ON x.funding_id = y.funding_id;

    -- Buoc 5a: level 1 - theo ky han (DP01, LN01)
    INSERT INTO mini_project.fact_summary_funding_daily
        (process_dt, funding_id, balance, avg_balance_mtd, acct_cnt, interest_rate, vof_cof_rate, margin)
    SELECT x.process_dt, x.funding_id, x.balance, COALESCE(y.avg_balance_mtd,0), x.acct_cnt,
           x.interest_rate, x.vof_cof_rate, x.vof_cof_rate - x.interest_rate
    FROM (
        SELECT vProcess_dt AS process_dt,
               (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='DP01') AS funding_id,
               sum(balance) AS balance, count(*) AS acct_cnt,
               round(avg(interest_rate)::numeric,6) AS interest_rate,
               round(avg(vof_rate)::numeric,6)      AS vof_cof_rate
        FROM mini_project.fact_dp_customer WHERE day_key = vDay_key
    ) x
    LEFT JOIN (
        SELECT round(avg(total_balance)::numeric,2) AS avg_balance_mtd
        FROM (SELECT day_key, sum(balance) AS total_balance FROM mini_project.fact_dp_customer
              WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key GROUP BY day_key) t
    ) y ON true
    UNION ALL
    SELECT x.process_dt, x.funding_id, x.balance, COALESCE(y.avg_balance_mtd,0), x.acct_cnt,
           x.interest_rate, x.vof_cof_rate, x.vof_cof_rate - x.interest_rate
    FROM (
        SELECT vProcess_dt AS process_dt,
               (SELECT funding_id FROM mini_project.dim_funding_structure WHERE funding_code='LN01') AS funding_id,
               sum(balance) AS balance, count(*) AS acct_cnt,
               round(avg(interest_rate)::numeric,6) AS interest_rate,
               round(avg(cof_rate)::numeric,6)      AS vof_cof_rate
        FROM mini_project.fact_ln_customer WHERE day_key = vDay_key
    ) x
    LEFT JOIN (
        SELECT round(avg(total_balance)::numeric,2) AS avg_balance_mtd
        FROM (SELECT day_key, sum(balance) AS total_balance FROM mini_project.fact_ln_customer
              WHERE day_key BETWEEN vBeginMonth_Daykey AND vDay_key GROUP BY day_key) t
    ) y ON true;

    -- Buoc 5b: level 0 + "theo loai hinh" = copy dong "theo ky han"
    INSERT INTO mini_project.fact_summary_funding_daily
        (process_dt, funding_id, balance, avg_balance_mtd, acct_cnt, interest_rate, vof_cof_rate, margin)
    SELECT x.process_dt, m.new_id, x.balance, x.avg_balance_mtd, x.acct_cnt, x.interest_rate, x.vof_cof_rate, x.margin
    FROM mini_project.fact_summary_funding_daily x
    JOIN mini_project.dim_funding_structure src ON src.funding_id = x.funding_id
    JOIN LATERAL (
        SELECT d.funding_id AS new_id
        FROM mini_project.dim_funding_structure d
        WHERE (src.funding_code = 'DP01' AND d.funding_code IN ('DP02','DP'))
           OR (src.funding_code = 'LN01' AND d.funding_code IN ('LN02','LN'))
    ) m ON true
    WHERE x.process_dt = vProcess_dt AND src.funding_code IN ('DP01','LN01');

    -- Buoc 5c: dong khong co du lieu = 0 (No QH, HSRR...) -> luon du 33 dong
    INSERT INTO mini_project.fact_summary_funding_daily
        (process_dt, funding_id, balance, avg_balance_mtd, acct_cnt, interest_rate, vof_cof_rate, margin)
    SELECT vProcess_dt, d.funding_id, 0,0,0,0,0,0
    FROM mini_project.dim_funding_structure d
    WHERE d.funding_id <> -1
      AND NOT EXISTS (SELECT 1 FROM mini_project.fact_summary_funding_daily s
                      WHERE s.process_dt = vProcess_dt AND s.funding_id = d.funding_id);

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            vErrMsg     = MESSAGE_TEXT,
            vErrDetail  = PG_EXCEPTION_DETAIL,
            vErrContext = PG_EXCEPTION_CONTEXT;
    END;   -- dong khoi con

    -- Buoc 6: ghi log (nam trong khoi chinh)
    INSERT INTO mini_project.procedure_log (procedure_name, start_time, end_time, is_successful, error_log)
    VALUES ('fact_summary_funding_daily_prc', vStartTime, clock_timestamp(),
            vErrMsg IS NULL,
            CASE WHEN vErrMsg IS NOT NULL THEN
                 'ERROR: ' || vErrMsg
                 || COALESCE(' | DETAIL: '  || NULLIF(vErrDetail,''), '')
                 || COALESCE(' | CONTEXT: ' || vErrContext, '')
            END);

    IF vErrMsg IS NOT NULL THEN
        COMMIT;
        RAISE EXCEPTION 'fact_summary_funding_daily_prc that bai tai ngay %: %', vDate, vErrMsg;
    END IF;
END;   -- dong khoi chinh
$$;

-- Chay 1 ngay:
-- CALL mini_project.fact_summary_funding_daily_prc('2023-12-15');
