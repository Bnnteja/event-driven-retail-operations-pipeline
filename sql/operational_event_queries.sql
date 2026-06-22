-- =========================================================
-- Operational Event Analytics Queries
-- Project: Event-Driven Retail Operations Pipeline on AWS
-- Database: retail_event_operations_db
-- =========================================================

-- 1. Preview inventory events
SELECT *
FROM inventory_events
LIMIT 10;

-- 2. Preview pricing events
SELECT *
FROM pricing_events
LIMIT 10;

-- 3. Low inventory events by store
SELECT
    store_id,
    COUNT(*) AS low_inventory_events
FROM inventory_events
WHERE inventory_remaining < threshold
GROUP BY store_id
ORDER BY low_inventory_events DESC;

-- 4. Average inventory remaining by SKU
SELECT
    sku,
    AVG(inventory_remaining) AS avg_inventory_remaining,
    COUNT(*) AS event_count
FROM inventory_events
GROUP BY sku
ORDER BY avg_inventory_remaining ASC;

-- 5. Pricing gap by fuel grade
SELECT
    fuel_grade,
    AVG(price_gap_vs_competitor) AS avg_price_gap,
    COUNT(*) AS pricing_event_count
FROM pricing_events
GROUP BY fuel_grade
ORDER BY avg_price_gap DESC;

-- 6. Stores with highest pricing gap
SELECT
    store_id,
    AVG(price_gap_vs_competitor) AS avg_price_gap
FROM pricing_events
GROUP BY store_id
ORDER BY avg_price_gap DESC;

-- 7. Pricing events above competitor threshold
SELECT
    store_id,
    fuel_grade,
    new_price,
    competitor_price,
    price_gap_vs_competitor,
    event_timestamp
FROM pricing_events
WHERE price_gap_vs_competitor > 0.05
ORDER BY price_gap_vs_competitor DESC;

-- 8. Event volume summary
SELECT
    'inventory_events' AS event_category,
    COUNT(*) AS total_events
FROM inventory_events

UNION ALL

SELECT
    'pricing_events' AS event_category,
    COUNT(*) AS total_events
FROM pricing_events;
