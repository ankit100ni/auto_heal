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

# ServiceNow API Credentials
# SNOW_INSTANCE="dev198775.service-now.com"
# SNOW_USER="admin"
# SNOW_PASS="mBkb^B1Fd%X1"

# Path to Node ID file
NODE_ID_FILE="/hab/svc/node-management-agent/data/node_guid"

# Check if the Node ID file exists
if [ ! -f "$NODE_ID_FILE" ]; then
    echo "❌ Error: Node ID file not found at $NODE_ID_FILE"
    exit 1
fi

# Retrieve Node ID
NODE_ID=$(cat "$NODE_ID_FILE" | tr -d '[:space:]')

# Validate Node ID
if [ -z "$NODE_ID" ]; then
    echo "❌ Error: Failed to retrieve Node ID. Exiting."
    exit 1
fi

echo "✅ Node ID retrieved: $NODE_ID"

# Check if jq and curl are installed
for cmd in jq curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Error: '$cmd' is not installed. Install it using: sudo apt install $cmd"
        exit 1
    fi
done

# Validate database connection
if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" &>/dev/null; then
    echo "❌ Error: Unable to connect to the database. Check credentials."
    exit 1
fi

echo "✅ Connected to database."

# Query to select all records where Incident_Number is NULL and Node_ID matches our retrieved Node ID
QUERY="SELECT primary_key, Node_ID, Server_Name, Inspec_Control_ID, Inspec_Control_Title, Inspec_Status 
       FROM $TABLE_NAME 
       WHERE Incident_Number IS NULL AND Node_ID = '$NODE_ID';"

# Execute MySQL query and iterate over results
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "$QUERY" | while IFS=$'\t' read -r primary_key node_id server_name control_id control_title status; do

    echo "🔍 Processing: Control ID: $control_id | Title: $control_title | Node_ID: $node_id"

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

    # Check if API request was successful
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to reach ServiceNow API for $control_id"
        continue
    fi

    # Extract Incident Number from response
    INCIDENT_NUMBER=$(echo "$RESPONSE" | jq -r '.result.number')

    if [ -n "$INCIDENT_NUMBER" ] && [ "$INCIDENT_NUMBER" != "null" ]; then
        echo "✅ Created Incident: $INCIDENT_NUMBER for $control_id"

        # Update `pre_scan` table with Incident Number
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "
            UPDATE $TABLE_NAME SET Incident_Number='$INCIDENT_NUMBER' WHERE primary_key='$primary_key';
        " &>/dev/null; then
            echo "✅ Updated $TABLE_NAME for Primary Key: $primary_key"
        else
            echo "❌ Error: Failed to update $TABLE_NAME for Primary Key: $primary_key"
        fi

        # Update `master` table with Incident Number and Status
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "
            UPDATE $MASTER_TABLE SET Incident_Number='$INCIDENT_NUMBER', Incident_Status='New' WHERE Primary_Key='$primary_key';
        " &>/dev/null; then
            echo "✅ Updated $MASTER_TABLE for Primary Key: $primary_key"
        else
            echo "❌ Error: Failed to update $MASTER_TABLE for Primary Key: $primary_key"
        fi
    else
        echo "❌ Failed to create an incident for $control_id. ServiceNow Response: $RESPONSE"
    fi

done

echo "🎯 Script execution completed!"

