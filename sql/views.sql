DROP VIEW IF EXISTS vw_customer_summary, vw_seller_performance, vw_product_performance,
                    vw_category_monthly, vw_sales, vw_orders, vw_delivery, vw_reviews CASCADE;

-- ORDER GRAIN: one row per order (all statuses) + delivery metrics + review
CREATE VIEW vw_orders AS
SELECT s.order_id,s.customer_id,
       c.customer_unique_id,c.customer_state,c.customer_city,
       o.order_status, o.order_purchase_timestamp AS purchase_ts,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
       COALESCE(s.item_count, 0) AS item_count,
       s.items_value::numeric AS items_value,
       s.freight_value::numeric AS freight_value,
       s.payment_value::numeric AS payment_value,
       s.avg_review_score::numeric AS review_score,
       v.ok AS is_valid_delivered,
       ROUND((EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 3600)::numeric, 1) AS approval_hours,
	   
       CASE WHEN v.ok THEN o.order_delivered_carrier_date::date  - o.order_purchase_timestamp::date END AS handling_days,
       CASE WHEN v.ok THEN o.order_delivered_customer_date::date - o.order_delivered_carrier_date::date END AS shipping_days,
       CASE WHEN v.ok THEN o.order_delivered_customer_date::date - o.order_purchase_timestamp::date END AS delivery_days,
       CASE WHEN v.ok THEN o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date END AS delay_days,
       CASE WHEN v.ok THEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date END AS is_late
FROM order_summary s
JOIN orders    o ON o.order_id    = s.order_id
JOIN customers c ON c.customer_id = s.customer_id
CROSS JOIN LATERAL (SELECT (o.order_status = 'delivered'
                            AND NOT o.has_date_issue
                            AND o.order_delivered_customer_date IS NOT NULL) AS ok) v;

-- ITEM GRAIN: one row per item sold (valid delivered orders only)
CREATE VIEW vw_sales AS
SELECT oi.order_id,oi.order_item_id,oi.product_id,oi.seller_id,
       o.customer_id,
       c.customer_unique_id,c.customer_state,
       sl.seller_state,
       COALESCE(t.product_category_name_english, 'unknown') AS category,
       oi.price::numeric AS price,
       oi.freight_value::numeric AS freight_value,
       o.order_purchase_timestamp AS purchase_ts,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month
FROM order_items oi
JOIN orders    o  ON o.order_id    = oi.order_id
JOIN customers c  ON c.customer_id = o.customer_id
JOIN sellers   sl ON sl.seller_id  = oi.seller_id
JOIN products  p  ON p.product_id  = oi.product_id
LEFT JOIN product_category_translation t ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
  AND NOT o.has_date_issue;

-- CATEGORY x MONTH
CREATE VIEW vw_category_monthly AS
SELECT order_month,
       category,
       COUNT(DISTINCT order_id) AS orders,
       COUNT(*)                 AS items,
       SUM(price)               AS revenue,
       SUM(freight_value)       AS freight
FROM vw_sales
GROUP BY order_month, category;

-- PRODUCT GRAIN
CREATE VIEW vw_product_performance AS
WITH sales AS (
    SELECT product_id, category,
           COUNT(*)                 AS units,
           COUNT(DISTINCT order_id) AS orders,
           SUM(price)               AS revenue,
           AVG(price)               AS avg_price,
           SUM(freight_value)       AS freight
    FROM vw_sales
    GROUP BY product_id, category
),
rev AS (   -- distinct (product, order) pairs so multi-item orders don't double count
    SELECT ps.product_id,
           AVG(o.review_score)    AS avg_review,
           COUNT(o.review_score)  AS reviews
    FROM (SELECT DISTINCT product_id, order_id FROM vw_sales) ps
    JOIN vw_orders o ON o.order_id = ps.order_id
    GROUP BY ps.product_id
)
SELECT s.*, r.avg_review, r.reviews, p.product_weight_g
FROM sales s
LEFT JOIN rev r      ON r.product_id = s.product_id
JOIN products p      ON p.product_id = s.product_id;

-- SELLER GRAIN
CREATE VIEW vw_seller_performance AS
WITH s AS (
    SELECT seller_id, seller_state,
           COUNT(DISTINCT order_id)   AS orders,
           COUNT(*)                   AS items,
           COUNT(DISTINCT product_id) AS products,
           SUM(price)                 AS revenue
    FROM vw_sales
    GROUP BY seller_id, seller_state
),
q AS (
    SELECT so.seller_id,
           AVG(o.review_score)    AS avg_review,
           AVG(o.is_late::int)    AS late_rate,   
           AVG(o.delivery_days)   AS avg_delivery_days
    FROM (SELECT DISTINCT seller_id, order_id FROM vw_sales) so
    JOIN vw_orders o ON o.order_id = so.order_id
    GROUP BY so.seller_id
)
SELECT s.*, q.avg_review, q.late_rate, q.avg_delivery_days
FROM s LEFT JOIN q USING (seller_id);

-- CUSTOMER GRAIN (customer_unique_id = the real person)
CREATE VIEW vw_customer_summary AS
SELECT customer_unique_id,
       COUNT(*)                                                  AS orders,
       SUM(items_value)                                          AS revenue,
       ROUND(AVG(items_value), 2)                                AS avg_order_value,
       MIN(purchase_ts)::date                                    AS first_order,
       MAX(purchase_ts)::date                                    AS last_order,
       (ARRAY_AGG(customer_state ORDER BY purchase_ts DESC))[1]  AS latest_state,
       (COUNT(*) > 1)                                            AS is_repeat
FROM vw_orders
WHERE is_valid_delivered
GROUP BY customer_unique_id;