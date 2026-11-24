-- (a) Tables
CREATE TABLE Students (
    student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(100), fee_due NUMERIC(10,2) CHECK (fee_due >= 0)
);
CREATE TABLE Payments (
    payment_id SERIAL PRIMARY KEY, student_id INT REFERENCES Students(student_id), amount NUMERIC(10,2) CHECK (amount > 0), paid_on DATE
);
CREATE TABLE payment_audit (
    audit_id SERIAL PRIMARY KEY, payment_id INT, student_id INT, amount NUMERIC(10,2), logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE daily_collections (
    collection_date DATE PRIMARY KEY, payment_count INT, total_amount NUMERIC(12,2)
);

INSERT INTO Students (student_number, full_name, fee_due) VALUES ('S001', 'Alice', 5000), ('S002', 'Bob', 0), ('S003', 'Charlie', 3000);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INT) RETURNS NUMERIC AS $$
DECLARE v_due NUMERIC; v_paid NUMERIC;
BEGIN
    SELECT fee_due INTO v_due FROM Students WHERE student_id = p_student_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student'; END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM Payments WHERE student_id = p_student_id;
    RETURN v_due - v_paid;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INT, p_amount NUMERIC, p_paid_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_balance NUMERIC;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
    v_balance := fn_fee_balance(p_student_id);
    IF p_amount > v_balance THEN RAISE EXCEPTION 'Payment exceeds balance'; END IF;
    INSERT INTO Payments (student_id, amount, paid_on) VALUES (p_student_id, p_amount, p_paid_on);
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_payment_audit() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO payment_audit (payment_id, student_id, amount) VALUES (NEW.payment_id, NEW.student_id, NEW.amount);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER after_payment_insert AFTER INSERT ON Payments FOR EACH ROW EXECUTE FUNCTION trg_payment_audit();

-- (e) View
CREATE VIEW v_fee_balances AS
SELECT s.student_number, s.full_name, (s.fee_due - COALESCE(SUM(p.amount), 0)) AS outstanding_balance
FROM Students s LEFT JOIN Payments p ON s.student_id = p.student_id
GROUP BY s.student_id, s.student_number, s.full_name, s.fee_due
HAVING (s.fee_due - COALESCE(SUM(p.amount), 0)) > 0;

-- (f) Index & EXPLAIN
CREATE INDEX idx_payments_student_date ON Payments(student_id, paid_on);
-- EXPLAIN SELECT * FROM Payments WHERE student_id = 1 AND paid_on BETWEEN '2023-01-01' AND '2023-12-31';

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM daily_collections WHERE collection_date = p_day;
    INSERT INTO daily_collections (collection_date, payment_count, total_amount)
    SELECT p_day, COUNT(*), SUM(amount) FROM Payments WHERE paid_on = p_day;
END; $$;