"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { PLYLoader } from "three/examples/jsm/loaders/PLYLoader.js";

const SOURCE = "/apartment.ply";

export default function ApartmentPointCloud() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [status, setStatus] = useState("Loading point cloud…");

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

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
    const camera = new THREE.PerspectiveCamera(60, 1, 0.01, 100_000);
    const controls = new OrbitControls(camera, canvas);
    controls.enableDamping = true;
    controls.autoRotate = true;
    controls.autoRotateSpeed = 0.4;

    let points: THREE.Points | undefined;
    let disposed = false;
    let frame = 0;

    const resize = () => {
      const bounds = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(bounds.width));
      const height = Math.max(1, Math.round(bounds.height));
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
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
        setStatus(`${geometry.attributes.position.count.toLocaleString()} points`);
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
      (points?.material as THREE.Material | undefined)?.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    };
  }, []);

  return (
    <div className="apartment-viewer">
      <canvas ref={canvasRef} />
      {status ? <span className="apartment-viewer__status">{status}</span> : null}
    </div>
  );
}
