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




