CREATE TABLE Patients
(
  patient_id INT,
  patient_number INT NOT NULL,
  gender VARCHAR(30) NOT NULL,
  dob DATETIME,
  dod DATETIME,
  expire_flag BOOLEAN NOT NULL,
  PRIMARY KEY (patient_id)
);

insert into Patients(patient_id,patient_number,dob,dod,expire_flag)
select row_id,SUBJECT_ID,dob,dod,expire_flag
from Patients_OG;


CREATE TABLE Service
(
  service_id INT AUTO_INCREMENT,
  curr_careunit VARCHAR(250),
  PRIMARY KEY (service_id)
);


INSERT INTO Service (curr_careunit)
SELECT DISTINCT CURR_SERVICE
FROM services_og


CREATE TABLE Admission_Type
(
  admission_type_id INT AUTO_INCREMENT,
  type VARCHAR(200),
  PRIMARY KEY (admission_type_id)
);

insert into Admission_Type(type)
select patient_id,patient_number,dob,dod,expire_flag
from admissions_OG;


CREATE TABLE Diagnose
(
  diagnoses_id INT,
  seq_num INT,
  ICD9_Code VARCHAR(10) ,
  title VARCHAR(200),
  PRIMARY KEY (diagnoses_id)
);



INSERT INTO Diagnose (diagnoses_id, seq_num, ICD9_Code, title)
SELECT
  DO.ROW_ID AS diagnoses_id,
  DO.SEQ_NUM AS seq_num,
  DO.ICD9_CODE AS ICD9_Code,
  DD.SHORT_TITLE AS title
FROM
  Diagnoses_OG DO
JOIN
  D_DIAGNOSES_OG DD ON DO.ICD9_CODE = DD.ICD9_CODE;




CREATE TABLE Procedures
(
  procedure_id INT,
  seq_num INT NOT NULL,
  ICD9_Code VARCHAR(200),
  title VARCHAR(200),
  PRIMARY KEY (procedure_id)
);


INSERT INTO Procedures (procedure_id, seq_num, ICD9_Code, title)
SELECT
  DO.ROW_ID AS procedure_id,
  DO.SEQ_NUM AS seq_num,
  DO.ICD9_CODE AS ICD9_Code,
  DD.SHORT_TITLE AS title
FROM
  Procedures_OG DO
JOIN
  D_Procedure_OG DD ON DO.ICD9_CODE = DD.ICD9_CODE;

CREATE TABLE Time
(
  time_id INT AUTO_INCREMENT,
  minute INT ,
  hour INT ,
  day INT ,
  month INT ,
  year INT,
  PRIMARY KEY (time_id)
);


-- For ADMITTIME
INSERT INTO Time (minute, hour, day, month, year)
SELECT
    EXTRACT(MINUTE FROM ADMITTIME) AS minute,
    EXTRACT(HOUR FROM ADMITTIME) AS hour,
    EXTRACT(DAY FROM ADMITTIME) AS day,
    EXTRACT(MONTH FROM ADMITTIME) AS month,
    EXTRACT(YEAR FROM ADMITTIME) AS year
FROM admissions_og;

-- For DISCHTIME
INSERT INTO Time (minute, hour, day, month, year)
SELECT
    EXTRACT(MINUTE FROM DISCHTIME) AS minute,
    EXTRACT(HOUR FROM DISCHTIME) AS hour,
    EXTRACT(DAY FROM DISCHTIME) AS day,
    EXTRACT(MONTH FROM DISCHTIME) AS month,
    EXTRACT(YEAR FROM DISCHTIME) AS year
FROM admissions_og;



CREATE TABLE Diagnoses_Group
(
  diagnoses_group_id INT NOT NULL,
  diagnoses_id INT NOT NULL,
  weight FLOAT,
  PRIMARY KEY (diagnoses_group_id)
);

INSERT INTO Diagnoses_Group (diagnoses_group_id, diagnoses_id, weight)
SELECT
    d.HADM_ID AS diagnoses_group_id,
    d.ROW_ID AS diagnoses_id,
    1.0 / COUNT(DISTINCT o.ROW_ID) AS weight
FROM Diagnoses_OG d
JOIN Diagnoses_OG o ON d.HADM_ID = o.HADM_ID
GROUP BY d.HADM_ID, d.ROW_ID;

CREATE TABLE Procedures_Group
(
  procedures_group_id INT,
  procedure_id INT NOT NULL,
  weight FLOAT
);


INSERT INTO Procedures_Group (procedures_group_id, procedure_id, weight)
SELECT
    d.HADM_ID AS procedures_group_id,
    d.ROW_ID AS procedure_id,
    1.0 / COUNT(DISTINCT o.ROW_ID) AS weight
FROM Procedures_OG d
JOIN Procedures_OG o ON d.HADM_ID = o.HADM_ID
GROUP BY d.HADM_ID, d.ROW_ID;

CREATE TABLE Hospitalization
(
  hospitalization_number INT, --ADMISSIONS
  icu_stay BOOLEAN,   -- ICUSTAYS
  duration INT,       
  n_diagones INT,     -- count (diagnoses_group_id)
  patient_id INT NOT NULL, --ADMISSIONS
  service_id INT NOT NULL, -- HADM_ID SERVICE
  admission_type_id INT NOT NULL, --admssion type admissions table = type from admission type table
  diagnoses_group_id INT NULL, --HADM_ID
  admit_time_id INT NOT NULL,
  disch_time_id INT NOT NULL,
  FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
  FOREIGN KEY (service_id) REFERENCES Service(service_id),
  FOREIGN KEY (admission_type_id) REFERENCES Admission_Type(admission_type_id),
  FOREIGN KEY (admit_time_id) REFERENCES Time(time_id),
  FOREIGN KEY (disch_time_id) REFERENCES Time(time_id)
);

INSERT INTO Hospitalization (hospitalization_number, patient_id, admission_type_id, service_id, admit_time_id, disch_time_id, icu_stay)
SELECT
    o.HADM_ID,
    p.patient_id,
    a.admission_type_id,
    ser.service_id,
    admit_time.time_id AS admit_time_id,
    disch_time.time_id AS disch_time_id,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM icustays_og i
            WHERE i.HADM_ID = o.HADM_ID
        ) THEN 1
        ELSE 0
    END AS icu_stay
FROM
    admissions_og AS o
JOIN
    admission_type AS a ON o.admission_type = a.type
JOIN
    patients AS p ON o.subject_id = p.patient_id
JOIN
    services_og AS s ON o.HADM_ID = s.HADM_ID
JOIN
    service AS ser ON s.CURR_SERVICE = ser.curr_careunit
JOIN
    time AS admit_time ON o.ADMITTIME = CONCAT(admit_time.year, '-', admit_time.month, '-', admit_time.day, ' ', admit_time.hour, ':', admit_time.minute, ':00')
JOIN
    time AS disch_time ON o.DISCHTIME = CONCAT(disch_time.year, '-', disch_time.month, '-', disch_time.day, ' ', disch_time.hour, ':', disch_time.minute, ':00');


UPDATE hospitalization
SET diagnoses_group_id = hospitalization_number;


UPDATE hospitalization
FROM admissions_og AS o
SET hospitalization_number = o.hospitalization_number;


UPDATE hospitalization h
JOIN (
    SELECT diagnoses_group_id, COUNT(*) AS count_per_group
    FROM Diagnoses_Group
    GROUP BY diagnoses_group_id
) dg_count ON h.diagnoses_group_id = dg_count.diagnoses_group_id
SET h.n_diagones = dg_count.count_per_group;


UPDATE hospitalization h
JOIN time t_admit ON h.admit_time_id = t_admit.time_id
JOIN time t_disch ON h.disch_time_id = t_disch.time_id
SET h.duration = TIMESTAMPDIFF(MINUTE, 
                                CONCAT(t_admit.year, '-', t_admit.month, '-', t_admit.day, ' ', t_admit.hour, ':', t_admit.minute, ':00'), 
                                CONCAT(t_disch.year, '-', t_disch.month, '-', t_disch.day, ' ', t_disch.hour, ':', t_disch.minute, ':00')
                             );




INSERT INTO Service (service_id, curr_careunit)
SELECT HADM_ID, CURR_SERVICE
FROM services_og
WHERE (HADM_ID, TRANSFERTIME) IN (
    SELECT HADM_ID, MAX(TRANSFERTIME) AS LatestTransferTime
    FROM services_og
    GROUP BY HADM_ID
)
ON DUPLICATE KEY UPDATE curr_careunit = VALUES(curr_careunit);





create table Treatments
   (patient_id integer REFERENCES Patients(patient_id),
    procedures_group_id int,
    total_n_treatment INT);

INSERT INTO Treatments (total_n_treatment, patient_id, Procedures_Group_id)
SELECT COUNT(hadm_id) AS total_n_treatment,
       subject_id AS patient_id,
       hadm_id AS ProceduresGroup_id
FROM procedures_og
GROUP BY subject_id, hadm_id;




