-- Create the database named "foodrush_analytics"
CREATE DATABASE foodrush_analytics;

-- Activate the foodrush_analytics database
USE foodrush_analytics;


-- 1. Staging: Restaurants
CREATE TABLE IF NOT EXISTS stg_restaurants (
    restaurant_id VARCHAR(10) PRIMARY KEY,
    cuisine VARCHAR(50),
    city VARCHAR(50),
    rating DECIMAL(2,1)
);

-- 2. Staging: Customers
CREATE TABLE IF NOT EXISTS stg_customers (
    customer_id VARCHAR(10) PRIMARY KEY,
    city VARCHAR(50),
    signup_date DATE
);

-- 3. Staging: Menu Items
CREATE TABLE IF NOT EXISTS stg_menu_items (
    item_id VARCHAR(10) PRIMARY KEY,
    restaurant_id VARCHAR(10),
    price DECIMAL(10,2)
);

-- 4. Staging: Orders
CREATE TABLE IF NOT EXISTS stg_orders (
    order_id VARCHAR(10) PRIMARY KEY,
    customer_id VARCHAR(10),
    restaurant_id VARCHAR(10),
    order_time DATETIME,
    delivery_time DATETIME,
    status VARCHAR(20)
);

-- 5. Staging: Order Items
CREATE TABLE IF NOT EXISTS stg_order_items (
    order_id VARCHAR(10),
    item_id VARCHAR(10),
    quantity INT,
    price DECIMAL(10,2),
    PRIMARY KEY (order_id, item_id)
);




-- DIMENSIONS


-- 1. Cities (Normalized)
CREATE TABLE IF NOT EXISTS dim_cities (
    city_id INT AUTO_INCREMENT PRIMARY KEY,
    city_name VARCHAR(50) NOT NULL UNIQUE,
    country VARCHAR(20)
);

-- 2. Cuisines (Normalized)
CREATE TABLE IF NOT EXISTS dim_cuisines (
    cuisine_id INT AUTO_INCREMENT PRIMARY KEY,
    cuisine_name VARCHAR(50) NOT NULL UNIQUE
);

-- 3. Customers Dimension
CREATE TABLE IF NOT EXISTS dim_customers (
    customer_id VARCHAR(10) PRIMARY KEY,
    city_id INT NOT NULL,
    signup_date DATE NOT NULL,
    
    FOREIGN KEY (city_id) REFERENCES dim_cities(city_id),
    INDEX idx_customer_city (city_id),
    INDEX idx_signup_date (signup_date)
);

-- 4. Restaurants Dimension
CREATE TABLE IF NOT EXISTS dim_restaurants (
    restaurant_id VARCHAR(10) PRIMARY KEY,
    cuisine_id INT NOT NULL,
    city_id INT NOT NULL,
    rating DECIMAL(2,1) CHECK (rating BETWEEN 0 AND 5.0),
    
    FOREIGN KEY (cuisine_id) REFERENCES dim_cuisines(cuisine_id),
    FOREIGN KEY (city_id) REFERENCES dim_cities(city_id),
    INDEX idx_restaurant_cuisine (cuisine_id),
    INDEX idx_restaurant_city (city_id)
);

-- 5. Menu Items Dimension
CREATE TABLE IF NOT EXISTS dim_menu_items (
    item_id VARCHAR(10) PRIMARY KEY,
    restaurant_id VARCHAR(10) NOT NULL,
    base_price DECIMAL(10,2) NOT NULL CHECK (base_price > 0),
    
    FOREIGN KEY (restaurant_id) REFERENCES dim_restaurants(restaurant_id),
    INDEX idx_menu_restaurant (restaurant_id)
);


-- FACT TABLES (Core Analytics Tables)


-- PRIMARY FACT: Order Level
CREATE TABLE IF NOT EXISTS fact_orders (
    order_id VARCHAR(10) PRIMARY KEY,
    customer_id VARCHAR(10) NOT NULL,
    restaurant_id VARCHAR(10) NOT NULL,
    
    order_time DATETIME NOT NULL,
    delivery_time DATETIME NULL,
    status ENUM('Delivered', 'Late', 'Cancelled') NOT NULL,
    
    -- Pre-aggregated for performance
    total_items INT NOT NULL DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id),
    FOREIGN KEY (restaurant_id) REFERENCES dim_restaurants(restaurant_id),
    
    -- Performance Indexes
    INDEX idx_order_time (order_time),
    INDEX idx_order_status (status),
    INDEX idx_customer_order_time (customer_id, order_time),
    INDEX idx_restaurant_order_time (restaurant_id, order_time)
);

-- SECOND FACT: Order Items (Line Level)
CREATE TABLE IF NOT EXISTS fact_order_items (
    order_item_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(10) NOT NULL,
    item_id VARCHAR(10) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL CHECK (price > 0),
    line_total DECIMAL(12,2) GENERATED ALWAYS AS (quantity * price) STORED,
    
    FOREIGN KEY (order_id) REFERENCES fact_orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES dim_menu_items(item_id),
    
    INDEX idx_orderitem_order (order_id),
    INDEX idx_orderitem_item (item_id),
    INDEX idx_composite_order_item (order_id, item_id)
);


-- Aggregate Table (for heavy dashboards)

CREATE TABLE IF NOT EXISTS agg_daily_sales (
    date DATE NOT NULL,
    restaurant_id VARCHAR(10) NOT NULL,
    cuisine_id INT,
    city_id INT,
    order_count INT DEFAULT 0,
    total_revenue DECIMAL(12,2) DEFAULT 0.00,
    cancelled_count INT DEFAULT 0,
    
    PRIMARY KEY (date, restaurant_id),
    FOREIGN KEY (restaurant_id) REFERENCES dim_restaurants(restaurant_id)
);



-- 1. Populate dim_cities (Unique cities from both customers and restaurants)
INSERT INTO dim_cities (city_name)
SELECT DISTINCT city FROM stg_customers
UNION
SELECT DISTINCT city FROM stg_restaurants;

-- 2. Populate dim_cuisines
INSERT INTO dim_cuisines (cuisine_name)
SELECT DISTINCT cuisine FROM stg_restaurants;

-- 3. Populate dim_restaurants
INSERT INTO dim_restaurants (restaurant_id, cuisine_id, city_id, rating)
SELECT 
    r.restaurant_id,
    c.cuisine_id,
    ci.city_id,
    r.rating
FROM stg_restaurants r
JOIN dim_cuisines c ON c.cuisine_name = r.cuisine
JOIN dim_cities ci ON ci.city_name = r.city;

-- 4. Populate dim_menu_items
INSERT INTO dim_menu_items (item_id, restaurant_id, base_price)
SELECT item_id, restaurant_id, price FROM stg_menu_items;

-- 5. Populate dim_customers
INSERT INTO dim_customers (customer_id, city_id, signup_date)
SELECT 
    c.customer_id,
    ci.city_id,
    c.signup_date
FROM stg_customers c
JOIN dim_cities ci ON ci.city_name = c.city;

-- 6. Populate fact_orders (with pre-aggregation)
INSERT INTO fact_orders (order_id, customer_id, restaurant_id, order_time, 
                        delivery_time, status, total_items, total_amount)
SELECT 
    o.order_id,
    o.customer_id,
    o.restaurant_id,
    o.order_time,
    o.delivery_time,
    o.status,
    COUNT(oi.item_id) as total_items,
    SUM(oi.quantity * oi.price) as total_amount
FROM stg_orders o
LEFT JOIN stg_order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.restaurant_id, 
         o.order_time, o.delivery_time, o.status;

-- 7. Populate fact_order_items
INSERT INTO fact_order_items (order_id, item_id, quantity, price)
SELECT order_id, item_id, quantity, price 
FROM stg_order_items;





-- BUSINESS QUESTIONS --


-- Top 10 Restaurants by Revenue
SELECT 
    r.restaurant_id,
    r.rating,
    c.cuisine_name,
    ci.city_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.line_total) AS total_revenue,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM fact_orders o
JOIN fact_order_items oi ON oi.order_id = o.order_id
JOIN dim_restaurants r ON o.restaurant_id = r.restaurant_id
JOIN dim_cuisines c ON r.cuisine_id = c.cuisine_id
JOIN dim_cities ci ON r.city_id = ci.city_id
WHERE o.status = 'Delivered'
GROUP BY r.restaurant_id, r.rating, c.cuisine_name, ci.city_name
ORDER BY total_revenue DESC
LIMIT 10;


-- Cities with Poor Delivery Performance
SELECT 
    ci.city_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(CASE WHEN o.status = 'Late' THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN o.status = 'Late' THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_percentage,
    AVG(TIMESTAMPDIFF(MINUTE, o.order_time, o.delivery_time)) AS avg_delivery_minutes
FROM fact_orders o
JOIN dim_restaurants r ON o.restaurant_id = r.restaurant_id
JOIN dim_cities ci ON r.city_id = ci.city_id
WHERE o.status IN ('Delivered', 'Late')
GROUP BY ci.city_name
HAVING late_percentage > 15 OR avg_delivery_minutes > 45
ORDER BY late_percentage DESC;


-- Top Valuable Customers (Customer Lifetime Value)
SELECT 
    c.customer_id,
    ci.city_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.line_total) AS total_spend,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value,
    MIN(o.order_time) AS first_order_date,
    MAX(o.order_time) AS last_order_date,
    DATEDIFF(MAX(o.order_time), MIN(o.order_time)) AS customer_tenure_days
FROM fact_orders o
JOIN fact_order_items oi ON oi.order_id = o.order_id
JOIN dim_customers c ON o.customer_id = c.customer_id
JOIN dim_cities ci ON c.city_id = ci.city_id
WHERE o.status = 'Delivered'
GROUP BY c.customer_id, ci.city_name
ORDER BY total_spend DESC
LIMIT 20;



-- Cuisine Saturation Analysis 
SELECT 
    c.cuisine_name,
    COUNT(DISTINCT r.restaurant_id) AS num_restaurants,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.line_total) AS total_revenue,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT r.restaurant_id), 2) AS revenue_per_restaurant
FROM dim_cuisines c
JOIN dim_restaurants r ON r.cuisine_id = c.cuisine_id
LEFT JOIN fact_orders o ON o.restaurant_id = r.restaurant_id AND o.status = 'Delivered'
LEFT JOIN fact_order_items oi ON oi.order_id = o.order_id
GROUP BY c.cuisine_name
ORDER BY num_restaurants DESC, revenue_per_restaurant ASC;


-- Customer Churn Risk
WITH customer_activity AS (
    SELECT 
        c.customer_id,
        ci.city_name,
        MAX(o.order_time) AS last_order_date,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(oi.line_total) AS total_spend
    FROM dim_customers c
    JOIN dim_cities ci ON c.city_id = ci.city_id
    LEFT JOIN fact_orders o ON o.customer_id = c.customer_id
    LEFT JOIN fact_order_items oi ON oi.order_id = o.order_id
    GROUP BY c.customer_id, ci.city_name
)
SELECT 
    customer_id,
    city_name,
    last_order_date,
    total_orders,
    total_spend,
    DATEDIFF(CURRENT_DATE, last_order_date) AS days_since_last_order,
    CASE 
        WHEN DATEDIFF(CURRENT_DATE, last_order_date) > 60 THEN 'High Risk'
        WHEN DATEDIFF(CURRENT_DATE, last_order_date) BETWEEN 30 AND 60 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS churn_risk
FROM customer_activity
WHERE DATEDIFF(CURRENT_DATE, last_order_date) > 30
ORDER BY days_since_last_order DESC;


-- Operational Trends Over Time (Monthly View)
SELECT 
    DATE_FORMAT(o.order_time, '%Y-%m') AS month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(CASE WHEN o.status = 'Delivered' THEN 1 ELSE 0 END) AS delivered_orders,
    SUM(CASE WHEN o.status = 'Late' THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN o.status = 'Late' THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_rate,
    SUM(oi.line_total) AS total_revenue,
    ROUND(SUM(oi.line_total) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM fact_orders o
JOIN fact_order_items oi ON oi.order_id = o.order_id
GROUP BY month
ORDER BY month DESC;