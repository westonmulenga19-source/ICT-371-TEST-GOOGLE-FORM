-- (a) Tables
CREATE TABLE Patients (patient_id SERIAL PRIMARY KEY, full_name VARCHAR(100));
CREATE TABLE Doctors (doctor_id SERIAL PRIMARY KEY, full_name VARCHAR(100));
CREATE TABLE Appointments (
    appointment_id SERIAL PRIMARY KEY, patient_id INT REFERENCES Patients(patient_id), doctor_id INT REFERENCES Doctors(doctor_id),
    appointment_day DATE, slot_time TIME CHECK (slot_time IN ('09:00', '10:00', '11:00', '12:00')),
    status VARCHAR(20) CHECK (status IN ('BOOKED', 'ATTENDED', 'CANCELLED')),
    UNIQUE (doctor_id, appointment_day, slot_time)
);
CREATE TABLE clinic_summary (summary_date DATE PRIMARY KEY, booked_count INT, attended_count INT, cancelled_count INT);

INSERT INTO Patients (full_name) VALUES ('P1'), ('P2'), ('P3');
INSERT INTO Doctors (full_name) VALUES ('D1'), ('D2'), ('D3');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id INT, p_day DATE) RETURNS INT AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Doctors WHERE doctor_id = p_doctor_id) THEN RAISE EXCEPTION 'Unknown doctor'; END IF;
    RETURN (SELECT COUNT(*) FROM Appointments WHERE doctor_id = p_doctor_id AND appointment_day = p_day AND status <> 'CANCELLED');
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_book_appointment(p_patient_id INT, p_doctor_id INT, p_day DATE, p_slot TIME) LANGUAGE plpgsql AS $$
BEGIN
    IF p_day < CURRENT_DATE THEN RAISE EXCEPTION 'Past date not allowed'; END IF;
    INSERT INTO Appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES (p_patient_id, p_doctor_id, p_day, p_slot, 'BOOKED');
END; $$;

-- (d) Trigger (Before Insert or Update to prevent clash)
CREATE OR REPLACE FUNCTION trg_prevent_clash() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> 'CANCELLED' THEN
        IF EXISTS (SELECT 1 FROM Appointments WHERE doctor_id = NEW.doctor_id AND appointment_day = NEW.appointment_day AND slot_time = NEW.slot_time AND status <> 'CANCELLED' AND appointment_id <> COALESCE(NEW.appointment_id, -1)) THEN
            RAISE EXCEPTION 'Slot already booked';
        END IF;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER before_appointment_change BEFORE INSERT OR UPDATE ON Appointments FOR EACH ROW EXECUTE FUNCTION trg_prevent_clash();

-- (e) View
CREATE VIEW v_today_appointments AS
SELECT p.full_name AS patient_name, d.full_name AS doctor_name, a.slot_time, a.status
FROM Appointments a JOIN Patients p ON a.patient_id = p.patient_id JOIN Doctors d ON a.doctor_id = d.doctor_id
WHERE a.appointment_day = CURRENT_DATE AND a.status = 'BOOKED';

-- (f) Index
CREATE INDEX idx_app_day_doctor ON Appointments(appointment_day, doctor_id);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM clinic_summary WHERE summary_date = p_day;
    INSERT INTO clinic_summary (summary_date, booked_count, attended_count, cancelled_count)
    SELECT p_day, 
           COUNT(*) FILTER (WHERE status = 'BOOKED'),
           COUNT(*) FILTER (WHERE status = 'ATTENDED'),
           COUNT(*) FILTER (WHERE status = 'CANCELLED')
    FROM Appointments WHERE appointment_day = p_day;
END; $$;