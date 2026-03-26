"""
Script to upload Apple Wallet passes (.pkpass files) to Google Cloud Storage.
Passes can then be served via the /api/pass/<username> endpoint.
"""
import os
import sys

from google.cloud import storage

CREDS_PATH = os.path.join(os.path.dirname(__file__), "../service_account.json")
PASSES_DIR = os.path.join(os.path.dirname(__file__), "../data/passes")

def upload_pass(username, pass_file_path):
    """Upload a single pass file to Google Cloud Storage."""
    if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
        if os.path.exists(CREDS_PATH):
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = CREDS_PATH
    
    if not os.path.exists(pass_file_path):
        print(f"❌ Pass file not found: {pass_file_path}")
        return False
    
    try:
        storage_client = storage.Client()
        passes_bucket = storage_client.bucket("epschedule-data")
        
        blob_name = f"passes/{username}.pkpass"
        blob = passes_bucket.blob(blob_name)
        
        blob.upload_from_filename(pass_file_path)
        
        print(f"✅ Uploaded pass for {username} to {blob_name}")
        return True
    except Exception as e:
        print(f"❌ Error uploading pass for {username}: {e}")
        return False

def upload_all_passes(passes_directory=None):
    """Upload all .pkpass files from a directory."""
    if passes_directory is None:
        passes_directory = PASSES_DIR
    
    if not os.path.exists(passes_directory):
        print(f"❌ Passes directory not found: {passes_directory}")
        print(f"💡 Create the directory and add .pkpass files named by username (e.g., 'cwest.pkpass')")
        return
    
    pass_files = [f for f in os.listdir(passes_directory) if f.endswith('.pkpass')]
    
    if not pass_files:
        print(f"⚠️  No .pkpass files found in {passes_directory}")
        return
    
    print(f"📦 Found {len(pass_files)} pass files to upload")
    
    uploaded = 0
    failed = 0
    
    for pass_file in pass_files:
        username = pass_file.replace('.pkpass', '')
        pass_path = os.path.join(passes_directory, pass_file)
        
        if upload_pass(username, pass_path):
            uploaded += 1
        else:
            failed += 1
    
    print(f"\n✅ Uploaded {uploaded} passes")
    if failed > 0:
        print(f"❌ Failed to upload {failed} passes")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        pass_file = sys.argv[1]
        if len(sys.argv) > 2:
            username = sys.argv[2]
        else:
            username = os.path.basename(pass_file).replace('.pkpass', '')
        upload_pass(username, pass_file)
    else:
        upload_all_passes()
