# FieldTalkMobile (`mobile/app`)

This is the canonical React Native Android app for the offline mobile prototype.

## Quick start (PowerShell, from `mobile/app`)

```powershell
npm ci
.\scripts\setup-android.ps1
npm run test
npm run lint
npm run android
```

For standalone packages (no Metro):

```powershell
npm run android:release-apk
npm run android:release-bundle
```

Important:
- `scripts/setup-android-model.ps1` downloads official multilingual `ggml-tiny.bin` to Android assets.
- Model binaries are intentionally ignored by Git.
- Release build uses debug signing only (development/non-production).

See repository root `README.md` for full acceptance checklist, offline validation steps, and troubleshooting.
