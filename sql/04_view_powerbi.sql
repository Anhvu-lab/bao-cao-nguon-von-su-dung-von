-- ============================================================================
-- 04. View phuc vu ket noi Power BI
--     Gom fact summary + dim, thut le ten chi tieu theo cap, lam tron so
-- ============================================================================

CREATE OR REPLACE VIEW mini_project.vw_funding_report AS
SELECT f.process_dt,
       d.funding_id,
       d.funding_code,
       repeat('   ', GREATEST(d.funding_level, 0)) || d.funding_name AS funding_name,
       d.funding_level,
       d.sort_order,
       f.avg_balance_mtd,
       f.balance,
       f.acct_cnt,
       ROUND(f.interest_rate, 2) AS interest_rate,
       ROUND(f.vof_cof_rate, 2)  AS vof_cof_rate,
       ROUND(f.vof_cof_rate, 2) - ROUND(f.interest_rate, 2) AS margin
FROM   mini_project.fact_summary_funding_daily f
JOIN   mini_project.dim_funding_structure d USING (funding_id);
