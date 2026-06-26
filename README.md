# Automated Monthly Reporting Pipeline — SQL + Excel + Power BI

A SQL-first reporting pipeline for a fictional retail company ("Meridian Retail Co.") that replaces a manual
monthly Excel-pull process: one SQL database, a library of KPI queries, and two BI layers (Excel dashboard +
Power BI build guide) consuming the same clean output.

**Portfolio project #2 of 3** mapping directly to FP&A job descriptions.
([Project 1: 3-statement model](https://github.com/KarisFang/fpa-portfolio-3-statement-model) ·
[Project 3: budget-vs-actual variance dashboard](https://github.com/KarisFang/fpa-portfolio-variance-dashboard))

## See it live

**[→ Open the interactive dashboard](https://karisfang.github.io/fpa-portfolio-reporting-pipeline/)** — no Power BI
account or download needed, just a browser. Hosted free on GitHub Pages from `docs/index.html`.

**A note on Power BI:** I built this on a MacBook with no Windows machine, no work/school email for the free
Power BI tenant, and limited disk space to run one through a VM. So instead of a live Power BI dashboard,
`powerbi/POWER_BI_BUILD_GUIDE.md` documents my actual thought process: the data model, every DAX measure, and
the report layout, written precisely enough to execute the moment I have Windows access. The HTML dashboard
above is what replaces it for now.

## The story in the data

This isn't flat synthetic noise — the generator (`database/seed_data.sql`) injects real seasonality, growth,
and mix-shift patterns so the KPI queries have something genuine to find:

- **North America** revenue +23.8% YoY, **Latin America** +28.9% YoY
- **Greater Asia** revenue **-37.8% YoY** — this single region's decline offsets most of the growth everywhere else
- **Online channel** share of revenue grows from 14.3% (FY24) to 19.6% (FY25) at Wholesale's expense
- Classic **Q4 holiday seasonality**: November/December run ~40-60% above the average month

## What's in this repo

| Folder | Contents |
|---|---|
| `database/` | `schema.sql` (star schema DDL), `seed_data.sql` (100% SQL synthetic data generator — recursive CTEs + weighted random sampling, no Python), `sales.db` (built SQLite database, ~14,000 transactions over 2 years) |
| `sql/` | `kpi_queries.sql` — 10 production-style KPI queries: monthly revenue/margin, MoM & YoY growth (`LAG`), running YTD (`SUM() OVER`), 3-month rolling average, regional YoY comparison, top-10 customers (`RANK`), category margin mix, channel mix shift, new-vs-repeat customers, automated variance-flagging |
| `exports/` | CSV extracts of every KPI query result, ready to import into Excel or Power BI |
| `excel/` | `FPA_Monthly_Reporting_Pack.xlsx` — a Dashboard tab (KPI cards + 3 live charts) backed by data tabs where every growth rate/margin/share is a **live Excel formula**, not a pre-baked number |
| `powerbi/` | `POWER_BI_BUILD_GUIDE.md` — exact DAX measures, data model relationships, and report layout to turn this into a real, publishable Power BI dashboard in ~15 minutes |
| `architecture/` | `architecture_diagram.svg` — pipeline architecture, data generation → SQLite → KPI queries → Excel / Power BI |
| `docs/` | `index.html` — a standalone interactive dashboard (Chart.js, dark "ledger" theme), hosted free on GitHub Pages from this folder, for viewing without Power BI |
| `methodology/` | `DATA_AND_KPI_METHODOLOGY.md` — how the synthetic data's seasonality/growth/mix-shift patterns were built, a real SQLite bug hit and fixed along the way, and the KPI query design choices |

## How the pipeline works

```
seed_data.sql  →  sales.db  →  kpi_queries.sql  →  CSV exports  →  Excel Dashboard
                  (SQLite)      (joins, CTEs,                  →  Power BI Dashboard
                                 window functions)
```

See `architecture/architecture_diagram.svg` for the visual version.

## Rebuilding it from scratch

```bash
cd database
sqlite3 sales.db < schema.sql
sqlite3 sales.db < seed_data.sql

# regenerate all CSV exports
sqlite3 -header -csv sales.db "SELECT ..." > ../exports/whatever.csv   # see kpi_queries.sql for the queries

# rebuild the Excel dashboard (only step that uses Python — to write .xlsx, not to do the analysis)
cd ../excel
python3 build_dashboard.py
```

## Why this is the FP&A skill, not just a SQL exercise

A monthly reporting pack that requires someone to manually pull data, paste it into Excel, and re-build the
same pivot tables every month is exactly the kind of process FP&A teams are expected to automate. This
project shows the full chain: a real (if synthetic) transactional source → reusable SQL logic for every KPI
→ two different consumption layers for two different audiences (spreadsheet-native stakeholders vs. an
interactive dashboard) — built once, refreshed on a schedule, not rebuilt from scratch every month.

---
Built by Karis Fang as a portfolio project for FP&A roles.
