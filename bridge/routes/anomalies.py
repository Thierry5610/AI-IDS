import os
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from consumer import stream_events

router = APIRouter()
STREAM = os.getenv("IDS_ANOMALIES_STREAM", "ids:anomalies")


@router.get("/stream/anomalies")
async def anomalies_sse(request: Request):
    async def generator():
        async for payload in stream_events(STREAM, "0"):
            if await request.is_disconnected():
                break
            if payload is None:
                yield {"comment": "heartbeat"}
            else:
                yield {"event": "anomaly", "data": payload}
    return EventSourceResponse(generator())
