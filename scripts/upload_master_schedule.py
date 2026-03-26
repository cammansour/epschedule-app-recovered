import json
import os
import sys

from google.cloud import storage

DIRNAME = os.path.dirname(__file__)
MASTER_SCHEDULE_PATH = os.path.join(DIRNAME, "../data/master_schedule.json")
CREDS_PATH = os.path.join(DIRNAME, "../service_account.json")

def upload_master_schedule():
    storage_client = storage.Client()
    data_bucket = storage_client.bucket("epschedule-data")

    with open(MASTER_SCHEDULE_PATH) as file:
        try:
            json.load(file)
        except json.decoder.JSONDecodeError:
            print("master_schedule.json is invalid, cancelling upload")
            sys.exit(1)

    schedule_blob = data_bucket.blob("master_schedule.json")
    schedule_blob.upload_from_filename(MASTER_SCHEDULE_PATH)

if __name__ == "__main__":
    if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
        if os.path.exists(CREDS_PATH):
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = CREDS_PATH
        else:
            print(f"Error: Service account file not found at {CREDS_PATH}")
            print("Please either:")
            print("  1. Place service_account.json in the project root, or")
            print("  2. Set GOOGLE_APPLICATION_CREDENTIALS environment variable to the path of your service account file")
            sys.exit(1)
    upload_master_schedule()
    print("✅ Successfully uploaded master_schedule.json to Google Cloud Storage")