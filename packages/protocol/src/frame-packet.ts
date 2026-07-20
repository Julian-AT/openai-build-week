export const FRAME_PACKET_MAGIC = "RFFP";
export const FRAME_PACKET_VERSION = 1;
export const FRAME_PACKET_HEADER_BYTES = 24;

export interface FramePacketMetadata {
  readonly protocol_version: 1;
  readonly session_id: string;
  readonly submap_id: number;
  readonly frame_id: number;
  readonly timestamp_ns: number;
  readonly clock_domain: "ios_monotonic_uptime";
  readonly image: {
    readonly codec: "jpeg";
    readonly width: number;
    readonly height: number;
    readonly orientation: "up";
    readonly color_space: "sRGB";
    readonly payload_bytes: number;
  };
  /** 3×3 row-major `K_encoded`, in encoded-orientation-up pixels. */
  readonly intrinsics_encoded: readonly number[];
  /** RF-COORD-1, serialized row-major by logical rows. */
  readonly world_from_camera_arkit: readonly number[];
  readonly tracking: {
    readonly state: "normal" | "limited" | "not_available";
    readonly reason: string;
    readonly world_frame_version: number;
  };
  readonly capture_quality: {
    readonly blur_score: number;
    readonly angular_velocity_rad_s: number;
    readonly translation_since_last_m: number;
    readonly rotation_since_last_deg: number;
    readonly exposure_s: number;
    readonly iso: number;
  };
}

export interface FramePacketHeader {
  readonly protocol_version: number;
  readonly flags: number;
  readonly metadata_length: number;
  readonly image_length: number;
  readonly frame_id: number;
}

export interface FramePacket {
  readonly header: FramePacketHeader;
  readonly metadata: FramePacketMetadata;
  readonly image: Uint8Array;
}

export function encodeFramePacket(input: {
  readonly metadata: FramePacketMetadata;
  readonly image: Uint8Array;
  readonly flags: number;
}): Uint8Array {
  if (input.metadata.protocol_version !== FRAME_PACKET_VERSION) {
    throw new TypeError("unsupported_frame_packet_version");
  }
  assertFrameMetadata(input.metadata, input.image);
  if (!Number.isSafeInteger(input.flags) || input.flags < 0 || input.flags > 0xffff) {
    throw new TypeError("invalid_frame_packet");
  }
  const metadataBytes = new TextEncoder().encode(JSON.stringify(input.metadata));
  const bytes = new Uint8Array(
    FRAME_PACKET_HEADER_BYTES + metadataBytes.byteLength + input.image.byteLength,
  );
  bytes.set(new TextEncoder().encode(FRAME_PACKET_MAGIC), 0);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  view.setUint16(4, FRAME_PACKET_VERSION, true);
  view.setUint16(6, input.flags, true);
  view.setUint32(8, metadataBytes.byteLength, true);
  view.setUint32(12, input.image.byteLength, true);
  view.setBigUint64(16, BigInt(input.metadata.frame_id), true);
  bytes.set(metadataBytes, FRAME_PACKET_HEADER_BYTES);
  bytes.set(input.image, FRAME_PACKET_HEADER_BYTES + metadataBytes.byteLength);
  return bytes;
}

export function parseFramePacket(value: Uint8Array): FramePacket {
  if (value.byteLength < FRAME_PACKET_HEADER_BYTES)
    throw new TypeError("invalid_frame_packet_length");
  if (new TextDecoder("utf-8", { fatal: true }).decode(value.slice(0, 4)) !== FRAME_PACKET_MAGIC) {
    throw new TypeError("invalid_frame_packet_magic");
  }
  const view = new DataView(value.buffer, value.byteOffset, value.byteLength);
  const protocolVersion = view.getUint16(4, true);
  if (protocolVersion !== FRAME_PACKET_VERSION)
    throw new TypeError("unsupported_frame_packet_version");
  const flags = view.getUint16(6, true);
  const metadataLength = view.getUint32(8, true);
  const imageLength = view.getUint32(12, true);
  const frameID = Number(view.getBigUint64(16, true));
  if (!Number.isSafeInteger(frameID)) throw new TypeError("invalid_frame_packet");
  const expectedLength = FRAME_PACKET_HEADER_BYTES + metadataLength + imageLength;
  if (expectedLength !== value.byteLength || expectedLength < FRAME_PACKET_HEADER_BYTES) {
    throw new TypeError("invalid_frame_packet_length");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(
        value.slice(FRAME_PACKET_HEADER_BYTES, FRAME_PACKET_HEADER_BYTES + metadataLength),
      ),
    );
  } catch {
    throw new TypeError("invalid_frame_packet_metadata");
  }
  const image = value.slice(FRAME_PACKET_HEADER_BYTES + metadataLength);
  const metadata = parseFrameMetadata(parsed, image);
  if (metadata.frame_id !== frameID) throw new TypeError("invalid_frame_packet_frame_id");
  return Object.freeze({
    header: Object.freeze({
      protocol_version: protocolVersion,
      flags,
      metadata_length: metadataLength,
      image_length: imageLength,
      frame_id: frameID,
    }),
    metadata,
    image,
  });
}

function parseFrameMetadata(value: unknown, image: Uint8Array): FramePacketMetadata {
  if (!isRecord(value) || !hasExactKeys(value, ROOT_KEYS))
    throw new TypeError("invalid_frame_packet_metadata");
  const metadata = value as unknown as FramePacketMetadata;
  assertFrameMetadata(metadata, image);
  return metadata;
}

function assertFrameMetadata(metadata: FramePacketMetadata, image: Uint8Array): void {
  if (
    metadata.protocol_version !== FRAME_PACKET_VERSION ||
    !matchesSessionID(metadata.session_id) ||
    !isInteger(metadata.submap_id, 0, 2 ** 31 - 1) ||
    !isInteger(metadata.frame_id, 0, Number.MAX_SAFE_INTEGER) ||
    !isInteger(metadata.timestamp_ns, 0, Number.MAX_SAFE_INTEGER) ||
    metadata.clock_domain !== "ios_monotonic_uptime" ||
    !isRecord(metadata.image) ||
    !hasExactKeys(metadata.image, IMAGE_KEYS) ||
    metadata.image.codec !== "jpeg" ||
    !isInteger(metadata.image.width, 1, 4_096) ||
    !isInteger(metadata.image.height, 1, 4_096) ||
    metadata.image.orientation !== "up" ||
    metadata.image.color_space !== "sRGB" ||
    metadata.image.payload_bytes !== image.byteLength ||
    image.byteLength < 4 ||
    image[0] !== 0xff ||
    image[1] !== 0xd8 ||
    image.at(-2) !== 0xff ||
    image.at(-1) !== 0xd9 ||
    !isFiniteArray(metadata.intrinsics_encoded, 9) ||
    !isFiniteArray(metadata.world_from_camera_arkit, 16) ||
    !isRecord(metadata.tracking) ||
    !hasExactKeys(metadata.tracking, TRACKING_KEYS) ||
    !["normal", "limited", "not_available"].includes(metadata.tracking.state) ||
    !boundedText(metadata.tracking.reason, 1, 64) ||
    !isInteger(metadata.tracking.world_frame_version, 0, 2 ** 31 - 1) ||
    !isRecord(metadata.capture_quality) ||
    !hasExactKeys(metadata.capture_quality, CAPTURE_QUALITY_KEYS) ||
    !Object.values(metadata.capture_quality).every((number) => Number.isFinite(number)) ||
    metadata.capture_quality.blur_score < 0 ||
    metadata.capture_quality.angular_velocity_rad_s < 0 ||
    metadata.capture_quality.translation_since_last_m < 0 ||
    metadata.capture_quality.rotation_since_last_deg < 0 ||
    metadata.capture_quality.exposure_s <= 0 ||
    !isInteger(metadata.capture_quality.iso, 1, 102_400)
  ) {
    throw new TypeError("invalid_frame_packet");
  }
}

const ROOT_KEYS = [
  "protocol_version",
  "session_id",
  "submap_id",
  "frame_id",
  "timestamp_ns",
  "clock_domain",
  "image",
  "intrinsics_encoded",
  "world_from_camera_arkit",
  "tracking",
  "capture_quality",
] as const;
const IMAGE_KEYS = [
  "codec",
  "width",
  "height",
  "orientation",
  "color_space",
  "payload_bytes",
] as const;
const TRACKING_KEYS = ["state", "reason", "world_frame_version"] as const;
const CAPTURE_QUALITY_KEYS = [
  "blur_score",
  "angular_velocity_rad_s",
  "translation_since_last_m",
  "rotation_since_last_deg",
  "exposure_s",
  "iso",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every((key) => key in value);
}

function isFiniteArray(value: unknown, length: number): value is readonly number[] {
  return Array.isArray(value) && value.length === length && value.every(Number.isFinite);
}

function isInteger(value: unknown, minimum: number, maximum: number): value is number {
  return (
    typeof value === "number" && Number.isSafeInteger(value) && value >= minimum && value <= maximum
  );
}

function boundedText(value: unknown, minimum: number, maximum: number): value is string {
  return (
    typeof value === "string" &&
    value.length >= minimum &&
    value.length <= maximum &&
    !value.includes("\u0000")
  );
}

function matchesSessionID(value: unknown): value is string {
  return typeof value === "string" && /^room_[a-z0-9_]{3,120}$/u.test(value);
}
