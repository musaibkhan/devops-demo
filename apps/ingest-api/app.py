"""Edge ingest API: accepts a dictated care note and durably queues it in the local Kafka."""
import json
import os
import random
import time
import uuid

from confluent_kafka import Producer
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, make_asgi_app
from pydantic import BaseModel

VERSION = os.getenv("APP_VERSION", "dev")
SITE = os.getenv("SITE_ID", "edge")
TOPIC = os.getenv("KAFKA_TOPIC", "care-notes")
# Fault injection for the canary demo: fraction of requests that fail with HTTP 500.
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))

producer = Producer({
    "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP"],
    "acks": "all",
    "enable.idempotence": True,
})
REQUESTS = Counter("ingest_requests_total", "Ingest requests by HTTP status and app version", ["code", "version"])

app = FastAPI()
app.mount("/metrics", make_asgi_app())


class Note(BaseModel):
    room: str
    audio_b64: str  # the dictation; transcribed in the cloud


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": VERSION}


@app.post("/notes", status_code=202)
def ingest(note: Note):
    if random.random() < ERROR_RATE:
        REQUESTS.labels("500", VERSION).inc()
        raise HTTPException(500, "injected failure")

    event = {
        "id": str(uuid.uuid4()),
        "site": SITE,
        "room": note.room,
        "audio_b64": note.audio_b64,
        "received_at": time.time(),
        "ingest_version": VERSION,
    }
    result = {}
    producer.produce(TOPIC, key=note.room, value=json.dumps(event),
                     on_delivery=lambda err, _msg: result.update(err=err))
    producer.flush(5)
    # Only acknowledge once Kafka has the note: a 202 means it cannot be lost.
    if "err" not in result or result["err"] is not None:
        REQUESTS.labels("503", VERSION).inc()
        raise HTTPException(503, "note not persisted, retry")

    REQUESTS.labels("202", VERSION).inc()
    return {"id": event["id"], "version": VERSION}
