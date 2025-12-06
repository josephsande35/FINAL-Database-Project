-- Run after connecting as postgres superuser
CREATE DATABASE blood_donation_db;
\c blood_donation_db;

-- Person (Superclass)
CREATE TABLE Person (
    Person_ID SERIAL PRIMARY KEY,
    First_name VARCHAR(50) NOT NULL CHECK (First_name ~ '^[A-Za-z ]+$'),
    Last_name VARCHAR(50) NOT NULL CHECK (Last_name ~ '^[A-Za-z ]+$'),
    Contact VARCHAR(15) NOT NULL CHECK (Contact ~ '^[+]?[0-9]{10,15}$')
);

-- Donor subclass
CREATE TABLE Donor (
    Donor_ID SERIAL PRIMARY KEY,
    Person_ID INT UNIQUE REFERENCES Person(Person_ID) ON DELETE CASCADE,
    Date_Last_Donation DATE CHECK (Date_Last_Donation <= CURRENT_DATE),
    Blood_Type VARCHAR(5) NOT NULL CHECK (Blood_Type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-'))
);

-- Staff subclass + sub-subclasses
CREATE TABLE Staff (
    Staff_ID SERIAL PRIMARY KEY,
    Person_ID INT UNIQUE REFERENCES Person(Person_ID) ON DELETE CASCADE,
    Job_Role VARCHAR(50) NOT NULL,
    Staff_Email VARCHAR(100) UNIQUE NOT NULL CHECK (Staff_Email ~ '.*@.*\..*')
);

CREATE TABLE Field_Staff (
    Field_Staff_ID SERIAL PRIMARY KEY,
    Staff_ID INT UNIQUE REFERENCES Staff(Staff_ID) ON DELETE CASCADE,
    Staff_Email VARCHAR(100) NOT NULL
);

CREATE TABLE Drive_Staff (
    Drive_Staff_ID SERIAL PRIMARY KEY,
    Staff_ID INT UNIQUE REFERENCES Staff(Staff_ID) ON DELETE CASCADE,
    Staff_Email VARCHAR(100) NOT NULL
);

-- Other entities
CREATE TABLE Drive_Event (
    Event_ID SERIAL PRIMARY KEY,
    Location VARCHAR(200) NOT NULL,
    Date DATE NOT NULL CHECK (Date >= CURRENT_DATE),
    Capacity INT NOT NULL CHECK (Capacity > 0)
);

CREATE TABLE Appointment (
    Appointment_ID SERIAL PRIMARY KEY,
    Donor_ID INT REFERENCES Donor(Donor_ID) ON DELETE SET NULL,
    Event_ID INT REFERENCES Drive_Event(Event_ID) ON DELETE CASCADE,
    Time_Slot TIME NOT NULL,
    Status VARCHAR(20) DEFAULT 'Scheduled' CHECK (Status IN ('Scheduled','Confirmed','Completed','Cancelled','No-Show'))
);

CREATE TABLE Blood_Unit (
    Unit_ID SERIAL PRIMARY KEY,
    Donor_ID INT REFERENCES Donor(Donor_ID) ON DELETE SET NULL,
    Collection_Date DATE NOT NULL DEFAULT CURRENT_DATE CHECK (Collection_Date <= CURRENT_DATE),
    Volume DECIMAL(5,2) CHECK (Volume BETWEEN 350.00 AND 500.00),
    Status VARCHAR(20) DEFAULT 'Collected' CHECK (Status IN ('Collected','Tested','Approved','Rejected','Distributed'))
);

CREATE TABLE Screen_Testing (
    Test_ID SERIAL PRIMARY KEY,
    Unit_ID INT UNIQUE REFERENCES Blood_Unit(Unit_ID) ON DELETE CASCADE,
    Test_Date DATE NOT NULL DEFAULT CURRENT_DATE CHECK (Test_Date <= CURRENT_DATE),
    Results_Status VARCHAR(20) CHECK (Results_Status IN ('Pass','Fail','Pending'))
);

CREATE TABLE Inventory (
    Inventory_ID SERIAL PRIMARY KEY,
    Unit_ID INT UNIQUE REFERENCES Blood_Unit(Unit_ID) ON DELETE CASCADE,
    Collection_Date DATE NOT NULL,
    Amount DECIMAL(6,2) NOT NULL CHECK (Amount > 0)
);


-- Create secure users/roles
CREATE ROLE donor_role NOLOGIN; CREATE ROLE field_staff_role NOLOGIN; 
CREATE ROLE drive_staff_role NOLOGIN; CREATE ROLE admin_role NOLOGIN;

CREATE USER donor_user PASSWORD 'donor123'; CREATE USER fieldstaff_user PASSWORD 'field123';
CREATE USER drivestaff_user PASSWORD 'drive123'; CREATE USER admin_user PASSWORD 'admin123';

GRANT donor_role TO donor_user; GRANT field_staff_role TO fieldstaff_user;
GRANT drive_staff_role TO drivestaff_user; GRANT admin_role TO admin_user;

-- Views for role-based access
CREATE VIEW donor_view AS
SELECT d.Donor_ID, p.First_name||' '||p.Last_name as Name, d.Blood_Type, d.Date_Last_Donation,
       a.Status, de.Location, de.Date as Event_Date
FROM Donor d JOIN Person p ON d.Person_ID=p.Person_ID 
LEFT JOIN Appointment a ON d.Donor_ID=a.Donor_ID 
LEFT JOIN Drive_Event de ON a.Event_ID=de.Event_ID;

CREATE VIEW drive_staff_view AS
SELECT de.*, COUNT(a.Appointment_ID) as Booked_Slots
FROM Drive_Event de LEFT JOIN Appointment a ON de.Event_ID=a.Event_ID 
GROUP BY de.Event_ID;

-- Grant privileges
GRANT SELECT ON donor_view TO donor_role;
GRANT SELECT,INSERT,UPDATE ON drive_staff_view,Drive_Event,Appointment TO drive_staff_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO admin_role;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO admin_role;



-- Procedure: Donor eligibility check
CREATE OR REPLACE PROCEDURE check_donor_eligibility(donor_id INT)
LANGUAGE plpgsql AS $$
DECLARE last_donation DATE;
BEGIN
    SELECT Date_Last_Donation INTO last_donation FROM Donor WHERE Donor_ID=donor_id;
    IF last_donation IS NULL OR (CURRENT_DATE - last_donation)>=112 THEN
        RAISE NOTICE 'Donor % eligible', donor_id;
    ELSE RAISE EXCEPTION 'Wait until %', last_donation + INTERVAL '112 days';
    END IF;
END;
$$;

-- Trigger: Update donor last donation
CREATE OR REPLACE FUNCTION update_donor_last_donation() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Status='Completed' THEN
        UPDATE Donor SET Date_Last_Donation=CURRENT_DATE WHERE Donor_ID=NEW.Donor_ID;
    END IF; RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_appointment_completed AFTER UPDATE ON Appointment 
FOR EACH ROW EXECUTE FUNCTION update_donor_last_donation();

-- ========================================
-- SAMPLE DATA FOR blood_donation_db
-- ========================================

-- 1. Insert People (base table for inheritance)
INSERT INTO Person (First_name, Last_name, Contact) VALUES
('Aarav', 'Sharma', '+919876543210'),
('Priya', 'Patel', '+918765432109'),
('Rahul', 'Verma', '+919912345678'),
('Sneha', 'Mehta', '+917890123456'),
('Vikram', 'Singh', '+919834567890'),
('Ananya', 'Reddy', '+918901234567'),
('Rohan', 'Gupta', '+919567890123'),
('Ishita', 'Joshi', '+917654890321'),
('Arjun', 'Kumar', '+919223344556'),
('Neha', 'Malhotra', '+918877665544');

-- 2. Donors
INSERT INTO Donor (Person_ID, Date_Last_Donation, Blood_Type) VALUES
(1, '2025-07-20', 'O+'),      -- Aarav
(2, '2025-08-15', 'A-'),      -- Priya
(3, NULL, 'B+'),             -- Rahul – never donated yet
(4, '2025-06-10', 'AB+'),     -- Sneha
(5, '2025-09-01', 'O-'),      -- Vikram
(6, NULL, 'A+'),             -- Ananya – eligible
(7, '2025-10-05', 'B-');      -- Rohan

-- 3. Staff (general)
INSERT INTO Person (First_name, Last_name, Contact) VALUES
('Dr. Sameer', 'Khan', '+919900112233'),
('Nurse Lakshmi', 'Nair', '+919988776655'),
('Rajesh', 'Yadav', '+919977665544'),
('Pooja', 'Deshmukh', '+919955443322');

INSERT INTO Staff (Person_ID, Job_Role, Staff_Email) VALUES
(11, 'Medical Officer', 'sameer.khan@bloodbank.org'),
(12, 'Nurse', 'lakshmi.nair@bloodbank.org'),
(13, 'Field Coordinator', 'rajesh.yadav@bloodbank.org'),
(14, 'Phlebotomist', 'pooja.d@bloodbank.org');

-- Subclasses of Staff
INSERT INTO Field_Staff (Staff_ID, Staff_Email) VALUES
((SELECT Staff_ID FROM Staff WHERE Staff_Email='rajesh.yadav@bloodbank.org'), 'rajesh.yadav@bloodbank.org');

INSERT INTO Drive_Staff (Staff_ID, Staff_Email) VALUES
((SELECT Staff_ID FROM Staff WHERE Staff_Email='pooja.d@bloodbank.org'), 'pooja.d@bloodbank.org'),
((SELECT Staff_ID FROM Staff WHERE Staff_Email='lakshmi.nair@bloodbank.org'), 'lakshmi.nair@bloodbank.org');

-- 4. Upcoming Blood Drive Events
INSERT INTO Drive_Event (Location, Date, Capacity) VALUES
('Juhu Beach Community Hall, Mumbai', '2025-12-20', 80),
('Infotech Park, Hinjewadi, Pune', '2025-12-22', 120),
('Koramangala Indoor Stadium, Bangalore', '2025-12-28', 150),
('Anna Nagar Tower Park, Chennai', '2026-01-05', 100),
('Sector 17 Plaza, Chandigarh', '2026-01-12', 60);

-- 5. Appointments (some confirmed, some still scheduled)
INSERT INTO Appointment (Donor_ID, Event_ID, Time_Slot, Status) VALUES
(1, 1, '09:30:00', 'Confirmed'),
(2, 1, '10:00:00', 'Confirmed'),
(3, 1, '11:00:00', 'Scheduled'),
(4, 2, '14:00:00', 'Scheduled'),
(5, 2, '14:30:00', 'Confirmed'),
(6, 3, '10:30:00', 'Scheduled'),
(7, 3, '11:30:00', 'Scheduled'),
(1, 4, '09:00:00', 'Scheduled');  -- Aarav wants to donate again (will be blocked by eligibility rule if <112 days)

-- 6. Some past completed appointments → generate blood units
-- (we'll mark a couple as Completed so trigger updates Date_Last_Donation and we can insert units)
UPDATE Appointment SET Status = 'Completed' WHERE Appointment_ID IN (1,2,5);

-- Now insert the collected blood units from those completed appointments
INSERT INTO Blood_Unit (Donor_ID, Collection_Date, Volume, Status) VALUES
(1, '2025-12-20', 450.00, 'Collected'),
(2, '2025-12-20', 420.00, 'Collected'),
(5, '2025-12-22', 480.00, 'Collected');

-- 7. Screening/Testing results
INSERT INTO Screen_Testing (Unit_ID, Test_Date, Results_Status) VALUES
(1, '2025-12-21', 'Pass'),
(2, '2025-12-21', 'Pass'),
(3, '2025-12-23', 'Fail');  -- just one bad unit for realism

-- Update blood unit status accordingly
UPDATE Blood_Unit SET Status = 'Approved' WHERE Unit_ID IN (1,2);
UPDATE Blood_Unit SET Status = 'Rejected' WHERE Unit_ID = 3;

-- 8. Inventory (approved units only)
INSERT INTO Inventory (Unit_ID, Collection_Date, Amount) VALUES
(1, '2025-12-20', 450.00),
(2, '2025-12-20', 420.00);

-- ========================================
-- Quick verification queries you can run
-- ========================================

-- See what donors see
SELECT * FROM donor_view ORDER BY Donor_ID;

-- See what drive staff see
SELECT * FROM drive_staff_view ORDER BY Date;

-- Check donor eligibility with the procedure
CALL check_donor_eligibility(1);  -- Aarav just donated → should raise exception
CALL check_donor_eligibility(3);  -- Rahul never donated → eligible
CALL check_donor_eligibility(6);  -- Ananya never donated → eligible

-- Current blood inventory
SELECT i.*, bu.Blood_Type, p.First_name || ' ' || p.Last_name AS Donor_Name
FROM Inventory i
JOIN Blood_Unit bu ON i.Unit_ID = bu.Unit_ID
JOIN Donor d ON bu.Donor_ID = d.Donor_ID
JOIN Person p ON d.Person_ID = p.Person_ID;



