#!/usr/bin/env python3
import json
import requests
import os
from urllib.parse import unquote

# Define file paths
config_file = 'config.json'
temp_state_file = 'snapshot_state.txt'

# Function to read the configuration from the config file
def read_config():
    with open(config_file, 'r') as file:
        config = json.load(file)
    return config

# Function to get the current snapshot list
def get_snapshots(api_token, droplet_id):
    headers = {
        'Authorization': f'Bearer {api_token}',
        'Content-Type': 'application/json',
    }
    response = requests.get(f'https://api.digitalocean.com/v2/droplets/{droplet_id}/snapshots', headers=headers)
    return response.json().get('snapshots', [])

# Function to read the previous state from the temp file
def read_previous_state():
    if not os.path.exists(temp_state_file):
        return []  # Return an empty list if the file doesn't exist
    with open(temp_state_file, 'r') as file:
        file_content = file.read()
        if not file_content.strip():
            return []  # Return an empty list if the file is empty
        return json.loads(file_content)

# Function to write the current state to the temp file
def write_current_state(current_state):
    with open(temp_state_file, 'w') as file:
        json.dump(current_state, file)

# Function to send a notification using ntfy.sh
# Inside the send_notification function:
def send_notification(message, ntfy_topic):
    headers = {
        'Title': 'Digital Ocean Snapshot Change',
        'tags': 'ocean,camera_flash',
    }
    data = {
         'message': message,
    }

    response = requests.post(f'https://ntfy.sh/{ntfy_topic}', headers=headers, data=data)

    if response.status_code != 200:
        print(f'Failed to send notification: {response.text}')  # Add this line for more details
#    else:
#        print('Notification sent successfully')

# Main function to check for changes and send notifications
def main():
    config = read_config()
    api_token = config.get('api_token')
    droplet_id = config.get('droplet_id')
    ntfy_topic = config.get('ntfy_topic')

    # Get the current snapshots and the previous state from the snapshot_state.txt
    current_snapshots = get_snapshots(api_token, droplet_id)
    previous_snapshots = read_previous_state()

    # Extract snapshot IDs from the current snapshots
    current_snapshot_ids = [snapshot['id'] for snapshot in current_snapshots]

    # Find new snapshots
    new_snapshots = [snapshot_id for snapshot_id in current_snapshot_ids if snapshot_id not in previous_snapshots]

    # Find removed snapshots
    removed_snapshots = [snapshot_id for snapshot_id in previous_snapshots if snapshot_id not in current_snapshot_ids]

    # Only update the previous state and send notifications if there are changes
    if new_snapshots or removed_snapshots:
        for snapshot_id in new_snapshots:
            message = f"New snapshot created: {snapshot_id}"
            decoded_message = unquote(message)
            send_notification(decoded_message, ntfy_topic)

        for snapshot_id in removed_snapshots:
            message = f"Snapshot removed: {snapshot_id}"
            decoded_message = unquote(message)
            send_notification(decoded_message, ntfy_topic)

        # Update the previous state to be the list of current snapshot IDs
        write_current_state(current_snapshot_ids)

if __name__ == "__main__":
    main()
