export const RF_COORDINATE_CONVENTION = "RF-COORD-1";

/** `C_arkit_from_opencv`, serialized logically by rows. */
export const C_ARKIT_FROM_OPENCV_ROW_MAJOR = Object.freeze([
  1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1,
] as const);

export interface EncodedImageIntrinsics {
  readonly fx: number;
  readonly fy: number;
  readonly cx: number;
  readonly cy: number;
}

/** `T_world_from_camera_cv = T_world_from_camera_arkit × C_arkit_from_opencv`. */
export function worldFromCameraOpenCV(worldFromCameraARKit: readonly number[]): readonly number[] {
  assertMatrix(worldFromCameraARKit);
  return Object.freeze(multiplyRowMajor4x4(worldFromCameraARKit, C_ARKIT_FROM_OPENCV_ROW_MAJOR));
}

/** Normalized OpenCV optical-axis ray for an encoded-orientation-up pixel. */
export function projectEncodedPixelToOpenCVRay(
  intrinsics: EncodedImageIntrinsics,
  x: number,
  y: number,
): readonly [number, number, number] {
  if (
    ![intrinsics.fx, intrinsics.fy].every((value) => Number.isFinite(value) && value > 0) ||
    ![intrinsics.cx, intrinsics.cy, x, y].every(Number.isFinite)
  ) {
    throw new TypeError("invalid_encoded_intrinsics");
  }
  const unnormalizedX = (x - intrinsics.cx) / intrinsics.fx;
  const unnormalizedY = (y - intrinsics.cy) / intrinsics.fy;
  const norm = Math.hypot(unnormalizedX, unnormalizedY, 1);
  return Object.freeze([unnormalizedX / norm, unnormalizedY / norm, 1 / norm]);
}

function multiplyRowMajor4x4(left: readonly number[], right: readonly number[]): number[] {
  const result = new Array<number>(16).fill(0);
  for (let row = 0; row < 4; row += 1) {
    for (let column = 0; column < 4; column += 1) {
      result[row * 4 + column] =
        element(left, row * 4) * element(right, column) +
        element(left, row * 4 + 1) * element(right, 4 + column) +
        element(left, row * 4 + 2) * element(right, 8 + column) +
        element(left, row * 4 + 3) * element(right, 12 + column);
    }
  }
  return result.map((value) => (Math.abs(value) < Number.EPSILON ? 0 : value));
}

function assertMatrix(value: readonly number[]): void {
  if (value.length !== 16 || !value.every(Number.isFinite))
    throw new TypeError("invalid_row_major_matrix");
}

function element(matrix: readonly number[], index: number): number {
  const value = matrix[index];
  if (value === undefined) throw new TypeError("invalid_row_major_matrix");
  return value;
}
