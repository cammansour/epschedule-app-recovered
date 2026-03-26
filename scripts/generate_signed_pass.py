"""
Simple script to generate and sign a pass - mimics the Swift PassKitService approach.
Uses the same certificate and creates passes easily.
"""
import json
import os
import sys
import subprocess
import tempfile
import shutil
from datetime import datetime, timedelta

STUDENT_DATA_PATH = os.path.join(os.path.dirname(__file__), "../data/student_ids_for_passes.json")
CERT_PATH = os.path.join(os.path.dirname(__file__), "../epschedule/Certificates_ios.p12")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "../data/passes")

def generate_signed_pass(student_data, team_id="YOUR_TEAM_ID"):
    """Generate and sign a pass for a student - simple approach."""
    
    username = student_data["username"]
    output_path = os.path.join(OUTPUT_DIR, f"{username}.pkpass")
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="pkpass_")
    
    try:
        expiration = (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%dT23:59:59Z")
        
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": "pass.eps.epschedule",  # Must match certificate UID exactly
            "serialNumber": student_data["formatted_id"],
            "teamIdentifier": team_id,
            "organizationName": "Eastside Preparatory School",
            "description": "Student ID Card",
            "logoText": "EPS",
            "foregroundColor": "rgb(0, 0, 0)",  # Swift uses black/white
            "backgroundColor": "rgb(255, 255, 255)",
            "generic": {
                "primaryFields": [
                    {
                        "key": "name",
                        "label": "Name",  # Swift uses "Name", working pass uses "STUDENT"
                        "value": student_data["full_name"]
                    }
                ],
                "secondaryFields": [
                    {
                        "key": "id",
                        "label": "Student ID",  # Swift uses "Student ID", working pass uses "ID"
                        "value": student_data["formatted_id"]
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
                "key": "grad_year",
                "label": "Class of",
                "value": str(student_data["grad_year"])
            })
        
        if student_data.get("email"):
            pass_json["generic"]["auxiliaryFields"] = [{
                "key": "email",
                "label": "Email",
                "value": student_data["email"]
            }]
        
        pass_json_path = os.path.join(temp_dir, "pass.json")
        with open(pass_json_path, 'w') as f:
            json.dump(pass_json, f, indent=2)
        
        icon_files = []
        all_image_files = []
        
        for icon_name in ["icon.png", "icon@2x.png", "icon@3x.png"]:
            icon_paths = [
                os.path.join(os.path.dirname(__file__), f"../epschedule/epschedule/{icon_name}"),
                os.path.join(os.path.dirname(__file__), f"../{icon_name}"),
            ]
            for icon_path in icon_paths:
                if os.path.exists(icon_path):
                    shutil.copy2(icon_path, os.path.join(temp_dir, icon_name))
                    icon_files.append(icon_name)
                    all_image_files.append(icon_name)
                    break
        
        for logo_name in ["logo.png", "logo@2x.png", "logo@3x.png"]:
            logo_paths = [
                os.path.join(os.path.dirname(__file__), f"../epschedule/epschedule/{logo_name}"),
                os.path.join(os.path.dirname(__file__), f"../{logo_name}"),
            ]
            for logo_path in logo_paths:
                if os.path.exists(logo_path):
                    shutil.copy2(logo_path, os.path.join(temp_dir, logo_name))
                    all_image_files.append(logo_name)
                    break
        
        for thumb_name in ["thumbnail.png", "thumbnail@2x.png", "thumbnail@3x.png"]:
            thumb_paths = [
                os.path.join(os.path.dirname(__file__), f"../epschedule/epschedule/{thumb_name}"),
                os.path.join(os.path.dirname(__file__), f"../{thumb_name}"),
            ]
            for thumb_path in thumb_paths:
                if os.path.exists(thumb_path):
                    shutil.copy2(thumb_path, os.path.join(temp_dir, thumb_name))
                    all_image_files.append(thumb_name)
                    break
        
        import hashlib
        manifest = {}
        
        def sha1_hash(file_path):
            with open(file_path, 'rb') as f:
                return hashlib.sha1(f.read()).hexdigest()
        
        manifest["pass.json"] = sha1_hash(pass_json_path)
        for image_file in all_image_files:
            manifest[image_file] = sha1_hash(os.path.join(temp_dir, image_file))
        
        manifest_path = os.path.join(temp_dir, "manifest.json")
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2, sort_keys=True)
        
        print(f"📄 Manifest created with {len(manifest)} files")
        
        signature_path = os.path.join(temp_dir, "signature")
        
        key_path = os.path.join(temp_dir, "key.pem")
        cert_path = os.path.join(temp_dir, "cert.pem")
        
        subprocess.run([
            "openssl", "pkcs12", "-in", CERT_PATH,
            "-nocerts", "-nodes", "-out", key_path,
            "-passin", "pass:"
        ], check=True, capture_output=True)
        
        subprocess.run([
            "openssl", "pkcs12", "-in", CERT_PATH,
            "-clcerts", "-nokeys", "-out", cert_path,
            "-passin", "pass:"
        ], check=True, capture_output=True)
        
        wwdr_path = None
        wwdr_certs = [
            ("../wwdr_g4.pem", "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer"),
            ("../wwdr.pem", "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"),
            ("../wwdr_g5.pem", "https://www.apple.com/certificateauthority/AppleWWDRCAG5.cer"),
        ]
        
        for wwdr_rel_path, wwdr_url in wwdr_certs:
            wwdr_full_path = os.path.join(os.path.dirname(__file__), wwdr_rel_path)
            if os.path.exists(wwdr_full_path):
                wwdr_path = wwdr_full_path
                break
        
        if not wwdr_path:
            print("📥 Downloading WWDR certificate...")
            try:
                import urllib.request
                wwdr_path = os.path.join(os.path.dirname(__file__), "../wwdr_g4.pem")
                urllib.request.urlretrieve(
                    "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer",
                    wwdr_path + ".cer"
                )
                subprocess.run([
                    "openssl", "x509", "-inform", "DER",
                    "-in", wwdr_path + ".cer",
                    "-out", wwdr_path
                ], check=True, capture_output=True)
                os.remove(wwdr_path + ".cer")
                print("✅ Downloaded WWDR G4 certificate")
            except Exception as e:
                print(f"⚠️  Could not download WWDR G4, trying G3...")
                try:
                    wwdr_path = os.path.join(os.path.dirname(__file__), "../wwdr.pem")
                    urllib.request.urlretrieve(
                        "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
                        wwdr_path + ".cer"
                    )
                    subprocess.run([
                        "openssl", "x509", "-inform", "DER",
                        "-in", wwdr_path + ".cer",
                        "-out", wwdr_path
                    ], check=True, capture_output=True)
                    os.remove(wwdr_path + ".cer")
                    print("✅ Downloaded WWDR G3 certificate")
                except Exception as e2:
                    print(f"⚠️  Could not download WWDR: {e2}")
                    wwdr_path = None
        
        sign_cmd = [
            "openssl", "smime", "-binary", "-sign",
            "-signer", cert_path,
            "-inkey", key_path,
            "-in", manifest_path,
            "-out", signature_path,
            "-outform", "DER",
            "-noattr"  # Don't include attributes
        ]
        
        if os.path.exists(wwdr_path):
            sign_cmd.extend(["-certfile", wwdr_path])
            print("✅ Using WWDR certificate")
        else:
            print("⚠️  WWDR certificate not found, signing without it")
        
        result = subprocess.run(sign_cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ Signing failed: {result.stderr}")
            if os.path.exists(wwdr_path):
                print("🔄 Retrying without WWDR certificate...")
                sign_cmd_no_wwdr = [
                    "openssl", "smime", "-binary", "-sign",
                    "-signer", cert_path,
                    "-inkey", key_path,
                    "-in", manifest_path,
                    "-out", signature_path,
                    "-outform", "DER",
                    "-noattr"
                ]
                result = subprocess.run(sign_cmd_no_wwdr, capture_output=True, text=True)
                if result.returncode != 0:
                    raise Exception(f"Signing failed: {result.stderr}")
            else:
                raise Exception(f"Signing failed: {result.stderr}")
        
        old_cwd = os.getcwd()
        os.chdir(temp_dir)
        try:
            import zipfile
            with zipfile.ZipFile(os.path.abspath(output_path), 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zipf:
                zipf.write("pass.json", "pass.json")
                for icon_file in icon_files:
                    zipf.write(icon_file, icon_file)
                zipf.write("manifest.json", "manifest.json")
                zipf.write("signature", "signature")
        finally:
            os.chdir(old_cwd)
        
        print(f"✅ Created signed pass: {output_path}")
        return output_path
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return None
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

def main():
    if len(sys.argv) > 1:
        username = sys.argv[1]
        with open(STUDENT_DATA_PATH, 'r') as f:
            data = json.load(f)
        
        student = next((s for s in data["students"] if s["username"] == username), None)
        if not student:
            print(f"❌ Student not found: {username}")
            sys.exit(1)
    else:
        with open(STUDENT_DATA_PATH, 'r') as f:
            data = json.load(f)
        student = data["students"][0]
    
    team_id = os.environ.get("TEAM_ID", "K33BDFCCHR")
    
    print(f"📋 Generating pass for: {student['full_name']}")
    print(f"   ID: {student['formatted_id']}")
    
    result = generate_signed_pass(student, team_id)
    
    if result:
        print(f"\n✅ Pass ready: {result}")
        print(f"   Size: {os.path.getsize(result)} bytes")
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
