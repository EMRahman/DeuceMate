# Contributing to DeuceMate

Thanks for your interest in contributing. DeuceMate is a native SwiftUI app for Apple Watch and iPhone, built for tennis hobbyists. Contributions that improve the core experience are welcome.

## Before You Start

Open an issue before writing code for anything non-trivial. This avoids wasted effort if the direction doesn't fit the project.

Good contributions:
- Bug fixes with a clear reproduction case
- Scoring edge cases that aren't handled correctly
- Performance improvements with measurable impact
- Accessibility improvements

Out of scope:
- Third-party dependencies (the zero-dependency policy is intentional)
- Cloud sync, accounts, or any form of data collection
- Features that require always-on network access
- UI redesigns without prior discussion

## Development Setup

Requirements:
- Xcode 15.2+
- macOS 13+
- Physical Apple Watch (or simulator) for watch app testing

```bash
git clone https://github.com/emrahman/deucemate.git
cd deucemate
open DeuceMate/DeuceMate.xcodeproj
```

The project has zero external dependencies — no `swift package resolve` or CocoaPods step needed.

## Project Structure

```
DeuceMate/
├── DeuceMate Watch App/     # watchOS app (primary scoring logic)
├── DeuceMate/               # iPhone companion app
└── Packages/DeuceMateCore/  # Shared Swift package (models, stats, sync)
```

Core business logic lives in `DeuceMateCore`. If your change affects scoring rules, stats calculations, or sync behaviour, it likely belongs there — and needs tests.

## Running Tests

```bash
# From Xcode: Cmd+U
# Or via xcodebuild (adjust the simulator name to one available on your machine):
# xcrun simctl list devices available | grep Watch

xcodebuild test \
  -project DeuceMate/DeuceMate.xcodeproj \
  -scheme "DeuceMate Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 9 (45mm),OS=latest"
```

Tests for `DeuceMateCore`:
```bash
cd DeuceMate/Packages/DeuceMateCore
swift test
```

## Pull Request Guidelines

1. **One thing per PR.** A focused PR is easier to review and faster to merge.
2. **Tests required for logic changes.** If you change scoring, stats, or sync code, include tests. PRs without tests for logic changes will not be merged. Equally, do not delete, skip, or weaken existing tests to make a build pass — fix the code instead. Removing or loosening a test requires explicit maintainer approval and a stated reason in the PR.
3. **No new dependencies.** The project intentionally uses only Apple frameworks.
4. **Match the existing code style.** SwiftUI + MVVM, value types where possible, no force-unwraps.
5. **Describe the why.** The PR description should explain why the change is needed, not just what it does.

## What Happens to AI-Generated PRs

AI-assisted contributions are fine — but they're held to the same standard as human-written code. A PR that compiles and passes tests but adds unnecessary complexity, breaks the zero-dependency policy, or doesn't match the app's design will be closed. Quality over quantity.

## Reporting Bugs

Open a GitHub issue with:
- watchOS and iOS version
- Apple Watch model
- Steps to reproduce
- Expected vs actual behaviour

For security issues, email mail@ehsanrahman.com directly rather than opening a public issue.

## Code of Conduct

Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md) — the short
version is: critique code and ideas, not people.

## License

By submitting a pull request, you agree that your contribution will be licensed under the [MIT License](LICENSE).
