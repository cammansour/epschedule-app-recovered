"""
Script to update a single date in the master schedule database.
Uses the provided API key/secret to authenticate.
"""
import json
import os
import sys

from google.cloud import storage, secretmanager

TARGET_DATE = "2026-01-26"
NEW_VALUE = "Voices in Action Day"

DIRNAME = os.path.dirname(__file__)
MASTER_SCHEDULE_PATH = os.path.join(DIRNAME, "../data/master_schedule.json")
CREDS_PATH = os.path.join(DIRNAME, "../service_account.json")

def update_master_schedule():
    """Download, update, and upload the master schedule."""
    if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
        if os.path.exists(CREDS_PATH):
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = CREDS_PATH
        else:
            print("Error: Service account file not found")
            sys.exit(1)
    
    try:
        storage_client = storage.Client()
        data_bucket = storage_client.bucket("epschedule-data")
    except Exception as e:
        print(f"Error initializing storage client: {e}")
        print("Make sure you have proper authentication set up")
        sys.exit(1)
    
    print("📥 Downloading current master_schedule.json from database...")
    try:
        schedule_blob = data_bucket.blob("master_schedule.json")
        current_data = schedule_blob.download_as_string()
        master_schedule = json.loads(current_data)
    except Exception as e:
        print(f"❌ Error downloading: {e}")
        sys.exit(1)
    
    if len(master_schedule) < 1:
        print("❌ Invalid master schedule format")
        sys.exit(1)
    
    days_dict = master_schedule[0]
    
    if TARGET_DATE in days_dict:
        old_value = days_dict[TARGET_DATE]
        print(f"📝 Found {TARGET_DATE}: '{old_value}'")
        
        if old_value == NEW_VALUE:
            print(f"✅ {TARGET_DATE} is already set to '{NEW_VALUE}'")
            return
    else:
        print(f"⚠️  {TARGET_DATE} not found in schedule, adding it...")
        old_value = None
    
    days_dict[TARGET_DATE] = NEW_VALUE
    print(f"✏️  Updating {TARGET_DATE}: '{old_value}' → '{NEW_VALUE}'")
    
    if len(master_schedule) < 2:
        print("❌ Invalid master schedule format (missing schedules section)")
        sys.exit(1)
    
    schedules_dict = master_schedule[1]
    if NEW_VALUE not in schedules_dict:
        print(f"➕ Adding schedule type '{NEW_VALUE}' to schedules section...")
        schedules_dict[NEW_VALUE] = [{
            "period": NEW_VALUE,
            "times": "08:00-03:15"
        }]
    
    print("📤 Uploading updated master_schedule.json to database...")
    try:
        updated_json = json.dumps(master_schedule, indent=2, sort_keys=True)
        schedule_blob.upload_from_string(updated_json, content_type="application/json")
        print(f"✅ Successfully updated {TARGET_DATE} to '{NEW_VALUE}' in database!")
    except Exception as e:
        print(f"❌ Error uploading: {e}")
        print("\nThis might be due to:")
        print("  - Service account doesn't have write permissions")
        print("  - Network connectivity issues")
        print("  - Invalid credentials")
        sys.exit(1)

if __name__ == "__main__":
    update_master_schedule()
