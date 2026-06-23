import os
from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes.attacks   import router as attacks_router
from routes.anomalies import router as anomalies_router

app = FastAPI(title="Beehive Bridge", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[os.getenv("CORS_ORIGIN", "http://localhost:5173")],
    allow_methods=["GET"],
    allow_headers=["*"],
)

app.include_router(attacks_router)
app.include_router(anomalies_router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "beehive-bridge"}
