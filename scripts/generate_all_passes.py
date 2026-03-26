"""
Generate student passes for all students or a subset.
Uses make_studentid_pass.py to generate each pass.
"""
import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(__file__)
STUDENT_DATA_PATH = os.path.join(SCRIPT_DIR, "../data/student_ids_for_passes.json")
MAKE_PASS_SCRIPT = os.path.join(SCRIPT_DIR, "make_studentid_pass.py")

def generate_all_passes(usernames=None, skip_existing=False):
    """
    Generate passes for students.
    
    Args:
        usernames: List of usernames to generate passes for. If None, generates for all students.
        skip_existing: If True, skip students who already have a pass file.
    """
    with open(STUDENT_DATA_PATH, "r") as f:
        data = json.load(f)
    
    if usernames:
        students = [s for s in data["students"] if s["username"] in usernames]
        if len(students) != len(usernames):
            found_usernames = {s["username"] for s in students}
            missing = set(usernames) - found_usernames
            print(f"⚠️  Warning: Some usernames not found: {missing}")
    else:
        students = data["students"]
    
    total = len(students)
    print(f"📋 Generating passes for {total} student(s)")
    print()
    
    output_dir = os.path.join(SCRIPT_DIR, "../data/passes")
    os.makedirs(output_dir, exist_ok=True)
    
    success_count = 0
    failed_count = 0
    skipped_count = 0
    
    for i, student in enumerate(students, 1):
        username = student["username"]
        pass_path = os.path.join(output_dir, f"{username}.pkpass")
        
        if skip_existing and os.path.exists(pass_path):
            print(f"[{i}/{total}] ⏭️  Skipping {username} (pass already exists)")
            skipped_count += 1
            continue
        
        print(f"[{i}/{total}] 📋 Generating pass for {student['full_name']} ({username})")
        
        try:
            result = subprocess.run(
                [sys.executable, MAKE_PASS_SCRIPT, username],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                if os.path.exists(pass_path):
                    size = os.path.getsize(pass_path)
                    print(f"         ✅ Success ({size:,} bytes)")
                    success_count += 1
                else:
                    print(f"         ⚠️  Script succeeded but pass file not found")
                    failed_count += 1
            else:
                print(f"         ❌ Failed: {result.stderr.strip() or result.stdout.strip()}")
                failed_count += 1
        except subprocess.TimeoutExpired:
            print(f"         ❌ Timeout after 30 seconds")
            failed_count += 1
        except Exception as e:
            print(f"         ❌ Error: {e}")
            failed_count += 1
        
        print()
    
    print("=" * 60)
    print("📊 Summary:")
    print(f"   ✅ Success: {success_count}")
    if skipped_count > 0:
        print(f"   ⏭️  Skipped: {skipped_count}")
    if failed_count > 0:
        print(f"   ❌ Failed: {failed_count}")
    print(f"   📦 Total: {total}")
    print("=" * 60)

def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Generate student passes in bulk",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 scripts/generate_all_passes.py
  
  python3 scripts/generate_all_passes.py ajagana atandon
  
  python3 scripts/generate_all_passes.py --skip-existing
  
  python3 scripts/generate_all_passes.py ajagana atandon --skip-existing
        """
    )
    
    parser.add_argument(
        "usernames",
        nargs="*",
        help="Usernames to generate passes for (if not provided, generates for all students)"
    )
    
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip students who already have a pass file"
    )
    
    args = parser.parse_args()
    
    usernames = args.usernames if args.usernames else None
    generate_all_passes(usernames=usernames, skip_existing=args.skip_existing)

if __name__ == "__main__":
    main()
