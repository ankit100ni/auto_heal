#!/bin/bash

# Database Credentials
DB_HOST="sql12.freesqldatabase.com"
DB_USER="sql12760516"
DB_PASS="$1"  # Pass as an argument
DB_NAME="sql12760516"
MASTER_TABLE="master"
REMEDIATION_TABLE="remediation"

# ServiceNow API Credentials
SNOW_INSTANCE="dev231713.service-now.com"
SNOW_USER="admin"
SNOW_PASS="D8a2/-IYhhoO"
SNOW_API_URL="https://$SNOW_INSTANCE.service-now.com/api/now/table/incident"

# Fetch all rows with Incident_Status = 'New'
QUERY="SELECT Primary_Key, Incident_Number, Inspec_Control_ID FROM $MASTER_TABLE WHERE Incident_Status='New';"

RESULTS=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "$QUERY")

# Loop through each result
while IFS=$'\t' read -r PRIMARY_KEY INCIDENT_NUMBER CONTROL_ID; do
    echo "Processing Incident: $INCIDENT_NUMBER for Control ID: $CONTROL_ID"

    # Add comment in ServiceNow ticket
    COMMENT="Automation Bot is looking into the ticket."
    curl -s -u "$SNOW_USER:$SNOW_PASS" -X PUT "$SNOW_API_URL/$INCIDENT_NUMBER" \
        -H "Content-Type: application/json" \
        -d "{\"comments\": \"$COMMENT\", \"state\": \"2\"}" > /dev/null

    # Update Incident_Status to 'In Progress' in master table
    UPDATE_QUERY="UPDATE $MASTER_TABLE SET Incident_Status='In Progress' WHERE Primary_Key='$PRIMARY_KEY';"
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$UPDATE_QUERY"

    # Fetch remediation command and file
    REM_QUERY="SELECT Remediation_Command, Remediation_File FROM $REMEDIATION_TABLE WHERE Inspec_Control_ID='$CONTROL_ID';"
    REM_COMMAND=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "$REM_QUERY")

    # Extract the file name from the command
    REM_FILE=$(echo "$REM_COMMAND" | awk '{print $4}')

    if [ -n "$REM_COMMAND" ]; then
        # Download the remediation script
        echo "Downloading remediation script: $REM_FILE"
        sudo wget -P /home/ubuntu/ "https://raw.githubusercontent.com/ankit100ni/auto_heal/refs/heads/main/job_scripts/$REM_FILE"
        
        # Give the script execute permission
        sudo chmod +x "/home/ubuntu/$REM_FILE"

        # Execute the remediation script
        echo "Executing remediation script: $REM_FILE"
        sudo /home/ubuntu/$REM_FILE
    else
        echo "No remediation command found for Control ID: $CONTROL_ID"
    fi
done <<< "$RESULTS"

echo "Automation process completed."

