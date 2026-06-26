# Power BI Build Guide — Meridian Retail Co. Monthly Reporting Dashboard

**A note on why this is a guide and not a published dashboard:** I built this whole portfolio on a MacBook.
Power BI Desktop is Windows-only, I don't have a work/school email for the free Power BI tenant signup, and
running Windows through a VM is constrained by limited disk space on this machine. Rather than skip Power BI
entirely or fake a screenshot, what follows is the exact thought process and steps I'd execute the moment I
have access to a Windows environment: the data model, every DAX measure, and the report layout, written
precisely enough that you (or I, on a different machine) could follow it and get the same working dashboard
in about 15 minutes. I'd rather show real reasoning I can defend in an interview than a screenshot I can't.

Everything below is exact and copy-pasteable. Once published to the Power BI Service, you'd have a
public/shareable link for a portfolio.

## 1. Get the data in

**Option A — CSV import (simplest, recommended for a portfolio demo):**
1. Open Power BI Desktop → **Get Data → Text/CSV**.
2. Import each file from `exports/`: `fact_sales.csv`, `dim_date.csv`, `dim_product.csv`, `dim_region.csv`,
   `dim_channel.csv`, `dim_customer.csv`.
3. In Power Query Editor, set data types: `dim_date[full_date]` → Date, all `*_id`/`*_key` columns → Whole Number,
   all revenue/cost columns → Fixed Decimal Number.

**Option B — Live SQL source (for true scheduled auto-refresh):**
Power BI has no native SQLite connector. To get real auto-refresh against the SQL source:
- Recreate `schema.sql` + `seed_data.sql` in a server database Power BI *does* support natively
  (SQL Server, Azure SQL, Postgres via ODBC) — the DDL and queries in this repo are close to ANSI SQL and
  port with minimal changes.
- Connect via **Get Data → SQL Server** (or Postgres), then use **Power BI Service → Scheduled Refresh** with
  an **On-premises Data Gateway** pointing at that server (1x/day or whatever cadence the monthly pack needs).
- If you keep the CSV approach instead, put the `exports/` files in a OneDrive/SharePoint folder — Power BI
  Service can auto-refresh CSV-based datasets stored there on a schedule without a Gateway.

## 2. Build the data model

In **Model view**, create these relationships (all 1-to-many, single direction, from dimension → fact):

| From | To |
|---|---|
| `dim_date[date_key]` | `fact_sales[date_key]` |
| `dim_product[product_id]` | `fact_sales[product_id]` |
| `dim_region[region_id]` | `fact_sales[region_id]` |
| `dim_channel[channel_id]` | `fact_sales[channel_id]` |
| `dim_customer[customer_id]` | `fact_sales[customer_id]` |
| `dim_region[region_id]` | `dim_customer[region_id]` |

This is a textbook star schema — one fact table, dimensions radiating out. Mark `dim_date` as a
**Date Table** (Model view → right-click `dim_date` → Mark as date table → pick `full_date`).

## 3. DAX measures (create these in a new Measures table for cleanliness)

```dax
Total Revenue = SUM(fact_sales[net_revenue])

Total Gross Profit = SUM(fact_sales[gross_profit])

Gross Margin % = DIVIDE([Total Gross Profit], [Total Revenue], 0)

Prior Month Revenue =
CALCULATE([Total Revenue], DATEADD(dim_date[full_date], -1, MONTH))

MoM Growth % = DIVIDE([Total Revenue] - [Prior Month Revenue], [Prior Month Revenue], 0)

Prior Year Revenue =
CALCULATE([Total Revenue], SAMEPERIODLASTYEAR(dim_date[full_date]))

YoY Growth % = DIVIDE([Total Revenue] - [Prior Year Revenue], [Prior Year Revenue], 0)

YTD Revenue = TOTALYTD([Total Revenue], dim_date[full_date])

Rolling 3-Month Avg Revenue =
AVERAGEX(
    DATESINPERIOD(dim_date[full_date], MAX(dim_date[full_date]), -3, MONTH),
    [Total Revenue]
)

Revenue Rank (Customer) = RANKX(ALL(dim_customer[customer_name]), [Total Revenue])
```

## 4. Report page layout (mirrors the Excel Dashboard tab 1:1)

| Visual | Type | Fields |
|---|---|---|
| KPI cards (x5) | Card | `[Total Revenue]`, `[MoM Growth %]`, `[YoY Growth %]`, `[YTD Revenue]`, `[Gross Margin %]` |
| Monthly trend | Line chart | Axis: `dim_date[year_month]`; Values: `[Total Revenue]`, `[Total Gross Profit]` |
| Revenue by region | Clustered column | Axis: `dim_region[region_name]`; Legend: `dim_date[year]`; Values: `[Total Revenue]` |
| Channel mix | Donut chart | Legend: `dim_channel[channel_name]`; Values: `[Total Revenue]`, filtered to FY2025 |
| Top customers | Table | `dim_customer[customer_name]`, `dim_region[region_name]`, `[Total Revenue]`, sorted descending, Top N filter = 10 |
| Region/Channel slicer | Slicer | `dim_region[region_name]`, `dim_channel[channel_name]` for interactivity |

Add a **Page-level filter** on `dim_date[year]` so a stakeholder can flip between FY2024 and FY2025 instantly —
this is the single feature that most replaces the "can you re-cut this for last year too?" email.

## 5. Publish & share (the plan, once I have Windows access)

**File → Publish → Power BI Service** (free workspace is fine). Once published, I'd:
- Use **File → Embed report → Publish to web** (the data is synthetic and non-sensitive, so this is safe here)
  to get a public link for this portfolio/resume.
- Or, failing that, just share the workspace link directly — recruiters with a free Power BI account could open it.

## Why this matters for an FP&A role

This is the exact workflow that replaces a "pull last month's numbers into Excel by hand" process:
SQL does the heavy aggregation once, and both Excel (for stakeholders who live in spreadsheets) and Power BI
(for a refreshable, interactive dashboard) consume the same clean output — instead of two people maintaining
two different, drifting versions of "the numbers."
