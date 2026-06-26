# Data Generation & KPI Methodology

## Why synthetic data, and why it's not just random noise

The brief calls for simulated transaction data rather than a real company's data (which would either be
confidential or, if public, wouldn't have clean transaction-level detail). The risk with synthetic data is
that it ends up too uniform to produce any real insight when queried. This generator avoids that by
explicitly encoding four real-world patterns into the random generation itself, all in `database/seed_data.sql`:

1. **Q4 holiday seasonality** — November/December transaction volume runs ~40-60% above an average month,
   with a corresponding January/February dip, via a `month_weights` lookup table.
2. **YoY growth** — overall transaction-weighted volume is ~8.6% higher in FY2025 than FY2024.
3. **A regional divergence** — `region_weights` shifts share away from "Greater Asia" and toward North
   America/Latin America between FY2024 and FY2025, producing a genuine -37.8% YoY decline in one region
   even as the total company is roughly flat — a realistic "the average hides the story" scenario.
4. **A channel mix shift** — `channel_weights` shifts share from Wholesale/Retail toward Online between the
   two years.

All of this is achieved with a **weighted cumulative-distribution join**: each dimension gets a small weights
table, a window function (`SUM() OVER`) turns the weights into cumulative ranges, and a `RANDOM() % N` draw
is joined against those ranges to land in the right bucket. 

### A genuine SQLite gotcha worth knowing about

The first version of the generator produced duplicate/inconsistent rows for the same transaction ID. The
cause: a CTE containing `RANDOM()` was referenced multiple times across the join chain, and SQLite was
**re-evaluating** the CTE (and therefore re-rolling the random numbers) on each reference instead of
computing it once. The fix is the `MATERIALIZED` keyword, which forces the CTE to be computed
once and reused: `rand_draw AS MATERIALIZED (...)`. Every random-generating CTE in `seed_data.sql` uses this.
This is the kind of bug that's invisible until you check row counts and totals carefully which is exactly
why every output below was validated against `COUNT(*)`, `SUM()`, and spot-checked aggregates before being
treated as final.

## KPI design choices

- **MoM and YoY growth use `LAG()`**, not a self-join, because a self-join on a date dimension for "give me
  the same period N rows back" is exactly the case window functions exist to simplify.
- **YTD revenue uses a running `SUM() OVER (PARTITION BY year ORDER BY month)`** rather than a subquery, 
  one pass over the data instead of a correlated subquery per row.
- **Top customers uses `RANK()` rather than `ROW_NUMBER()`** deliberately — ties should share a rank in a
  customer leaderboard, not be arbitrarily separated.
- **The "new vs. repeat customer" query** uses `MIN() OVER`-style logic (via a CTE finding each customer's
  first transaction month) because that's a genuinely common FP&A/RevOps ask — "how much of this month's
  revenue is from customers we already had vs. new logos" and it's a good demonstration that not every
  useful KPI is a simple `GROUP BY`.
- **The anomaly-flagging query** (months where MoM growth exceeds ±15%) exists because a real monthly
  reporting pipeline shouldn't just produce a wall of numbers. It should also be able to answer "what
  actually needs my attention this month," which is what an automated exceptions based alert would filter on.

## Where Excel picks up vs. where SQL already did the work

The CSV exports from SQL are already aggregated to the monthly/regional/channel/category grain — that's the
heavy lifting. The Excel workbook deliberately does **not** just redisplay SQL-computed growth rates; the
`Data_Monthly` tab imports only the raw monthly revenue/gross-profit figures and computes MoM%, YoY%, the
3-month rolling average, and YTD running total as live Excel formulas, so the workbook is genuinely
interactive (change a historical number, the whole sheet recalculates) rather than a static pasted report.
