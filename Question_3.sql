-- (a) Tables
CREATE TABLE Books (book_id SERIAL PRIMARY KEY, title VARCHAR(100));
CREATE TABLE Loans (
    loan_id SERIAL PRIMARY KEY, book_id INT REFERENCES Books(book_id), borrower_name VARCHAR(100),
    borrowed_on DATE, due_on DATE, returned_on DATE NULL, fine_amount NUMERIC(10,2) DEFAULT 0,
    CHECK (due_on >= borrowed_on)
);
CREATE TABLE loan_audit (audit_id SERIAL PRIMARY KEY, loan_id INT, old_returned_on DATE, new_returned_on DATE, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE overdue_summary (snapshot_date DATE PRIMARY KEY, overdue_count INT, total_fine NUMERIC(10,2));

INSERT INTO Books (title) VALUES ('Book A'), ('Book B'), ('Book C');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id INT, p_as_of DATE) RETURNS NUMERIC AS $$
DECLARE v_due DATE; v_returned DATE; v_days INT;
BEGIN
    SELECT due_on, returned_on INTO v_due, v_returned FROM Loans WHERE loan_id = p_loan_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown loan'; END IF;
    
    IF v_returned IS NOT NULL THEN p_as_of := v_returned; END IF;
    v_days := p_as_of - v_due;
    IF v_days > 0 THEN RETURN v_days * 2; ELSE RETURN 0; END IF;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id INT, p_returned_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_due DATE; v_borrowed DATE; v_existing_return DATE;
BEGIN
    SELECT due_on, borrowed_on, returned_on INTO v_due, v_borrowed, v_existing_return FROM Loans WHERE loan_id = p_loan_id;
    IF v_existing_return IS NOT NULL THEN RAISE EXCEPTION 'Already returned'; END IF;
    IF p_returned_on < v_borrowed THEN RAISE EXCEPTION 'Return date before borrow date'; END IF;
    
    UPDATE Loans SET returned_on = p_returned_on, fine_amount = fn_loan_fine(p_loan_id, p_returned_on) WHERE loan_id = p_loan_id;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_loan_audit() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN
        INSERT INTO loan_audit (loan_id, old_returned_on, new_returned_on) VALUES (OLD.loan_id, OLD.returned_on, NEW.returned_on);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER after_loan_update AFTER UPDATE ON Loans FOR EACH ROW EXECUTE FUNCTION trg_loan_audit();

-- (e) View
CREATE VIEW v_overdue_loans AS
SELECT l.loan_id, b.title, l.borrower_name, l.due_on, CURRENT_DATE - l.due_on AS days_overdue, (CURRENT_DATE - l.due_on) * 2 AS fine
FROM Loans l JOIN Books b ON l.book_id = b.book_id
WHERE l.returned_on IS NULL AND l.due_on < CURRENT_DATE;

-- (f) Index
CREATE INDEX idx_loans_book_returned ON Loans(book_id, returned_on);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of DATE) LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM overdue_summary WHERE snapshot_date = p_as_of;
    INSERT INTO overdue_summary (snapshot_date, overdue_count, total_fine)
    SELECT p_as_of, COUNT(*), SUM(fn_loan_fine(loan_id, p_as_of)) FROM Loans WHERE returned_on IS NULL AND due_on < p_as_of;
END; $$;