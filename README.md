# BLE Classroom Attendance (anti-proxy)

A two-app (Student + Teacher) Flutter system over one Supabase backend that marks a
student **present** only if they are (a) really themselves, (b) a live person, and
(c) physically near the teacher. **The phone never decides attendance — the
`validate_attendance` edge function does, server-side.**

```
attendance/
├─ packages/shared/      models, evidence schema, Supabase repos, BLE token logic, Riverpod providers
├─ apps/teacher/         login → courses → start session (advertise) → live roster → end → flag review
├─ apps/student/         login → bind device → face+liveness → scan token+RSSI → submit → result
├─ tools/ble_probe/      Step-One BLE proving harness (run this FIRST)
└─ supabase/             migrations (schema + RLS), validate_attendance edge function, seed
```

State management is **Riverpod**. The monorepo uses a **Dart pub workspace** with
**Melos 7** on top for scripts.

---

## Verified plugin versions (pub.dev, checked Jun 2026)

| Package | Pinned | Role |
|---|---|---|
| `flutter_blue_plus` | ^2.3.8 | BLE central (student scan + GATT read); probe scanner |
| `ble_peripheral` | ^2.4.0 | BLE peripheral + GATT server (teacher advertise) |
| `universal_ble` | 2.0.4 | (evaluated) single-plugin central+peripheral — see BLE findings |
| `google_mlkit_face_detection` | ^0.13.2 | face detection + blink/turn/smile signals (iOS 15.5+) |
| `tflite_flutter` | ^0.12.1 | MobileFaceNet embedding + MiniFASNet anti-spoof inference |
| `supabase_flutter` | ^2.14.2 | Auth + Realtime + Postgrest + Edge Functions |
| `flutter_riverpod` | ^3.3.2 | state management |
| `camera` | ^0.12.0+1 | front-camera capture |
| `permission_handler` | ^12.0.3 | runtime permissions |
| `melos` | ^7.8.2 | monorepo tooling |

> **Plugin-API caveat.** This codebase was authored against the documented APIs of
> the versions above, but the Flutter/Dart toolchain was **not available in the
> authoring environment**, so `pub get` / `flutter analyze` were not run here. Run
> them first (below). The most likely spot to need a one-line tweak is
> `ble_peripheral` enum identifiers (`CharacteristicProperties` / `AttributePermission`)
> — the **probe step verifies the BLE path empirically**, which is exactly why it
> comes first.

---

## STEP ONE (non-negotiable): prove the BLE path on real devices

### Why this shapes everything
Apple's CoreBluetooth only allows **two** keys in a foreground peripheral
advertisement — `CBAdvertisementDataLocalNameKey` and
`CBAdvertisementDataServiceUUIDsKey`. **Manufacturer data and service data are
silently dropped on iOS**, and iOS→Android ad discovery is unreliable. So a
rotating token cannot live in the advertisement payload when the teacher is on iOS.

**Chosen mechanism (built into the apps):** advertise a *fixed* service UUID for
discovery + RSSI, then **deliver the rotating token via a GATT characteristic read**
after the student connects. This avoids the iOS payload limit and works in all four
OS combos. The probe confirms this empirically before you trust it.

### Run the probe
```bash
cd tools/ble_probe
flutter create --platforms=android,ios .     # generate native runners (see "Native scaffolding")
# re-apply the committed AndroidManifest.xml + ios/Runner/Info.plist if flutter create overwrote them
flutter run                                  # install on device A and device B
```
On device A open **Advertise → Start**. On device B open **Scan → Scan**. Each
observation row shows which channel carried the rotating value: `name`, `mfg`
(manufacturer data), `gatt`. Repeat for all four combinations and fill the matrix:

### BLE findings matrix — FILL THIS IN after running the probe

| Advertiser → Scanner | Discovered (service UUID)? | RSSI seen? | `name` value? | `mfg` value? | `gatt` read? |
|---|---|---|---|---|---|
| Android → Android | ☐ | ☐ | ☐ | ☐ | ☐ |
| Android → iOS     | ☐ | ☐ | ☐ | ☐ | ☐ |
| iOS → Android     | ☐ | ☐ | ☐ | ☐ | ☐ |
| iOS → iOS         | ☐ | ☐ | ☐ | ☐ | ☐ |

**Expected (to be confirmed by you):** `gatt` ✅ in all four; `mfg` ✅ only when the
advertiser is Android; `name` flaky on iOS. If `gatt` wins all four (expected), the
production apps are already wired to it — nothing to change. If your hardware shows
something different, that's the whole point of running this first: tell me and we
adjust `packages/shared/lib/src/ble/`.

---

## Setup

### 0. Prerequisites
- Flutter 3.27+ (Dart 3.6+), Xcode 15.3+, Android Studio, CocoaPods.
- `dart pub global activate melos 7.8.2`
- Supabase CLI (`supabase --version`).
- Two physical phones (BLE + camera don't work in simulators/emulators).

### 1. Bootstrap the workspace
```bash
cd attendance
dart pub get        # resolves the whole pub workspace
melos bootstrap     # optional; runs pub get + wires scripts
melos run analyze   # static check (do this before first run)
melos run test      # runs shared/ unit tests
```

### 2. Supabase backend
```bash
cd supabase
supabase link --project-ref <your-project-ref>
supabase db push                         # applies migrations/0001_init + 0002_rls
supabase functions deploy validate_attendance
# Edge function secrets (service role lets it write the authoritative decision):
supabase secrets set SUPABASE_URL=<url> \
  SUPABASE_ANON_KEY=<anon> SUPABASE_SERVICE_ROLE_KEY=<service-role>
```
Enable **Realtime** on the `attendance` table (migration adds it to the
`supabase_realtime` publication; confirm in Dashboard → Database → Replication).

#### Create users (email/password) and link profiles
Auth identities must exist before the `public.users` rows. Create a teacher and a
student in Dashboard → Authentication → Add user (or via the Admin API), copy their
UUIDs into `supabase/seed.sql`, then:
```bash
supabase db execute --file seed.sql
```
Login model: the apps collect the **code** (`TEACH-001` / `STU-1001`) plus email +
password; sign-in is email/password and the app asserts the code + role match the
profile.

### 3. Drop in the face models (optional but recommended)
Put `mobilefacenet.tflite` and `antispoof.tflite` into
`apps/student/assets/models/` (see that folder's README for sources + tensor
shapes). **Without them the app still runs** using a documented stub scorer
(`face_model_version: "stub"` in the evidence); liveness then rests on the active
challenge until you add the real anti-spoof model.

### 4. Native scaffolding (one-time, per app)
The repo ships `lib/`, `pubspec.yaml`, the **AndroidManifest.xml**, and **Info.plist**
for each app, but not the full generated native projects. In each of
`apps/teacher`, `apps/student`, `tools/ble_probe`:
```bash
flutter create --org com.yourorg --platforms=android,ios .
```
Then make sure the committed `android/app/src/main/AndroidManifest.xml` and
`ios/Runner/Info.plist` are the ones in place (re-copy if `flutter create`
regenerated them). Set minimums:
- **Android**: `minSdkVersion 23` in `android/app/build.gradle`.
- **iOS**: deployment target **15.5** (ML Kit requirement) in Xcode / Podfile
  (`platform :ios, '15.5'`).

### 5. Run the apps
Pass Supabase config via `--dart-define` (the anon key is publishable, gated by RLS):
```bash
# Teacher
cd apps/teacher
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<anon>

# Student
cd apps/student
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<anon>
```

---

## How a check-in flows

1. **Teacher** signs in → picks a course → **Start session**. The app creates a
   `sessions` row, pre-generates `session_tokens` (rotating ~5s), starts the BLE
   peripheral (fixed service UUID), and serves the *current* token over a GATT
   characteristic. Keep the screen foregrounded.
2. **Student** signs in → (first run) binds this device → enrolls a face once →
   taps **Mark**. The app runs a **randomized active challenge** (blink / turn /
   smile) on the live camera, computes an **on-device face-match** vs the enrolled
   template and a **passive anti-spoof** score, then **scans** for the session
   beacon (RSSI) and **GATT-reads the current token**.
3. The app submits the **evidence object** to `validate_attendance`.
4. The **server** verifies session open, token in window, device binding, face +
   liveness, and proximity; dedupes; and writes `present` or `flagged` with a
   reason. The roster updates live via Realtime; the student sees the verdict.
5. **Teacher** can open **Review flagged** to approve/reject.

### Evidence object (`attendance.evidence` jsonb)
```jsonc
{
  "face_match_score": 0.91,        // cosine sim vs enrolled template (on-device)
  "liveness_passed": true,         // passive AND active
  "challenge_type": "blink",       // randomized active challenge
  "challenge_passed": true,
  "passive_spoof_score": 0.97,     // null in stub mode
  "ble_token": "ABCD2345",         // GATT-read from the teacher
  "rssi": -62,                     // proximity proxy
  "device_id": "….",               // checked vs bound device
  "face_model_version": "mobilefacenet-tflite",
  "wifi_bssid": null, "geo": null, "attestation": null   // placeholders for future policy
}
```

## Anti-proxy controls (defense in depth)
- **Who you are** — on-device face match against a locally-stored enrolled template.
- **A live person** — passive anti-spoof model + randomized active challenge.
- **Physically present** — fixed-beacon discovery + RSSI + a token that rotates ~5s
  and is only obtainable in the room over BLE (tokens are *not* readable from the DB
  by students — no RLS select policy on `session_tokens`).
- **Your device** — one active device per account, checked server-side.
- **Server authority** — `validate_attendance` (service role) makes every final
  decision; RLS stops students inserting anything but their own pending row and
  reading anyone else's; teachers see only their own sessions.

## Server-side policy knobs
In `supabase/functions/validate_attendance/index.ts`:
`FACE_MATCH_MIN`, `PASSIVE_SPOOF_MIN`, `RSSI_MIN`, `TOKEN_SKEW_MS`. Tighten as your
deployment + the BLE findings dictate.

## Known limitations / next steps
- Teacher advertising is **foreground-only** (by design — iOS background ads drop the
  local name and throttle frequency).
- `wifi_bssid` / `geo` / `attestation` are evidence placeholders; the server already
  reads the object, so adding Play Integrity / App Attest is a policy change, not a
  schema migration.
- Re-installing the student app rotates the device id and forces an admin re-bind
  (intentional friction).
