-- (a) Tables
CREATE TABLE customers (customer_id SERIAL PRIMARY KEY, full_name VARCHAR(100));
CREATE TABLE readings (
    reading_id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(customer_id), reading_month DATE,
    previous_reading INT CHECK (previous_reading >= 0), current_reading INT CHECK (current_reading >= 0),
    UNIQUE(customer_id, reading_month)
);
CREATE TABLE bills (
    bill_id SERIAL PRIMARY KEY, reading_id INT UNIQUE REFERENCES readings(reading_id), charge NUMERIC(10,2), amount_paid NUMERIC(10,2) DEFAULT 0, due_on DATE,
    CHECK (amount_paid >= 0 AND amount_paid <= charge)
);
CREATE TABLE receivable_snapshot (snapshot_date DATE PRIMARY KEY, total_due NUMERIC(12,2));

INSERT INTO customers (full_name) VALUES ('C1'), ('C2'), ('C3');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_water_charge(p_units INT) RETURNS NUMERIC AS $$
BEGIN
    IF p_units < 0 THEN RAISE EXCEPTION 'Units cannot be negative'; END IF;
    IF p_units <= 10 THEN RETURN p_units * 5.00;
    ELSE RETURN (10 * 5.00) + ((p_units - 10) * 8.00); END IF;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id INT, p_due_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_curr INT; v_prev INT; v_charge NUMERIC;
BEGIN
    SELECT current_reading, previous_reading INTO v_curr, v_prev FROM readings WHERE reading_id = p_reading_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown reading'; END IF;
    IF EXISTS (SELECT 1 FROM bills WHERE reading_id = p_reading_id) THEN RAISE EXCEPTION 'Bill already exists'; END IF;
    
    v_charge := fn_water_charge(v_curr - v_prev);
    INSERT INTO bills (reading_id, charge, due_on) VALUES (p_reading_id, v_charge, p_due_on);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_check_reading() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.current_reading < NEW.previous_reading THEN RAISE EXCEPTION 'Current reading cannot be less than previous'; END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER before_reading_insert_update BEFORE INSERT OR UPDATE ON readings FOR EACH ROW EXECUTE FUNCTION trg_check_reading();

-- (e) View
CREATE VIEW v_overdue_bills AS
SELECT c.full_name, b.due_on, (b.charge - b.amount_paid) AS outstanding_amount
FROM bills b JOIN readings r ON b.reading_id = r.reading_id JOIN customers c ON r.customer_id = c.customer_id
WHERE b.due_on < CURRENT_DATE AND b.amount_paid < b.charge;

-- (f) Index
CREATE INDEX idx_bills_due_paid ON bills(due_on, amount_paid);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_receivables() LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM receivable_snapshot WHERE snapshot_date = CURRENT_DATE;
    INSERT INTO receivable_snapshot (snapshot_date, total_due)
    SELECT CURRENT_DATE, SUM(charge - amount_paid) FROM bills WHERE amount_paid < charge;
END; $$;