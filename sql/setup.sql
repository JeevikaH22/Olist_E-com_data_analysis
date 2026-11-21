SELECT 'orders' AS tbl, COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers;

SELECT table_name,column_name,data_type,is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;

ALTER TABLE orders    ALTER COLUMN order_id SET NOT NULL;
ALTER TABLE customers ALTER COLUMN customer_id SET NOT NULL;
ALTER TABLE products  ALTER COLUMN product_id SET NOT NULL;
ALTER TABLE sellers   ALTER COLUMN seller_id SET NOT NULL;

ALTER TABLE orders    ADD PRIMARY KEY (order_id);
ALTER TABLE customers ADD PRIMARY KEY (customer_id);
ALTER TABLE products  ADD PRIMARY KEY (product_id);
ALTER TABLE sellers   ADD PRIMARY KEY (seller_id);

CREATE INDEX ON orders (customer_id);
CREATE INDEX ON orders (order_purchase_timestamp);
CREATE INDEX ON order_items (order_id);
CREATE INDEX ON order_items (product_id);
CREATE INDEX ON order_items (seller_id);
CREATE INDEX ON order_payments (order_id);
CREATE INDEX ON order_reviews (order_id);
CREATE INDEX ON customers (customer_unique_id);

CREATE OR REPLACE VIEW order_summary AS
SELECT
  o.order_id, o.customer_id, o.order_status,
  o.order_purchase_timestamp, o.order_delivered_customer_date, o.order_estimated_delivery_date,
  i.items_value, i.freight_value, i.item_count,
  p.payment_value,
  r.avg_review_score
FROM orders o
LEFT JOIN (SELECT order_id, SUM(price) items_value, SUM(freight_value) freight_value, COUNT(*) item_count
           FROM order_items GROUP BY order_id) i USING (order_id)
LEFT JOIN (SELECT order_id, SUM(payment_value) payment_value
           FROM order_payments GROUP BY order_id) p USING (order_id)
LEFT JOIN (SELECT order_id, AVG(review_score) avg_review_score
           FROM order_reviews GROUP BY order_id) r USING (order_id);