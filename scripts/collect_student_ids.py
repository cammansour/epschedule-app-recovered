"""
Script to collect all student IDs, grad years, and names for pass generation.
Stores data in a JSON file for later use.
"""
import csv
import json
import os
import sys

from google.cloud import storage

CREDS_PATH = os.path.join(os.path.dirname(__file__), "../service_account.json")
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "../data/student_ids_for_passes.json")

def get_grad_year_prefix(gradyear, sid):
    """Get grad year prefix (4 digits) or '0000' for faculty."""
    if gradyear:
        return str(gradyear)
    if sid and len(sid) >= 8 and sid.isdigit():
        return sid[:4]
    return "0000"

def format_student_id(gradyear, sid):
    """Format student ID with grad year prepended."""
    prefix = get_grad_year_prefix(gradyear, sid)
    if not sid:
        return prefix
    
    sid_str = str(sid).strip()
    if gradyear and len(sid_str) >= 8 and sid_str.isdigit():
        return prefix + sid_str[-4:]
    return prefix + sid_str

def get_full_name(schedule):
    """Get full name from schedule (preferred_name or firstname + lastname)."""
    first = schedule.get("preferred_name") or schedule.get("firstname") or ""
    last = schedule.get("lastname") or ""
    full_name = f"{first} {last}".strip()
    return full_name if full_name else "Unknown"

def collect_student_data():
    """Collect all student data from schedules.json."""
    if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
        if os.path.exists(CREDS_PATH):
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = CREDS_PATH
        else:
            print("⚠️  No credentials found. Trying to use default credentials...")
    
    print("📥 Downloading schedules.json from database...")
    try:
        storage_client = storage.Client()
        data_bucket = storage_client.bucket("epschedule-data")
        schedules_blob = data_bucket.blob("schedules.json")
        schedules_data = json.loads(schedules_blob.download_as_string())
        print(f"✅ Downloaded {len(schedules_data)} schedules")
    except Exception as e:
        print(f"❌ Error downloading schedules: {e}")
        print("\n💡 Trying to load from local file...")
        local_schedules_path = os.path.join(os.path.dirname(__file__), "../data/schedules.json")
        if os.path.exists(local_schedules_path):
            with open(local_schedules_path, 'r') as f:
                schedules_data = json.load(f)
            print(f"✅ Loaded {len(schedules_data)} schedules from local file")
        else:
            print(f"❌ Local file not found at {local_schedules_path}")
            sys.exit(1)
    
    students = []
    skipped = 0
    
    for username, schedule in schedules_data.items():
        sid = schedule.get("sid")
        gradyear = schedule.get("gradyear")
        
        if not sid:
            skipped += 1
            continue
        
        if isinstance(sid, int):
            sid = str(sid)
        
        formatted_id = format_student_id(gradyear, sid)
        
        full_name = get_full_name(schedule)
        
        student_data = {
            "username": username,
            "full_name": full_name,
            "firstname": schedule.get("firstname") or "",
            "lastname": schedule.get("lastname") or "",
            "preferred_name": schedule.get("preferred_name") or "",
            "grad_year": gradyear,
            "grad_year_prefix": get_grad_year_prefix(gradyear, sid),
            "raw_sid": sid,
            "formatted_id": formatted_id,  # ID with grad year prepended (for barcode)
            "email": schedule.get("email") or f"{username}@eastsideprep.org"
        }
        
        students.append(student_data)
    
    students.sort(key=lambda x: x["full_name"])
    
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    output_data = {
        "generated_at": str(__import__("datetime").datetime.now().isoformat()),
        "total_students": len(students),
        "skipped": skipped,
        "students": students
    }
    
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(output_data, f, indent=2, sort_keys=False)
    
    csv_file = OUTPUT_FILE.replace('.json', '.csv')
    with open(csv_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            "username", "full_name", "firstname", "lastname", "preferred_name",
            "grad_year", "grad_year_prefix", "raw_sid", "formatted_id", "email"
        ])
        writer.writeheader()
        writer.writerows(students)
    
    print(f"\n✅ Successfully collected data for {len(students)} students")
    print(f"📁 Saved JSON to: {OUTPUT_FILE}")
    print(f"📁 Saved CSV to: {csv_file}")
    print(f"⏭️  Skipped {skipped} entries (no ID)")
    
    print("\n📊 Summary by grad year:")
    grad_year_counts = {}
    for student in students:
        year = student["grad_year"] or "Faculty/Unknown"
        grad_year_counts[year] = grad_year_counts.get(year, 0) + 1
    
    for year in sorted(grad_year_counts.keys(), key=lambda x: x if isinstance(x, int) else 9999):
        print(f"   {year}: {grad_year_counts[year]} students")
    
    return output_data

if __name__ == "__main__":
    collect_student_data()
