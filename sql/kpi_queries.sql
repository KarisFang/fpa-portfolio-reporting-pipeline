-- =====================================================================
-- KPI Query Library — Automated Monthly Reporting Pipeline
-- Every query below is something an FP&A analyst would run (or
-- automate) to build the monthly reporting pack. Each demonstrates a
-- specific SQL technique called out in the comment header.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. MONTHLY REVENUE & GROSS MARGIN TREND (basic JOIN + GROUP BY)
-- ---------------------------------------------------------------------
SELECT
    d.year_month,
    COUNT(*)                                   AS transactions,
    ROUND(SUM(f.net_revenue), 0)                AS net_revenue,
    ROUND(SUM(f.gross_profit), 0)                AS gross_profit,
    ROUND(100.0 * SUM(f.gross_profit) / SUM(f.net_revenue), 1) AS gross_margin_pct
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year_month
ORDER BY d.year_month;


-- ---------------------------------------------------------------------
-- 2. MONTH-OVER-MONTH AND YEAR-OVER-YEAR GROWTH (WINDOW FUNCTIONS: LAG)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT d.year_month, d.year, d.month, SUM(f.net_revenue) AS net_revenue
    FROM fact_sales f JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.year_month, d.year, d.month
)
SELECT
    year_month,
    ROUND(net_revenue, 0) AS net_revenue,
    ROUND(LAG(net_revenue) OVER (ORDER BY year_month), 0)                       AS prior_month_revenue,
    ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY year_month))
          / LAG(net_revenue) OVER (ORDER BY year_month), 1)                     AS mom_growth_pct,
    ROUND(LAG(net_revenue, 12) OVER (ORDER BY year_month), 0)                    AS same_month_last_year,
    ROUND(100.0 * (net_revenue - LAG(net_revenue, 12) OVER (ORDER BY year_month))
          / LAG(net_revenue, 12) OVER (ORDER BY year_month), 1)                  AS yoy_growth_pct
FROM monthly
ORDER BY year_month;


-- ---------------------------------------------------------------------
-- 3. RUNNING (CUMULATIVE) YTD REVENUE BY YEAR (WINDOW FUNCTION: SUM OVER)
-- ---------------------------------------------------------------------
SELECT
    d.year, d.month,
    ROUND(SUM(f.net_revenue), 0) AS month_revenue,
    ROUND(SUM(SUM(f.net_revenue)) OVER (PARTITION BY d.year ORDER BY d.month), 0) AS ytd_revenue
FROM fact_sales f JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;


-- ---------------------------------------------------------------------
-- 4. 3-MONTH ROLLING AVERAGE REVENUE (WINDOW FUNCTION: AVG OVER ROWS BETWEEN)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT d.year_month, SUM(f.net_revenue) AS net_revenue
    FROM fact_sales f JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.year_month
)
SELECT
    year_month,
    ROUND(net_revenue, 0) AS net_revenue,
    ROUND(AVG(net_revenue) OVER (ORDER BY year_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS rolling_3mo_avg
FROM monthly
ORDER BY year_month;


-- ---------------------------------------------------------------------
-- 5. REVENUE BY REGION, YEAR-OVER-YEAR — THE "WHAT'S DRIVING THE NUMBER" VIEW
-- (CTE + self-join pattern via conditional aggregation)
-- ---------------------------------------------------------------------
WITH region_year AS (
    SELECT r.region_name, d.year, SUM(f.net_revenue) AS net_revenue
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN dim_region r ON f.region_id = r.region_id
    GROUP BY r.region_name, d.year
)
SELECT
    region_name,
    ROUND(MAX(CASE WHEN year = 2024 THEN net_revenue END), 0) AS fy2024_revenue,
    ROUND(MAX(CASE WHEN year = 2025 THEN net_revenue END), 0) AS fy2025_revenue,
    ROUND(100.0 * (MAX(CASE WHEN year = 2025 THEN net_revenue END)
                    - MAX(CASE WHEN year = 2024 THEN net_revenue END))
          / MAX(CASE WHEN year = 2024 THEN net_revenue END), 1)                  AS yoy_growth_pct
FROM region_year
GROUP BY region_name
ORDER BY yoy_growth_pct ASC;   -- worst performers first — exactly how a CFO wants to see it


-- ---------------------------------------------------------------------
-- 6. TOP 10 CUSTOMERS BY REVENUE, WITH RANK (WINDOW FUNCTION: RANK)
-- ---------------------------------------------------------------------
SELECT
    RANK() OVER (ORDER BY SUM(f.net_revenue) DESC) AS revenue_rank,
    c.customer_name,
    c.segment,
    r.region_name,
    ROUND(SUM(f.net_revenue), 0)  AS total_revenue,
    ROUND(SUM(f.gross_profit), 0) AS total_gross_profit
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
JOIN dim_region r ON c.region_id = r.region_id
GROUP BY c.customer_id, c.customer_name, c.segment, r.region_name
ORDER BY total_revenue DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- 7. PRODUCT MIX & MARGIN BY CATEGORY (JOIN + aggregate + margin calc)
-- ---------------------------------------------------------------------
SELECT
    p.category,
    COUNT(*) AS units_sold_transactions,
    SUM(f.quantity) AS total_units,
    ROUND(SUM(f.net_revenue), 0) AS net_revenue,
    ROUND(SUM(f.gross_profit), 0) AS gross_profit,
    ROUND(100.0 * SUM(f.gross_profit) / SUM(f.net_revenue), 1) AS gross_margin_pct,
    ROUND(100.0 * SUM(f.net_revenue) / (SELECT SUM(net_revenue) FROM fact_sales), 1) AS pct_of_total_revenue
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.category
ORDER BY net_revenue DESC;


-- ---------------------------------------------------------------------
-- 8. CHANNEL MIX SHIFT OVER TIME (CTE + window function: share of total)
-- ---------------------------------------------------------------------
WITH channel_year AS (
    SELECT d.year, ch.channel_name, SUM(f.net_revenue) AS net_revenue
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN dim_channel ch ON f.channel_id = ch.channel_id
    GROUP BY d.year, ch.channel_name
)
SELECT
    year,
    channel_name,
    ROUND(net_revenue, 0) AS net_revenue,
    ROUND(100.0 * net_revenue / SUM(net_revenue) OVER (PARTITION BY year), 1) AS pct_of_year_revenue
FROM channel_year
ORDER BY year, net_revenue DESC;


-- ---------------------------------------------------------------------
-- 9. NEW vs. REPEAT CUSTOMER REVENUE BY MONTH (CTE + window function: MIN OVER)
-- Identifies each customer's first-ever purchase month, then classifies
-- every subsequent transaction as "New" or "Repeat" for that month.
-- ---------------------------------------------------------------------
WITH first_purchase AS (
    SELECT customer_id, MIN(d.year_month) AS first_month
    FROM fact_sales f JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY customer_id
),
tagged AS (
    SELECT
        d.year_month,
        f.customer_id,
        f.net_revenue,
        CASE WHEN d.year_month = fp.first_month THEN 'New' ELSE 'Repeat' END AS customer_type
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN first_purchase fp ON f.customer_id = fp.customer_id
)
SELECT
    year_month,
    customer_type,
    ROUND(SUM(net_revenue), 0) AS net_revenue,
    COUNT(DISTINCT customer_id) AS distinct_customers
FROM tagged
GROUP BY year_month, customer_type
ORDER BY year_month, customer_type;


-- ---------------------------------------------------------------------
-- 10. ANOMALY FLAG — months where revenue moved >15% MoM (CTE + LAG +
-- HAVING-style filter via a wrapping SELECT, useful for an automated
-- "exceptions only" email/Slack alert instead of a full report)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT d.year_month, SUM(f.net_revenue) AS net_revenue
    FROM fact_sales f JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.year_month
),
with_growth AS (
    SELECT
        year_month,
        net_revenue,
        100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY year_month))
              / LAG(net_revenue) OVER (ORDER BY year_month) AS mom_growth_pct
    FROM monthly
)
SELECT *
FROM with_growth
WHERE ABS(mom_growth_pct) > 15
ORDER BY year_month;
