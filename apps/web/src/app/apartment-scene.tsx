"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { PLYLoader } from "three/examples/jsm/loaders/PLYLoader.js";

import { labelVoxels, type RegionLabel } from "../lib/apartment-analysis.ts";
import { reconstructSurface } from "../lib/apartment-surface.ts";

const SOURCE = "/apartment.ply";
const SURFACE_RES = 190;
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
    let model: THREE.Mesh | undefined;
    let modelMaterial: THREE.MeshStandardMaterial | undefined;
    let modelReady = false;
    let disposed = false;
    let frame = 0;
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
        });
        points = new THREE.Points(geometry, pointsMaterial);
        scene.add(points);

        camera.near = radius / 500;
        camera.far = radius * 40;
        camera.position.set(radius * 1.6, radius * 1.05, radius * 1.6);
        controls.target.set(0, 0, 0);
        controls.update();
        canvas.dataset.rendererState = "ready";
        setStatus("Building 3D model…");

        window.setTimeout(() => {
          if (disposed || !points) return;
          const built = buildSurface(geometry, SURFACE_RES);
          model = built.mesh;
          modelMaterial = model.material as THREE.MeshStandardMaterial;
          modelMaterial.transparent = true;
          modelMaterial.opacity = 0;

          const result = labelVoxels(built.centers, built.cellSize);
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
      modelOpacity += ((showModel ? 1 : 0) - modelOpacity) * 0.16;
      // The point cloud stays opaque and crisp; only the model fades in over it.
      if (points) points.visible = !showModel || modelOpacity < 0.92;
      if (model && modelMaterial) {
        modelMaterial.opacity = modelOpacity;
        model.visible = modelOpacity > 0.03;
      }
      labelsHost.style.opacity = String(Math.max(0, (modelOpacity - 0.25) / 0.75));
      renderer.render(scene, camera);
      if (modelReady && modelOpacity > 0.25) positionLabels();
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

function buildSurface(
  geometry: THREE.BufferGeometry,
  resolution: number,
): { mesh: THREE.Mesh; centers: Float32Array; cellSize: number } {
  const positions = geometry.attributes.position.array as Float32Array;
  const surface = reconstructSurface(positions, resolution);

  const meshGeometry = new THREE.BufferGeometry();
  meshGeometry.setAttribute("position", new THREE.BufferAttribute(surface.positions, 3));
  meshGeometry.setIndex(new THREE.BufferAttribute(surface.indices, 1));
  meshGeometry.computeVertexNormals();

  const material = new THREE.MeshStandardMaterial({
    color: 0xd8d3c6,
    roughness: 0.92,
    metalness: 0,
    side: THREE.DoubleSide,
  });
  return {
    mesh: new THREE.Mesh(meshGeometry, material),
    centers: surface.centers,
    cellSize: surface.cellSize,
  };
}
