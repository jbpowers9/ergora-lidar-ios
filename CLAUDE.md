# ErgoraLiDAR

SwiftUI + RoomPlan iOS app for LiDAR room scanning and Ergora API submission.

- **Entry:** `ErgoraLiDAR/ErgoraLiDARApp.swift` → `ContentView`
- **Privacy:** `NSCameraUsageDescription` is set via target build setting `INFOPLIST_KEY_NSCameraUsageDescription` (a standalone `Info.plist` inside the synchronized `ErgoraLiDAR/` folder would be copied as a resource and conflict with the generated plist).
- **Navigation:** `NavigationStack` + `AppRoute` in `ContentView.swift`
- **Scan flow:** `ScanFlowModel` holds `sketchPayload`, `lastCapturedRoom`, and `selectedScanFloor`. After a scan, `RoomScanView` replaces the path so `roomScan` is not under `scanResult` (avoids losing results via the back gesture).

See the project README or Xcode target settings for deployment target and signing.
