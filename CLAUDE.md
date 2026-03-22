# ErgoraLiDAR

SwiftUI + RoomPlan iOS app for LiDAR room scanning and Ergora API submission.

- **Entry:** `ErgoraLiDAR/ErgoraLiDARApp.swift` → `ContentView`
- **Privacy:** `NSCameraUsageDescription` is set via target build setting `INFOPLIST_KEY_NSCameraUsageDescription` (a standalone `Info.plist` inside the synchronized `ErgoraLiDAR/` folder would be copied as a resource and conflict with the generated plist).
- **Navigation:** `NavigationStack` + `AppRoute` in `ContentView.swift`
- **Scan flow:** `ScanFlowModel` holds `sketchPayload`, `lastCapturedRoom`, and `selectedScanFloor`. After a scan, `RoomScanView` replaces the path so `roomScan` is not under `scanResult` (avoids losing results via the back gesture).

See the project README or Xcode target settings for deployment target and signing.

- **Scan token expiry** is controlled by the Ergora web app (`src/app/api/reports/[id]/sketch/scan-token/route.ts` in the Next.js repo), not this iOS project. The appraiser rescans the QR code after expiry; the app keeps the current `sketchPayload` in memory when using “Return to Start” after a 401.
