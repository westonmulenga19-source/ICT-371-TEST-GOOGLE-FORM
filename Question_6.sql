-- (a) Tables
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY, full_name VARCHAR(100), basic_salary NUMERIC(10,2) CHECK (basic_salary >= 0),
    allowance NUMERIC(10,2) CHECK (allowance >= 0), deduction NUMERIC(10,2) CHECK (deduction >= 0), active BOOLEAN
);
CREATE TABLE payroll (
    payroll_id SERIAL PRIMARY KEY, employee_id INT REFERENCES employees(employee_id), pay_month DATE,
    gross_pay NUMERIC(10,2), net_pay NUMERIC(10,2), UNIQUE(employee_id, pay_month)
);
CREATE TABLE salary_audit (audit_id SERIAL PRIMARY KEY, employee_id INT, old_salary NUMERIC, new_salary NUMERIC, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

INSERT INTO employees (full_name, basic_salary, allowance, deduction, active) VALUES 
('E1', 5000, 500, 200, true), ('E2', 4000, 400, 100, false);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INT) RETURNS NUMERIC AS $$
DECLARE v_basic NUMERIC; v_allow NUMERIC; v_ded NUMERIC; v_net NUMERIC;
BEGIN
    SELECT basic_salary, allowance, deduction INTO v_basic, v_allow, v_ded FROM employees WHERE employee_id = p_employee_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown employee'; END IF;
    v_net := (v_basic + v_allow) - v_ded;
    IF v_net < 0 THEN RAISE EXCEPTION 'Negative net pay'; END IF;
    RETURN v_net;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE) LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    IF EXTRACT(DAY FROM p_month) <> 1 THEN RAISE EXCEPTION 'Month must be start date'; END IF;
    FOR r IN SELECT employee_id, basic_salary + allowance AS gross FROM employees WHERE active = true LOOP
        IF NOT EXISTS (SELECT 1 FROM payroll WHERE employee_id = r.employee_id AND pay_month = p_month) THEN
            INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay) 
            VALUES (r.employee_id, p_month, r.gross, fn_net_pay(r.employee_id));
        END IF;
    END LOOP;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_salary_audit() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.basic_salary <> NEW.basic_salary THEN
        INSERT INTO salary_audit (employee_id, old_salary, new_salary) VALUES (OLD.employee_id, OLD.basic_salary, NEW.basic_salary);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER after_salary_update AFTER UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION trg_salary_audit();

-- (e) View
CREATE VIEW v_payroll_report AS
SELECT e.full_name, p.pay_month, p.gross_pay, p.net_pay
FROM payroll p JOIN employees e ON p.employee_id = e.employee_id;

-- (f) Index
CREATE INDEX idx_payroll_month ON payroll(pay_month);