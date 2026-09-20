#!/usr/bin/env python3
"""Based Meter results API.

A tiny stdlib-only HTTP service that records basedness results in SQLite and
serves the most recent entries to the based.romanpeters.nl front-end.

Endpoints (all under /api):
  GET  /api/healthz   -> {"ok": true}
  GET  /api/results   -> {"recent": [{text, score}, ...]}  (10 most recent)
  POST /api/results   body {"text": str, "score": float}
                       -> {"recent": [...]}  (10 most recent *before* this
                          insert, so the caller's own entry is excluded)
"""
import json
import os
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB_PATH = os.environ.get("DB_PATH", "/data/results.db")
PORT = int(os.environ.get("PORT", "8080"))
RECENT_LIMIT = 10
MAX_ROWS = 500

_lock = threading.Lock()


def _connect():
    conn = sqlite3.connect(DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with _lock:
        conn = _connect()
        try:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS results ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                "ts INTEGER NOT NULL, "
                "text TEXT NOT NULL, "
                "score REAL NOT NULL)"
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_results_id_desc ON results (id DESC)"
            )
            conn.commit()
        finally:
            conn.close()


def recent(limit=RECENT_LIMIT):
    with _lock:
        conn = _connect()
        try:
            rows = conn.execute(
                "SELECT text, score FROM results ORDER BY id DESC LIMIT ?",
                (limit,),
            ).fetchall()
        finally:
            conn.close()
    return [{"text": row["text"], "score": row["score"]} for row in rows]


def add(text, score):
    """Insert a result and return the recent list as it was *before* the
    insert, so the caller's own entry is never included in the response."""
    snapshot = recent()
    with _lock:
        conn = _connect()
        try:
            conn.execute(
                "INSERT INTO results (ts, text, score) VALUES (?, ?, ?)",
                (int(time.time()), text, score),
            )
            conn.execute(
                "DELETE FROM results WHERE id NOT IN ("
                "SELECT id FROM results ORDER BY id DESC LIMIT ?)",
                (MAX_ROWS,),
            )
            conn.commit()
        finally:
            conn.close()
    return snapshot


class Handler(BaseHTTPRequestHandler):
    server_version = "BasedMeterAPI/1.0"
    protocol_version = "HTTP/1.1"

    def _send(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/healthz":
            self._send(200, {"ok": True})
        elif path == "/api/results":
            self._send(200, {"recent": recent()})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path != "/api/results":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"error": "invalid JSON body"})
            return
        text = str(data.get("text", "")).strip()
        if not text:
            self._send(400, {"error": "text is required"})
            return
        try:
            score = float(data.get("score", 0.0))
        except (TypeError, ValueError):
            self._send(400, {"error": "score must be a number"})
            return
        score = max(0.0, min(1.0, score))
        self._send(200, {"recent": add(text, score)})

    def log_message(self, format, *args):
        pass


def main():
    directory = os.path.dirname(DB_PATH)
    if directory:
        os.makedirs(directory, exist_ok=True)
    init_db()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    server.serve_forever()


if __name__ == "__main__":
    main()
