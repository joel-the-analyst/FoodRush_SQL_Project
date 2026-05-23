# FoodRush Data Warehouse (foodrush_analytics)

*Data Engineering & Business Intelligence Documentation*

## 1. Executive Summary
The FoodRush Analytics project transforms raw operational data from FoodRush (a food delivery platform) into a clean, optimized data warehouse.

Before this project, raw data regarding orders, tracking, menus, and customers was scattered across separate raw spreadsheets. This code builds a permanent Star Schema architecture (a standard hub-and-spoke model for organizing data) designed to provide instant answers to business-critical questions across Finance, Operations, and Marketing.

**Business Value**

* **Reduces Database Stress:** Aggregates and simplifies data so heavy executive dashboards (e.g., Tableau, Power BI) don't slow down the live app.

* **Single Source of Truth:** Unifies customer and restaurant geographic records, eliminating data duplication.

* **Fast Decision Making:** Enables quick identification of at-risk customers, late-delivery cities, and low-performing restaurant cuisines.

## 2. Architecture Overview & Data Modeling
The data warehouse uses an industry-standard Star Schema design, separating core operational business metrics (Facts) from descriptive context elements (Dimensions).

**Staging Layer**

*Prefix: stg_*

These temporary tables mirror raw operational data directly from the food delivery application. They serve as the landing pad before data cleansing, deduplication, and structuring begin.

**Dimension Tables (Contextual Data)**

*Prefix: dim_*

Dimensions answer the who, where, and what of the business.

* dim_cities / dim_cuisines: Fully normalized tables. This structure cleans up data entry anomalies by separating names from numeric IDs.

* dim_restaurants / dim_customers / dim_menu_items: Contain static or slow-changing characteristics, optimized with relational foreign keys.

**Fact Tables (Core Business Metrics)**

*Prefix: fact_ & agg_*

Fact tables store the measurable, quantitative data resulting from business actions.

* fact_orders: Holds order-level transactions. Features pre-calculated metrics (total_items, total_amount) to speed up macro dashboard renders.

* fact_order_items: Holds individual item-level records (the lines inside a receipt). Uses database-calculated logic (line_total) to prevent pricing mathematical drift.

* agg_daily_sales: A highly compressed, high-performance summary table updated daily to instantly feed high-level executive revenue dashboards without processing millions of historical rows.


## 3. Technical Database Specifications

**Optimization & Performance Features**

* Index Strategies: Strategic single and composite indexes are mapped across time components and relational links (e.g., idx_customer_order_time) to bypass full table scans during filtering.

* Data Integrity Rules: Applied hard structural rules such as CHECK (rating BETWEEN 0 AND 5.0) and CHECK (quantity > 0) to guarantee bad or corrupted data cannot enter reporting systems.

* Automated Computations: The line_total field uses storage-optimized columns (GENERATED ALWAYS AS (quantity * price) STORED) to compute values at ingestion rather than query runtime.


## 4. Analytical Insights & Business Value Mapping

The analytical queries embedded in this warehouse translate raw lines of data into tactical tools for different business departments.

**Top 10 Restaurants by Revenue**

**What it does:** Identifies top-performing partners based purely on completed sales values while calculating their average transaction ticket size.

![image alt](https://github.com/joel-the-analyst/FoodRush_SQL_Project/blob/0b94ba8b1821740af2b6fab3e7771841fb789762/Business%20Question%201.png)

**Cities with Poor Delivery Performance**

**What it does:** Flags locations where late orders surpass $15\%$ of total volume or where average trip duration breaks a 45-minute threshold.

![image](https://github.com/joel-the-analyst/FoodRush_SQL_Project/blob/45e940d636c79cdc068b2273e620b004543f610d/Business%20Question%202.png)

**Customer Lifetime Value (CLV)**

**What it does:** Extracts top spending users, mapping out how long they have been with the platform alongside how frequently they purchase.

![image](https://github.com/joel-the-analyst/FoodRush_SQL_Project/blob/45e940d636c79cdc068b2273e620b004543f610d/Business%20Question%203.png)

**Cuisine Saturation Analysis**

**What it does:** Maps out how many restaurants offer a specific food type against the actual revenue generated per store for that food category.

![image alt](https://github.com/joel-the-analyst/FoodRush_SQL_Project/blob/45e940d636c79cdc068b2273e620b004543f610d/Business%20Question%204.png)

**Customer Churn Risk**

**What it does:** Groups users into structured risk brackets based on the days elapsed since their last order ($>60$ Days = High Risk, $30\text{--}60$ Days = Medium Risk).

**Operational Trends Over Time**

**What it does:** Generates a month-over-month baseline view tracking aggregate volume growth, late fulfillment rates, and gross financial revenue.
