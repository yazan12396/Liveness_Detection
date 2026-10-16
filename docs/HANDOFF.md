# Handoff: from Liveness Prototype to Production App

This document carries everything decided in the prototype phase into the new
production project. A new Claude Code session (or a new developer) should read
it fully before writing any code.

- **Prototype repo (this one):** https://github.com/yazan12396/Liveness_Detection
- **Owner:** Yazan
- **Company context:** ISP (internet service provider) in Jordan; the app will
  onboard subscribers and may later host other services.
- **Scope of the first production feature:** Active Liveness (challenge-response
  head/eye/smile movements). More features will be specified later by the owner.

---

## 1. What the prototype is

A Flutter Android test app (Arabic RTL UI) built to measure free liveness tools
on a real phone. It is a **testing tool, not a base for production**: it has
test-only features (attempt-type labels, accuracy log) and makes all decisions
on the device.

| Screen | Tools | Purpose |
|---|---|---|
| Active Liveness | `camera` + `google_mlkit_face_detection` | 3 random challenges from: look left, look right, blink, smile |
| Passive Liveness | `passive_liveness` + ML Kit bounding box | MiniFASNetV2-SE model + texture/screen heuristics, screen flash |
| Document Capture | `google_mlkit_document_scanner` | ID scan (Android only) |
| Test Log | `shared_preferences`, `share_plus` | Accuracy per attempt type, CSV export |

Toolchain used: Flutter 3.47.7 via FVM (`.fvmrc`), Dart 3.13, Android Studio
JBR as `JAVA_HOME`.

---

## 2. Test results (real phones, October 2026)

| Attack | Active | Passive (front camera) | Passive (rear camera) |
|---|---|---|---|
| Bona fide (real face) accepted | 17/18 (94%) | 18/18 (100%) | n/a |
| Print attack rejected | 3/3 | 2/6 | 5/5 |
| Video replay rejected | 0/3 | 2/7 | n/a |
| Screen replay (photo on screen) | not tested | not tested | not tested |

Findings:

1. **Active Liveness alone is beaten by a pre-recorded video** of the person
   doing the movements. It only checks motion, not whether the face is real.
2. **Passive Liveness (free `passive_liveness` 0.1.3) is weak with the front
   camera.** Rear-camera results are over-optimistic and must not be trusted;
   real attackers always use the front camera.
3. **Root cause found in `passive_liveness`:** its "Genuine 3D Depth Rescue"
   rule flips a frame to *real* when the model says *spoof* but the image shows
   depth of field. A phone-recorded video has natural depth, so every accepted
   video had a model realScore of 0.001–0.03. Fix if passive is used: also
   require mean `realScore >= 0.5` (on the same data: video 0/7 accepted,
   real faces still 18/18). Small sample; must be retested.
4. One real-face rejection happened because the face was too close and not
   fully in frame. Production must guide the user ("move back") instead of
   timing out.
5. The real-face active test confirmed the yaw sign convention works on device
   (see section 4).

Conclusion: each method alone can be fooled. Production needs layers
(section 6). The free on-device passive model is not production-grade.

---

## 3. Key concepts and terms

| English | Arabic | Meaning |
|---|---|---|
| Liveness Detection | كشف الحيوية | Umbrella term: a live person is in front of the camera |
| Presentation Attack Detection (PAD) | كشف هجمات العرض | Formal term (ISO/IEC 30107) |
| Active Liveness (Challenge-Response) | الكشف النشط | User performs random movements |
| Passive Liveness | الكشف السلبي | Image analysis, no user action |
| Hybrid Liveness | الكشف المدمج | Active + passive on the same frames, at the same time |
| Print / Screen / Video Replay Attack | هجوم صورة مطبوعة / شاشة / فيديو | Presentation attacks in front of the camera |
| Deepfake (real-time face swap) | التزييف العميق | Attacker wears the victim's face live |
| Injection Attack | هجوم الحقن | Fake video fed into the app instead of the camera |
| Device Integrity | سلامة الجهاز | Play Integrity API (Android), App Attest (iOS) |
| Face Matching (1:1) | مطابقة الوجه | Selfie vs ID photo / government record |
| APCER / BPCER | — | Attacks wrongly accepted / real people wrongly rejected |

---

## 4. Active Liveness: exact behaviour to carry over

Reference implementation: `lib/services/face_camera.dart` and
`lib/screens/active_liveness_screen.dart` in this repo.

**Camera**
- Front camera, `ResolutionPreset.medium`, `enableAudio: false`,
  `imageFormatGroup: ImageFormatGroup.nv21`, app locked to portrait.
- Frames from `startImageStream`; drop frames while one is being processed.
- ML Kit input: `InputImage.fromBytes` with NV21 single plane,
  rotation = `sensorOrientation` (valid for portrait-locked front and rear).

**ML Kit options**
- `FaceDetectorOptions(enableClassification: true, performanceMode: fast,
  minFaceSize: 0.25)`.
- Values used per frame: `headEulerAngleY`, `leftEyeOpenProbability`,
  `rightEyeOpenProbability`, `smilingProbability`.
- Exactly one face required; 0 or 2+ faces shows a hint and does not progress.

**Rules (current thresholds)**

| Challenge | Neutral first | Done when |
|---|---|---|
| Look left | abs(yaw) < 12° | yaw > +25° |
| Look right | abs(yaw) < 12° | yaw < −25° |
| Blink | both eyes > 0.7 | both eyes < 0.25 |
| Smile | smile < 0.3 | smile > 0.8 |

- Sign convention: positive `headEulerAngleY` = user's own left (ML Kit:
  face turned toward the right side of the unmirrored image). Confirmed on
  device.
- A challenge only counts after its neutral pose is seen ("arming"), so a
  static smile or turned photo cannot pass instantly.
- 3 challenges, random order from 4; 8 s timeout each; pass = all completed.
- Thresholds are not official values; tune them from field testing.

**Planned improvements (agreed, not yet built)**
1. More challenge types: look up/down (`headEulerAngleX`, pitch), tilt
   (`headEulerAngleZ`, roll), wink (one eye), open mouth (contours/landmarks).
2. 4–5 challenges per session, random timing between them.
3. Short reaction window (2–3 s) and record reaction time.
4. **Fail immediately on a wrong action** (asked left, turned right).
5. Face continuity: `enableTracking: true`, same `trackingId` for the whole
   session; detect sudden jumps in box position/size (clip switching).
6. Face-fully-in-frame and distance guidance ("move closer / move back").
7. Auto-capture a selfie frame at the end of the same session.
8. Later: challenge list + nonce issued by the server; server verifies order
   and timing from uploaded frames/video (session-based, not live streaming).

Known limits even after these: real-time deepfakes and injection attacks.
Those need device integrity + injection detection + server-side checks.

---

## 5. Recommended production architecture (lean, scalable)

Verify every package's latest stable version and API on pub.dev at setup time;
do not copy versions from this document.

**Project setup**
- Flutter latest stable via FVM, committed `.fvmrc`.
- Flavors: `dev`, `staging`, `prod` (separate applicationId suffix, app name,
  icon, API base URL). Config per flavor via `--dart-define-from-file`
  (`config/dev.json` etc.). No secrets in the repo.
- Real applicationId / bundle id: company reverse domain (to be decided).
- Strict lints (`very_good_analysis` or `flutter_lints` with extra rules).
- Localization: Arabic + English with `gen-l10n` (ARB files), RTL-first UI.

**Structure (feature-first, layered inside each feature)**

```
lib/
  app/            # app widget, router, theme, flavor bootstrap
  core/           # network client, errors/Result, storage, logging, utils
  features/
    onboarding/   # presentation/ application/ domain/ data/
    ...
packages/
  liveness/       # standalone Dart/Flutter package (see below)
```

**Core libraries (common choices for an app this size)**
- State management + DI: Riverpod (or Bloc; pick one and keep it).
- Routing: `go_router`.
- Networking: `dio` with interceptors (auth token, refresh, logging, retry).
- Models: `freezed` + `json_serializable`.
- Secure storage: `flutter_secure_storage` for tokens.
- Crash reporting / analytics: Firebase Crashlytics or Sentry (decide).
- Tests: unit + widget tests with `mocktail`.
- CI: GitHub Actions running analyze, test, build per flavor.

**Liveness as its own package (`packages/liveness`)**
- Public interface only, e.g. `LivenessService.startSession(config)` returning
  a result with `passed`, completed challenges, timings, captured selfie
  frame, and evidence for the server.
- Implementation hidden behind the interface (ML Kit today), so it can later
  be swapped for a commercial certified SDK without touching app features.
- Keep thresholds and challenge set in a config object, not hard-coded.
- Design the result so it can be uploaded to a backend later, even if v1
  decides on the device.

**Security baseline for release**
- R8/obfuscation, no debug logs of biometric data, HTTPS only.
- Device Integrity (Play Integrity / App Attest) verified on the server.
- Biometric images never stored on device longer than needed.

---

## 6. Target eKYC pipeline (full picture)

| # | Step | Where |
|---|---|---|
| 1 | Document Capture + OCR | Phone |
| 2 | Hybrid Liveness (initial screening) | Phone |
| 3 | Device Integrity (request token) | Phone; verified on server |
| 4 | Secure upload (nonce, signed, HTTPS) | Phone to server |
| 5 | Server-side Liveness + Deepfake Detection | Server / vendor |
| 6 | Face Matching vs ID and government record | Server |
| 7 | Final decision + Manual Review when unsure | Server |
| 8 | Audit trail | Server |

Rule: the phone collects evidence and screens; the server decides.

The bank app the owner tried used server-side passive liveness on a recorded
video with no movements (plus likely manual review). That is the modern trend:
minimal user friction, strong checks on the server.

---

## 7. Jordan regulatory notes (verify with the regulator before building)

- **TRC (Telecommunications Regulatory Commission)** licenses eKYC
  self-registration for operators (Orange, Umniah, Zain). Its published
  customer-journey document: ID scan + OCR, selfie matched against Civil Status
  (CSPD) / Passports (PSD) records, liveness check. Full current instruction
  text was not found online.
- **Sanad digital ID:** since the 2026 Civil Status Law amendment it has the
  same legal status as the physical ID; public and private entities, including
  telecom, must accept it. Uses iris biometrics; 2.6M+ users. Possible shortcut:
  identity via Sanad (ask the Ministry of Digital Economy and Entrepreneurship
  about integration).
- **Central Bank of Jordan:** eKYC instructions 7/2021 amended by 9/2022
  require biometrics for remote onboarding (financial services only).
- Action: identify which regulator applies to the company's service and get
  the official instruction text before finalising the design.

---

## 8. Environment notes from the old machine

- On the old network, `dl.google.com` timed out. The prototype's
  `android/settings.gradle.kts` rewrites Google Maven to `dl-ssl.google.com`.
  On a new machine/network this is probably unnecessary; add it only if
  Gradle fails to download from `dl.google.com`.
- `passive_liveness` 0.1.3 applies the old Kotlin Gradle Plugin; future
  Flutter versions will refuse to build it. Avoid it in production.
- `google_mlkit_document_scanner` is Android only; iOS needs VisionKit
  (`VNDocumentCameraViewController`) or another package.

---

## 9. Open questions for the owner (answer before scaffolding)

1. App name and applicationId / bundle id (company domain)?
2. Platforms: Android only, or Android + iOS?
3. State management preference (Riverpod or Bloc)?
4. Is there an existing backend? Stack, auth method, API style?
5. Design system / brand guidelines available?
6. Crash reporting tool (Firebase or Sentry)? CI host (GitHub Actions)?
7. Minimum Android / iOS versions to support?
8. Which regulator governs the service, and is Sanad integration an option?

---

## 10. How to start on the new machine

1. Install Flutter tooling (FVM, Android Studio, Git), then clone this repo
   next to the new project for reference:
   `git clone https://github.com/yazan12396/Liveness_Detection.git`
2. Create an empty folder for the production app and open Claude Code there.
3. Paste the starter prompt below.

Starter prompt:

> Read `docs/HANDOFF.md` in https://github.com/yazan12396/Liveness_Detection
> (cloned at `<path>`). It summarises a liveness prototype and the decisions
> made. We are now building the production app for our ISP company. First ask
> me the open questions in section 9, then set up the project foundation
> following section 5 (verify latest package versions on pub.dev), then build
> the Active Liveness feature as `packages/liveness` using section 4 as the
> spec. Explain things to me briefly, in Arabic, with English technical terms.
