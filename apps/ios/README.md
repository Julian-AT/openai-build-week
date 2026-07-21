# Reframe iOS

The native SwiftUI application owns Reframe's live spatial-editing experience.
ARKit is pose and world authority during a healthy session; RealityKit renders
virtual assets, reveal geometry, occluders, shadows, coaching, and product UI
over the untouched camera feed.

## Ownership

The app owns local capture durability, frame selection, target seeds, immediate
raycast previews, verified artifact activation, the committed EditKit cache,
offline rendering, and immediate local inverse application.

It never grants Realtime or GPT authority to mutate scene state. It does not
invent server revisions, trust model indices as identity, or wait for network
or inference in the render loop.

## Commands

```sh
swift test --package-path apps/ios/Packages/SpatialCore
xcodebuild build \
  -project apps/ios/Reframe/Reframe.xcodeproj \
  -scheme Reframe \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Physical deployment requires a developer-team bundle identifier and the normal
iOS camera and microphone permissions. Credentials and gateway addresses are
runtime configuration, never source files.

## Known limitations

Current physical evidence proves bounded placement behavior, not the complete
SAM-driven replacement path. Durable frame/target transport, artifact event
activation, persistent reconnect hydration, real reveal/occluder rendering,
offline/reconnect acceptance, and phone FPS/thermal/visual gates remain open.
