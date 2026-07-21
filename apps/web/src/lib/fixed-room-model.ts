export interface RoomModelPart {
  readonly size: readonly [number, number, number];
  readonly position: readonly [number, number, number];
  readonly color: string;
}

export interface FixedRoomModel {
  readonly id: "reframe-fixed-room-model-v1";
  readonly parts: readonly RoomModelPart[];
}

/**
 * The meshed room used as the 3D-model side of the comparison. It mirrors the
 * point-cloud layout as solid geometry and stays source-owned, never a binary.
 */
export function createFixedRoomModel(): FixedRoomModel {
  const parts: RoomModelPart[] = [
    { size: [7.6, 0.06, 5.45], position: [0, 0, -2.02], color: "#474033" },
    { size: [3.7, 0.03, 2.55], position: [0, 0.03, -2.35], color: "#574a2e" },
    { size: [7.6, 3.4, 0.06], position: [0, 1.7, -4.75], color: "#5f6359" },
    { size: [0.06, 3.4, 5.45], position: [-3.8, 1.7, -2.02], color: "#333b33" },
    { size: [1.52, 1.35, 0.04], position: [-2.19, 2.03, -4.71], color: "#a8baa3" },
    { size: [2.5, 0.42, 0.86], position: [1.4, 0.4, -3.9], color: "#804f33" },
    { size: [2.5, 1.02, 0.22], position: [1.4, 0.92, -4.24], color: "#754730" },
    { size: [0.3, 0.82, 0.86], position: [0.2, 0.52, -3.9], color: "#663b29" },
    { size: [0.3, 0.82, 0.86], position: [2.6, 0.52, -3.9], color: "#663b29" },
    { size: [0.92, 0.06, 0.76], position: [-2.25, 0.5, -3.32], color: "#291f17" },
    { size: [0.5, 0.48, 0.5], position: [-2.25, 0.24, -3.32], color: "#211a14" },
    { size: [0.34, 0.34, 0.34], position: [-2.22, 0.4, -3.38], color: "#3a2a1e" },
    { size: [0.62, 0.78, 0.5], position: [-2.22, 0.95, -3.38], color: "#457b3a" },
  ];
  return { id: "reframe-fixed-room-model-v1", parts };
}
