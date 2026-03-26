"""
Sign a .pkpass file using Apple Developer certificate.
Requires: openssl, certificate file (.p12 or .pem with private key)
"""
import os
import sys
import subprocess
import tempfile
import json
import shutil

def sign_pass_with_certificate(pkpass_path, cert_path, cert_password=None, wwdr_cert_path=None):
    """
    Sign a .pkpass file using a certificate.
    
    Args:
        pkpass_path: Path to the .pkpass file to sign
        cert_path: Path to certificate (.p12 or .pem)
        cert_password: Password for .p12 certificate (if needed)
        wwdr_cert_path: Path to Apple WWDR intermediate certificate (optional)
    """
    
    if not os.path.exists(pkpass_path):
        print(f"❌ Pass file not found: {pkpass_path}")
        return False
    
    if not os.path.exists(cert_path):
        print(f"❌ Certificate not found: {cert_path}")
        return False
    
    temp_dir = tempfile.mkdtemp(prefix="pkpass_sign_")
    
    try:
        print(f"📦 Extracting pass package...")
        subprocess.run(["unzip", "-q", pkpass_path, "-d", temp_dir], check=True)
        
        manifest_path = os.path.join(temp_dir, "manifest.json")
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        
        print(f"✅ Extracted pass package")
        print(f"📄 Manifest contains {len(manifest)} files")
        
        print(f"🔐 Signing manifest.json...")
        
        cert_ext = os.path.splitext(cert_path)[1].lower()
        
        if cert_ext == '.p12':
            key_path = os.path.join(temp_dir, "key.pem")
            cert_pem_path = os.path.join(temp_dir, "cert.pem")
            
            password = cert_password or ""
            
            print(f"🔑 Extracting private key from certificate...")
            cmd = [
                "openssl", "pkcs12", "-in", cert_path,
                "-nocerts", "-nodes", "-out", key_path,
                "-passin", f"pass:{password}"
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                if not cert_password:
                    print("🔐 Certificate requires a password")
                    import getpass
                    password = getpass.getpass("Enter certificate password: ")
                    cmd = [
                        "openssl", "pkcs12", "-in", cert_path,
                        "-nocerts", "-nodes", "-out", key_path,
                        "-passin", f"pass:{password}"
                    ]
                    result = subprocess.run(cmd, capture_output=True, text=True)
                
                if result.returncode != 0:
                    print(f"❌ Failed to extract private key: {result.stderr}")
                    return False
            
            print(f"📜 Extracting certificate...")
            cmd = [
                "openssl", "pkcs12", "-in", cert_path,
                "-clcerts", "-nokeys", "-out", cert_pem_path,
                "-passin", f"pass:{password}"
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"❌ Failed to extract certificate: {result.stderr}")
                return False
            
            print(f"✍️  Signing manifest.json...")
            signature_path = os.path.join(temp_dir, "signature")
            cmd = [
                "openssl", "smime", "-binary", "-sign",
                "-signer", cert_pem_path,
                "-inkey", key_path,
                "-in", manifest_path,
                "-out", signature_path,
                "-outform", "DER",
                "-noattr"
            ]
            if wwdr_cert_path and os.path.exists(wwdr_cert_path):
                cmd.extend(["-certfile", wwdr_cert_path])
                print(f"   Using WWDR certificate: {os.path.basename(wwdr_cert_path)}")
            else:
                print(f"   ⚠️  Warning: WWDR certificate not found - pass may not work in Apple Wallet")
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"❌ Signing failed: {result.stderr}")
                if result.stdout:
                    print(f"   stdout: {result.stdout}")
                return False
            
            print(f"✅ Signed manifest.json with WWDR certificate")
                
        elif cert_ext in ['.pem', '.key']:
            signature_path = os.path.join(temp_dir, "signature")
            cmd = [
                "openssl", "smime", "-binary", "-sign",
                "-signer", cert_path,
                "-inkey", cert_path,
                "-in", manifest_path,
                "-out", signature_path,
                "-outform", "DER"
            ]
            
            if wwdr_cert_path and os.path.exists(wwdr_cert_path):
                cmd.extend(["-certfile", wwdr_cert_path])
                print(f"   Using WWDR certificate: {os.path.basename(wwdr_cert_path)}")
            else:
                print(f"   ⚠️  Warning: WWDR certificate not found - pass may not work in Apple Wallet")
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"❌ Signing failed: {result.stderr}")
                if result.stdout:
                    print(f"   stdout: {result.stdout}")
                return False
            
            print(f"✅ Signed manifest.json with WWDR certificate")
        else:
            print(f"❌ Unsupported certificate format: {cert_ext}")
            print("   Supported formats: .p12, .pem")
            return False
        
        print(f"📦 Repackaging signed pass...")
        if os.path.exists(pkpass_path):
            os.remove(pkpass_path)  # Remove old file
        
        import zipfile
        abs_pkpass_path = os.path.abspath(pkpass_path)
        
        with zipfile.ZipFile(abs_pkpass_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            if os.path.exists(os.path.join(temp_dir, "pass.json")):
                zf.write(os.path.join(temp_dir, "pass.json"), "pass.json")
            
            if os.path.exists(os.path.join(temp_dir, "manifest.json")):
                zf.write(os.path.join(temp_dir, "manifest.json"), "manifest.json")
            
            if os.path.exists(os.path.join(temp_dir, "signature")):
                zf.write(os.path.join(temp_dir, "signature"), "signature")
            
            for icon_file in ["icon.png", "icon@2x.png", "icon@3x.png"]:
                icon_path = os.path.join(temp_dir, icon_file)
                if os.path.exists(icon_path):
                    zf.write(icon_path, icon_file)
            
            for logo_file in ["logo.png", "logo@2x.png", "logo@3x.png"]:
                logo_path = os.path.join(temp_dir, logo_file)
                if os.path.exists(logo_path):
                    zf.write(logo_path, logo_file)
            
            for thumb_file in ["thumbnail.png", "thumbnail@2x.png", "thumbnail@3x.png"]:
                thumb_path = os.path.join(temp_dir, thumb_file)
                if os.path.exists(thumb_path):
                    zf.write(thumb_path, thumb_file)
        
        print(f"✅ Created signed pass: {pkpass_path}")
        print(f"📦 File size: {os.path.getsize(pkpass_path)} bytes")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 sign_pass.py <pkpass_file> <certificate_file> [certificate_password]")
        print("\nExample:")
        print("  python3 sign_pass.py data/passes/ajagana.pkpass epschedule/Certificates_ios.p12")
        print("  python3 sign_pass.py data/passes/ajagana.pkpass epschedule/Certificates_ios.p12 'password'")
        sys.exit(1)
    
    pkpass_path = sys.argv[1]
    cert_path = sys.argv[2]
    cert_password = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("CERT_PASSWORD")
    
    wwdr_cert = os.path.join(os.path.dirname(__file__), "../wwdr_g4.pem")
    if not os.path.exists(wwdr_cert):
        wwdr_cert = os.path.join(os.path.dirname(__file__), "../wwdr.pem")
    if not os.path.exists(wwdr_cert):
        wwdr_cert = None
    
    success = sign_pass_with_certificate(pkpass_path, cert_path, cert_password, wwdr_cert)
    
    if success:
        print("\n✅ Pass signed successfully!")
        print("   You can now add it to Apple Wallet")
    else:
        print("\n❌ Failed to sign pass")
        sys.exit(1)

if __name__ == "__main__":
    main()
