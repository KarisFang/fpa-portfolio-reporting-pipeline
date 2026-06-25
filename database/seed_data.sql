-- =====================================================================
-- Synthetic data generator for "Meridian Retail Co." (fictional company)
-- Entirely SQL — no external scripting. Uses recursive CTEs + a weighted
-- cumulative-distribution join to inject realistic seasonality and mix
-- shifts into otherwise-random data, so the KPI queries have something
-- real to find (growth, Q4 seasonality, a softening region, channel mix shift).
-- =====================================================================

PRAGMA foreign_keys = OFF;

-- ---------------------------------------------------------------------
-- DIM_DATE: every day from 2024-01-01 to 2025-12-31
-- ---------------------------------------------------------------------
WITH RECURSIVE date_seq(d) AS (
    SELECT date('2024-01-01')
    UNION ALL
    SELECT date(d, '+1 day') FROM date_seq WHERE d < date('2025-12-31')
)
INSERT INTO dim_date (date_key, full_date, day, month, month_name, quarter, year, fiscal_year, year_month, is_month_end)
SELECT
    CAST(strftime('%Y%m%d', d) AS INTEGER),
    d,
    CAST(strftime('%d', d) AS INTEGER),
    CAST(strftime('%m', d) AS INTEGER),
    CASE strftime('%m', d)
        WHEN '01' THEN 'January' WHEN '02' THEN 'February' WHEN '03' THEN 'March'
        WHEN '04' THEN 'April' WHEN '05' THEN 'May' WHEN '06' THEN 'June'
        WHEN '07' THEN 'July' WHEN '08' THEN 'August' WHEN '09' THEN 'September'
        WHEN '10' THEN 'October' WHEN '11' THEN 'November' ELSE 'December' END,
    (CAST(strftime('%m', d) AS INTEGER) - 1) / 3 + 1,
    CAST(strftime('%Y', d) AS INTEGER),
    CAST(strftime('%Y', d) AS INTEGER),
    strftime('%Y-%m', d),
    CASE WHEN date(d, '+1 day') = date(strftime('%Y-%m-01', d), '+1 month') THEN 1 ELSE 0 END
FROM date_seq;

-- ---------------------------------------------------------------------
-- DIM_REGION
-- ---------------------------------------------------------------------
INSERT INTO dim_region (region_id, region_name, country) VALUES
(1, 'North America', 'United States'),
(2, 'Europe', 'Germany'),
(3, 'Greater Asia', 'China'),
(4, 'APAC', 'Australia'),
(5, 'Latin America', 'Brazil');

-- ---------------------------------------------------------------------
-- DIM_CHANNEL
-- ---------------------------------------------------------------------
INSERT INTO dim_channel (channel_id, channel_name) VALUES
(1, 'Online'),
(2, 'Retail'),
(3, 'Wholesale');

-- ---------------------------------------------------------------------
-- DIM_PRODUCT — 4 categories x 3 products
-- ---------------------------------------------------------------------
INSERT INTO dim_product (product_id, product_name, category, unit_cost, unit_price) VALUES
(1,  'Aurora Laptop 14',        'Electronics', 620.00, 1199.00),
(2,  'Aurora Laptop 16 Pro',    'Electronics', 980.00, 1899.00),
(3,  'Aurora Tablet Air',       'Electronics', 280.00,  599.00),
(4,  'Aurora Wireless Earbuds', 'Accessories',  38.00,  129.00),
(5,  'Aurora Smartwatch',       'Accessories', 110.00,  329.00),
(6,  'Aurora Charging Dock',    'Accessories',  14.00,   49.00),
(7,  'Aurora Cloud Suite (Annual)', 'Software',  8.00,   99.00),
(8,  'Aurora Security Suite (Annual)', 'Software', 5.00,  59.00),
(9,  'Aurora Creative Studio (Annual)', 'Software', 12.00, 149.00),
(10, 'Aurora Care Plan',        'Services',     6.00,   89.00),
(11, 'Aurora Setup & Migration','Services',    18.00,  119.00),
(12, 'Aurora Premium Support',  'Services',    22.00,  179.00);

-- ---------------------------------------------------------------------
-- DIM_CUSTOMER — ~60 customers spread across regions and segments
-- ---------------------------------------------------------------------
INSERT INTO dim_customer (customer_id, customer_name, segment, region_id)
WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 60)
SELECT
    n,
    'Customer ' || printf('%03d', n),
    CASE WHEN n % 5 = 0 THEN 'Enterprise' WHEN n % 2 = 0 THEN 'SMB' ELSE 'Consumer' END,
    ((n - 1) % 5) + 1
FROM seq;

-- ---------------------------------------------------------------------
-- MONTH_WEIGHTS (temp helper): encodes YoY growth (~9%) + Q4 seasonality
-- spike (+35%) + a Jan/Feb post-holiday dip (-15%). Used to weight which
-- month a synthetic transaction lands in.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS month_weights;
CREATE TEMP TABLE month_weights (year INTEGER, month INTEGER, weight INTEGER);
INSERT INTO month_weights (year, month, weight) VALUES
(2024,1,72),(2024,2,75),(2024,3,90),(2024,4,92),(2024,5,95),(2024,6,98),
(2024,7,96),(2024,8,97),(2024,9,100),(2024,10,118),(2024,11,140),(2024,12,150),
(2025,1,78),(2025,2,80),(2025,3,98),(2025,4,100),(2025,5,103),(2025,6,107),
(2025,7,104),(2025,8,106),(2025,9,109),(2025,10,128),(2025,11,152),(2025,12,163);

DROP TABLE IF EXISTS month_buckets;
CREATE TEMP TABLE month_buckets AS
SELECT
    year, month, weight,
    SUM(weight) OVER (ORDER BY year, month) - weight AS lower_bound,
    SUM(weight) OVER (ORDER BY year, month) AS upper_bound
FROM month_weights;

-- ---------------------------------------------------------------------
-- REGION_WEIGHTS: 'Greater Asia' (region 3) softens over time relative to
-- the others — gives the later variance-analysis project a real story.
-- Two weight sets: 2024 vs 2025.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS region_weights;
CREATE TEMP TABLE region_weights (year INTEGER, region_id INTEGER, weight INTEGER);
INSERT INTO region_weights (year, region_id, weight) VALUES
(2024,1,32),(2024,2,24),(2024,3,26),(2024,4,12),(2024,5,6),
(2025,1,35),(2025,2,26),(2025,3,18),(2025,4,14),(2025,5,7);

DROP TABLE IF EXISTS region_buckets;
CREATE TEMP TABLE region_buckets AS
SELECT
    year, region_id, weight,
    SUM(weight) OVER (PARTITION BY year ORDER BY region_id) - weight AS lower_bound,
    SUM(weight) OVER (PARTITION BY year ORDER BY region_id) AS upper_bound
FROM region_weights;

-- ---------------------------------------------------------------------
-- PRODUCT_WEIGHTS: makes some SKUs sell far more than others (realistic
-- Pareto-ish mix) instead of flat-uniform product selection.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS product_weights;
CREATE TEMP TABLE product_weights (product_id INTEGER, weight INTEGER);
INSERT INTO product_weights (product_id, weight) VALUES
(1,18),(2,9),(3,14),(4,22),(5,13),(6,10),(7,16),(8,11),(9,8),(10,12),(11,7),(12,6);

DROP TABLE IF EXISTS product_buckets;
CREATE TEMP TABLE product_buckets AS
SELECT
    product_id, weight,
    SUM(weight) OVER (ORDER BY product_id) - weight AS lower_bound,
    SUM(weight) OVER (ORDER BY product_id) AS upper_bound
FROM product_weights;

-- ---------------------------------------------------------------------
-- CHANNEL_WEIGHTS: Online overtakes Retail over the two years (a real
-- mix-shift story for the dashboard).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS channel_weights;
CREATE TEMP TABLE channel_weights (year INTEGER, channel_id INTEGER, weight INTEGER);
INSERT INTO channel_weights (year, channel_id, weight) VALUES
(2024,1,38),(2024,2,42),(2024,3,20),
(2025,1,48),(2025,2,34),(2025,3,18);

DROP TABLE IF EXISTS channel_buckets;
CREATE TEMP TABLE channel_buckets AS
SELECT
    year, channel_id, weight,
    SUM(weight) OVER (PARTITION BY year ORDER BY channel_id) - weight AS lower_bound,
    SUM(weight) OVER (PARTITION BY year ORDER BY channel_id) AS upper_bound
FROM channel_weights;

-- ---------------------------------------------------------------------
-- FACT_SALES: ~14,000 synthetic transactions, weighted-random across
-- month / region / product / channel, then a real, random customer
-- within the chosen region, plausible quantity/discount by channel.
-- ---------------------------------------------------------------------
WITH RECURSIVE seq(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 14000
),
rand_draw AS MATERIALIZED (
    SELECT
        n,
        ABS(RANDOM()) % (SELECT MAX(upper_bound) FROM month_buckets)      AS r_month,
        ABS(RANDOM()) % 1000                                              AS r_day,
        ABS(RANDOM()) % 1000                                              AS r_region,
        ABS(RANDOM()) % 1000                                              AS r_product,
        ABS(RANDOM()) % 1000                                              AS r_channel,
        ABS(RANDOM()) % 1000                                              AS r_qty,
        ABS(RANDOM()) % 1000                                              AS r_disc,
        ABS(RANDOM()) % 1000                                              AS r_cust
    FROM seq
),
picked_month AS MATERIALIZED (
    SELECT rd.n, mb.year, mb.month, rd.r_day, rd.r_region, rd.r_product, rd.r_channel, rd.r_qty, rd.r_disc, rd.r_cust
    FROM rand_draw rd
    JOIN month_buckets mb ON rd.r_month >= mb.lower_bound AND rd.r_month < mb.upper_bound
),
picked_region AS MATERIALIZED (
    SELECT pm.n, pm.year, pm.month, pm.r_day, pm.r_product, pm.r_channel, pm.r_qty, pm.r_disc, pm.r_cust, rb.region_id
    FROM picked_month pm
    JOIN region_buckets rb ON rb.year = pm.year
        AND (pm.r_region % (SELECT MAX(upper_bound) FROM region_buckets WHERE year = pm.year)) >= rb.lower_bound
        AND (pm.r_region % (SELECT MAX(upper_bound) FROM region_buckets WHERE year = pm.year)) < rb.upper_bound
),
picked_product AS MATERIALIZED (
    SELECT pr.*, pb.product_id
    FROM picked_region pr
    JOIN product_buckets pb
        ON (pr.r_product % (SELECT MAX(upper_bound) FROM product_buckets)) >= pb.lower_bound
        AND (pr.r_product % (SELECT MAX(upper_bound) FROM product_buckets)) < pb.upper_bound
),
picked_channel AS MATERIALIZED (
    SELECT pp.*, cb.channel_id
    FROM picked_product pp
    JOIN channel_buckets cb ON cb.year = pp.year
        AND (pp.r_channel % (SELECT MAX(upper_bound) FROM channel_buckets WHERE year = pp.year)) >= cb.lower_bound
        AND (pp.r_channel % (SELECT MAX(upper_bound) FROM channel_buckets WHERE year = pp.year)) < cb.upper_bound
),
assembled AS MATERIALIZED (
    SELECT
        pc.n,
        pc.year, pc.month,
        1 + (pc.r_day % 28) AS day_of_month,
        pc.region_id,
        pc.product_id,
        pc.channel_id,
        pc.r_qty, pc.r_disc, pc.r_cust
    FROM picked_channel pc
)
INSERT INTO fact_sales (
    transaction_id, date_key, product_id, region_id, channel_id, customer_id,
    quantity, unit_price, unit_cost, gross_revenue, discount_amt, net_revenue, total_cost, gross_profit
)
SELECT
    a.n,
    CAST(strftime('%Y%m%d', printf('%04d-%02d-%02d', a.year, a.month, a.day_of_month)) AS INTEGER),
    a.product_id,
    a.region_id,
    a.channel_id,
    a.region_id + 5 * (a.r_cust % 12),  -- direct calc: customers are assigned region_id = ((id-1)%5)+1, so this always lands in the right region (12 customers/region)
    CASE a.channel_id
        WHEN 3 THEN 5 + (a.r_qty % 46)     -- Wholesale: 5-50 units
        WHEN 1 THEN 1 + (a.r_qty % 4)      -- Online: 1-4 units
        ELSE 1 + (a.r_qty % 3)             -- Retail: 1-3 units
    END AS qty,
    dp.unit_price,
    dp.unit_cost,
    (CASE a.channel_id WHEN 3 THEN 5 + (a.r_qty % 46) WHEN 1 THEN 1 + (a.r_qty % 4) ELSE 1 + (a.r_qty % 3) END) * dp.unit_price AS gross_rev,
    ROUND(
        (CASE a.channel_id WHEN 3 THEN 5 + (a.r_qty % 46) WHEN 1 THEN 1 + (a.r_qty % 4) ELSE 1 + (a.r_qty % 3) END) * dp.unit_price
        * (CASE a.channel_id WHEN 3 THEN 0.08 + (a.r_disc % 100) / 1000.0 ELSE 0.00 + (a.r_disc % 60) / 1000.0 END)
    , 2) AS disc_amt,
    0, 0, 0  -- placeholders, corrected below
FROM assembled a
JOIN dim_product dp ON dp.product_id = a.product_id;

-- Fix net_revenue / total_cost / gross_profit now that gross_revenue & discount_amt exist
UPDATE fact_sales
SET net_revenue = ROUND(gross_revenue - discount_amt, 2),
    total_cost  = ROUND(quantity * unit_cost, 2);
UPDATE fact_sales
SET gross_profit = ROUND(net_revenue - total_cost, 2);

PRAGMA foreign_keys = ON;
