#!/bin/bash

# Database Credentials
DB_HOST="sql12.freesqldatabase.com"
DB_USER="sql12760516"
DB_PASS="$1"  # Pass as an argument
DB_NAME="sql12760516"
TABLE_NAME="pre_scan"
MASTER_TABLE="master"

# ServiceNow API Credentials
SNOW_INSTANCE="dev231713.service-now.com"
SNOW_USER="admin"
SNOW_PASS="D8a2/-IYhhoO"

# Query to select all records where Incident_Number is NULL
QUERY="SELECT primary_key, Node_ID, Server_Name, Inspec_Control_ID, Inspec_Control_Title, Inspec_Status FROM $TABLE_NAME WHERE Incident_Number IS NULL;"

# Execute MySQL query and iterate over results
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "$QUERY" | while IFS=$'\t' read -r primary_key node_id server_name control_id control_title status; do

    # Create JSON payload for ServiceNow incident
    INCIDENT_PAYLOAD=$(cat <<EOF
{
    "short_description": "Security issue detected: $control_title",
    "description": "Node ID: $node_id\nServer Name: $server_name\nControl ID: $control_id\nControl Title: $control_title\nStatus: $status",
    "impact": "2",
    "urgency": "2",
    "state": "1",
    "caller_id": "System Administrator",
    "assignment_group": "Automation"
}
EOF
)

    # Call ServiceNow API to create an incident
    RESPONSE=$(curl -s -u "$SNOW_USER:$SNOW_PASS" -X POST "https://$SNOW_INSTANCE/api/now/table/incident" \
        --header "Content-Type: application/json" \
        --data "$INCIDENT_PAYLOAD")

    # Extract Incident Number from response
    INCIDENT_NUMBER=$(echo "$RESPONSE" | jq -r '.result.number')

    if [ -n "$INCIDENT_NUMBER" ]; then
        echo "Created Incident: $INCIDENT_NUMBER for $control_id"

        # Update `pre_scan` table with Incident Number
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "
            UPDATE $TABLE_NAME SET Incident_Number='$INCIDENT_NUMBER' WHERE primary_key='$primary_key';
        "

        # Update `master` table with Incident Number and Status
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "
            UPDATE $MASTER_TABLE SET Incident_Number='$INCIDENT_NUMBER', Incident_Status='New' WHERE Primary_Key='$primary_key';
        "
    else
        echo "Failed to create an incident for $control_id"
    fi

done

