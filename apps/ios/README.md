# Reframe for iPhone

[Back to Reframe](../../README.md)

The SwiftUI application owns Reframe's live spatial-editing experience. ARKit
tracks the room; RealityKit renders previews and committed virtual content over
the untouched camera feed.

## Responsibilities

- Capture camera poses, planes, and target seeds; provide bounded `.rfcap` recording.
- Produce immediate reticle and floor-placement feedback on device.
- Render verified USDZ assets without blocking the frame loop.
- Keep a local scene replica for confirmation, restore, and offline continuity.
- Carry typed and Realtime turns to the same gateway-owned preview boundary.

The reusable `SpatialCore` package separates capture, edit, render, and wire
protocol behavior from the branded application.

## Build and test

```sh
swift test --package-path apps/ios/Packages/SpatialCore
xcodebuild build \
  -project apps/ios/Reframe/Reframe.xcodeproj \
  -scheme Reframe \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Use Xcode with Swift 6.1 and the iOS 18 SDK. Camera tracking and the complete AR
experience require a physical iPhone.

## Runtime connection

The application reads `REFRAME_GATEWAY_URL`, `REFRAME_ROOM_ID`,
`REFRAME_ROOM_CREDENTIAL`, and `REFRAME_ROOM_EXPIRES_AT_MS` from the active
scheme environment. Room credentials are short-lived; the standard OpenAI key
stays on the gateway. Camera and microphone permission copy is already declared
by the app target.
