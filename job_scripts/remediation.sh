#!/bin/bash


source /root/.db_config
# Database Credentials
# DB_HOST="mysql-2392fef6-ankit10093-528e.k.aivencloud.com"
# DB_USER="avnadmin"
# DB_PASS="$1"  # Get password from the first argument
# DB_NAME="defaultdb"
# DB_PORT="19635"
TABLE_NAME="pre_scan"
MASTER_TABLE="master"
REMEDIATION_TABLE="remediation"

# ServiceNow API Credentials
# SNOW_INSTANCE="dev198775"
# SNOW_USER="admin"
# SNOW_PASS="mBkb^B1Fd%X1"
SNOW_API_URL="https://$SNOW_INSTANCE_NAME.service-now.com/api/now/table/incident"

# Fetch Node_ID from file
NODE_ID=$(cat /hab/svc/node-management-agent/data/node_guid | tr -d '[:space:]')

# Fetch all rows with Incident_Status = 'New' and matching Node_ID
QUERY="SELECT Primary_Key, Incident_Number, Inspec_Control_ID FROM $MASTER_TABLE WHERE Incident_Status='New' AND Node_ID='$NODE_ID';"

RESULTS=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "$QUERY")

# Loop through each result
while IFS=$'\t' read -r PRIMARY_KEY INCIDENT_NUMBER CONTROL_ID; do
    echo "Processing Incident: $INCIDENT_NUMBER for Control ID: $CONTROL_ID"

    # Fetch sys_id for the given Incident_Number
    SYS_ID=$(curl -s -u "$SNOW_USER:$SNOW_PASS" -X GET "$SNOW_API_URL?sysparm_query=number=$INCIDENT_NUMBER" \
        -H "Accept: application/json" | jq -r '.result[0].sys_id')

    if [ -z "$SYS_ID" ]; then
        echo "Error: Incident with number $INCIDENT_NUMBER not found."
        continue
    fi

    # Fetch remediation command and file
    REM_QUERY="SELECT Remediation_Command, Remediation_File FROM $REMEDIATION_TABLE WHERE Inspec_Control_ID='$CONTROL_ID';"
    REM_RESULT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "$REM_QUERY")

    # Extract values
    REM_COMMAND=$(echo "$REM_RESULT" | awk -F'\t' '{print $1}')
    REM_FILE=$(echo "$REM_RESULT" | awk -F'\t' '{print $2}')

    # If both remediation file and command are empty, update ServiceNow ticket and continue
    if { [ -z "$REM_FILE" ] || [ "$REM_FILE" = "NULL" ]; } && { [ -z "$REM_COMMAND" ] || [ "$REM_COMMAND" = "NULL" ]; }; then
        # Call external API
        KB_API_URL="https://progress-proc-us-east-2-1.syntha.progress.com/api/v1/kb/42cc87ce-4939-464a-830f-b0a27f296dbd/ask"
        KB_API_TOKEN="$NUCLIA_API_KEY"
        KB_QUERY="Provide Remediation steps for $CONTROL_ID"
        KB_SEARCH_CONFIG="Inspec_Compliance"
        TMP_KB_FILE=$(mktemp)

        curl --location --request POST "$KB_API_URL" \
            --header "X-NUCLIA-SERVICEACCOUNT: $KB_API_TOKEN" \
            --header "content-type: application/json" \
            --data-raw "{\"query\": \"$KB_QUERY\", \"search_configuration\": \"$KB_SEARCH_CONFIG\"}" \
            -o "$TMP_KB_FILE"

        echo "KB API response saved to $TMP_KB_FILE"

        # Check if KB API response contains item
        if jq -e '.item' "$TMP_KB_FILE" >/dev/null; then
            # Concatenate all "text" values under .item.type == "answer" into a single string
            KB_ANSWER_RAW=$(jq -r 'select(.item.type == "answer") | .item.text' "$TMP_KB_FILE" | paste -sd "" -)
            # Replace literal \n with actual newlines for formatting
            KB_ANSWER_FORMATTED=$(echo "$KB_ANSWER_RAW" | sed 's/\\n/\n/g')
            # Write to a fixed filename
            KB_ANSWER_FILE="/tmp/kb_remediation_${INCIDENT_NUMBER}.txt"
            echo -e "$KB_ANSWER_FORMATTED" > "$KB_ANSWER_FILE"
            sync  # Ensure file is written

            # Upload KB answer as attachment to ServiceNow incident
            curl -s -u "$SNOW_USER:$SNOW_PASS" -X POST "https://$SNOW_INSTANCE_NAME.service-now.com/api/now/attachment/file?table_name=incident&table_sys_id=$SYS_ID&file_name=kb_remediation.txt" \
                -H "Accept: application/json" \
                -F "file=@$KB_ANSWER_FILE" > /dev/null

            # Update ServiceNow ticket status to In Progress
            COMMENT="Automation Bot uploaded KB remediation steps. Ticket moved to In Progress."
            curl -s -u "$SNOW_USER:$SNOW_PASS" -X PUT "$SNOW_API_URL/$SYS_ID?sysparm_exclude_ref_link=true" \
                -H "Content-Type: application/json" \
                -d "{\"comments\": \"$COMMENT\", \"state\": \"2\"}" > /dev/null

            # Update Incident_Status to 'TRANSFERRED' in master table
            UPDATE_QUERY="UPDATE $MASTER_TABLE SET Incident_Status='TRANSFERRED' WHERE Primary_Key='$PRIMARY_KEY';"
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "$UPDATE_QUERY"

            # rm -f "$KB_ANSWER_FILE"
            echo "No remediation solution found for Control ID: $CONTROL_ID. KB answer uploaded as attachment to ServiceNow."
            continue
        fi
        # If KB API did not return an answer, also continue to next incident
        continue
    fi

    # Add comment in ServiceNow ticket only if remediation is available
    COMMENT="Automation Bot is looking into the ticket."
    curl -s -u "$SNOW_USER:$SNOW_PASS" -X PUT "$SNOW_API_URL/$SYS_ID?sysparm_exclude_ref_link=true" \
        -H "Content-Type: application/json" \
        -d "{\"comments\": \"$COMMENT\", \"state\": \"2\"}" > /dev/null

    # Update Incident_Status to 'In Progress' in master table
    UPDATE_QUERY="UPDATE $MASTER_TABLE SET Incident_Status='In Progress' WHERE Primary_Key='$PRIMARY_KEY';"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "$UPDATE_QUERY"

    if [ -n "$REM_FILE" ]; then
        echo "Downloading remediation script: $REM_FILE"
        
        # Download the remediation file to /home/ubuntu
        sudo wget -P /home/ubuntu/ "https://raw.githubusercontent.com/ankit100ni/auto_heal/refs/heads/main/remediations/$REM_FILE"
        
        # Give execute permission
        sudo chmod +x "/home/ubuntu/$REM_FILE"
    else
        echo "No remediation file found for Control ID: $CONTROL_ID"
    fi

    if [ -n "$REM_COMMAND" ]; then
        echo "Executing remediation command in /home/ubuntu: $REM_COMMAND"
        
        # Change directory to /home/ubuntu and execute the command
        (cd /home/ubuntu && eval "$REM_COMMAND")
    else
        echo "No remediation command found for Control ID: $CONTROL_ID"
    fi
done <<< "$RESULTS"

echo "Automation process completed."

