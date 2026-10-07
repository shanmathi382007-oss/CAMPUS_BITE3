-- CampusBite PostgreSQL schema (PostgreSQL 11+)
-- Run this inside the already-created database "campusbite"
DROP VIEW IF EXISTS v_daily_sales, v_popular_food;
DROP TABLE IF EXISTS reviews, payments, order_items, orders, food_items, users CASCADE;

CREATE TABLE users(
 user_id SERIAL PRIMARY KEY, name VARCHAR(80) NOT NULL,
 email VARCHAR(100) NOT NULL UNIQUE, phone VARCHAR(15), password VARCHAR(100) NOT NULL,
 role VARCHAR(10) NOT NULL DEFAULT 'student' CHECK(role IN('student','admin')),
 college_id VARCHAR(20) UNIQUE, department VARCHAR(60), year SMALLINT,
 created_at TIMESTAMP DEFAULT NOW());

CREATE TABLE food_items(
 food_id SERIAL PRIMARY KEY, food_name VARCHAR(80) NOT NULL UNIQUE,
 category VARCHAR(20) NOT NULL CHECK(category IN('Breakfast','Main Course','Snacks','Beverages')),
 description VARCHAR(255), price NUMERIC(8,2) NOT NULL CHECK(price>=0),
 available_quantity INT NOT NULL DEFAULT 0 CHECK(available_quantity>=0),
 availability BOOLEAN NOT NULL DEFAULT TRUE, image VARCHAR(255));

CREATE TABLE orders(
 order_id SERIAL PRIMARY KEY, user_id INT NOT NULL REFERENCES users(user_id),
 order_date TIMESTAMP DEFAULT NOW(), pickup_time VARCHAR(10) NOT NULL,
 total_amount NUMERIC(9,2) NOT NULL,
 order_status VARCHAR(20) DEFAULT 'Pending' CHECK(order_status IN('Pending','Accepted','Preparing','Ready for Pickup','Completed','Cancelled')),
 payment_status VARCHAR(10) DEFAULT 'Pending' CHECK(payment_status IN('Paid','Pending')),
 completed_at TIMESTAMP NULL);

CREATE TABLE order_items(
 order_item_id SERIAL PRIMARY KEY,
 order_id INT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
 food_id INT NOT NULL REFERENCES food_items(food_id),
 quantity INT NOT NULL CHECK(quantity>0), price NUMERIC(8,2) NOT NULL, subtotal NUMERIC(9,2) NOT NULL);

CREATE TABLE payments(
 payment_id SERIAL PRIMARY KEY, order_id INT NOT NULL UNIQUE REFERENCES orders(order_id) ON DELETE CASCADE,
 payment_method VARCHAR(20) NOT NULL CHECK(payment_method IN('UPI','Card','Cash at Canteen')),
 amount NUMERIC(9,2) NOT NULL, payment_status VARCHAR(10) NOT NULL CHECK(payment_status IN('Paid','Pending')),
 transaction_id VARCHAR(40), payment_date TIMESTAMP DEFAULT NOW());

CREATE TABLE reviews(
 review_id SERIAL PRIMARY KEY, user_id INT NOT NULL REFERENCES users(user_id),
 food_id INT NOT NULL REFERENCES food_items(food_id),
 rating SMALLINT NOT NULL CHECK(rating BETWEEN 1 AND 5), comment VARCHAR(255),
 review_date TIMESTAMP DEFAULT NOW());

-- TRIGGER 1: reduce stock after an order item is inserted; availability = FALSE at 0
CREATE OR REPLACE FUNCTION fn_reduce_stock() RETURNS TRIGGER AS $$
BEGIN
 UPDATE food_items SET available_quantity=available_quantity-NEW.quantity,
        availability=(available_quantity-NEW.quantity>0)
 WHERE food_id=NEW.food_id;
 RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_reduce_stock AFTER INSERT ON order_items
 FOR EACH ROW EXECUTE FUNCTION fn_reduce_stock();

-- TRIGGER 2: keep availability in sync when admin edits stock
CREATE OR REPLACE FUNCTION fn_stock_sync() RETURNS TRIGGER AS $$
BEGIN
 IF NEW.available_quantity=0 THEN NEW.availability:=FALSE; END IF;
 RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_stock_sync BEFORE UPDATE ON food_items
 FOR EACH ROW EXECUTE FUNCTION fn_stock_sync();

-- STORED PROCEDURE: update order status, stamp completion time, restore stock on cancel
CREATE OR REPLACE PROCEDURE sp_update_order_status(oid INT, st TEXT)
LANGUAGE plpgsql AS $$
DECLARE old TEXT;
BEGIN
 SELECT order_status INTO old FROM orders WHERE order_id=oid;
 UPDATE orders SET order_status=st,
   completed_at=CASE WHEN st='Completed' THEN NOW() ELSE completed_at END
 WHERE order_id=oid;
 IF st='Cancelled' AND old<>'Cancelled' THEN
  UPDATE food_items f SET available_quantity=f.available_quantity+oi.quantity, availability=TRUE
  FROM order_items oi WHERE oi.food_id=f.food_id AND oi.order_id=oid;
 END IF;
END $$;

-- VIEWS
CREATE VIEW v_daily_sales AS
 SELECT order_date::date AS day, COUNT(*)::int AS orders,
  COALESCE(SUM(total_amount) FILTER (WHERE order_status<>'Cancelled'),0) AS revenue,
  (COUNT(*) FILTER (WHERE order_status='Completed'))::int AS completed,
  (COUNT(*) FILTER (WHERE order_status='Cancelled'))::int AS cancelled
 FROM orders GROUP BY order_date::date;

CREATE VIEW v_popular_food AS
 SELECT f.food_id, f.food_name, SUM(oi.quantity)::int AS sold
 FROM food_items f JOIN order_items oi ON oi.food_id=f.food_id
 JOIN orders o ON o.order_id=oi.order_id AND o.order_status<>'Cancelled'
 GROUP BY f.food_id, f.food_name ORDER BY sold DESC;

-- SEED MENU (demo users are created with hashed passwords by server.js on start)
INSERT INTO food_items(food_name,category,description,price,available_quantity) VALUES
('Idli','Breakfast','Soft steamed idli with sambar and chutney',30,50),
('Dosa','Breakfast','Crispy dosa served with chutney',40,40),
('Pongal','Breakfast','Creamy ven pongal with ghee',35,30),
('Poori','Breakfast','Fluffy poori with potato masala',40,30),
('Parotta','Main Course','Flaky layered parotta',20,60),
('Chicken Biriyani','Main Course','Chicken biriyani served with traditional spices',100,40),
('Veg Meals','Main Course','Full South Indian veg meals',80,40),
('Samosa','Snacks','Crispy potato samosa',15,50),
('Vada','Snacks','Hot medhu vada',15,50),
('Sandwich','Snacks','Veg grilled sandwich',40,25),
('Tea','Beverages','Hot masala tea',15,100),
('Coffee','Beverages','Filter coffee',20,100),
('Fresh Juice','Beverages','Seasonal fresh fruit juice',40,30);
