import json
import logging
import os
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit, unquote

from google.api_core.exceptions import NotFound
from google.cloud import storage, pubsub_v1, logging as gcp_logging

PROJECT = "project-f131ec20-0df6-4cfa-bf0"
BUCKET = "cs528-12kfiles-bucket-thomas"
PREFIX = "12k-files/"
TOPIC = "forbidden-requests"

HOST = "0.0.0.0"
# 8080 by default for local testing; set PORT=80 on the VM.
PORT = int(os.environ.get("PORT", "8080"))

# Cloud Logging: attach a handler to Python's standard logging.
# It ships logs in a background thread, so logging doesn't block requests.
gcp_logging.Client(project=PROJECT).setup_logging(log_level=logging.INFO)
logger = logging.getLogger("hw4-service1")

LEVELS = {
    "INFO": logging.INFO,
    "WARNING": logging.WARNING,
    "ERROR": logging.ERROR,
    "CRITICAL": logging.CRITICAL,
}


def log(severity, message, **fields):
    """Write one structured log entry to Cloud Logging."""
    logger.log(LEVELS[severity], message, extra={"json_fields": fields})


def norm(s):
    return s.strip().lower().replace("_", " ").replace("-", " ")


FORBIDDEN = {norm(c) for c in [
    "North Korea", "Iran", "Cuba", "Myanmar", "Iraq",
    "Libya", "Sudan", "Zimbabwe", "Syria",
]}

# Created once at startup and reused for every request.
bucket = storage.Client(project=PROJECT).bucket(BUCKET)
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT, TOPIC)


class MyServer(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # silence the built-in per-request access log

    def send_text_response(self, text, status_code=200, include_body=True):
        body = text.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))  # bytes, not characters
        self.end_headers()
        if include_body:
            self.wfile.write(body)

    # GET and POST

    def do_GET(self):
        # Drop any ?query string, decode %20 etc., remove the leading slash.
        path = unquote(urlsplit(self.path).path)
        self.serve_file(path.lstrip("/"))

    def do_POST(self):
        # Expected payload: {"file": "file_5.txt"} or {"file": "12k-files/5.html"}
        try:
            length = int(self.headers.get("Content-Length", 0) or 0)
            raw = self.rfile.read(length) if length > 0 else b""
            name = json.loads(raw).get("file", "")
        except (ValueError, AttributeError):
            # bad Content-Length, invalid JSON, or JSON that isn't an object
            name = ""
        self.serve_file(str(name))

    # Error 501

    def not_implemented(self):
        log("ERROR", "501 not implemented",
            method=self.command, path=self.path, client=self.client_address[0])
        # A response to HEAD must not carry a body.
        self.send_text_response("Not implemented", 501,
                                include_body=self.command != "HEAD")

    do_PUT = do_DELETE = do_HEAD = do_CONNECT = not_implemented
    do_OPTIONS = do_TRACE = do_PATCH = not_implemented

    # Serve file

    def serve_file(self, name):
        # 1. Banned-country check
        country = self.headers.get("X-country", "")
        if norm(country) in FORBIDDEN:
            log("CRITICAL", "forbidden country request",
                country=country, path=self.path, method=self.command,
                client=self.client_address[0])
            publisher.publish(topic_path, json.dumps(
                {"country": country, "path": self.path}).encode()).result()
            self.send_text_response("Permission denied", 400)
            return

        # 2. Map the client's 12k-files/N.html paths to file_N.txt
        name = name.removeprefix("12k-files/")
        m = re.fullmatch(r"(\d+)\.html", name)
        if m:
            name = f"file_{m.group(1)}.txt"

        if not name.endswith(".txt"):
            log("WARNING", "404 invalid file name",
                file=name, method=self.command, client=self.client_address[0])
            self.send_text_response("File not found", 404)
            return

        # 3. One round trip to Cloud Storage
        try:
            content = bucket.blob(PREFIX + name).download_as_text()
        except NotFound:
            log("WARNING", "404 file not found",
                file=name, method=self.command, client=self.client_address[0])
            self.send_text_response("File not found", 404)
            return
        except Exception as e:
            # Not a missing file: a real server-side failure (permissions, network, ...)
            log("ERROR", "500 storage error",
                file=name, error=str(e), client=self.client_address[0])
            self.send_text_response("Internal server error", 500)
            return

        self.send_text_response(content, 200)


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), MyServer)
    print(f"Serving on {HOST}:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()