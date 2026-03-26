"""
Look up a user's three schedules from schedules.json (GCS).
Uses GOOGLE_APPLICATION_CREDENTIALS from env or service_account.json.
Prints each term's schedule and the vars (keys) associated with each.
"""
import json
import os
import sys

CREDS_PATH = os.path.join(os.path.dirname(__file__), "../service_account.json")
if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ and os.path.exists(CREDS_PATH):
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = CREDS_PATH

from google.cloud import storage

TERM_NAMES = ["Fall", "Winter", "Spring"]

def main():
    username = sys.argv[1].strip().lower() if len(sys.argv) > 1 else "rmackenzie"
    print(f"Looking up schedules for: {username}")
    print()

    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket("epschedule-data")
        data = json.loads(bucket.blob("schedules.json").download_as_string())
    except Exception as e:
        print(f"Error loading schedules: {e}")
        local = os.path.join(os.path.dirname(__file__), "../data/schedules.json")
        if os.path.exists(local):
            with open(local) as f:
                data = json.load(f)
            print("Using local data/schedules.json")
        else:
            sys.exit(1)

    if username not in data:
        print(f"User '{username}' not found in schedules.")
        sys.exit(1)

    schedule = data[username]
    top_vars = [k for k in schedule.keys() if k != "classes"]
    print("Top-level vars for this user:", ", ".join(top_vars))
    print()

    classes = schedule.get("classes", [])
    if len(classes) != 3:
        print(f"Expected 3 terms, got {len(classes)}")
        sys.exit(1)

    for term_id, term_name in enumerate(TERM_NAMES):
        term_classes = classes[term_id]
        print(f"--- {term_name} (term_id={term_id}) ---")
        if term_classes:
            class_vars = list(term_classes[0].keys())
            print(f"  Vars per class: {', '.join(class_vars)}")
        else:
            class_vars = []
            print("  Vars per class: (none)")
        print(f"  Classes ({len(term_classes)}):")
        for c in term_classes:
            name = c.get("name", "?")
            period = c.get("period", "?")
            room = c.get("room") or "-"
            teacher = c.get("teacher_username") or "-"
            print(f"    {period}: {name} | room={room} | teacher={teacher}")
        print()

    return 0

if __name__ == "__main__":
    sys.exit(main())
