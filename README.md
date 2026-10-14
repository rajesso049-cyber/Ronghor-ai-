# Ronghor AI — Android starter project

Ronghor AI is a branded Flutter Android starter app with a FastAPI backend. It includes a chat UI, locally saved conversation history, optional web search via the model API, speech-to-text input, text-to-speech playback, backend URL settings, a logo SVG, and a GitHub Actions workflow that builds a release APK.

## Important scope note

This is a working starter foundation, not a finished ChatGPT/Grok replacement. Accounts/cloud sync, long-term server-side memory, image generation, file uploads/analysis, subscriptions, and autonomous automation workflows are not implemented yet. The mobile app stores its current chat history locally on the device. Web search requires a model/API account that supports the configured tool. Model names and availability depend on your API account.

## Repository layout

- `lib/main.dart` — Flutter app
- `assets/ronghor_ai_logo.svg` — brand logo source
- `backend/main.py` — FastAPI backend
- `backend/Dockerfile` — container deployment
- `.github/workflows/android-apk.yml` — GitHub Actions APK build

## Build the APK using GitHub Actions (phone-friendly)

1. Create a GitHub repository named `ronghor-ai`.
2. Extract this ZIP on your phone, then upload the extracted files/folders to the repository while preserving their paths. Do not upload only the ZIP as the repository contents.
3. Ensure `.github/workflows/android-apk.yml` is present in the repository.
4. Open the repository's **Actions** tab.
5. Select **Build Ronghor AI Android APK**.
6. Tap **Run workflow** (or push a commit to `main`/`master`).
7. Wait for the workflow to finish successfully.
8. Open the completed run and download the `ronghor-ai-release-apk` artifact.
9. Extract the downloaded artifact ZIP to get `app-release.apk`.
10. Open the APK on your Android phone and approve installation if Android asks.

The workflow creates the Android platform scaffold if it is missing, then runs `flutter pub get`, `flutter analyze`, and `flutter build apk --release`.

## Connect the AI backend

The APK is only the mobile client. To get AI responses, deploy the backend in `backend/` to a server that can stay online.

### Local backend test

Requires Python 3.11+ (Python 3.12 recommended).

```bash
cd backend
python -m venv .venv
# Linux/macOS:
source .venv/bin/activate
# Windows PowerShell:
# .venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp .env.example .env
```

Edit `.env` and set a real API key privately. Check the model name available to your account and change `OPENAI_MODEL` if needed.

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Check `http://localhost:8000/health`.

**Do not expose this local HTTP URL to the public internet.** For a physical Android phone, `10.0.2.2` will not reach your computer; that address is for the Android emulator. Set the app's backend URL in Settings to your deployed HTTPS backend URL.

### Deployment notes

- Set `OPENAI_API_KEY` as a server-side secret in your hosting provider.
- Set `OPENAI_MODEL` to a model available to your API account.
- Set `APP_ALLOWED_ORIGINS` to your intended web origins if you later add a web frontend.
- Add authentication, rate limits, abuse prevention, request logging with redaction, and per-user quotas before allowing public users.
- Never place provider API keys in Flutter source, APK assets, GitHub commits, or screenshots.
- Add TLS/HTTPS before production use.

## Features currently included

- Dark purple/blue branded chat screen
- Chat request to a backend
- Optional web search toggle
- Local conversation history
- Speech-to-text input where supported by the device
- Text-to-speech playback
- Backend URL settings
- GitHub Actions release APK artifact

## Planned next features

1. Server-side login and account-specific conversation history
2. Durable user-controlled memory
3. Image generation endpoint and gallery
4. File upload and document analysis
5. Real-time voice conversations
6. Tool-calling agent workflows with approval gates
7. Subscription/usage limits and admin controls
8. App signing and Google Play release preparation

## Build locally (if Flutter is installed)

```bash
flutter pub get
flutter create --platforms=android --org com.ronghorai --project-name ronghor_ai .
flutter build apk --release
```

The release APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
