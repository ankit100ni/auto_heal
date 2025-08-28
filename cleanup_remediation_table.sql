-- SQL Queries to Clean Up Remediation Table
-- Run these queries to ensure consistent NULL/empty handling

-- 1. First, let's see the current state of the table
SELECT 
    Inspec_Control_ID,
    CASE 
        WHEN Remediation_File IS NULL THEN 'NULL'
        WHEN Remediation_File = '' THEN 'EMPTY_STRING'
        ELSE CONCAT('VALUE: ', Remediation_File)
    END as File_Status,
    CASE 
        WHEN Remediation_Command IS NULL THEN 'NULL'
        WHEN Remediation_Command = '' THEN 'EMPTY_STRING'
        ELSE CONCAT('VALUE: ', Remediation_Command)
    END as Command_Status
FROM remediation
ORDER BY Inspec_Control_ID;

-- 2. Update all empty strings to NULL for consistency
UPDATE remediation 
SET Remediation_File = NULL 
WHERE Remediation_File = '';

UPDATE remediation 
SET Remediation_Command = NULL 
WHERE Remediation_Command = '';

-- 3. For controls that should have NULL values (xccdf controls), ensure they are NULL
UPDATE remediation 
SET Remediation_File = NULL, Remediation_Command = NULL 
WHERE Inspec_Control_ID LIKE 'xccdf_%';

-- 4. For the empty row (if it exists), either delete it or set proper values
DELETE FROM remediation 
WHERE Inspec_Control_ID = '' OR Inspec_Control_ID IS NULL;

-- 5. For the systemd-journal-remote control that has empty values, set them to NULL
UPDATE remediation 
SET Remediation_File = NULL, Remediation_Command = NULL 
WHERE Inspec_Control_ID = 'xccdf_org.cisecurity.benchmarks_rule_4.2.1.1.3_Ensure_systemd-journal-remote_is_enabled';

-- 6. Verify the final state - all should show either NULL or actual values
SELECT 
    Inspec_Control_ID,
    CASE 
        WHEN Remediation_File IS NULL THEN 'NULL'
        ELSE CONCAT('VALUE: ', Remediation_File)
    END as File_Status,
    CASE 
        WHEN Remediation_Command IS NULL THEN 'NULL'
        ELSE CONCAT('VALUE: ', Remediation_Command)
    END as Command_Status
FROM remediation
ORDER BY Inspec_Control_ID;
