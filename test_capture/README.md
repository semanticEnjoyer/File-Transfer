# TestCapture

Capture screenshots and screen recordings on your Android phone, add a **title, notes, priority and project**, and send them to your **Windows PC over Wi-Fi**. No cloud, no third-party sharing apps.

- **Phone app:** pick media from the gallery (or take a photo or video), fill in the details, then tap *Save & send*. Captures queue on the phone and upload automatically whenever the PC is reachable.
- **PC app (hub):** a dashboard with filters by status, priority and project, plus search, a detail view, image zoom, video playback in your default player, status tracking (Open → In progress → Reported → Done) and **one-click HTML/Markdown report export**.

The same Flutter codebase builds both apps. On Android it runs as the capture app, and on Windows it runs as the hub.

---

## Get the apps (easiest: GitHub builds them for you)

1. Create a free GitHub account and a new **private** repository.
2. Upload this folder to it (GitHub Desktop is the simplest way, or `git push`).
3. Open the **Actions** tab. The *Build apps* workflow starts on its own; if it doesn't, click *Run workflow*.
4. After about 10 minutes, open the finished run and download:
   - **TestCapture-android**: contains `app-release.apk`. Copy it to your phone and install it (allow "install unknown apps").
   - **TestCapture-windows**: unzip it anywhere and run `TestCapture.exe`. Keep the whole folder together.

## Or build on your own PC

You need:
- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows), stable channel
- Visual Studio 2022 with **"Desktop development with C++"** (for the Windows app)
- Android Studio (for the Android SDK), with USB debugging enabled on your phone

```powershell
cd test_capture
./tool/setup.ps1          # generates android/ and windows/ folders (run once)
flutter run -d windows    # start the PC hub
flutter run               # with the phone plugged in: installs the phone app
# release builds:
flutter build windows --release
flutter build apk --release
```

---

## First run

1. Start **TestCapture on the PC**. If Windows Firewall asks, allow it on **Private networks**.
2. Start **TestCapture on the phone**, then tap *Connect to your PC*. Your PC appears in the list.
3. Enter the **6-digit PIN** shown in the PC app's sidebar. Pairing is done once.
4. Tap **New capture**, pick screenshots or videos, add notes and a priority, and send.

If the PC doesn't show up in the list (some routers block discovery), type the address shown in the PC sidebar, for example `192.168.1.20:47800`.

## Where your data lives

- **PC:** `Documents\TestCapture\` holds `items.json` (all captures), `media\` (files) and `Reports\` (exported reports).
- **Phone:** inside the app. *Menu → Free up space* removes phone copies once they are on the PC.

## How it works

| Part | Detail |
|---|---|
| Discovery | Phone broadcasts on UDP port 47801, and the PC answers with its name |
| Transfer | HTTP on port 47800 (local network only); files stream directly to disk, so large videos are fine |
| Security | PIN pairing gives each phone a secret token, and the PC rejects requests without it. A PIN works once and changes after 5 wrong tries. |
| Reliability | Uploads go to a `.part` file and are renamed only when complete; failed uploads retry automatically |

## Project layout

```
lib/
  main.dart              picks phone or PC mode
  core/                  shared models, theme, protocol constants, JSON storage
  hub/                   PC: HTTP server, store, dashboard UI, report export
  phone/                 Android: capture screen, pairing, upload queue
android/app/src/main/AndroidManifest.xml   network permissions
tool/setup.ps1           generates platform folders
.github/workflows/       cloud builds (APK + Windows)
```

## Roadmap ideas

- Share from the Android share sheet straight into TestCapture
- Auto-import new screenshots and screen recordings
- Draw or annotate on screenshots; timestamp notes on videos
- In-app video player on PC; video thumbnails
- Edit captures from the phone after sending; comments
- Optional remote mode (self-hosted server) for use outside your Wi-Fi
