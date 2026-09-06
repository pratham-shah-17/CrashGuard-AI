# Architecture Diagrams

Hand-authored diagrams for the flows that matter most in CrashGuard AI. For the
auto-generated dependency graph, see
[`docs/architecture/architecture.md`](architecture/architecture.md).

## Emergency workflow (crash to dispatch)

```mermaid
sequenceDiagram
    participant Sensor as Accelerometer + GPS
    participant Crash as CrashDetectionService
    participant Orch as EmergencyOrchestrator
    participant Triage as AiTriageService (4-tier)
    participant Dispatch as Dispatch channels
    participant Bystander as Voice/TTS guidance

    Sensor->>Crash: spike + velocity drop + stillness
    Crash->>Orch: crash confirmed (severity_hint 1..5)
    Orch->>Triage: triage(photo?, voice, severity_hint)
    Triage-->>Orch: severity_level, required_services, first_aid_focus
    par Parallel dispatch
        Orch->>Dispatch: SMS to 108/112 (Twilio, server-side)
        Orch->>Dispatch: BLE mesh beacon (AES-GCM)
        Orch->>Dispatch: Supabase Realtime nearby_sos broadcast
    end
    Orch->>Bystander: TTS first aid in user's language
```

## AI inference tiers (degradation path)

```mermaid
flowchart TD
    Start([Triage requested]) --> T1{Gemma 4 27B<br/>reachable?}
    T1 -->|Yes, online| Vision[Tier 1: Gemma 4 27B + vision<br/>Supabase Edge Function, 5s timeout]
    T1 -->|No| T2{Gemma 4 E4B<br/>downloaded?}
    T2 -->|Yes, on-device| Local[Tier 2: Gemma 4 E4B Q4_K_M<br/>flutter_gemma / LiteRT]
    T2 -->|No| T3[Tier 3: Weighted heuristic<br/>deterministic, 0ms]
    T3 -->|unavailable| T4[Tier 4: Keyword classifier<br/>always available]
    Vision --> Result([Structured severity JSON])
    Local --> Result
    T3 --> Result
    T4 --> Result
    Result --> Note[Dispatch always fires<br/>regardless of which tier triaged]
```

## Offline-first data sync

```mermaid
flowchart LR
    subgraph Device
        SQLite[(Local SQLite<br/>via PowerSync)]
        App[Flutter App]
    end
    subgraph Cloud
        Supabase[(Supabase PostgreSQL)]
        Edge[Supabase Edge Functions]
    end

    App -->|read/write, works offline| SQLite
    SQLite <-.->|background sync when online| Supabase
    App -->|triage / SMS / family-track| Edge
    Edge --> Supabase

    Note1[Facility + trauma-center data<br/>synced regionally, queried offline]
    SQLite --- Note1
```

## BLE mesh communication

```mermaid
flowchart TD
    A[Device A: SOS triggered] -->|AES-GCM encrypted beacon| BLE((BLE broadcast))
    BLE --> B[Device B: nearby CrashGuard AI user]
    BLE --> C[Device C: nearby CrashGuard AI user]
    B --> Decode[Decode bearing + distance<br/>from BLE payload + own GPS]
    C --> Decode
    Decode --> Radar[Bystander Radar UI<br/>real bearing/distance, no fake positions]
```
