# ADR 0001: Modular Feature Architecture

## Status
Accepted

## Context
As CrashGuard AI scales to billions of users and multiple development teams, the monolithic `lib/` structure becomes a bottleneck for merge conflicts and domain clarity.

## Decision
We will adopt a **Modular Feature-First Architecture**.
- `lib/core/`: Cross-cutting concerns (Theme, Networking, Persistence).
- `lib/features/`: Domain-specific folders (Triage, Mesh, Mapping).
- `lib/shared/`: Reusable UI components.

## Consequences
- **Positive**: Clearer ownership, easier testing, faster onboarding.
- **Negative**: Increased initial boilerplate for new features.
