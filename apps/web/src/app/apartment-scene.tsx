"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { PLYLoader } from "three/examples/jsm/loaders/PLYLoader.js";

import { labelVoxels, type RegionLabel } from "../lib/apartment-analysis.ts";

const SOURCE = "/apartment.ply";
const VOXEL_GRID = 150;

type View = "points" | "model";

export default function ApartmentScene() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const labelsHostRef = useRef<HTMLDivElement>(null);
  const [view, setView] = useState<View>("model");
  const [status, setStatus] = useState("Loading point cloud…");
  const [labels, setLabels] = useState<readonly RegionLabel[]>([]);

  const viewRef = useRef<View>(view);
  const apiRef = useRef<{ setView: (next: View) => void } | null>(null);
  viewRef.current = view;

  useEffect(() => {
    const canvas = canvasRef.current;
    const labelsHost = labelsHostRef.current;
    if (!canvas || !labelsHost) return;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ canvas, antialias: false });
    } catch {
      canvas.dataset.rendererState = "fallback";
      setStatus("");
      return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    const scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xf3f1e6, 0x1b1d16, 2.4));
    const keyLight = new THREE.DirectionalLight(0xffffff, 1.5);
    keyLight.position.set(1, 2, 1.5);
    scene.add(keyLight);

    const camera = new THREE.PerspectiveCamera(60, 1, 0.01, 100_000);
    const controls = new OrbitControls(camera, canvas);
    controls.enableDamping = true;
    controls.autoRotate = true;
    controls.autoRotateSpeed = 0.35;

    let points: THREE.Points | undefined;
    let model: THREE.InstancedMesh | undefined;
    let modelReady = false;
    let disposed = false;
    let frame = 0;
    let labelAnchors: readonly RegionLabel[] = [];

    const applyView = () => {
      const next = viewRef.current;
      if (points) points.visible = next === "points" || !modelReady;
      if (model) model.visible = next === "model" && modelReady;
      labelsHost.style.opacity = next === "model" && modelReady ? "1" : "0";
    };
    apiRef.current = {
      setView: (next) => {
        viewRef.current = next;
        applyView();
      },
    };

    const resize = () => {
      const bounds = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(bounds.width));
      const height = Math.max(1, Math.round(bounds.height));
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    };

    const projected = new THREE.Vector3();
    const positionLabels = () => {
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const spans = labelsHost.children;
      for (let i = 0; i < labelAnchors.length; i += 1) {
        const span = spans[i] as HTMLElement | undefined;
        if (!span) continue;
        const anchor = labelAnchors[i];
        projected.set(anchor.position[0], anchor.position[1], anchor.position[2]).project(camera);
        const inFront = projected.z < 1;
        span.style.opacity = inFront ? "1" : "0";
        span.style.transform = `translate(-50%, -50%) translate(${
          (projected.x * 0.5 + 0.5) * width
        }px, ${(-projected.y * 0.5 + 0.5) * height}px)`;
      }
    };

    new PLYLoader().load(
      SOURCE,
      (geometry) => {
        if (disposed) return;
        geometry.computeBoundingBox();
        const center = new THREE.Vector3();
        geometry.boundingBox?.getCenter(center);
        geometry.translate(-center.x, -center.y, -center.z);
        geometry.computeBoundingSphere();
        const radius = geometry.boundingSphere?.radius ?? 1;

        points = new THREE.Points(
          geometry,
          new THREE.PointsMaterial({ size: 1.25, sizeAttenuation: false, vertexColors: true }),
        );
        scene.add(points);

        camera.near = radius / 500;
        camera.far = radius * 40;
        camera.position.set(radius * 1.4, radius * 0.9, radius * 1.4);
        controls.target.set(0, 0, 0);
        controls.update();
        canvas.dataset.rendererState = "ready";
        applyView();
        setStatus("Building 3D model…");

        window.setTimeout(() => {
          if (disposed) return;
          const built = buildModel(geometry, VOXEL_GRID);
          model = built.mesh;
          scene.add(model);
          labelAnchors = labelVoxels(built.centers, built.voxelSize);
          modelReady = true;
          setLabels(labelAnchors);
          setStatus("");
          applyView();
        }, 30);
      },
      undefined,
      () => {
        canvas.dataset.rendererState = "fallback";
        setStatus("Point cloud unavailable");
      },
    );

    const renderLoop = () => {
      controls.update();
      renderer.render(scene, camera);
      if (viewRef.current === "model" && modelReady) positionLabels();
      frame = window.requestAnimationFrame(renderLoop);
    };
    resize();
    renderLoop();

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(canvas);
    const handleContextLost = (event: Event) => {
      event.preventDefault();
      canvas.dataset.rendererState = "fallback";
    };
    canvas.addEventListener("webglcontextlost", handleContextLost);

    return () => {
      disposed = true;
      apiRef.current = null;
      window.cancelAnimationFrame(frame);
      canvas.removeEventListener("webglcontextlost", handleContextLost);
      resizeObserver.disconnect();
      controls.dispose();
      points?.geometry.dispose();
      (points?.material as THREE.Material | undefined)?.dispose();
      model?.geometry.dispose();
      (model?.material as THREE.Material | undefined)?.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    };
  }, []);

  const changeView = (next: View) => {
    setView(next);
    apiRef.current?.setView(next);
  };

  return (
    <div className="apartment-viewer">
      <canvas ref={canvasRef} />
      <div ref={labelsHostRef} className="apartment-viewer__labels" aria-hidden="true">
        {labels.map((label) => (
          <span key={label.text} className="apartment-viewer__label">
            {label.text}
          </span>
        ))}
      </div>
      <div className="apartment-viewer__toggle">
        <button type="button" data-active={view === "points"} onClick={() => changeView("points")}>
          Point cloud
        </button>
        <button type="button" data-active={view === "model"} onClick={() => changeView("model")}>
          3D model
        </button>
      </div>
      {status ? <span className="apartment-viewer__status">{status}</span> : null}
    </div>
  );
}

function buildModel(
  geometry: THREE.BufferGeometry,
  grid: number,
): { mesh: THREE.InstancedMesh; centers: Float32Array; voxelSize: number } {
  const position = geometry.attributes.position;
  const color = geometry.attributes.color;
  const size = new THREE.Vector3();
  geometry.boundingBox?.getSize(size);
  const voxelSize = Math.max(size.x, size.y, size.z) / grid || 1;

  const cells = new Map<
    number,
    { sx: number; sy: number; sz: number; r: number; g: number; b: number; n: number }
  >();
  const offset = 4096;
  const span = 8192;
  for (let i = 0; i < position.count; i += 1) {
    const x = position.getX(i);
    const y = position.getY(i);
    const z = position.getZ(i);
    const key =
      ((Math.round(x / voxelSize) + offset) * span + (Math.round(y / voxelSize) + offset)) * span +
      (Math.round(z / voxelSize) + offset);
    let cell = cells.get(key);
    if (!cell) {
      cell = { sx: 0, sy: 0, sz: 0, r: 0, g: 0, b: 0, n: 0 };
      cells.set(key, cell);
    }
    cell.sx += x;
    cell.sy += y;
    cell.sz += z;
    cell.r += color.getX(i);
    cell.g += color.getY(i);
    cell.b += color.getZ(i);
    cell.n += 1;
  }

  const centers = new Float32Array(cells.size * 3);
  const mesh = new THREE.InstancedMesh(
    new THREE.BoxGeometry(voxelSize, voxelSize, voxelSize),
    new THREE.MeshLambertMaterial(),
    cells.size,
  );
  const dummy = new THREE.Object3D();
  const tint = new THREE.Color();
  let index = 0;
  for (const cell of cells.values()) {
    const cx = cell.sx / cell.n;
    const cy = cell.sy / cell.n;
    const cz = cell.sz / cell.n;
    centers[index * 3] = cx;
    centers[index * 3 + 1] = cy;
    centers[index * 3 + 2] = cz;
    dummy.position.set(cx, cy, cz);
    dummy.updateMatrix();
    mesh.setMatrixAt(index, dummy.matrix);
    mesh.setColorAt(index, tint.setRGB(cell.r / cell.n, cell.g / cell.n, cell.b / cell.n));
    index += 1;
  }
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  return { mesh, centers, voxelSize };
}
