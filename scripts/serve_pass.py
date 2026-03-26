"""
Local server to preview and serve .pkpass files.
Serves the pass with application/vnd.apple.pkpass MIME type.
Open on iPhone (same WiFi) to add to Apple Wallet.
"""
import http.server
import json
import os
import socket
import sys
import webbrowser
import zipfile

PORT = 8089
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PASSES_DIR = os.path.join(BASE_DIR, "..", "data", "passes")

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "localhost"

def extract_pass_data(pkpass_path):
    with zipfile.ZipFile(pkpass_path, "r") as zf:
        with zf.open("pass.json") as f:
            return json.load(f)

LOCAL_IP = get_local_ip()

def build_html(username):
    """Build page with download links for all signing variants."""
    main_pass = os.path.join(PASSES_DIR, f"{username}.pkpass")
    pass_data = extract_pass_data(main_pass)

    generic = pass_data.get("generic", {})
    primary = generic.get("primaryFields", [{}])[0]
    secondary = generic.get("secondaryFields", [])
    auxiliary = generic.get("auxiliaryFields", [])
    barcodes = pass_data.get("barcodes", [])
    barcode = barcodes[0] if barcodes else pass_data.get("barcode", {})

    bg = pass_data.get("backgroundColor", "rgb(1, 46, 86)")
    fg = pass_data.get("foregroundColor", "rgb(255, 255, 255)")
    label_color = pass_data.get("labelColor", "rgb(180, 200, 220)")
    org = pass_data.get("organizationName", "")
    barcode_msg = barcode.get("message", "")

    sec_html = ""
    for field in secondary:
        sec_html += f'<div class="field"><div class="label">{field.get("label","")}</div><div class="value">{field.get("value","")}</div></div>'

    aux_html = ""
    for field in auxiliary:
        aux_html += f'<div class="field"><div class="label">{field.get("label","")}</div><div class="value">{field.get("value","")}</div></div>'

    variants = []
    for suffix in ["", "_smime", "_cms", "_noattr"]:
        fname = f"{username}{suffix}.pkpass"
        fpath = os.path.join(PASSES_DIR, fname)
        if os.path.exists(fpath):
            size = os.path.getsize(fpath)
            label = {
                "": "Default (smime)",
                "_smime": "smime -sign (with attrs)",
                "_cms": "cms -sign",
                "_noattr": "smime -sign -noattr",
            }.get(suffix, suffix)
            variants.append((fname, label, size))

    variant_buttons = ""
    for fname, label, size in variants:
        url = f"/pass/{fname}"
        variant_buttons += f"""
        <a href="{url}" class="dl-btn">
            <span class="dl-label">{label}</span>
            <span class="dl-size">{size:,} bytes</span>
        </a>"""

    phone_url = f"http://{LOCAL_IP}:{PORT}"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Wallet Pass - {primary.get('value','Student ID')}</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif;background:#111;min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:40px 16px;color:#fff}}
h1{{font-size:14px;text-transform:uppercase;letter-spacing:2px;color:#666;margin-bottom:24px}}
.card{{width:340px;background:{bg};border-radius:14px;overflow:hidden;box-shadow:0 20px 60px rgba(0,0,0,.5);margin-bottom:30px}}
.card-header{{display:flex;justify-content:space-between;align-items:center;padding:16px 20px 4px}}
.card-org{{font-size:11px;opacity:.5}}
.card-type{{font-size:10px;text-transform:uppercase;letter-spacing:1px;opacity:.4}}
.primary{{padding:16px 20px 8px}}
.primary .label{{font-size:9px;text-transform:uppercase;letter-spacing:1.5px;color:{label_color}}}
.primary .value{{font-size:28px;font-weight:700;margin-top:2px}}
.fields{{display:flex;gap:20px;padding:8px 20px 14px}}
.field .label{{font-size:9px;text-transform:uppercase;letter-spacing:1.2px;color:{label_color}}}
.field .value{{font-size:15px;font-weight:600;margin-top:2px}}
.barcode-area{{background:#fff;margin:6px 20px 18px;border-radius:8px;padding:16px;text-align:center}}
.barcode-lines{{display:flex;align-items:flex-end;justify-content:center;gap:1px;height:55px;margin-bottom:8px}}
.barcode-line{{background:#000}}
.barcode-text{{font-family:'SF Mono',Menlo,monospace;font-size:13px;color:#333;letter-spacing:2px}}
.downloads{{width:340px;display:flex;flex-direction:column;gap:10px;margin-bottom:24px}}
.dl-btn{{display:flex;justify-content:space-between;align-items:center;background:#1a1a2e;border:1px solid #333;border-radius:10px;padding:14px 18px;text-decoration:none;color:#fff;transition:background .15s}}
.dl-btn:hover{{background:#252545}}
.dl-label{{font-size:14px;font-weight:500}}
.dl-size{{font-size:11px;color:#888}}
.note{{text-align:center;max-width:380px;margin-top:10px}}
.note p{{color:#777;font-size:12px;line-height:1.6}}
.note .url{{font-family:'SF Mono',monospace;font-size:12px;background:#1a1a2e;padding:6px 12px;border-radius:6px;color:#7ec8e3;margin-top:6px;display:inline-block}}
.ok{{margin-top:16px;padding:10px 18px;background:#0a1f0a;border:1px solid #1a3a1a;border-radius:8px;color:#4c4;font-size:11px;text-align:center}}
</style>
</head>
<body>
<h1>Apple Wallet Pass</h1>

<div class="card">
  <div class="card-header">
    <div>
      <div style="font-size:18px;font-weight:700;letter-spacing:1px">{pass_data.get('logoText','')}</div>
      <div class="card-org">{org}</div>
    </div>
    <div class="card-type">Student ID</div>
  </div>
  <div class="primary">
    <div class="label">{primary.get('label','')}</div>
    <div class="value">{primary.get('value','')}</div>
  </div>
  <div class="fields">{sec_html}</div>
  {"<div class='fields'>" + aux_html + "</div>" if aux_html else ""}
  <div class="barcode-area">
    <div class="barcode-lines" id="bc"></div>
    <div class="barcode-text">{barcode.get('altText', barcode_msg)}</div>
  </div>
</div>

<div class="downloads">
  <div style="font-size:11px;text-transform:uppercase;letter-spacing:1.5px;color:#666;margin-bottom:4px">Download .pkpass</div>
  {variant_buttons}
</div>

<div class="note">
  <p>Open on iPhone (same WiFi) to add to Apple Wallet:</p>
  <div class="url">{phone_url}</div>
</div>

<div class="ok">
  Pass Type ID: {pass_data.get('passTypeIdentifier','')} &bull;
  Team: {pass_data.get('teamIdentifier','')} &bull;
  Serial: {pass_data.get('serialNumber','')}
</div>

<script>
const c=document.getElementById('bc');
for(let i=0;i<70;i++){{const l=document.createElement('div');l.className='barcode-line';l.style.height=(35+Math.random()*20)+'px';l.style.width=(Math.random()>.4?2:1)+'px';if(Math.random()>.7)l.style.background='#fff';c.appendChild(l)}}
</script>
</body>
</html>"""

class PassHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            html = build_html(USERNAME)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html.encode())

        elif self.path.startswith("/pass/") and self.path.endswith(".pkpass"):
            fname = self.path.split("/")[-1]
            fpath = os.path.join(PASSES_DIR, fname)
            if os.path.exists(fpath):
                with open(fpath, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.apple.pkpass")
                self.send_header("Content-Disposition", f'attachment; filename="{fname}"')
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_error(404, f"Pass not found: {fname}")
        else:
            self.send_error(404)

    def log_message(self, fmt, *args):
        if args and "404" in str(args[0]):
            super().log_message(fmt, *args)

USERNAME = "cmansour"

def main():
    global USERNAME
    USERNAME = sys.argv[1] if len(sys.argv) > 1 else "cmansour"
    pkpass_path = os.path.join(PASSES_DIR, f"{USERNAME}.pkpass")

    if not os.path.exists(pkpass_path):
        print(f"Pass not found: {pkpass_path}")
        sys.exit(1)

    pass_data = extract_pass_data(pkpass_path)
    name = pass_data.get("generic", {}).get("primaryFields", [{}])[0].get("value", USERNAME)

    print()
    print(f"  Wallet Pass Server")
    print(f"  Student:  {name}")
    print(f"  Serial:   {pass_data.get('serialNumber', '?')}")
    print()
    print(f"  Mac:      http://localhost:{PORT}")
    print(f"  iPhone:   http://{LOCAL_IP}:{PORT}")
    print()
    print(f"  Open the iPhone URL in Safari to add to Wallet.")
    print(f"  Ctrl+C to stop.")
    print()

    webbrowser.open(f"http://localhost:{PORT}")

    server = http.server.HTTPServer(("0.0.0.0", PORT), PassHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()

if __name__ == "__main__":
    main()
