# Technical Architecture: CrashGuard AI

## 1. The Emergency Orchestration Pipeline
The `EmergencyOrchestrator` is the central brain of the system. It manages the state machine:
`Idle -> Countdown -> Triaging -> Active -> Resolved`

### Data Flow:
1. **Trigger**: Hardware button, Accelerometer (Crash), or UI Button.
2. **Telemetry**: Collection of GPS, Speed, and User Profile.
3. **AI Triage**: Tiered inference (Local -> Cloud).
4. **Dispatch**: Simultaneous broadcast via Encrypted BLE Mesh and Supabase.

## 2. Security & Privacy (Mesh)
We use **AES-GCM-256** for all mesh payloads.
- **Key Rotation**: Ephemeral keys are generated per incident (Future Phase).
- **Identity Protection**: Medical profiles are compressed and encrypted, visible only to authorized responders.

## 3. Data Persistence (PowerSync)
CrashGuard AI is **Offline-First**. 
- Local changes are written to SQLite.
- PowerSync handles background synchronization to Supabase when a signal returns.
- Row-Level Security (RLS) ensures users can only access their own incident data.

## 4. AI Strategy
**Gemma 4 IT** is integrated for on-device reasoning. 
- **Tiered Inference**: If the model fails to load, the system falls back to a regex-based heuristic triage to ensure no delay in dispatch.
