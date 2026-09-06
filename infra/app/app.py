#!/usr/bin/env python3

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

import psycopg2


DB = {
    "host": "192.168.140.20",
    "port": 5432,
    "dbname": "phase4app",
    "user": "phase4_app",
    "password": os.environ["PHASE4_DB_PASSWORD"],
    "connect_timeout": 2,
}


def check_database():
    conn = None

    try:
        conn = psycopg2.connect(**DB)

        with conn.cursor() as cur:
            cur.execute(
                "SELECT message "
                "FROM support_status "
                "WHERE id = 1;"
            )
            row = cur.fetchone()

        if row:
            return True, row[0]

        return False, "expected database row not found"

    except Exception as exc:
        return False, str(exc)

    finally:
        if conn:
            conn.close()


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(
            "%s - %s" %
            (self.address_string(), fmt % args),
            flush=True,
        )

    def do_GET(self):
        healthy, detail = check_database()

        if self.path == "/health":
            status = 200 if healthy else 503

            body = json.dumps({
                "service": "phase4-web",
                "database": "up" if healthy else "down",
                "detail": detail,
            }).encode()

            self.send_response(status)
            self.send_header(
                "Content-Type",
                "application/json",
            )
            self.send_header(
                "Content-Length",
                str(len(body)),
            )
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/metrics":
            value = 1 if healthy else 0

            body = (
                "# HELP phase4_db_up Whether the application "
                "can query PostgreSQL\n"
                "# TYPE phase4_db_up gauge\n"
                f"phase4_db_up {value}\n"
            ).encode()

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "text/plain; version=0.0.4",
            )
            self.send_header(
                "Content-Length",
                str(len(body)),
            )
            self.end_headers()
            self.wfile.write(body)
            return

        body = b"Phase 4 support application\n"

        self.send_response(200)
        self.send_header(
            "Content-Type",
            "text/plain",
        )
        self.send_header(
            "Content-Length",
            str(len(body)),
        )
        self.end_headers()
        self.wfile.write(body)


HTTPServer(
    ("192.168.140.10", 8080),
    Handler,
).serve_forever()
