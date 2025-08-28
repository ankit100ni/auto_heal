#!/bin/bash

# Database Credentials
source /root/.db_config

# DB_HOST="mysql-2392fef6-ankit10093-528e.k.aivencloud.com"
# DB_USER="avnadmin"
# DB_PASS="$1"  # Get password from the first argument
# DB_NAME="defaultdb"
# DB_PORT="19635"
TABLE_NAME="pre_scan"
MASTER_TABLE="master"

# Path to the JSON file
JSON_FILE="/home/ubuntu/reports/log.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Install it using 'sudo apt install jq'"
    exit 1
fi

# Get the public IP address
SERVER_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Ensure the IP retrieval was successful
if [ -z "$SERVER_IP" ]; then
    echo "Error: Could not retrieve public IP."
    exit 1
fi

# Generate Node ID
NODE_ID=$(cat /hab/svc/node-management-agent/data/node_guid | tr -d '[:space:]')

# Extract only failed controls and insert into DB (one entry per control)
jq -c '.profiles[].controls[]' "$JSON_FILE" | while read -r control; do
    CONTROL_ID=$(echo "$control" | jq -r '.id')
    TITLE=$(echo "$control" | jq -r '.title')

    # Check if this control has any failed results
    FAILED_COUNT=$(echo "$control" | jq '[.results[] | select(.status == "failed")] | length')
    
    # Only insert if there are failed results AND the control doesn't already exist for this node
    if [ "$FAILED_COUNT" -gt 0 ]; then
        # Check if this control already exists for this node to prevent duplicates
        EXISTING_COUNT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "
            SELECT COUNT(*) FROM $TABLE_NAME 
            WHERE Node_ID='$NODE_ID' AND Inspec_Control_ID='$CONTROL_ID';
        ")
        
        if [ "$EXISTING_COUNT" -eq 0 ]; then
            STATUS="failed"

            # Insert into pre_scan and capture primary key
            PRIMARY_KEY=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "
                INSERT INTO $TABLE_NAME (Node_ID, Server_Name, Inspec_Control_ID, Inspec_Control_Title, Inspec_Status)
                VALUES ('$NODE_ID', '$SERVER_IP', '$CONTROL_ID', '$TITLE', '$STATUS');
                SELECT LAST_INSERT_ID();
            ")

            # Insert into master table
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
            INSERT INTO $MASTER_TABLE (Primary_Key, Node_ID, Inspec_Control_ID, Inspec_Control_Title)
            VALUES ('$PRIMARY_KEY', '$NODE_ID', '$CONTROL_ID', '$TITLE');
EOF
            echo "Inserted control: $CONTROL_ID"
        else
            echo "Skipped duplicate control: $CONTROL_ID (already exists for Node_ID: $NODE_ID)"
        fi
    fi
done

echo "Failed controls inserted into $TABLE_NAME and $MASTER_TABLE with Node ID: $NODE_ID and Server IP: $SERVER_IP."

