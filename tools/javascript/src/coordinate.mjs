import {
  RunnerFailure,
  caseResult,
  parseJsonBytesStrict,
  readFixtureFile,
  rejectedCaseResult,
  sha256Hex,
} from "./loader.mjs";

export const RR_FLOAT_MAX = 3.4028234663852886e38;
const SCALAR_ABSOLUTE_TOLERANCE = 1e-5;
const SCALAR_RELATIVE_TOLERANCE = 1e-6;
const RIGID_TOLERANCE = 1e-4;
const HOMOGENEOUS_ROW_TOLERANCE = 1e-6;

function requireCoordinate(condition, message, rejectionClass = "coordinate_invalid") {
  if (!condition) throw new RunnerFailure(rejectionClass, message);
}

export function quantizeRrFloat(value) {
  requireCoordinate(typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= RR_FLOAT_MAX, "value is outside finite binary32 range", "numeric_out_of_range");
  const quantized = Math.fround(value);
  requireCoordinate(Number.isFinite(quantized), "value overflows binary32", "numeric_out_of_range");
  return quantized;
}

export function rrFloatEqual(left, right) {
  const a = quantizeRrFloat(left);
  const b = quantizeRrFloat(right);
  return Math.abs(a - b) <= SCALAR_ABSOLUTE_TOLERANCE + SCALAR_RELATIVE_TOLERANCE * Math.max(Math.abs(a), Math.abs(b));
}

export function rrTranslationEqual(left, right) {
  return rrFloatEqual(left, right) && Math.abs(quantizeRrFloat(left) - quantizeRrFloat(right)) <= 1e-4;
}

export function rrTransformedIntrinsicsEqual(left, right) {
  return rrFloatEqual(left, right) && Math.abs(quantizeRrFloat(left) - quantizeRrFloat(right)) <= 1e-3;
}

function quantizedArray(values, length) {
  requireCoordinate(Array.isArray(values) && values.length === length, `expected ${length} matrix/vector values`);
  return values.map(quantizeRrFloat);
}

function determinant3(matrix) {
  const [a, b, c, d, e, f, g, h, i] = matrix;
  return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
}

function validateProperRotation(rotation) {
  let orthogonalitySquared = 0;
  for (let row = 0; row < 3; row += 1) {
    for (let column = 0; column < 3; column += 1) {
      let dot = 0;
      for (let index = 0; index < 3; index += 1) dot += rotation[index * 3 + row] * rotation[index * 3 + column];
      const difference = dot - (row === column ? 1 : 0);
      orthogonalitySquared += difference * difference;
    }
  }
  requireCoordinate(Math.sqrt(orthogonalitySquared) <= RIGID_TOLERANCE, "rotation is not orthonormal");
  requireCoordinate(Math.abs(determinant3(rotation) - 1) <= RIGID_TOLERANCE, "rotation determinant is not +1");
  return rotation;
}

export function validateRigidTransform(values) {
  const matrix = quantizedArray(values, 16);
  const rotation = [matrix[0], matrix[1], matrix[2], matrix[4], matrix[5], matrix[6], matrix[8], matrix[9], matrix[10]];
  validateProperRotation(rotation);
  const expectedLastRow = [0, 0, 0, 1];
  requireCoordinate(matrix.slice(12).every((value, index) => Math.abs(value - expectedLastRow[index]) <= HOMOGENEOUS_ROW_TOLERANCE), "homogeneous last row is invalid");
  return matrix;
}

function multiplyMatrixVector(matrix, vector, size) {
  const output = new Array(size).fill(0);
  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) output[row] += matrix[row * size + column] * vector[column];
  }
  return output.map((value) => Object.is(value, -0) ? 0 : value);
}

export function projectCameraPoint(intrinsics, cameraPoint) {
  const [x, y, z] = quantizedArray(cameraPoint, 3);
  requireCoordinate(z !== 0, "camera point lies on the projection plane");
  const fx = quantizeRrFloat(intrinsics.fx);
  const fy = quantizeRrFloat(intrinsics.fy);
  const cx = quantizeRrFloat(intrinsics.cx);
  const cy = quantizeRrFloat(intrinsics.cy);
  requireCoordinate(fx > 0 && fy > 0, "intrinsic focal lengths must be positive");
  return {
    encoded_pixel: [fx * (x / z) + cx, fy * (y / z) + cy].map((value) => Object.is(value, -0) ? 0 : value),
    visible: z < 0,
  };
}

export function transformIntrinsics(sensorIntrinsics, encodedFromSensor, encodedSize, orientation) {
  requireCoordinate(orientation === "up", "encoded orientation must be physically upright");
  const transform = quantizedArray(encodedFromSensor, 9);
  const [width, height] = encodedSize;
  requireCoordinate(Number.isInteger(width) && width > 0 && Number.isInteger(height) && height > 0, "encoded size is invalid");
  const matrix = [
    quantizeRrFloat(sensorIntrinsics.fx), 0, quantizeRrFloat(sensorIntrinsics.cx),
    0, quantizeRrFloat(sensorIntrinsics.fy), quantizeRrFloat(sensorIntrinsics.cy),
    0, 0, 1,
  ];
  const product = new Array(9).fill(0);
  for (let row = 0; row < 3; row += 1) {
    for (let column = 0; column < 3; column += 1) {
      for (let index = 0; index < 3; index += 1) product[row * 3 + column] += transform[row * 3 + index] * matrix[index * 3 + column];
    }
  }
  requireCoordinate(Math.abs(product[6]) <= HOMOGENEOUS_ROW_TOLERANCE && Math.abs(product[7]) <= HOMOGENEOUS_ROW_TOLERANCE && Math.abs(product[8] - 1) <= HOMOGENEOUS_ROW_TOLERANCE, "encoded pixel transform is not affine");
  return {
    encoded_intrinsics: {
      fx: Math.hypot(product[0], product[1]),
      fy: Math.hypot(product[3], product[4]),
      cx: product[2],
      cy: product[5],
    },
    encoded_size: [width, height],
    orientation: "up",
  };
}

export function applyWorldCorrection(fromVersion, toVersion, transform, pointFrom) {
  requireCoordinate(Number.isInteger(fromVersion) && Number.isInteger(toVersion) && fromVersion >= 1 && toVersion > fromVersion, "world correction must target a strictly newer epoch");
  return multiplyMatrixVector(validateRigidTransform(transform), quantizedArray(pointFrom, 4), 4);
}

function binary32Hex(value) {
  const bytes = Buffer.alloc(4);
  bytes.writeFloatBE(quantizeRrFloat(value));
  return bytes.toString("hex");
}

export function executeCoordinateOperation(input) {
  switch (input.operation) {
    case "project":
      requireCoordinate(input.pixel_center === "half_integer", "pixel-center convention is unsupported");
      return projectCameraPoint(input.intrinsics, input.camera_point);
    case "transform_intrinsics":
      return transformIntrinsics(input.sensor_intrinsics, input.encoded_from_sensor, input.encoded_size, input.orientation);
    case "arkit_to_opencv_camera":
      return { opencv_camera_point: multiplyMatrixVector(validateProperRotation(quantizedArray(input.conversion, 9)), quantizedArray(input.camera_point, 3), 3) };
    case "apply_world_correction":
      return { point_to: applyWorldCorrection(input.from_world_frame_version, input.to_world_frame_version, input.to_from_from_transform, input.point_from) };
    case "validate_rr_float":
      return { binary32_hex: binary32Hex(input.value) };
    case "validate_rigid_transform":
      validateRigidTransform(input.values);
      return { valid: true };
    default:
      throw new RunnerFailure("coordinate_invalid", "unsupported coordinate operation");
  }
}

export async function executeCoordinateCase(fixture, fixtureCase) {
  try {
    const output = executeCoordinateOperation(parseJsonBytesStrict(await readFixtureFile(fixture, fixtureCase.input)));
    const bytes = Buffer.from(`${JSON.stringify(output)}\n`, "utf8");
    const kind = fixtureCase.expected.artifacts[0]?.kind;
    return caseResult(fixtureCase.case_id, "accept", null, kind ? [{ kind, byte_length: bytes.length, sha256: sha256Hex(bytes) }] : []);
  } catch (error) {
    return rejectedCaseResult(fixtureCase, error);
  }
}
