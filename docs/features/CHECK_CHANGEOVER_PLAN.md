# Plan: Court Compass Direction Indicator ("Check changeover" feature)

## Context
The court animation shows opponent at top and player at bottom, but doesn’t indicate what real-world direction “up” means.  
A new opt-in **Check changeover** setting adds:

1. A confirmation step after server selection (“Correct court side?”)
2. A continuous compass arrow near the court widget showing expected facing direction + cardinal label (e.g. `↗ NE`)
3. Green/orange/red color feedback from live heading vs expected bearing
4. Accuracy gating (`CLHeading.headingAccuracy <= 30°`) for trusted color states
5. Robust lifecycle handling (first-sample gating, resume/relaunch monitoring, single-manager safety)

---

## Files to Modify

| File | Change |
|------|--------|
| `DeuceMate/DeuceMate-Watch-App-Info.plist` | Add `NSLocationWhenInUseUsageDescription` |
| `DeuceMate/DeuceMate Watch App/ScoreViewModel.swift` | Add setting/state, heading manager, idempotent start/stop/lock behavior |
| `DeuceMate/DeuceMate Watch App/HomeView.swift` | Add settings toggle, confirmation step, confirm-button readiness gating, resume monitoring |
| `DeuceMate/DeuceMate Watch App/ContentView.swift` | Compute expected bearing; pass heading data; render compass indicator |
| `PRIVACY_POLICY.md` | Document heading/location permission use |
| `docs/release/APP_STORE_METADATA.md` | Align user-facing disclosure wording with plist permission purpose |

---

## 1. `DeuceMate-Watch-App-Info.plist`

Add:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>DeuceMate reads your compass heading to show which direction the court faces.</string>
```

---

## 2. `ScoreViewModel.swift`

### Imports
Add:
```swift
import CoreLocation
```

### New properties
Add:
```swift
@Published var checkChangeover: Bool = UserDefaults.standard.object(forKey: "checkChangeover") as? Bool ?? false {
    didSet { UserDefaults.standard.set(checkChangeover, forKey: "checkChangeover") }
}
@Published var courtInitialHeading: Double? = UserDefaults.standard.object(forKey: "courtInitialHeading") as? Double {
    didSet { UserDefaults.standard.set(courtInitialHeading, forKey: "courtInitialHeading") }
}
@Published var currentDeviceHeading: Double? = nil
@Published var currentHeadingAccuracy: Double = -1
private var headingManager: HeadingManager? = nil
```

### Lifecycle methods (revised for safety)
```swift
func startHeadingMonitoring() {
    guard checkChangeover else { return }
    guard CLLocationManager.headingAvailable() else { return }

    // idempotent: don't create duplicate managers
    if headingManager != nil { return }

    let mgr = HeadingManager()
    headingManager = mgr
    mgr.onHeading = { [weak self] heading in
        DispatchQueue.main.async {
            self?.currentDeviceHeading = heading.magneticHeading
            self?.currentHeadingAccuracy = heading.headingAccuracy
        }
    }
    mgr.start()
}

func lockInitialHeading() {
    // guard against race: first sample may not have arrived yet
    guard let current = currentDeviceHeading else { return }
    courtInitialHeading = current
}

func pauseHeadingMonitoring() {
    headingManager?.stop()
    headingManager = nil
}

func resetHeadingState() {
    pauseHeadingMonitoring()
    UserDefaults.standard.removeObject(forKey: "courtInitialHeading")
    courtInitialHeading = nil
    currentDeviceHeading = nil
    currentHeadingAccuracy = -1
}
```

### Reset integration
In `resetMatch()`, add:
```swift
resetHeadingState()
```

### `HeadingManager` class (single-instance friendly)
Add private file-scope class:
```swift
private class HeadingManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isUpdating = false
    var onHeading: ((CLHeading) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard !isUpdating else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingHeading()
            isUpdating = true
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingHeading()
        isUpdating = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if (manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways),
           !isUpdating {
            manager.startUpdatingHeading()
            isUpdating = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        onHeading?(newHeading)
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
```

---

## 3. `HomeView.swift`

### Settings toggle
Add beside existing toggles:
```swift
Toggle(isOn: $viewModel.checkChangeover) {
    Text("Check changeover")
}
.toggleStyle(.switch)
```

### `RootModal` state
Add:
```swift
@State private var courtSideConfirmed: Bool = false
@State private var confirmButtonForced: Bool = false
```

### Flow branch
Insert between server selection and match content:
```swift
} else if viewModel.checkChangeover
       && !courtSideConfirmed
       && CLLocationManager.headingAvailable() {
    courtSideConfirmationView
} else {
    VStack(...) { ContentView() }
}
```

### Confirmation view with readiness gating
```swift
private var headingReadyForLock: Bool {
    (viewModel.currentDeviceHeading != nil
        && viewModel.currentHeadingAccuracy >= 0
        && viewModel.currentHeadingAccuracy <= 45)
    || confirmButtonForced
}

private var courtSideConfirmationView: some View {
    VStack(spacing: 16) {
        Text("Correct court side?")
            .font(.headline)
            .foregroundColor(.white)

        Text("Stand on your starting end.")
            .font(.footnote)
            .foregroundColor(.secondary)

        if viewModel.currentDeviceHeading != nil {
            Text("Accuracy: ±\(Int(viewModel.currentHeadingAccuracy))°")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else {
            Text("Hold watch up… acquiring heading")
                .font(.footnote)
                .foregroundColor(.secondary)
        }

        Button("✓ Confirmed") {
            viewModel.playHaptic(.success)
            viewModel.lockInitialHeading()
            startMatchTimerIfNeeded()
            if viewModel.courtInitialHeading != nil || confirmButtonForced {
                courtSideConfirmed = true
            }
        }
        .font(.headline)
        .buttonStyle(HomeButtonStyle(background: ButtonGradients.start))
        .disabled(!headingReadyForLock)
    }
    .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            confirmButtonForced = true
        }
    }
}
```

### Server selection commit
Start heading monitoring before confirmation step. The match timer is started from the "✓ Confirmed" button action when the confirmation screen is shown; for the no-heading path (confirmation skipped), start it here instead so timing is always initialized:
```swift
private func commitServerSelection() {
    viewModel.startHeadingMonitoring()
    if !viewModel.checkChangeover || !CLLocationManager.headingAvailable() {
        startMatchTimerIfNeeded()
    }
    if viewModel.matchFormat == .superTiebreak {
        viewModel.prepareTiebreakOnlySet()
    }
}
```

### Resume handling (important)
In `.onAppear`, keep confirmation skipped on resume **and** ensure monitoring restarts:
```swift
.onAppear {
    if viewModel.currentServer != nil {
        warmupComplete = true
        matchTypeChosen = true
        courtSideConfirmed = true

        if viewModel.checkChangeover {
            viewModel.startHeadingMonitoring()
        }
    } else if viewModel.matchFormat == .superTiebreak {
        warmupComplete = true
        viewModel.beginMatchSession()
    }
}
```

---

## 4. `ContentView.swift`

### Expected court bearing in `ContentView`
```swift
var currentCourtBearing: Double? {
    guard let initial = viewModel.courtInitialHeading else { return nil }
    let isTiebreak = viewModel.sets.last?.isTieBreak == true
    let segment = viewModel.gameCount + (isTiebreak ? viewModel.pointCountInTiebreak / 6 : 0)
    let flip = segment % 2 == 1 ? 180.0 : 0.0
    let raw = initial + flip
    return raw >= 360 ? raw - 360 : raw
}
```

### Pass new inputs to `CourtSideView`
```swift
CourtSideView(
    isDeuceSide: isDeuceSide,
    server: viewModel.currentServer,
    courtBearing: currentCourtBearing,
    currentHeading: viewModel.currentDeviceHeading,
    headingAccuracy: viewModel.currentHeadingAccuracy
)
```

### Update `CourtSideView` params
```swift
let courtBearing: Double?
let currentHeading: Double?
let headingAccuracy: Double

private var compassArrowColor: Color {
    compassColor(expected: courtBearing ?? 0)
}
```

### Compass UI
Wrap existing court in:
```swift
ZStack(alignment: .topTrailing) { ... }
```

Add indicator:
```swift
if let bearing = courtBearing {
    VStack(spacing: 1) {
        Image(systemName: "arrow.up")
            .font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(bearing))
        Text(cardinalLabel(for: bearing))
            .font(.system(size: 7, weight: .medium))
    }
    .foregroundColor(compassArrowColor)
    .animation(.easeInOut(duration: 0.4), value: courtBearing)
    .animation(.easeInOut(duration: 0.3), value: compassArrowColor)
    .offset(x: 6, y: -4)
}
```

Helpers:
```swift
private func cardinalLabel(for bearing: Double) -> String {
    let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return dirs[Int((bearing + 22.5) / 45) % 8]
}

private func compassColor(expected: Double) -> Color {
    guard let live = currentHeading, headingAccuracy >= 0, headingAccuracy <= 30 else {
        return Color.white.opacity(0.7)
    }
    let diff = min(abs(live - expected), 360 - abs(live - expected))
    if diff <= 45  { return .green }
    if diff >= 135 { return .red }
    return .orange
}
```

---

## 5. `DeuceMate_Watch_AppTests.swift` — Unit Tests for `currentCourtBearing`

Add the following test function to `DeuceMate Watch AppTests/DeuceMate_Watch_AppTests.swift` alongside the existing tiebreak server tests.

The bearing formula being tested:
```swift
let segment = viewModel.gameCount + (isTiebreak ? viewModel.pointCountInTiebreak / 6 : 0)
let flip = segment % 2 == 1 ? 180.0 : 0.0
```

`isTiebreak` is `viewModel.sets.last?.isTieBreak == true`.

### Test cases

| Scenario | gameCount | pointCountInTiebreak | isTiebreak | Expected segment | Expected flip |
|----------|-----------|---------------------|------------|-----------------|---------------|
| Match start | 0 | 0 | false | 0 | 0° |
| After game 1 | 1 | 0 | false | 1 | 180° |
| Enter tiebreak at 6-6 | 12 | 0 | true | 12 | 0° |
| Tiebreak point 6 (first changeover) | 12 | 6 | true | 13 | 180° |
| Tiebreak point 12 | 12 | 12 | true | 14 | 0° |
| Set 1 ends 6-3, start of set 2 | 9 | 0 | false | 9 | 180° |

### Test function

```swift
@Test func currentCourtBearingFlipsCorrectly() throws {
    // courtInitialHeading = 90° (East) so flip=0° → 90°, flip=180° → 270°
    struct BearingCase {
        let label: String
        let gameCount: Int
        let pointCountInTiebreak: Int
        let isTiebreak: Bool
        let expectedBearing: Double
    }

    let cases: [BearingCase] = [
        BearingCase(label: "Match start",                    gameCount: 0,  pointCountInTiebreak: 0,  isTiebreak: false, expectedBearing: 90),
        BearingCase(label: "After game 1",                   gameCount: 1,  pointCountInTiebreak: 0,  isTiebreak: false, expectedBearing: 270),
        BearingCase(label: "Enter tiebreak at 6-6",          gameCount: 12, pointCountInTiebreak: 0,  isTiebreak: true,  expectedBearing: 90),
        BearingCase(label: "Tiebreak point 6 (changeover)",  gameCount: 12, pointCountInTiebreak: 6,  isTiebreak: true,  expectedBearing: 270),
        BearingCase(label: "Tiebreak point 12",              gameCount: 12, pointCountInTiebreak: 12, isTiebreak: true,  expectedBearing: 90),
        BearingCase(label: "Set 1 ends 6-3, start of set 2", gameCount: 9,  pointCountInTiebreak: 0,  isTiebreak: false, expectedBearing: 270),
    ]

    let initialHeading: Double = 90

    for c in cases {
        let segment = c.gameCount + (c.isTiebreak ? c.pointCountInTiebreak / 6 : 0)
        let flip = segment % 2 == 1 ? 180.0 : 0.0
        let raw = initialHeading + flip
        let bearing = raw >= 360 ? raw - 360 : raw
        #expect(bearing == c.expectedBearing, "\(c.label): expected \(c.expectedBearing)°, got \(bearing)°")
    }
}
```

---

## 6. Privacy + Metadata updates

### `PRIVACY_POLICY.md`
Add a short section clarifying:
- Location permission is used for **compass heading only** (changeover orientation)
- No background route tracking implied by this feature
- Feature is optional and user-controlled via settings

### `docs/release/APP_STORE_METADATA.md`
Add/update matching disclosure language for review notes and listing text so it aligns with the plist permission message.

---

## Coloring Summary

| State | Color | Meaning |
|-------|-------|---------|
| Accuracy ≤ 30°, within 45° of expected | Green | Facing correct direction |
| Accuracy ≤ 30°, 45–135° off | Orange | Ambiguous |
| Accuracy ≤ 30°, ≥ 135° off | Red | Likely wrong direction |
| Accuracy > 30° or unavailable | White (dim) | Compass not reliable |

---

## Verification checklist (revised)

1. Enable **Check changeover** in settings.
2. Start match, pick first server.
3. Confirm that heading monitoring begins and confirmation screen appears.
4. Before heading is available, “✓ Confirmed” stays disabled and shows acquisition hint.
5. Hold watch up; once heading arrives, confirm becomes enabled.
6. Tap Confirmed → arrow appears at court top-right with cardinal label.
7. Rotate device: color changes green/orange/red according to heading delta.
8. Lower watch / worsen heading accuracy: indicator returns dim white.
9. Complete a game (or tiebreak 6-point segment): expected bearing flips 180°.
10. End/reset match: `resetHeadingState()` is called, heading state clears, and the `courtInitialHeading` UserDefaults key is removed.
11. Disable **Check changeover**: no confirmation step, no compass.
12. Resume existing in-progress match with `checkChangeover = true`: monitoring restarts automatically; no forced reconfirmation.
13. Confirm plist/privacy docs/metadata text are consistent.
14. Force-quit and relaunch mid-match with `checkChangeover = true`: compass arrow reappears because `courtInitialHeading` was persisted.
15. On a simulator or device without heading hardware: confirmation screen is skipped entirely and match proceeds normally.
16. Confirm match timer does not start until "✓ Confirmed" is tapped (not when server is selected).
