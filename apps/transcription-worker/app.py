"""Cloud transcription worker: consumes mirrored care notes and "transcribes" them.

The model is a stub (sleep); the interesting part is the processing contract:
offsets are committed only after a note is processed (at-least-once), and the
consumer leaves the group cleanly on SIGTERM so KEDA scale-downs don't stall others.
"""
import json
import os
import signal
import time

from confluent_kafka import Consumer
from prometheus_client import Counter, Histogram, start_http_server

TOPIC = os.getenv("KAFKA_TOPIC", "edge.care-notes")
TRANSCRIBE_SECONDS = float(os.getenv("TRANSCRIBE_SECONDS", "2"))

DONE = Counter("notes_transcribed_total", "Notes transcribed", ["site"])
FAILED = Counter("notes_failed_total", "Notes that could not be parsed")
LATENCY = Histogram(
    "note_end_to_end_seconds",
    "Time from ingest at the edge to transcription done",
    buckets=(1, 5, 10, 30, 60, 120, 300, 900),
)


def log(**fields):
    print(json.dumps(fields), flush=True)


def main():
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    start_http_server(9100)

    consumer = Consumer({
        "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP"],
        "group.id": os.getenv("KAFKA_GROUP", "transcription-worker"),
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
    })
    consumer.subscribe([TOPIC])
    log(event="started", topic=TOPIC)

    while running:
        msg = consumer.poll(1.0)
        if msg is None:
            continue
        if msg.error():
            log(event="kafka_error", error=str(msg.error()))
            continue
        try:
            note = json.loads(msg.value())
            note_id, received_at = note["id"], float(note["received_at"])
        except (ValueError, KeyError, TypeError):
            FAILED.inc()
            log(event="bad_message", offset=msg.offset())
            consumer.commit(msg, asynchronous=False)  # skip poison message
            continue

        time.sleep(TRANSCRIBE_SECONDS)  # stand-in for the speech-to-text model
        consumer.commit(msg, asynchronous=False)

        DONE.labels(note.get("site", "unknown")).inc()
        LATENCY.observe(time.time() - received_at)
        # Never log the dictation itself: it is patient data.
        log(event="transcribed", id=note_id, site=note.get("site"), room=note.get("room"))

    consumer.close()
    log(event="stopped")


if __name__ == "__main__":
    main()
