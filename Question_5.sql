-- (a) Tables
CREATE TABLE Students (student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(100));
CREATE TABLE Rooms (room_id SERIAL PRIMARY KEY, room_number VARCHAR(10) UNIQUE, capacity INT CHECK (capacity > 0));
CREATE TABLE Allocations (
    allocation_id SERIAL PRIMARY KEY, student_id INT REFERENCES Students(student_id), room_id INT REFERENCES Rooms(room_id),
    allocated_on DATE, released_on DATE NULL, status VARCHAR(10) CHECK (status IN ('ACTIVE', 'ENDED')),
    CHECK ((status = 'ACTIVE' AND released_on IS NULL) OR (status = 'ENDED' AND released_on IS NOT NULL))
);
CREATE TABLE occupancy_snapshot (snapshot_date DATE, room_id INT REFERENCES Rooms(room_id), occupied_beds INT, free_beds INT, PRIMARY KEY (snapshot_date, room_id));

INSERT INTO Rooms (room_number, capacity) VALUES ('R1', 2), ('R2', 2), ('R3', 1);
INSERT INTO Students (student_number, full_name) VALUES ('S1', 'Alice'), ('S2', 'Bob');

-- (b) Function
CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INT) RETURNS INT AS $$
DECLARE v_cap INT; v_occ INT;
BEGIN
    SELECT capacity INTO v_cap FROM Rooms WHERE room_id = p_room_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown room'; END IF;
    SELECT COUNT(*) INTO v_occ FROM Allocations WHERE room_id = p_room_id AND status = 'ACTIVE';
    RETURN v_cap - v_occ;
END; $$ LANGUAGE plpgsql;

-- (c) Procedure
CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INT, p_room_id INT, p_allocated_on DATE) LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Allocations WHERE student_id = p_student_id AND status = 'ACTIVE') THEN RAISE EXCEPTION 'Student already has active allocation'; END IF;
    IF fn_free_beds(p_room_id) <= 0 THEN RAISE EXCEPTION 'No beds available'; END IF;
    INSERT INTO Allocations (student_id, room_id, allocated_on, status) VALUES (p_student_id, p_room_id, p_allocated_on, 'ACTIVE');
END; $$;

-- (d) Trigger
CREATE OR REPLACE FUNCTION trg_enforce_capacity() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'ACTIVE' THEN
        IF (SELECT COUNT(*) FROM Allocations WHERE room_id = NEW.room_id AND status = 'ACTIVE' AND allocation_id <> COALESCE(NEW.allocation_id, -1)) >= (SELECT capacity FROM Rooms WHERE room_id = NEW.room_id) THEN
            RAISE EXCEPTION 'Room capacity exceeded';
        END IF;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER before_allocation_insert_update BEFORE INSERT OR UPDATE ON Allocations FOR EACH ROW EXECUTE FUNCTION trg_enforce_capacity();

-- (e) View
CREATE VIEW v_room_occupancy AS
SELECT r.room_id, r.room_number, r.capacity, 
       COALESCE(COUNT(a.allocation_id), 0) AS occupied_beds,
       r.capacity - COALESCE(COUNT(a.allocation_id), 0) AS free_beds
FROM Rooms r LEFT JOIN Allocations a ON r.room_id = a.room_id AND a.status = 'ACTIVE'
GROUP BY r.room_id, r.room_number, r.capacity;

-- (f) Index
CREATE INDEX idx_alloc_room_status ON Allocations(room_id, status);

-- (g) Scheduled Job
CREATE OR REPLACE PROCEDURE pr_refresh_occupancy() LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM occupancy_snapshot WHERE snapshot_date = CURRENT_DATE;
    INSERT INTO occupancy_snapshot (snapshot_date, room_id, occupied_beds, free_beds)
    SELECT CURRENT_DATE, room_id, occupied_beds, free_beds FROM v_room_occupancy;
END; $$;