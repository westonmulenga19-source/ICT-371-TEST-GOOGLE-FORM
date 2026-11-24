-- (a) Tables
CREATE TABLE students (student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(100));
CREATE TABLE applications (
    application_id SERIAL PRIMARY KEY, student_id INT REFERENCES students(student_id),
    age_at_application INT CHECK (age_at_application > 0), monthly_income NUMERIC(10,2) CHECK (monthly_income >= 0),
    average_mark NUMERIC(5,2) CHECK (average_mark BETWEEN 0 AND 100), submitted_on DATE, status VARCHAR(20) DEFAULT 'PENDING'
);
CREATE TABLE decision_audit (audit_id SERIAL PRIMARY KEY, application_id INT, old_status VARCHAR(20), new_status VARCHAR(20), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

INSERT INTO students (student_number, full_name) VALUES ('S1', 'Alice'), ('S2', 'Bob'), ('S3', 'Charlie');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INT, p_income NUMERIC, p_mark NUMERIC) RETURNS BOOLEAN AS $$
BEGIN
    IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL OR p_income < 0 OR p_age <= 0 OR p_mark < 0 OR p_mark > 100 THEN RAISE EXCEPTION 'Invalid inputs'; END IF;
    RETURN (p_age BETWEEN 18 AND 25) AND (p_income <= 3000) AND (p_mark >= 70);
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INT) LANGUAGE plpgsql AS $$
DECLARE v_age INT; v_inc NUMERIC; v_mark NUMERIC; v_stat VARCHAR(20); v_eligible BOOLEAN;
BEGIN
    SELECT age_at_application, monthly_income, average_mark, status INTO v_age, v_inc, v_mark, v_stat FROM applications WHERE application_id = p_application_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application'; END IF;
    IF v_stat <> 'PENDING' THEN RAISE EXCEPTION 'Application already assessed'; END IF;
    
    v_eligible := fn_scholarship_eligible(v_age, v_inc, v_mark);
    IF v_eligible THEN UPDATE applications SET status = 'APPROVED' WHERE application_id = p_application_id;
    ELSE UPDATE applications SET status = 'REJECTED' WHERE application_id = p_application_id; END IF;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_decision_audit() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO decision_audit (application_id, old_status, new_status) VALUES (OLD.application_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER after_application_update AFTER UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION trg_decision_audit();

-- (e) View
CREATE VIEW v_approved_applicants AS
SELECT s.student_number, s.full_name, a.average_mark, a.status
FROM applications a JOIN students s ON a.student_id = s.student_id
WHERE a.status = 'APPROVED';

-- (f) Index
CREATE INDEX idx_app_status_date ON applications(status, submitted_on);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_assess_pending() LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT application_id FROM applications WHERE status = 'PENDING' LOOP
        CALL pr_assess_application(r.application_id);
    END LOOP;
END; $$;