#!/bin/bash

# Database Credentials
DB_HOST="mysql-2392fef6-ankit10093-528e.k.aivencloud.com"
DB_USER="avnadmin"
DB_PASS="$1"  # Get password from the first argument
DB_NAME="defaultdb"
DB_PORT="19635"
MASTER_TABLE="master"

# ServiceNow API Credentials
SNOW_INSTANCE="dev198775"
SNOW_USER="admin"
SNOW_PASS="mBkb^B1Fd%X1"
SNOW_API_URL="https://$SNOW_INSTANCE.service-now.com/api/now/table/incident"

# Get Node_ID from the file
NODE_ID=$(cat /hab/svc/node-management-agent/data/node_guid | tr -d '[:space:]')

if [ -z "$NODE_ID" ]; then
    echo "Error: Node_ID could not be retrieved. Exiting."
    exit 1
fi

# Fetch all rows with Incident_Status = 'In Progress' and matching Node_ID
QUERY="SELECT Primary_Key, Incident_Number, Inspec_Control_ID FROM $MASTER_TABLE WHERE Incident_Status='In Progress' AND Node_ID='$NODE_ID';"
RESULTS=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "$QUERY" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$RESULTS" ]; then
    echo "Error: Failed to retrieve records or no matching incidents found."
    exit 1
fi

# Loop through each result
while IFS=$'\t' read -r PRIMARY_KEY INCIDENT_NUMBER CONTROL_ID; do
    echo "Processing Incident: $INCIDENT_NUMBER for Control ID: $CONTROL_ID"

    # Execute Inspec command
    inspec exec https://github.com/AkashKhurana3092/ubuntu_compliance --controls "$CONTROL_ID"
    
    if [ $? -eq 0 ]; then
        echo "✅ Inspec check passed for $CONTROL_ID. Updating ServiceNow..."

        # Fetch sys_id for the given Incident_Number
        SYS_ID=$(curl -s -u "$SNOW_USER:$SNOW_PASS" -X GET "$SNOW_API_URL?sysparm_query=number=$INCIDENT_NUMBER" \
            -H "Accept: application/json" | jq -r '.result[0].sys_id')

        if [ -z "$SYS_ID" ] || [ "$SYS_ID" == "null" ]; then
            echo "❌ Error: Incident with number $INCIDENT_NUMBER not found in ServiceNow. Skipping..."
            continue
        fi

        # Update Incident_Status to 'Resolved' in ServiceNow
        RESPONSE=$(curl -s -u "$SNOW_USER:$SNOW_PASS" -X PUT "$SNOW_API_URL/$SYS_ID?sysparm_exclude_ref_link=true" \
            -H "Content-Type: application/json" \
            -d '{"state": "6", "comments": "✅ Inspec compliance check passed. Marking as Resolved."}')
        
        if echo "$RESPONSE" | grep -q '"error"'; then
            echo "❌ Error updating ServiceNow for Incident: $INCIDENT_NUMBER"
            continue
        fi

        # Update Incident_Status to 'Resolved' in the database
        UPDATE_QUERY="UPDATE $MASTER_TABLE SET Incident_Status='Resolved' WHERE Primary_Key='$PRIMARY_KEY';"
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "$UPDATE_QUERY" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "✅ Database updated: Incident $INCIDENT_NUMBER marked as Resolved."
        else
            echo "❌ Error updating database for Incident: $INCIDENT_NUMBER"
        fi
    else
        echo "❌ Inspec check failed for $CONTROL_ID. Keeping incident open."
    fi

done <<< "$RESULTS"

echo "✅ Processing completed."

