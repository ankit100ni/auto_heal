-- Query to remove duplicate entries from both tables
-- This will keep only the first occurrence of each Node_ID + Inspec_Control_ID combination

-- First, create a temporary table with the minimum Primary_Key for each unique combination
CREATE TEMPORARY TABLE temp_unique_entries AS
SELECT MIN(Primary_Key) as Primary_Key
FROM pre_scan
GROUP BY Node_ID, Inspec_Control_ID;

-- Delete duplicates from master table (keep only those in temp table)
DELETE FROM master 
WHERE Primary_Key NOT IN (SELECT Primary_Key FROM temp_unique_entries);

-- Delete duplicates from pre_scan table (keep only those in temp table)
DELETE FROM pre_scan 
WHERE Primary_Key NOT IN (SELECT Primary_Key FROM temp_unique_entries);

-- Drop temporary table
DROP TEMPORARY TABLE temp_unique_entries;

-- Verify the cleanup
SELECT 'After cleanup - pre_scan count:' as info, COUNT(*) as count FROM pre_scan
UNION ALL
SELECT 'After cleanup - master count:' as info, COUNT(*) as count FROM master;
