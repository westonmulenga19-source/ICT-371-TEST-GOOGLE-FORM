-- (a) Tables
CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    unit_price NUMERIC(10,2) CHECK (unit_price > 0),
    stock_qty INT CHECK (stock_qty >= 0)
);

CREATE TABLE sales (
    sale_id SERIAL PRIMARY KEY,
    medicine_id INT REFERENCES medicines(medicine_id),
    quantity INT CHECK (quantity > 0),
    unit_price NUMERIC(10,2),
    sold_on DATE DEFAULT CURRENT_DATE
);

CREATE TABLE stock_audit (
    audit_id SERIAL PRIMARY KEY,
    medicine_id INT REFERENCES medicines(medicine_id),
    old_qty INT,
    new_qty INT,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE daily_sales (
    sales_date DATE PRIMARY KEY,
    total_qty INT,
    total_amount NUMERIC(12,2)
);

-- Seed Data
INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES 
('Paracetamol', 5.00, 100), ('Amoxicillin', 15.50, 50), ('Ibuprofen', 8.00, 20);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INT, p_quantity INT) 
RETURNS NUMERIC AS $$
DECLARE v_price NUMERIC;
BEGIN
    IF p_quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
    SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine'; END IF;
    RETURN v_price * p_quantity;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INT, p_quantity INT, p_sold_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_stock INT; v_price NUMERIC;
BEGIN
    SELECT stock_qty, unit_price INTO v_stock, v_price FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;
    IF v_stock < p_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
    
    INSERT INTO sales (medicine_id, quantity, unit_price, sold_on) VALUES (p_medicine_id, p_quantity, v_price, p_sold_on);
    UPDATE medicines SET stock_qty = stock_qty - p_quantity WHERE medicine_id = p_medicine_id;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_stock_audit() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stock_qty <> NEW.stock_qty THEN
        INSERT INTO stock_audit (medicine_id, old_qty, new_qty) VALUES (OLD.medicine_id, OLD.stock_qty, NEW.stock_qty);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER after_stock_update AFTER UPDATE ON medicines FOR EACH ROW EXECUTE FUNCTION trg_stock_audit();

-- (e) View
CREATE VIEW v_low_stock AS 
SELECT medicine_name, unit_price, stock_qty 
FROM medicines WHERE stock_qty < 10;

-- (f) Index & EXPLAIN
CREATE INDEX idx_sales_medicine_date ON sales(medicine_id, sold_on);
-- EXPLAIN SELECT * FROM sales WHERE medicine_id = 1 AND sold_on BETWEEN '2023-01-01' AND '2023-12-31';

-- (g) Scheduled Job (Using pg_cron syntax as standard)
CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM daily_sales WHERE sales_date = p_day;
    INSERT INTO daily_sales (sales_date, total_qty, total_amount)
    SELECT p_day, SUM(quantity), SUM(quantity * unit_price) FROM sales WHERE sold_on = p_day;
END; $$;
-- Schedule: SELECT cron.schedule('0 15 * * *', $$CALL pr_refresh_sales(CURRENT_DATE - 1)$$);