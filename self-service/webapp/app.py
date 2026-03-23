#!/usr/bin/env python3
"""
Self-service request portal for dynamic IP whitelisting.
Accepts requests with duration and source IP, saves to JSON files for polysquid to consume.
"""

from flask import Flask, render_template, request, jsonify
from waitress import serve
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import logging

app = Flask(__name__)

# Configuration
REQUESTS_DIR = os.getenv("REQUESTS_DIR", "/shared/requests")
REQUEST_PORT = int(os.getenv("REQUEST_PORT", 5000))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format="%(asctime)s %(levelname)s %(message)s"
)
log = logging.getLogger("self-service-portal")

# Ensure requests directory exists
Path(REQUESTS_DIR).mkdir(parents=True, exist_ok=True)


@app.route("/", methods=["GET"])
def index():
    """Serve the request portal form."""
    return render_template("portal.html")


@app.route("/api/request", methods=["POST"])
def submit_request():
    """
    Accept a whitelist request with duration and client IP.
    Saves to a JSON file for polysquid to read and process.
    
    Expected JSON:
    {
        "duration_minutes": 60,
        "reason": "Optional description"
    }
    
    Source IP is automatically captured.
    """
    try:
        data = request.get_json() or {}
        
        # Validate and extract fields
        duration_minutes = data.get("duration_minutes")
        reason = str(data.get("reason", ""))[:500]
        
        if not duration_minutes:
            return jsonify({"error": "duration_minutes is required"}), 400
        
        try:
            duration_minutes = int(duration_minutes)
            if duration_minutes < 1 or duration_minutes > 1440:  # Max 24 hours
                return jsonify({"error": "duration_minutes must be between 1 and 1440"}), 400
        except ValueError:
            return jsonify({"error": "duration_minutes must be an integer"}), 400
        
        # Get source IP — use X-Real-IP set by nginx ($remote_addr) to prevent
        # client-controlled X-Forwarded-For header from spoofing an arbitrary IP.
        source_ip = request.headers.get("X-Real-IP") or request.remote_addr
        
        # Build request object
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(minutes=duration_minutes)

        request_obj = {
            "timestamp": now.isoformat().replace("+00:00", "Z"),
            "source_ip": source_ip,
            "duration_minutes": duration_minutes,
            "expires_at": expires_at.isoformat().replace("+00:00", "Z"),
            "reason": reason,
            "status": "pending"
        }
        
        # Save to file (request_<timestamp>.json)
        filename = f"request_{now.strftime('%Y%m%d_%H%M%S_%f')}.json"
        filepath = Path(REQUESTS_DIR) / filename
        
        with filepath.open("w") as f:
            json.dump(request_obj, f, indent=2)
        
        log.info(f"Request received: {source_ip} for {duration_minutes} minutes, saved to {filename}")
        
        return jsonify({
            "status": "success",
            "message": f"Request submitted for {duration_minutes} minutes",
            "request_id": filename,
            "expires_at": expires_at.isoformat().replace("+00:00", "Z")
        }), 201
    
    except Exception as e:
        log.error(f"Error processing request: {e}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/api/whoami", methods=["GET"])
def whoami():
    """Return the client IP as seen by the server (from nginx X-Real-IP)."""
    source_ip = request.headers.get("X-Real-IP") or request.remote_addr
    return jsonify({"ip": source_ip}), 200


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint."""
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    log.info(f"Starting Self-Service Portal on port {REQUEST_PORT}, requests dir: {REQUESTS_DIR}")
    serve(app, host="0.0.0.0", port=REQUEST_PORT)
