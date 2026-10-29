import json
import os
import time
import uuid
from datetime import datetime, timezone

import pymysql
from flask import Flask, g, jsonify, request
from werkzeug.exceptions import HTTPException

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024

APP_VERSION = "0.2.0"


def log_event(event, **fields):
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "security-lab-api",
        "version": APP_VERSION,
        "event": event,
        "request_id": g.request_id,
        **fields,
    }
    print(json.dumps(record, ensure_ascii=False), flush=True)


def db_configured():
    required = (
        "DB_HOST",
        "DB_NAME",
        "DB_USER",
        "DB_PASSWORD",
        "DB_SSL_CA",
    )
    return all(os.environ.get(name) for name in required)


def open_db():
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
        connect_timeout=5,
        read_timeout=5,
        write_timeout=5,
        ssl_ca=os.environ["DB_SSL_CA"],
        ssl_verify_cert=True,
        ssl_verify_identity=True,
        local_infile=False,
    )


@app.before_request
def begin_request():
    g.started_at = time.perf_counter()
    g.request_id = str(uuid.uuid4())


@app.after_request
def record_request(response):
    response.headers["X-Request-ID"] = g.request_id
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    if request.path != "/healthz" or response.status_code != 200:
        log_event(
            "http_request",
            method=request.method,
            path=request.path,
            status=response.status_code,
            duration_ms=round(
                (time.perf_counter() - g.started_at) * 1000, 2
            ),
            peer_ip=request.remote_addr,
        )
    return response


@app.get("/")
def index():
    return jsonify(
        service="security-lab-api",
        version=APP_VERSION,
        status="ok",
    )


@app.get("/healthz")
def health():
    return jsonify(status="ok")


@app.get("/api/info")
def info():
    return jsonify(
        project="security-observability-lab",
        version=APP_VERSION,
        database="configured" if db_configured() else "not-configured",
    )


@app.get("/api/db")
def database_status():
    if not db_configured():
        log_event("db_error", error_type="ConfigurationMissing")
        return jsonify(
            database="not-configured",
            request_id=g.request_id,
        ), 503

    try:
        with open_db() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT id, message "
                    "FROM lab_status WHERE id = %s",
                    (1,),
                )
                row = cursor.fetchone()

        if row is None:
            log_event("db_error", error_type="VerificationRowMissing")
            return jsonify(
                database="connected",
                error="verification-data-missing",
                request_id=g.request_id,
            ), 503

        log_event("db_query", outcome="success")
        return jsonify(
            database="connected",
            data=row,
            request_id=g.request_id,
        )

    except (pymysql.MySQLError, OSError, ValueError) as error:
        log_event("db_error", error_type=type(error).__name__)
        return jsonify(
            database="unavailable",
            request_id=g.request_id,
        ), 503


@app.errorhandler(HTTPException)
def http_error(error):
    return jsonify(
        error=error.name,
        status=error.code,
        request_id=g.request_id,
    ), error.code