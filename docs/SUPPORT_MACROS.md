# Support reply macros — CrashGuard AI

Copy-paste for **Discord / email / GitHub issues**. Adjust tone for audience.

## SMS did not send

> CrashGuard AI tries **automated SMS through our secure relay** (Twilio + Supabase Edge). Please confirm: (1) Android SMS permission granted, (2) project secrets deployed on Supabase, (3) device has signal. If the **Dispatch status** panel shows failed for SMS, use **Dial 112/108** shown in-app — that path always remains available. We never claim SMS delivery without carrier confirmation.

## GPS unknown / inaccurate

> Location uses GPS + fused provider. **Indoors / tunnels** can block fixes — the app continues with **SMS without precise coords** where policy allows, and shows honest status in **Dispatch**. Please move to open sky and retry; enable **high accuracy** location for Android.

## On-device Gemma (model) not working

> Tier 2 needs the **~2.4 GB Gemma 4 E4B** download (`flutter_gemma`). If it’s missing or failed, the app **automatically uses Tier 3–4** (heuristic / keyword) — check the triage **source label**. Web builds **do not** run on-device Gemma.

## BLE mesh / radar empty

> Mesh requires **Bluetooth on** and typically **another CrashGuard AI user nearby** with the app active — it’s a **supplement** to SMS and emergency numbers, not a guarantee. iOS background BLE is **more limited** than Android.

## iOS vs Android differences

> **Android** is the reference platform for **foreground crash detection and SMS automation**. **iOS** has stricter background rules — see `docs/PLATFORM_MATRIX.md` and `docs/project-history/AUDIT_REPORT.md`. We recommend **Android for field demos** of the full pipeline.

## Privacy / data

> Location and triage data are handled per our **Privacy Policy** (`assets/legal/`). Tier 1 cloud triage sends minimal structured context to our Edge Function; Tier 2 on-device can run **without cloud** when configured. We avoid logging raw coordinates in production logs.
