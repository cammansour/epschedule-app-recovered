"""
Create a .pkpass package structure for a student.
Note: This creates the structure but requires Apple Developer certificates for signing.
"""
import json
import os
import hashlib
import zipfile
import shutil
from datetime import datetime, timedelta

STUDENT_DATA_PATH = os.path.join(os.path.dirname(__file__), "../data/student_ids_for_passes.json")
PASSES_DIR = os.path.join(os.path.dirname(__file__), "../data/passes")
ICON_DIR = os.path.join(os.path.dirname(__file__), "../epschedule/epschedule/Assets.xcassets/icon.imageset")

def sha1_hash(data):
    """Calculate SHA1 hash of data."""
    if isinstance(data, str):
        data = data.encode('utf-8')
    return hashlib.sha1(data).hexdigest()

def create_pass_package(student_data, output_dir=None):
    """Create a .pkpass package for a student."""
    if output_dir is None:
        output_dir = PASSES_DIR
    
    os.makedirs(output_dir, exist_ok=True)
    
    username = student_data["username"]
    temp_dir = os.path.join(output_dir, f"{username}_temp")
    
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)
    
    try:
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": "pass.eps.epschedule",
            "serialNumber": student_data["formatted_id"],
            "teamIdentifier": "K33BDFCCHR",  # Team ID
            "organizationName": "Eastside Preparatory School",
            "description": "Student ID Card",
            "foregroundColor": "rgb(255, 255, 255)",  # Match StudentID.pkpass
            "backgroundColor": "rgb(1, 46, 86)",
            "labelColor": "rgb(180, 200, 220)",
            "generic": {
                "primaryFields": [
                    {
                        "key": "name",
                        "label": "STUDENT",
                        "value": student_data["full_name"].split()[0] + " " + student_data["full_name"].split()[-1][0] + "." if len(student_data["full_name"].split()) > 1 else student_data["full_name"]
                    }
                ],
                "secondaryFields": [
                    {
                        "key": "id",
                        "label": "ID",
                        "value": student_data["formatted_id"]
                    }
                ],
                "backFields": [
                    {
                        "key": "fullname",
                        "label": "Full Name",
                        "value": student_data["full_name"]
                    },
                    {
                        "key": "school",
                        "label": "School",
                        "value": "Eastside Preparatory School"
                    }
                ]
            },
            "barcodes": [
                {
                    "message": student_data["formatted_id"],
                    "format": "PKBarcodeFormatCode128",
                    "messageEncoding": "iso-8859-1",
                    "altText": student_data["formatted_id"]
                }
            ]
        }
        
        if student_data.get("grad_year"):
            pass_json["generic"]["secondaryFields"].append({
                "key": "gradyear",
                "label": "GRAD YEAR:",
                "value": str(student_data["grad_year"])
            })
        
        
        pass_json_str = json.dumps(pass_json, indent=2)
        pass_json_path = os.path.join(temp_dir, "pass.json")
        with open(pass_json_path, 'w') as f:
            f.write(pass_json_str)
        
        print(f"✅ Created pass.json for {student_data['full_name']}")
        
        icon_files = []
        icon_names = ["icon.png", "icon@2x.png", "icon@3x.png"]
        for icon_name in icon_names:
            possible_paths = [
                os.path.join(os.path.dirname(__file__), f"../epschedule/epschedule/{icon_name}"),
                os.path.join(ICON_DIR, icon_name),
                os.path.join(os.path.dirname(__file__), f"../{icon_name}"),
                os.path.join(os.path.dirname(__file__), f"../data/{icon_name}"),
            ]
            
            for icon_path in possible_paths:
                if os.path.exists(icon_path):
                    dest_path = os.path.join(temp_dir, icon_name)
                    shutil.copy2(icon_path, dest_path)
                    icon_files.append(icon_name)
                    print(f"✅ Added {icon_name}")
                    break
        
        manifest = {}
        
        with open(pass_json_path, 'rb') as f:
            manifest["pass.json"] = sha1_hash(f.read())
        
        for icon_name in icon_files:
            icon_path = os.path.join(temp_dir, icon_name)
            with open(icon_path, 'rb') as f:
                manifest[icon_name] = sha1_hash(f.read())
        
        manifest_path = os.path.join(temp_dir, "manifest.json")
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, sort_keys=True, separators=(',', ':'))
        
        print(f"✅ Created manifest.json with {len(manifest)} files")
        
        signature_path = os.path.join(temp_dir, "signature")
        with open(signature_path, 'w') as f:
            f.write("# This is a placeholder signature.\n")
            f.write("# In production, this must be a PKCS#7 signature created with your Apple Developer certificate.\n")
            f.write("# The signature signs the manifest.json file.\n")
        
        print("⚠️  Created placeholder signature (requires Apple Developer certificate for production)")
        
        pkpass_path = os.path.join(output_dir, f"{username}.pkpass")
        
        with zipfile.ZipFile(pkpass_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arc_name = os.path.relpath(file_path, temp_dir)
                    zipf.write(file_path, arc_name)
        
        print(f"✅ Created {pkpass_path}")
        print(f"📦 Package size: {os.path.getsize(pkpass_path)} bytes")
        
        shutil.rmtree(temp_dir)
        
        print(f"\n⚠️  NOTE: This pass is NOT signed and will NOT work in Apple Wallet.")
        print(f"   You need to:")
        print(f"   1. Replace 'YOUR_TEAM_ID' with your Apple Developer Team ID")
        print(f"   2. Sign the manifest.json with your Apple Developer certificate")
        print(f"   3. Replace the placeholder signature with the actual PKCS#7 signature")
        
        return pkpass_path
        
    except Exception as e:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
        raise e

def main():
    with open(STUDENT_DATA_PATH, 'r') as f:
        data = json.load(f)
    
    first_student = data["students"][0]
    
    print(f"📋 Creating pass package for: {first_student['full_name']}")
    print(f"   Username: {first_student['username']}")
    print(f"   Formatted ID: {first_student['formatted_id']}")
    print()
    
    pkpass_path = create_pass_package(first_student)
    
    print(f"\n✅ Pass package created: {pkpass_path}")

if __name__ == "__main__":
    main()
