-- =====================================================================
-- Automated Monthly Reporting Pipeline — Database Schema
-- Star schema: one fact table (transactions) + four dimension tables
-- Designed to support the exact KPIs an FP&A monthly reporting pack needs:
-- revenue, gross margin, growth (MoM/YoY), regional/product/channel mix.
-- =====================================================================

DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_region;
DROP TABLE IF EXISTS dim_channel;
DROP TABLE IF EXISTS dim_customer;

-- ---------------------------------------------------------------------
-- DATE DIMENSION
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key        INTEGER PRIMARY KEY,   -- YYYYMMDD
    full_date       TEXT NOT NULL,         -- 'YYYY-MM-DD'
    day             INTEGER NOT NULL,
    month           INTEGER NOT NULL,
    month_name      TEXT NOT NULL,
    quarter         INTEGER NOT NULL,
    year            INTEGER NOT NULL,
    fiscal_year      INTEGER NOT NULL,     -- FY = calendar year (Jan start, for simplicity)
    year_month      TEXT NOT NULL,         -- 'YYYY-MM' for easy grouping
    is_month_end    INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------
-- PRODUCT DIMENSION
-- ---------------------------------------------------------------------
CREATE TABLE dim_product (
    product_id      INTEGER PRIMARY KEY,
    product_name    TEXT NOT NULL,
    category        TEXT NOT NULL,
    unit_cost       REAL NOT NULL,
    unit_price      REAL NOT NULL
);

-- ---------------------------------------------------------------------
-- REGION DIMENSION
-- ---------------------------------------------------------------------
CREATE TABLE dim_region (
    region_id       INTEGER PRIMARY KEY,
    region_name     TEXT NOT NULL,
    country         TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- CHANNEL DIMENSION
-- ---------------------------------------------------------------------
CREATE TABLE dim_channel (
    channel_id      INTEGER PRIMARY KEY,
    channel_name    TEXT NOT NULL          -- Online / Retail / Wholesale
);

-- ---------------------------------------------------------------------
-- CUSTOMER DIMENSION
-- ---------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_id     INTEGER PRIMARY KEY,
    customer_name   TEXT NOT NULL,
    segment         TEXT NOT NULL,         -- Enterprise / SMB / Consumer
    region_id       INTEGER NOT NULL,
    FOREIGN KEY (region_id) REFERENCES dim_region(region_id)
);

-- ---------------------------------------------------------------------
-- FACT TABLE: one row per transaction line
-- ---------------------------------------------------------------------
CREATE TABLE fact_sales (
    transaction_id  INTEGER PRIMARY KEY,
    date_key        INTEGER NOT NULL,
    product_id      INTEGER NOT NULL,
    region_id       INTEGER NOT NULL,
    channel_id      INTEGER NOT NULL,
    customer_id     INTEGER NOT NULL,
    quantity        INTEGER NOT NULL,
    unit_price      REAL NOT NULL,
    unit_cost       REAL NOT NULL,
    gross_revenue   REAL NOT NULL,
    discount_amt    REAL NOT NULL DEFAULT 0,
    net_revenue     REAL NOT NULL,
    total_cost      REAL NOT NULL,
    gross_profit    REAL NOT NULL,
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (product_id) REFERENCES dim_product(product_id),
    FOREIGN KEY (region_id) REFERENCES dim_region(region_id),
    FOREIGN KEY (channel_id) REFERENCES dim_channel(channel_id),
    FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id)
);

CREATE INDEX idx_fact_date ON fact_sales(date_key);
CREATE INDEX idx_fact_product ON fact_sales(product_id);
CREATE INDEX idx_fact_region ON fact_sales(region_id);
CREATE INDEX idx_fact_channel ON fact_sales(channel_id);
CREATE INDEX idx_fact_customer ON fact_sales(customer_id);
