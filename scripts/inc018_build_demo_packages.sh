#!/usr/bin/env bash
set -euo pipefail

root=".lab-artifacts/inc018"
rm -rf "$root"
mkdir -p "$root"

build_package() {
    local version="$1"
    local mode="$2"
    local pkgroot="$root/support-demo-$version"

    mkdir -p "$pkgroot/DEBIAN" "$pkgroot/usr/local/bin" "$pkgroot/lib/systemd/system"

    cat >"$pkgroot/DEBIAN/control" <<EOF
Package: support-demo
Version: $version
Section: utils
Priority: optional
Architecture: all
Maintainer: Ubuntu KVM Support Lab <lab@example.invalid>
Description: Controlled package-regression demo for support troubleshooting
EOF

    if [[ "$mode" == "healthy" ]]; then
        cat >"$pkgroot/usr/local/bin/support-demo" <<'EOF'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b"status=ok version=1.0\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
EOF
    else
        cat >"$pkgroot/usr/local/bin/support-demo" <<'EOF'
#!/usr/bin/env python3
import sys

print("support-demo 1.1: controlled regression: invalid startup configuration", flush=True)
sys.exit(42)
EOF
    fi

    chmod 0755 "$pkgroot/usr/local/bin/support-demo"

    cat >"$pkgroot/lib/systemd/system/support-demo.service" <<'EOF'
[Unit]
Description=INC018 controlled package-regression demo
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/support-demo
Restart=no

[Install]
WantedBy=multi-user.target
EOF

    cat >"$pkgroot/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable support-demo.service >/dev/null 2>&1 || true
exit 0
EOF
    chmod 0755 "$pkgroot/DEBIAN/postinst"

    dpkg-deb --build "$pkgroot" "$root/support-demo_${version}_all.deb" >/dev/null
}

build_package "1.0" "healthy"
build_package "1.1" "broken"

echo "Built:"
ls -lh "$root"/*.deb
