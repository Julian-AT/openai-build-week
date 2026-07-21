"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { PLYLoader } from "three/examples/jsm/loaders/PLYLoader.js";

import { labelVoxels, type RegionLabel } from "../lib/apartment-analysis.ts";

const SOURCE = "/apartment.ply";
const VOXEL_GRID = 150;
const LABEL_GAP = 26;

type View = "points" | "model";

export default function ApartmentScene() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const labelsHostRef = useRef<HTMLDivElement>(null);
  const [view, setView] = useState<View>("model");
  const [status, setStatus] = useState("Loading point cloud…");
  const [labels, setLabels] = useState<readonly RegionLabel[]>([]);

  const viewRef = useRef<View>(view);
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

    const camera = new THREE.PerspectiveCamera(58, 1, 0.01, 100_000);
    const controls = new OrbitControls(camera, canvas);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.autoRotate = true;
    controls.autoRotateSpeed = 0.28;

    const contentQuat = new THREE.Quaternion();
    let points: THREE.Points | undefined;
    let pointsMaterial: THREE.PointsMaterial | undefined;
    let model: THREE.InstancedMesh | undefined;
    let modelMaterial: THREE.MeshLambertMaterial | undefined;
    let modelReady = false;
    let disposed = false;
    let frame = 0;
    let pointsOpacity = 1;
    let modelOpacity = 0;
    let anchors: readonly RegionLabel[] = [];

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
      const placed: { span: HTMLElement; x: number; y: number }[] = [];
      for (let i = 0; i < anchors.length; i += 1) {
        const span = spans[i] as HTMLElement | undefined;
        if (!span) continue;
        projected
          .set(anchors[i].position[0], anchors[i].position[1], anchors[i].position[2])
          .applyQuaternion(contentQuat)
          .project(camera);
        if (projected.z >= 1) {
          span.style.opacity = "0";
          continue;
        }
        span.style.opacity = "1";
        placed.push({
          span,
          x: (projected.x * 0.5 + 0.5) * width,
          y: (-projected.y * 0.5 + 0.5) * height,
        });
      }
      placed.sort((a, b) => a.y - b.y);
      for (let i = 1; i < placed.length; i += 1) {
        const previous = placed[i - 1] as { y: number };
        if (placed[i].y < previous.y + LABEL_GAP) placed[i].y = previous.y + LABEL_GAP;
      }
      for (const item of placed) {
        item.span.style.transform = `translate(-50%, -50%) translate(${item.x}px, ${item.y}px)`;
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

        pointsMaterial = new THREE.PointsMaterial({
          size: 1.5,
          sizeAttenuation: false,
          vertexColors: true,
          transparent: true,
        });
        points = new THREE.Points(geometry, pointsMaterial);
        scene.add(points);

        camera.near = radius / 500;
        camera.far = radius * 40;
        camera.position.set(radius * 1.3, radius * 0.85, radius * 1.3);
        controls.target.set(0, 0, 0);
        controls.update();
        canvas.dataset.rendererState = "ready";
        setStatus("Building 3D model…");

        window.setTimeout(() => {
          if (disposed || !points) return;
          const built = buildModel(geometry, VOXEL_GRID);
          model = built.mesh;
          modelMaterial = model.material as THREE.MeshLambertMaterial;
          modelMaterial.transparent = true;
          modelMaterial.opacity = 0;

          const result = labelVoxels(built.centers, built.voxelSize);
          anchors = result.labels;
          if (result.up) {
            contentQuat.setFromUnitVectors(
              new THREE.Vector3(result.up[0], result.up[1], result.up[2]).normalize(),
              new THREE.Vector3(0, 1, 0),
            );
          }
          points.quaternion.copy(contentQuat);
          model.quaternion.copy(contentQuat);
          scene.add(model);
          modelReady = true;
          setLabels(anchors);
          setStatus("");
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
      const showModel = viewRef.current === "model" && modelReady;
      pointsOpacity += ((showModel ? 0 : 1) - pointsOpacity) * 0.16;
      modelOpacity += ((showModel ? 1 : 0) - modelOpacity) * 0.16;
      if (points && pointsMaterial) {
        pointsMaterial.opacity = pointsOpacity;
        points.visible = pointsOpacity > 0.02;
      }
      if (model && modelMaterial) {
        modelMaterial.opacity = modelOpacity;
        model.visible = modelOpacity > 0.02;
      }
      labelsHost.style.opacity = String(modelOpacity);
      renderer.render(scene, camera);
      if (modelReady && modelOpacity > 0.02) positionLabels();
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
      window.cancelAnimationFrame(frame);
      canvas.removeEventListener("webglcontextlost", handleContextLost);
      resizeObserver.disconnect();
      controls.dispose();
      points?.geometry.dispose();
      pointsMaterial?.dispose();
      model?.geometry.dispose();
      modelMaterial?.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    };
  }, []);

  const changeView = (next: View) => {
    setView(next);
    viewRef.current = next;
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
