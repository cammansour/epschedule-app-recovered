"""
Create and sign a Student ID pass the same way as StudentID.pkpass.
1. Build unsigned pass (pass.json, manifest.json, icons).
2. Sign with sign_pass.py using Certificates_ios.p12 (or pass.cer + key).
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile

STUDENT_DATA_PATH = os.path.join(os.path.dirname(__file__), "../data/student_ids_for_passes.json")
P12_PATH = os.path.join(os.path.dirname(__file__), "../epschedule/Certificates_ios.p12")
PASS_CER_PATH = os.path.join(os.path.dirname(__file__), "../pass.cer")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "../data/passes")
SCRIPT_DIR = os.path.dirname(__file__)

def sha1_file(path):
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()

def first_last_initial(full_name):
    parts = full_name.split()
    if len(parts) <= 1:
        return full_name
    return f"{parts[0]} {parts[-1][0]}."

def build_unsigned_pass(student_data, team_id="K33BDFCCHR", temp_dir=None):
    """Build pass.json + manifest + icons. No signature."""
    if temp_dir is None:
        import tempfile
        temp_dir = __import__("tempfile").mkdtemp(prefix="pkpass_")

    pass_json = {
        "formatVersion": 1,
        "passTypeIdentifier": "pass.eps.epschedule",
        "serialNumber": student_data["formatted_id"],
        "teamIdentifier": team_id,
        "organizationName": "Eastside Preparatory School",
        "description": "Student ID Card",
        "foregroundColor": "rgb(255, 255, 255)",
        "backgroundColor": "rgb(1, 46, 86)",
        "labelColor": "rgb(180, 200, 220)",
        "generic": {
            "primaryFields": [
                {"key": "name", "label": "STUDENT", "value": first_last_initial(student_data["full_name"])}
            ],
            "secondaryFields": [
                {"key": "id", "label": "ID", "value": student_data["formatted_id"]}
            ],
            "backFields": [
                {"key": "fullname", "label": "Full Name", "value": student_data["full_name"]},
                {"key": "school", "label": "School", "value": "Eastside Preparatory School"},
            ],
        },
        "barcodes": [
            {
                "message": student_data["formatted_id"],
                "format": "PKBarcodeFormatCode128",
                "messageEncoding": "iso-8859-1",
                "altText": student_data["formatted_id"],
            }
        ],
    }
    if student_data.get("grad_year"):
        pass_json["generic"]["secondaryFields"].append({
            "key": "gradyear",
            "label": "GRAD YEAR:",
            "value": str(student_data["grad_year"]),
        })

    pass_path = os.path.join(temp_dir, "pass.json")
    with open(pass_path, "w") as f:
        json.dump(pass_json, f, indent=2)

    icon_names = ["icon.png", "icon@2x.png", "icon@3x.png"]
    logo_names = ["logo.png", "logo@2x.png", "logo@3x.png"]
    thumbnail_names = ["thumbnail.png", "thumbnail@2x.png", "thumbnail@3x.png"]
    
    icon_dirs = [
        os.path.join(SCRIPT_DIR, "../epschedule/epschedule"),
        os.path.join(SCRIPT_DIR, ".."),
    ]
    added = []
    
    for name in icon_names:
        for d in icon_dirs:
            src = os.path.join(d, name)
            if os.path.exists(src):
                dst = os.path.join(temp_dir, name)
                shutil.copy2(src, dst)
                added.append(name)
                break
    
    for name in logo_names:
        for d in icon_dirs:
            src = os.path.join(d, name)
            if os.path.exists(src):
                dst = os.path.join(temp_dir, name)
                shutil.copy2(src, dst)
                added.append(name)
                break
    
    for name in thumbnail_names:
        for d in icon_dirs:
            src = os.path.join(d, name)
            if os.path.exists(src):
                dst = os.path.join(temp_dir, name)
                shutil.copy2(src, dst)
                added.append(name)
                break

    manifest = {"pass.json": sha1_file(pass_path)}
    all_files = icon_names + logo_names + thumbnail_names
    for name in all_files:
        if name in added:
            manifest[name] = sha1_file(os.path.join(temp_dir, name))

    manifest_path = os.path.join(temp_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, separators=(",", ":"))

    return temp_dir, added

def zip_unsigned(temp_dir, all_files, out_path):
    """Zip pass.json, manifest.json, and all image files. No signature."""
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.write(os.path.join(temp_dir, "pass.json"), "pass.json")
        for name in all_files:
            zf.write(os.path.join(temp_dir, name), name)
        zf.write(os.path.join(temp_dir, "manifest.json"), "manifest.json")

def main():
    team_id = os.environ.get("TEAM_ID", "K33BDFCCHR")
    username = sys.argv[1] if len(sys.argv) > 1 else None

    with open(STUDENT_DATA_PATH, "r") as f:
        data = json.load(f)
    if username:
        student = next((s for s in data["students"] if s["username"] == username), None)
        if not student:
            print(f"❌ Student not found: {username}")
            sys.exit(1)
    else:
        student = data["students"][0]

    print(f"📋 Building pass for: {student['full_name']} ({student['formatted_id']})")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    import tempfile
    temp_dir = tempfile.mkdtemp(prefix="pkpass_")
    try:
        _, all_files = build_unsigned_pass(student, team_id, temp_dir)

        final_name = f"{student['username']}.pkpass"
        final_path = os.path.join(OUTPUT_DIR, final_name)
        zip_unsigned(temp_dir, all_files, final_path)
        print(f"✅ Unsigned pass built: {final_path}")

        cert = P12_PATH
        if not os.path.exists(cert):
            print(f"❌ Certificate not found: {cert}")
            print("   Need Certificates_ios.p12 with private key for signing")
            sys.exit(1)

        sign_script = os.path.join(SCRIPT_DIR, "sign_pass.py")
        rc = subprocess.run(
            [sys.executable, sign_script, final_path, cert],
        ).returncode
        if rc != 0:
            print("❌ Signing failed")
            sys.exit(1)

        print(f"✅ Signed pass: {final_path}")
        print(f"   Size: {os.path.getsize(final_path)} bytes")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == "__main__":
    main()
