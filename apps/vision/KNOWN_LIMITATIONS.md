# Vision verification record

This package-local record keeps operational findings with the capability they
affect. It is not a product promise and contains no model weights, captures,
credentials, or machine-specific paths.

## Verified

- The pinned DA3Metric-Large source and checkpoint load on the permitted NVIDIA
  A100 runtime with the locked Torch 2.6.0 CUDA 12.4 environment.
- A real canonicalized JPEG from the catalog smoke path completed the private
  FastAPI worker request and returned a typed, request-bound metric-depth
  artifact. The worker rejected the original malformed/trailing-byte JPEG
  before inference.
- Model-source, checkpoint, configuration, input, and output digests are
  checked before a result can be used. Pose alignment and exporters are
  deliberately disabled at this boundary.
- The SAM 3.1 adapter has strict point/box prompt binding, bounded one-target
  session state, monotonic frame checks, RLE digest validation, and a safe
  single-output fallback for predictor builds that normalize the object ID to
  zero. The local fake-provider and predictor-boundary tests pass alongside
  the vision suite.
- On the permitted A100 80 GB runtime, the pinned SAM 3.1 release source
  (`9f22cb976fb6e38dad5bb34940fad852dd897d0e`) initialized the official
  multiplex predictor from the verified checkpoint SHA-256
  `0567debeec80ba4ac6369540c6c248025283cb3ff2b92827509e57e2b3541cb6`.
  A normalized box prompt over a 640x480 frame returned one mask with object
  ID zero, confidence 0.996, and 72,770 foreground pixels.

## Errors found and handled

- The workstation driver exposes CUDA 12.4, while the original Torch lock
  selected a CUDA 13 wheel. The lock now selects the official Torch 2.6.0 and
  torchvision 0.21.0 CUDA 12.4 wheels on Linux x86_64.
- The downloader smoke JPEG contained trailing bytes that Pillow tolerated but
  the strict wire contract rejected. The proof path now uses a canonical
  re-encoded JPEG and preserves the rejection behavior for untrusted input.
- DA3 imports an optional pose-alignment dependency. The geometry worker
  installs an explicit disabled boundary so metric depth cannot silently gain
  pose authority or an unapproved exporter.

## Pending capability gates

- SAM 3.1 model activation is verified on the prepared A100 runtime, but the
  repository still cannot claim a production worker deployment: the local
  vision lock remains on its older Torch/CUDA profile and the physical room
  capture path has not yet supplied a real frame. A synthetic box smoke is
  runtime evidence only, not a target-track quality or device acceptance.
- Robust ARKit/depth alignment, conservative volume extraction, Open3D TSDF,
  plane atlases, and isolated reveal generation still need provider-backed
  implementation and recorded quality gates.
- CUDA cold-load and warm-inference timings are workstation evidence only;
  sustained iPhone rendering, thermal behavior, RealityKit ordering, and
  physical-device visual acceptance remain human/device checks.

## Potential upgrades

- Keep one explicit GPU coordinator across DA3, semantics, TSDF, and reveal
  jobs, with cancellation and newest-frame retention under bounded VRAM.
- Add a calibrated multi-view capture benchmark with residual, coverage, and
  OOM telemetry before enabling dense geometry or removal.
- Persist redacted provider timing and rejection diagnostics alongside each
  artifact revision so replay can distinguish source, alignment, and model
  failures without retaining raw room imagery.
- Add a real ARKit frame acceptance using a box/reticle seed, then verify
  cross-frame tracking and conservative geometry before enabling replacement.
