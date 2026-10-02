# Social Downloader V6

Flutter Android client + FastAPI backend using SaveAPI as the resolver.

## Features
- Automatic platform detection from the pasted URL
- TikTok, YouTube, Instagram, Facebook, X, Pinterest, Likee, Snapchat, Threads, VK, Rutube, 9GAG and Twitch when supported by the SaveAPI plan/API
- Multiple links
- Media/quality selection from `medias[]` and `formats[]`
- Per-download progress, speed and ETA
- Cancel download
- Local download history
- Dark UI
- API key stays on the backend

## Backend
1. Python 3.11+ recommended.
2. `cd backend`
3. `python -m venv .venv`
4. Windows: `.venv\\Scripts\\activate`
5. `python -m pip install -r requirements.txt`
6. Copy `.env.example` to `.env` and set `SAVEAPI_KEY`.
7. Run: `uvicorn main:app --host 0.0.0.0 --port 8000`

## Flutter
1. `cd flutter`
2. `flutter pub get`
3. Set `backendBaseUrl` in `lib/main.dart`:
   - Android emulator: `http://10.0.2.2:8000`
   - Real phone: `http://YOUR_PC_LAN_IP:8000`
4. `flutter run`

The app downloads resolved media URLs directly from the source CDN. CDN URLs can expire, so resolve immediately before downloading. Only download content you are authorized to save, and comply with each platform's terms.
