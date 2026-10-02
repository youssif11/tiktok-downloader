import os
from urllib.parse import urlparse

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()
API_KEY = os.getenv("SAVEAPI_KEY", "").strip()
BASE = os.getenv("SAVEAPI_BASE", "https://api.saveapi.org/v1").rstrip("/")

app = FastAPI(title="Social Downloader Backend", version="6.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=False, allow_methods=["*"], allow_headers=["*"])


def require_key():
    if not API_KEY:
        raise HTTPException(500, "SAVEAPI_KEY is not configured on the server")


def check_public_http_url(value: str):
    p = urlparse(value)
    if p.scheme not in {"http", "https"} or not p.netloc:
        raise HTTPException(400, "Invalid public http(s) URL")


async def saveapi_get(path: str, params: dict):
    require_key()
    async with httpx.AsyncClient(timeout=35, follow_redirects=True) as client:
        r = await client.get(f"{BASE}{path}", params=params, headers={"Authorization": f"Bearer {API_KEY}"})
    try:
        data = r.json()
    except Exception:
        raise HTTPException(r.status_code, "SaveAPI returned a non-JSON response")
    if r.status_code >= 400:
        err = data.get("error", {}) if isinstance(data, dict) else {}
        raise HTTPException(r.status_code, err.get("message", f"SaveAPI HTTP {r.status_code}"))
    return data


@app.get("/health")
def health():
    return {"ok": True, "saveapi_configured": bool(API_KEY)}


@app.get("/api/platforms")
async def platforms():
    return await saveapi_get("/platforms", {})


@app.get("/api/detect")
async def detect(url: str = Query(..., min_length=8)):
    check_public_http_url(url)
    return await saveapi_get("/detect", {"url": url})


@app.get("/api/resolve")
async def resolve(url: str = Query(..., min_length=8)):
    check_public_http_url(url)
    data = await saveapi_get("/download", {"url": url})
    # Do not expose the secret key. SaveAPI response contains only media URLs and metadata.
    return data
