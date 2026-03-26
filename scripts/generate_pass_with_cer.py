"""
Generate and sign a pass using pass.cer (or Certificates_ios.p12).
Matches the structure used to create StudentID.pkpass.
"""
import json
import os
import sys
import subprocess
import tempfile
import shutil
import hashlib
import zipfile
from datetime import datetime, timedelta

STUDENT_DATA_PATH = os.path.join(os.path.dirname(__file__), "../data/student_ids_for_passes.json")
CERT_PATH = os.path.join(os.path.dirname(__file__), "../pass.cer")
P12_PATH = os.path.join(os.path.dirname(__file__), "../epschedule/Certificates_ios.p12")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "../data/passes")

def generate_signed_pass(student_data, team_id="K33BDFCCHR"):
    """Generate and sign a pass - matches create_pass_package.py structure."""
    
    username = student_data["username"]
    output_path = os.path.join(OUTPUT_DIR, f"{username}.pkpass")
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="pkpass_")
    
    try:
        expiration = (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%dT23:59:59Z")
        
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": "pass.eps.epschedule",
            "serialNumber": student_data["formatted_id"],
            "teamIdentifier": team_id,
            "organizationName": "Eastside Preparatory School",
            "description": "Student ID Card",
            "foregroundColor": "rgb(255, 255, 255)",  # Match working pass colors
            "backgroundColor": "rgb(1, 46, 86)",
            "labelColor": "rgb(180, 200, 220)",
            "generic": {
                "primaryFields": [
                    {
                        "key": "name",
                        "label": "STUDENT",  # Match working pass
                        "value": student_data["full_name"].split()[0] + " " + student_data["full_name"].split()[-1][0] + "." if len(student_data["full_name"].split()) > 1 else student_data["full_name"]
                    }
                ],
                "secondaryFields": [
                    {
                        "key": "id",
                        "label": "ID",  # Match working pass
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
            "barcodes": [  # Use array at root like working pass
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
        
        pass_json_path = os.path.join(temp_dir, "pass.json")
        with open(pass_json_path, 'w') as f:
            json.dump(pass_json, f, indent=2)
        
        icon_files = []
        for icon_name in ["icon.png", "icon@2x.png", "icon@3x.png"]:
            icon_paths = [
                os.path.join(os.path.dirname(__file__), f"../epschedule/epschedule/{icon_name}"),
                os.path.join(os.path.dirname(__file__), f"../{icon_name}"),
            ]
            for icon_path in icon_paths:
                if os.path.exists(icon_path):
                    shutil.copy2(icon_path, os.path.join(temp_dir, icon_name))
                    icon_files.append(icon_name)
                    break
        
        manifest = {}
        
        def sha1_hash(file_path):
            with open(file_path, 'rb') as f:
                return hashlib.sha1(f.read()).hexdigest()
        
        manifest["pass.json"] = sha1_hash(pass_json_path)
        for icon_file in icon_files:
            manifest[icon_file] = sha1_hash(os.path.join(temp_dir, icon_file))
        
        manifest_path = os.path.join(temp_dir, "manifest.json")
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2, sort_keys=True)
        
        signature_path = os.path.join(temp_dir, "signature")
        
        if os.path.exists(P12_PATH):
            cert_file = P12_PATH
            print("✅ Using Certificates_ios.p12")
            
            key_path = os.path.join(temp_dir, "key.pem")
            cert_pem_path = os.path.join(temp_dir, "cert.pem")
            
            subprocess.run([
                "openssl", "pkcs12", "-in", cert_file,
                "-nocerts", "-nodes", "-out", key_path,
                "-passin", "pass:"
            ], check=True, capture_output=True)
            
            subprocess.run([
                "openssl", "pkcs12", "-in", cert_file,
                "-clcerts", "-nokeys", "-out", cert_pem_path,
                "-passin", "pass:"
            ], check=True, capture_output=True)
            
            signer_cert = cert_pem_path
            signer_key = key_path
            
        elif os.path.exists(CERT_PATH):
            print("⚠️  pass.cer found but needs private key for signing")
            print("   Looking for corresponding .p12 or .pem file...")
            if os.path.exists(P12_PATH):
                cert_file = P12_PATH
                key_path = os.path.join(temp_dir, "key.pem")
                cert_pem_path = os.path.join(temp_dir, "cert.pem")
                subprocess.run([
                    "openssl", "pkcs12", "-in", cert_file,
                    "-nocerts", "-nodes", "-out", key_path,
                    "-passin", "pass:"
                ], check=True, capture_output=True)
                subprocess.run([
                    "openssl", "pkcs12", "-in", cert_file,
                    "-clcerts", "-nokeys", "-out", cert_pem_path,
                    "-passin", "pass:"
                ], check=True, capture_output=True)
                signer_cert = cert_pem_path
                signer_key = key_path
            else:
                raise Exception("Need .p12 file with private key for signing")
        else:
            raise Exception("No certificate found. Need Certificates_ios.p12 or pass.cer with private key")
        
        wwdr_path = None
        wwdr_certs = [
            ("../wwdr_g4.pem", "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer"),
            ("../wwdr.pem", "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"),
        ]
        
        for wwdr_rel_path, wwdr_url in wwdr_certs:
            wwdr_full_path = os.path.join(os.path.dirname(__file__), wwdr_rel_path)
            if os.path.exists(wwdr_full_path):
                wwdr_path = wwdr_full_path
                break
        
        if not wwdr_path:
            print("📥 Downloading WWDR G4 certificate...")
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
        
        sign_cmd = [
            "openssl", "smime", "-binary", "-sign",
            "-signer", signer_cert,
            "-inkey", signer_key,
            "-in", manifest_path,
            "-out", signature_path,
            "-outform", "DER",
            "-noattr"
        ]
        
        if wwdr_path:
            sign_cmd.extend(["-certfile", wwdr_path])
            print("✅ Using WWDR certificate")
        
        result = subprocess.run(sign_cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception(f"Signing failed: {result.stderr}")
        
        old_cwd = os.getcwd()
        os.chdir(temp_dir)
        try:
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
