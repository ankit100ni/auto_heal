-- Single comprehensive query to clean up remediation table
-- This will standardize all NULL/empty values

-- Step 1: Convert all empty strings to NULL
UPDATE remediation SET Remediation_File = NULL WHERE Remediation_File = '';
UPDATE remediation SET Remediation_Command = NULL WHERE Remediation_Command = '';

-- Step 2: Ensure xccdf controls have NULL values (since they don't have remediation files/commands)
UPDATE remediation 
SET Remediation_File = NULL, Remediation_Command = NULL 
WHERE Inspec_Control_ID LIKE 'xccdf_%';

-- Step 3: Remove any completely empty rows
DELETE FROM remediation 
WHERE (Inspec_Control_ID = '' OR Inspec_Control_ID IS NULL);

-- Step 4: Set systemd-journal-remote to NULL (as it appears to have no remediation)
UPDATE remediation 
SET Remediation_File = NULL, Remediation_Command = NULL 
WHERE Inspec_Control_ID = 'xccdf_org.cisecurity.benchmarks_rule_4.2.1.1.3_Ensure_systemd-journal-remote_is_enabled';
