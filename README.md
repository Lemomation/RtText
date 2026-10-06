# RtText

RtText is an AI-messaging Android app built with Flutter and Supabase — like
WhatsApp, but you chat with AI characters that users create and share.

## Status

Milestone 1: app scaffold with Material 3 dark-first theme, Google OAuth
(Supabase), go_router navigation with an auth gate, placeholder screens for
chats / chat thread / discover / character profile / character creation /
profile, and GitHub Actions CI.

## Tech stack

- Flutter (Material 3, dark-first)
- Supabase (`supabase_flutter` v2) — auth, database, storage, edge functions
- `go_router` for navigation, `provider` for state
- `flutter_animate` for motion design

## Building locally

Requires Flutter 3.35+ and Android SDK 35.

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=<your-supabase-url> \
  --dart-define=SUPABASE_ANON_KEY=<your-supabase-anon-key>

flutter build apk --release \
  --dart-define=SUPABASE_URL=<your-supabase-url> \
  --dart-define=SUPABASE_ANON_KEY=<your-supabase-anon-key>
```

If the `--dart-define` values are missing, the app still launches and shows a
configuration error screen instead of crashing.

## CI

`.github/workflows/build.yml` runs on every push to `main` and on all PRs:

1. `flutter pub get`
2. `flutter analyze` (warnings are fatal)
3. `flutter test`
4. `flutter build apk --release` with Supabase values injected
5. Uploads the APK as an artifact (`rttext-release-apk`)

### Secrets

Add these as repository secrets in GitHub (Settings → Secrets and variables →
Actions) so CI builds connect to the real Supabase project:

| Secret              | Purpose                          |
| ------------------- | -------------------------------- |
| `SUPABASE_URL`      | Supabase project URL             |
| `SUPABASE_ANON_KEY` | Supabase anon (public) key       |

Both are the public client values — safe to embed in the app; Row Level
Security on Supabase protects the data. Until the secrets are set, CI builds
use placeholders and the built APK shows the configuration error screen.

The **GEMMA API key** (for AI replies) never appears in the app or CI — it is
stored as a secret **inside Supabase** (edge function secret) and only the
Supabase backend uses it.

## Android notes

- Application ID: `com.lemomation.rttext`
- minSdk 23, targetSdk/compileSdk 35, AGP 8.x, Kotlin, Gradle 8.12
- OAuth redirect deep link: `io.supabase.flutterdeepauth://login-callback/`
  (configured in the Android manifest and passed to `signInWithOAuth`)
