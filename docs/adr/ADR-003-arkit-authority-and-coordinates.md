# ADR-003: ARKit World Authority and RR-COORD-1

Status: Accepted  
Date: 2026-07-14

## Context

Incorrect orientation, crop, intrinsics, pose direction, matrix layout, timestamp precision, or world-reset handling can make every spatial subsystem appear plausible while being wrong.

## Project constraints

- The base iPhone path cannot use LiDAR scene depth or scene reconstruction.
- Swift, JavaScript, and Python must reproduce the same projection.
- ARKit is the sole pose/world authority during a healthy native session.

## Alternatives considered

1. Let each subsystem convert coordinates locally.
2. Replace ARKit poses with learned poses.
3. Use the single RR-COORD-1 convention and explicit conversion artifacts.

## Decision

Adopt alternative 3. RR-COORD-1 is defined by the glossary. Every FramePacket carries physically upright encoded bytes, encoded-pixel intrinsics, directed `encoded_from_sensor`, world-frame identity/version, and `world_from_camera`. Mathematics uses column vectors; matrices serialize row-major. OpenCV conversion is explicit and tested. `monotonic_timestamp_ns` is always an unsigned decimal string in the device boot-time domain; integer nanoseconds are forbidden at the JSON boundary. A world reset creates a new world-frame version and never silently aligns it. A validated correction maps `p_to = T_to_from_from · p_from`, targets a strictly newer version, and has the same base/target version; when alignment is unknown the new epoch is quarantined until validation or explicit reseed.

## Evidence

- ARKit scene depth and scene reconstruction require supported LiDAR hardware: https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth and https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)
- `capturedImage` is not orientation-adjusted; `displayTransform` handles rotation/aspect crop: https://developer.apple.com/documentation/arkit/arframe/displaytransform(for:viewportsize:)
- Raw feature points are unstable observations, not durable geometry: https://developer.apple.com/documentation/arkit/arframe/rawfeaturepoints

## Consequences

- All consumers share one projection fixture and transform vocabulary.
- Learned providers may estimate depth but cannot rewrite a healthy ARKit trajectory.
- World resets stop live integration or create explicit correction evidence.

## Risks

- JSON precision, transpose, pixel-center, and orientation bugs remain easy to introduce.
- Apple API conventions still require physical-device sanity checks.

## Fallback

Reject a packet or pause the submap when its coordinate version is unknown, inconsistent, or fails validation. Preserve it in `.rrcap` for diagnosis; never guess a transform.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-002`: project synthetic known rays with error at most one encoded pixel, then pass a physical-device checkerboard/orientation fixture. Timebox: first contract/capture slice. Failure blocks semantic lifting, fusion, reveal, and live integration until corrected.

## Requirements and contracts affected

`NFR-COORD-001`, `FR-CAPTURE-001`, `FR-TARGET-001`, CON-001, CON-002, CON-003, and CON-004.

## Supersession

Replaces duplicated or incomplete coordinate examples in the archived inputs. No canonical ADR is superseded.
