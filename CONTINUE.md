# Continue on the NVIDIA workstation

This is the active cross-device handoff for branch
`refactor/reframe-foundation`. Read `AGENTS.md` and
`MASTER_TECHNICAL_PROMPT.md` before changing product behavior.

## Last verified state

- Git was clean before this handoff was written.
- The latest implementation commits before this file are:
  - `053da61` — pinned DA3Metric-Large loader and geometry profile;
  - `d5f193b` — metric-depth provider and fail-closed output validation;
  - `1b66fef` — encoded-frame intrinsics in the worker contract.
- `bun run check:quick` passed.
- `apps/vision`: 21 tests passed; Ruff and basedpyright passed.
- A real DA3Metric-Large inference passed on MPS. The Reframe provider returned
  finite, digest-bound metric depth after applying the official focal-length
  conversion.
- No model weights, credentials, captures, or machine-specific paths are in
  Git.

## Next action

On the NVIDIA PC, check out this branch, verify the NVIDIA driver, install the
locked workspace, and start the DA3 `geometry` profile on CUDA. Do this before
working on SAM, LaMa, TSDF, or additional architecture.

The recommended environment is native Ubuntu 24.04 or Ubuntu 24.04 under WSL2.
Keep the iOS/Xcode build on the Mac.

## 1. Transfer the branch

The handoff commit must be pushed from the old computer before cloning or
pulling it on the new computer:

```sh
git push origin refactor/reframe-foundation
```

Then, on the NVIDIA workstation:

```sh
git clone https://github.com/Julian-AT/openai-build-week.git
cd openai-build-week
git switch refactor/reframe-foundation
git pull --ff-only
git status --short
git log -5 --oneline
```

`git status --short` must be empty. The newest commit should be the handoff
commit containing this file. Do not reconstruct work from `main`.

## 2. Verify the NVIDIA host

Install the latest production NVIDIA driver using the official NVIDIA/Ubuntu
or Windows driver flow, reboot, and run:

```sh
nvidia-smi
```

For the locked Reframe PyTorch 2.13 environment, the driver must support its
CUDA 13 runtime. Upgrade the driver if `nvidia-smi` reports an older maximum
CUDA version. The PyTorch wheels install their CUDA runtime libraries; a full
system CUDA toolkit is not needed for the first DA3 smoke test.

On Windows, install the NVIDIA Windows driver and run the remaining Linux
commands inside WSL2. Do not install a second Linux display driver inside WSL.

## 3. Install the repository toolchain

The repository pins Bun 1.3.11, uv 0.11.16 in CI, and supports Python
3.12–3.13 for vision. Install those exact tool versions:

```sh
sudo apt-get update
sudo apt-get install -y build-essential curl git unzip
curl -fsSL https://bun.sh/install | bash -s "bun-v1.3.11"
curl -LsSf https://astral.sh/uv/0.11.16/install.sh | sh
uv python install 3.13.12
bun --version
uv --version
python3 --version
```

Start a new shell if `bun` or `uv` is not yet on `PATH`, then install and
verify the locked workspace:

```sh
bun install --frozen-lockfile
uv sync --project apps/vision --frozen --extra torch
bun run check:quick
uv run --project apps/vision --frozen pytest -q
```

Verify that the locked PyTorch installation sees the GPU:

```sh
uv run --project apps/vision --frozen --extra torch python -c 'import torch; assert torch.cuda.is_available(); p=torch.cuda.get_device_properties(0); print({"torch": torch.__version__, "cuda": torch.version.cuda, "gpu": p.name, "capability": torch.cuda.get_device_capability(0), "vram_gib": round(p.total_memory/2**30, 2)})'
```

If this fails, fix the driver/runtime boundary. Do not weaken
`select_accelerator`, change the lock, or silently fall back to CPU.

## 4. Prepare the pinned DA3 runtime

Keep sources, environments, and weights outside the repository:

```sh
export REFRAME_DATA_DIR="$HOME/.cache/Reframe"
mkdir -p "$REFRAME_DATA_DIR/sources" "$REFRAME_DATA_DIR/models" "$REFRAME_DATA_DIR/environments"
git clone https://github.com/ByteDance-Seed/Depth-Anything-3.git "$REFRAME_DATA_DIR/sources/depth-anything-3"
git -C "$REFRAME_DATA_DIR/sources/depth-anything-3" checkout --detach 3fe327a6abe2e5db95b54444ea95463dbfef5610
```

Download the exact Apache-2.0 checkpoint revision:

```sh
uvx hf download depth-anything/DA3METRIC-LARGE \
  --revision 4010e39f3634a45bc60553321fb49fb760bd594e \
  --local-dir "$REFRAME_DATA_DIR/models/da3metric-large"
sha256sum "$REFRAME_DATA_DIR/models/da3metric-large/model.safetensors"
```

Expected model file:

```text
bytes:   1336734448
sha256:  bbea5b0b3ee389849cffa7ddae89de064a90abd2b055fc5aa99aac68db324776
```

DA3's upstream package imports research/export dependencies too broadly, so
Reframe loads it through a verified, export-disabled boundary. Reproduce the
currently measured isolated environment; do not install DA3's unbounded
`all` extra:

```sh
uv venv --python 3.12.11 "$REFRAME_DATA_DIR/environments/da3-cuda"
source "$REFRAME_DATA_DIR/environments/da3-cuda/bin/activate"
uv pip install \
  torch==2.13.0 torchvision==0.28.0 numpy==1.26.4 pillow==12.1.1 \
  safetensors==0.8.0 huggingface-hub==1.24.0 einops==0.8.2 \
  opencv-python-headless==4.11.0.86 omegaconf==2.3.1 \
  trimesh==4.12.2 imageio==2.37.4 e3nn==0.6.0 addict==2.4.0 \
  evo==1.37.0 pillow-heif==1.4.0 matplotlib==3.11.1 \
  moviepy==1.0.3 plyfile==1.1.4 pycolmap==4.1.1
uv pip install --no-deps -e "$REFRAME_DATA_DIR/sources/depth-anything-3"
uv pip install -e ./apps/vision
```

Start the worker. Use a local secret value; never commit or paste it into logs:

```sh
export REFRAME_VISION_TOKEN="replace-with-a-local-high-entropy-token"
export REFRAME_VISION_PROFILE=geometry
export REFRAME_VISION_HOST=127.0.0.1
export REFRAME_VISION_PORT=8790
export REFRAME_DA3_SOURCE_DIR="$REFRAME_DATA_DIR/sources/depth-anything-3"
export REFRAME_DA3_MODEL_DIR="$REFRAME_DATA_DIR/models/da3metric-large"
export REFRAME_DA3_DEVICE=cuda
python -m reframe_vision.main
```

In a second shell with the same token value:

```sh
curl --fail --silent \
  -H "Authorization: Bearer $REFRAME_VISION_TOKEN" \
  http://127.0.0.1:8790/readyz
```

The response must be `ready`, identify `da3metric-large`, and expose only
`metric_depth: true`. Record cold load time, warm inference time, peak VRAM,
and any OOM. Do not claim the CUDA path is measured before this succeeds.

## 5. LaMa checkpoint preparation

LaMa is a reveal fallback, not the object-replacement system. It fills only
background pixels that cannot be reconstructed from observed views. Download
the required official archive directly; do not download the entire Google
Drive folder because it also contains a multi-gigabyte training bundle:

```sh
mkdir -p "$REFRAME_DATA_DIR/models/lama-official"
uvx --from gdown gdown \
  'https://drive.google.com/uc?id=11RbsVSav3O-fReBsPHBE1nn8kcFIMnKp' \
  -O "$REFRAME_DATA_DIR/models/lama-official/big-lama.zip"
sha256sum "$REFRAME_DATA_DIR/models/lama-official/big-lama.zip"
unzip "$REFRAME_DATA_DIR/models/lama-official/big-lama.zip" \
  -d "$REFRAME_DATA_DIR/models/lama-official"
sha256sum "$REFRAME_DATA_DIR/models/lama-official/big-lama/models/best.ckpt"
```

Expected hashes:

```text
big-lama.zip:  d7161bba4d68b438f9fa7f09dcb750a223804c300c68d214a5e0be16251fba8d
best.ckpt:     fccb7adffd53ec0974ee5503c3731c2c2f1e7e07856fd9228cdcc0b46fd5d423
```

The official checkpoint is a legacy PyTorch-Lightning pickle. Do **not** call
`torch.load(..., weights_only=False)` in the application process. The next
LaMa task is to create a restricted, one-time converter that extracts only the
generator tensors into `safetensors`, verifies both digests, and then loads
only the converted artifact in the isolated reveal worker.

## 6. SAM 3.1 manual gate

SAM 3.1 is gated and uses the SAM License. A human must visit
`https://huggingface.co/facebook/sam3.1`, review/accept the terms, and then run:

```sh
uvx hf auth login
uvx hf auth whoami
```

After acceptance, pin the official source at
`46957e47805eaa273f4aa7bbbd25a88bca9108ce`, resolve the exact accessible
checkpoint revision, download it into `$REFRAME_DATA_DIR/models`, and record
its byte length and SHA-256 before writing the provider. Keep SAM in a separate
Python 3.12/CUDA environment. The official project requires PyTorch 2.7+ and
CUDA 12.6+.

An RTX 2060 Super commonly has limited VRAM for these models. Never keep SAM,
DA3, LaMa, and TSDF workloads resident concurrently until measured. Follow the
master scheduler: one heavy lane at a time, newest eligible geometry frame
only, bounded resolution, and explicit OOM reporting.

## Open threads

- Implement robust ARKit sparse-correspondence alignment before TSDF.
- Add bounded Open3D CUDA `VoxelBlockGrid` integration only after accepted
  alignment exists.
- Convert and benchmark LaMa safely, then bind it to the existing
  `RevealFillProvider` boundary.
- Implement SAM 3.1 target tracking after the human license gate.
- The current GitHub workflow still contains legacy `apps/inference` and
  `ReRoomDeviceProof` paths. Fix those paths in a separate CI-only commit before
  opening a PR; do not mix that repair into a model provider slice.
- The NVIDIA machine cannot verify the iOS target. Keep Swift package tests and
  the Reframe simulator build as a Mac gate.

## Do not

- Do not commit weights, Hugging Face tokens, `.env` files, captures, vector
  databases, or generated evidence.
- Do not revive GSD, `.planning`, root scripts, fixture corpora, or legacy
  ReRoom names.
- Do not treat LaMa as segmentation or replacement logic.
- Do not let a model commit scene state. Models propose; deterministic code
  authorizes, validates, confirms, commits, and restores.
- Do not run all GPU models simultaneously on the 2060 Super.
- Do not push from the new PC until the checked-out handoff commit and clean
  worktree have been confirmed.

Primary setup references: [NVIDIA Linux driver guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/ubuntu.html),
[PyTorch CUDA documentation](https://pytorch.org/docs/stable/cuda.html),
[Hugging Face CLI](https://huggingface.co/docs/huggingface_hub/en/guides/cli),
[SAM 3 source](https://github.com/facebookresearch/sam3), and
[DA3 source](https://github.com/ByteDance-Seed/Depth-Anything-3).
