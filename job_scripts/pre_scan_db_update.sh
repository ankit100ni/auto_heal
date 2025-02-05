#!/bin/bash

# Database Credentials
DB_HOST="sql12.freesqldatabase.com"
DB_USER="sql12760516"
DB_PASS="Sl4qyzXg9T"
DB_NAME="sql12760516"
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

# Extract only failed controls and insert into DB
jq -c '.profiles[].controls[]' "$JSON_FILE" | while read -r control; do
    CONTROL_ID=$(echo "$control" | jq -r '.id')
    TITLE=$(echo "$control" | jq -r '.title')

    # Extract failed statuses only
    echo "$control" | jq -c '.results[] | select(.status == "failed")' | while read -r result; do
        STATUS="failed"

        # Insert into pre_scan and capture primary key
        PRIMARY_KEY=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se "
            INSERT INTO $TABLE_NAME (Node_ID, Server_Name, Inspec_Control_ID, Inspec_Control_Title, Inspec_Status)
            VALUES ('$NODE_ID', '$SERVER_IP', '$CONTROL_ID', '$TITLE', '$STATUS');
            SELECT LAST_INSERT_ID();
        ")

        # Insert into master table
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
        INSERT INTO $MASTER_TABLE (Primary_Key, Node_ID, Inspec_Control_ID, Inspec_Control_Title)
        VALUES ('$PRIMARY_KEY', '$NODE_ID', '$CONTROL_ID', '$TITLE');
EOF
    done
done

echo "Failed controls inserted into $TABLE_NAME and $MASTER_TABLE with Node ID: $NODE_ID and Server IP: $SERVER_IP."

