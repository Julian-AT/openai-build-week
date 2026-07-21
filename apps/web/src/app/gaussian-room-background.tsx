"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";

import { createFixedGaussianRoom } from "../lib/fixed-gaussian-room.ts";

const vertexShader = /* glsl */ `
  attribute float splatRadius;
  varying vec3 vColor;
  varying float vDepth;
  uniform float viewportHeight;

  void main() {
    vec4 viewPosition = modelViewMatrix * vec4(position, 1.0);
    float depth = max(0.15, -viewPosition.z);
    gl_Position = projectionMatrix * viewPosition;
    gl_PointSize = clamp(
      splatRadius * viewportHeight * projectionMatrix[1][1] / depth,
      1.25,
      30.0
    );
    vColor = color;
    vDepth = depth;
  }
`;

const fragmentShader = /* glsl */ `
  varying vec3 vColor;
  varying float vDepth;

  void main() {
    vec2 offset = gl_PointCoord * 2.0 - 1.0;
    float distanceSquared = dot(offset, offset);
    if (distanceSquared > 1.0) discard;

    float gaussian = exp(-4.2 * distanceSquared);
    float distanceFade = 1.0 - smoothstep(4.0, 9.0, vDepth) * 0.36;
    gl_FragColor = vec4(vColor, gaussian * 0.76 * distanceFade);
  }
`;

export default function GaussianRoomBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        alpha: true,
        antialias: false,
        canvas,
        powerPreference: "high-performance",
        premultipliedAlpha: true,
      });
    } catch {
      canvas.dataset.rendererState = "fallback";
      return;
    }

    const model = createFixedGaussianRoom();
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 20);
    camera.position.set(0.05, 1.48, 3.25);
    camera.lookAt(0, 1.18, -3.5);

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(model.positions, 3));
    geometry.setAttribute("color", new THREE.BufferAttribute(model.colors, 3));
    geometry.setAttribute("splatRadius", new THREE.BufferAttribute(model.radii, 1));
    geometry.computeBoundingSphere();

    const material = new THREE.ShaderMaterial({
      blending: THREE.NormalBlending,
      depthTest: true,
      depthWrite: false,
      fragmentShader,
      transparent: true,
      uniforms: { viewportHeight: { value: 1 } },
      vertexColors: true,
      vertexShader,
    });
    const splats = new THREE.Points(geometry, material);
    splats.frustumCulled = true;
    scene.add(splats);

    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.setClearColor(0x10120f, 0);

    const render = () => {
      const bounds = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(bounds.width));
      const height = Math.max(1, Math.round(bounds.height));
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      material.uniforms.viewportHeight.value = height;
      renderer.render(scene, camera);
      canvas.dataset.rendererState = "ready";
    };

    const resizeObserver = new ResizeObserver(render);
    resizeObserver.observe(canvas);
    render();

    const handleContextLost = (event: Event) => {
      event.preventDefault();
      canvas.dataset.rendererState = "fallback";
    };
    canvas.addEventListener("webglcontextlost", handleContextLost);

    return () => {
      canvas.removeEventListener("webglcontextlost", handleContextLost);
      resizeObserver.disconnect();
      scene.remove(splats);
      geometry.dispose();
      material.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    };
  }, []);

  return (
    <div className="gaussian-room-background" aria-hidden="true">
      <canvas ref={canvasRef} />
    </div>
  );
}
