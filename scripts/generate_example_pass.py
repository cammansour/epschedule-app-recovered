"""
Example script showing how to generate a pass.json structure for a student.
This is the JSON structure that would be used to create a .pkpass file.
"""
import json
import os
from datetime import datetime, timedelta

STUDENT_DATA_PATH = os.path.join(os.path.dirname(__file__), "../data/student_ids_for_passes.json")

def generate_pass_json(student_data):
    """Generate pass.json structure for a student."""
    
    expiration = (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%dT23:59:59Z")
    
    pass_structure = {
        "formatVersion": 1,
        "passTypeIdentifier": "pass.eps.epschedule",  # Your Apple Developer Pass Type ID
        "serialNumber": student_data["formatted_id"],  # Unique ID for this pass
        "teamIdentifier": "YOUR_TEAM_ID",  # Your Apple Developer Team ID
        "organizationName": "Eastside Preparatory School",
        "description": "Student ID Card",
        "logoText": "EPS",
        "foregroundColor": "rgb(0, 0, 0)",
        "backgroundColor": "rgb(255, 255, 255)",
        "expirationDate": expiration,
        "generic": {
            "primaryFields": [
                {
                    "key": "name",
                    "label": "Name",
                    "value": student_data["full_name"]
                }
            ],
            "secondaryFields": [
                {
                    "key": "id",
                    "label": "Student ID",
                    "value": student_data["formatted_id"]
                }
            ],
            "auxiliaryFields": []
        },
        "barcode": {
            "message": student_data["formatted_id"],  # Barcode encodes the formatted ID
            "format": "PKBarcodeFormatCode128",
            "messageEncoding": "iso-8859-1"
        }
    }
    
    if student_data.get("grad_year"):
        pass_structure["generic"]["secondaryFields"].append({
            "key": "grad_year",
            "label": "Class of",
            "value": str(student_data["grad_year"])
        })
    
    if student_data.get("email"):
        pass_structure["generic"]["auxiliaryFields"].append({
            "key": "email",
            "label": "Email",
            "value": student_data["email"]
        })
    
    return pass_structure

def main():
    with open(STUDENT_DATA_PATH, 'r') as f:
        data = json.load(f)
    
    first_student = data["students"][0]
    
    print(f"📋 Generating example pass for: {first_student['full_name']}")
    print(f"   Username: {first_student['username']}")
    print(f"   Formatted ID: {first_student['formatted_id']}")
    print(f"   Grad Year: {first_student.get('grad_year', 'N/A')}")
    print()
    
    pass_json = generate_pass_json(first_student)
    
    output_path = os.path.join(os.path.dirname(__file__), "../data/example_pass_ajagana.json")
    with open(output_path, 'w') as f:
        json.dump(pass_json, f, indent=2)
    
    print(f"✅ Generated example pass structure:")
    print(f"   Saved to: {output_path}")
    print()
    print("📄 Pass structure:")
    print(json.dumps(pass_json, indent=2))
    print()
    print("📝 Notes:")
    print("   - Replace 'YOUR_TEAM_ID' with your Apple Developer Team ID")
    print("   - Replace 'pass.eps.epschedule' with your registered Pass Type ID")
    print("   - This pass.json needs to be signed with your Apple Developer certificate")
    print("   - After signing, package it with manifest.json and signature into a .pkpass file")

if __name__ == "__main__":
    main()
