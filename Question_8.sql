-- (a) Tables
CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY, registration VARCHAR(20) UNIQUE, current_odometer INT CHECK (current_odometer >= 0),
    last_service_odometer INT CHECK (last_service_odometer >= 0), CHECK (current_odometer >= last_service_odometer)
);
CREATE TABLE trips (
    trip_id SERIAL PRIMARY KEY, vehicle_id INT REFERENCES vehicles(vehicle_id), trip_on DATE,
    start_odometer INT, end_odometer INT, CHECK (end_odometer > start_odometer)
);
CREATE TABLE service_alerts (vehicle_id INT PRIMARY KEY REFERENCES vehicles(vehicle_id), km_since_service INT, flagged_on DATE);

INSERT INTO vehicles (registration, current_odometer, last_service_odometer) VALUES ('V1', 10000, 5000), ('V2', 4000, 4000), ('V3', 15000, 10000);

-- (b) Function
CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INT) RETURNS BOOLEAN AS $$
DECLARE v_diff INT;
BEGIN
    SELECT current_odometer - last_service_odometer INTO v_diff FROM vehicles WHERE vehicle_id = p_vehicle_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
    RETURN v_diff >= 5000;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INT, p_trip_on DATE, p_start INT, p_end INT) LANGUAGE plpgsql AS $$
DECLARE v_curr INT;
BEGIN
    SELECT current_odometer INTO v_curr FROM vehicles WHERE vehicle_id = p_vehicle_id;
    IF p_end <= p_start THEN RAISE EXCEPTION 'End must be greater than start'; END IF;
    IF p_start <> v_curr THEN RAISE EXCEPTION 'Start must match current odometer'; END IF;
    INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer) VALUES (p_vehicle_id, p_trip_on, p_start, p_end);
    UPDATE vehicles SET current_odometer = p_end WHERE vehicle_id = p_vehicle_id;
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_trip_insert() RETURNS TRIGGER AS $$
DECLARE v_curr INT;
BEGIN
    SELECT current_odometer INTO v_curr FROM vehicles WHERE vehicle_id = NEW.vehicle_id FOR UPDATE;
    IF NEW.start_odometer <> v_curr THEN RAISE EXCEPTION 'Start odometer mismatch'; END IF;
    IF NEW.end_odometer <= NEW.start_odometer THEN RAISE EXCEPTION 'Invalid mileage'; END IF;
    UPDATE vehicles SET current_odometer = NEW.end_odometer WHERE vehicle_id = NEW.vehicle_id;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER before_trip_insert BEFORE INSERT ON trips FOR EACH ROW EXECUTE FUNCTION trg_trip_insert();

-- (e) View
CREATE VIEW v_service_due AS
SELECT registration, (current_odometer - last_service_odometer) AS km_since_service
FROM vehicles WHERE (current_odometer - last_service_odometer) >= 5000;

-- (f) Index
CREATE INDEX idx_trips_vehicle_date ON trips(vehicle_id, trip_on);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts() LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM service_alerts WHERE vehicle_id IN (SELECT vehicle_id FROM vehicles WHERE current_odometer - last_service_odometer < 5000);
    INSERT INTO service_alerts (vehicle_id, km_since_service, flagged_on)
    SELECT vehicle_id, current_odometer - last_service_odometer, CURRENT_DATE
    FROM vehicles WHERE current_odometer - last_service_odometer >= 5000
    ON CONFLICT (vehicle_id) DO UPDATE SET km_since_service = EXCLUDED.km_since_service, flagged_on = EXCLUDED.flagged_on;
END; $$;