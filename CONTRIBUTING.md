# Contributing to CrashGuard AI

First off, thank you for considering contributing to CrashGuard AI. It's dedicated contributors like you who help make CrashGuard AI a reliable life-saving emergency platform.

## Branch Strategy
We use **Trunk-Based Development**.
- Short-lived feature branches: `feat/feature-name` or `fix/bug-name`.
- Merge into `main` frequently.
- All PRs require a green CI build.

## Code Standards
- Follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style).
- Run `flutter analyze` before committing.
- Ensure all new features have unit tests in `test/`.

## Commit Messages
Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
- `feat: ...` for new features
- `fix: ...` for bug fixes
- `docs: ...` for documentation changes
- `chore: ...` for maintenance

## Getting Started
1. Fork the repo.
2. Run `./scripts/setup.ps1` (PowerShell — Windows, or `pwsh` on macOS/Linux).
3. Create your branch.
4. Submit a PR!
