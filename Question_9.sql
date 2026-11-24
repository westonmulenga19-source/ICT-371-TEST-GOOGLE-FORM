-- (a) Tables
CREATE TABLE farmers (farmer_id SERIAL PRIMARY KEY, farmer_number VARCHAR(20) UNIQUE, full_name VARCHAR(100));
CREATE TABLE deliveries (
    delivery_id SERIAL PRIMARY KEY, farmer_id INT REFERENCES farmers(farmer_id), grade CHAR(1) CHECK (grade IN ('A', 'B', 'C')),
    weight_kg NUMERIC(10,2) CHECK (weight_kg > 0), unit_rate NUMERIC(10,2), total_value NUMERIC(12,2),
    delivered_on DATE, is_paid BOOLEAN DEFAULT FALSE
);
CREATE TABLE daily_purchases (purchase_date DATE PRIMARY KEY, total_weight NUMERIC(12,2), total_value NUMERIC(12,2));

INSERT INTO farmers (farmer_number, full_name) VALUES ('F1', 'Farmer 1'), ('F2', 'Farmer 2'), ('F3', 'Farmer 3');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade CHAR) RETURNS NUMERIC AS $$
BEGIN
    CASE p_grade
        WHEN 'A' THEN RETURN 5.00;
        WHEN 'B' THEN RETURN 4.00;
        WHEN 'C' THEN RETURN 3.00;
        ELSE RAISE EXCEPTION 'Unsupported grade';
    END CASE;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INT, p_grade CHAR, p_weight NUMERIC, p_date DATE) LANGUAGE plpgsql AS $$
DECLARE v_rate NUMERIC;
BEGIN
    IF p_weight <= 0 THEN RAISE EXCEPTION 'Weight must be positive'; END IF;
    IF NOT EXISTS (SELECT 1 FROM farmers WHERE farmer_id = p_farmer_id) THEN RAISE EXCEPTION 'Unknown farmer'; END IF;
    v_rate := fn_maize_rate(p_grade);
    INSERT INTO deliveries (farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on, is_paid) 
    VALUES (p_farmer_id, p_grade, p_weight, v_rate, p_weight * v_rate, p_date, false);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_delivery_calc() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.weight_kg <= 0 THEN RAISE EXCEPTION 'Weight must be positive'; END IF;
    NEW.unit_rate := fn_maize_rate(NEW.grade);
    NEW.total_value := NEW.weight_kg * NEW.unit_rate;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER before_delivery_insert_update BEFORE INSERT OR UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION trg_delivery_calc();

-- (e) View
CREATE VIEW v_farmer_amount AS
SELECT f.farmer_number, f.full_name, COALESCE(SUM(d.total_value), 0) AS total_unpaid_delivery_value
FROM farmers f LEFT JOIN deliveries d ON f.farmer_id = d.farmer_id AND d.is_paid = false
GROUP BY f.farmer_id, f.farmer_number, f.full_name;

-- (f) Index
CREATE INDEX idx_deliveries_farmer_date ON deliveries(farmer_id, delivered_on);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM daily_purchases WHERE purchase_date = p_day;
    INSERT INTO daily_purchases (purchase_date, total_weight, total_value)
    SELECT p_day, SUM(weight_kg), SUM(total_value) FROM deliveries WHERE delivered_on = p_day;
END; $$;