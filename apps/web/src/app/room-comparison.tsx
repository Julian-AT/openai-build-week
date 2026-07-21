"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";

import { createFixedGaussianRoom } from "../lib/fixed-gaussian-room.ts";
import { createFixedRoomModel } from "../lib/fixed-room-model.ts";

const vertexShader = /* glsl */ `
  attribute float splatRadius;
  varying vec3 vColor;
  varying float vDepth;
  uniform float viewportHeight;

  void main() {
    vec4 viewPosition = modelViewMatrix * vec4(position, 1.0);
    float depth = max(0.15, -viewPosition.z);
    gl_Position = projectionMatrix * viewPosition;
    gl_PointSize = clamp(splatRadius * viewportHeight * projectionMatrix[1][1] / depth, 1.25, 30.0);
    vColor = color;
    vDepth = depth;
  }
`;

const fragmentShader = /* glsl */ `
  varying vec3 vColor;
  varying float vDepth;

  void main() {
    vec2 offset = gl_PointCoord * 2.0 - 1.0;
    if (dot(offset, offset) > 1.0) discard;
    float gaussian = exp(-4.2 * dot(offset, offset));
    float distanceFade = 1.0 - smoothstep(4.0, 9.0, vDepth) * 0.36;
    gl_FragColor = vec4(vColor, gaussian * 0.76 * distanceFade);
  }
`;

function buildPointCloud(): THREE.Points {
  const room = createFixedGaussianRoom();
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(room.positions, 3));
  geometry.setAttribute("color", new THREE.BufferAttribute(room.colors, 3));
  geometry.setAttribute("splatRadius", new THREE.BufferAttribute(room.radii, 1));
  geometry.computeBoundingSphere();
  const material = new THREE.ShaderMaterial({
    depthWrite: false,
    fragmentShader,
    transparent: true,
    uniforms: { viewportHeight: { value: 1 } },
    vertexColors: true,
    vertexShader,
  });
  return new THREE.Points(geometry, material);
}

function buildRoomModel(): THREE.Group {
  const group = new THREE.Group();
  for (const part of createFixedRoomModel().parts) {
    const mesh = new THREE.Mesh(
      new THREE.BoxGeometry(...part.size),
      new THREE.MeshLambertMaterial({ color: new THREE.Color(part.color) }),
    );
    mesh.position.set(...part.position);
    group.add(mesh);
  }
  return group;
}

export default function RoomComparison() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, canvas });
    } catch {
      canvas.dataset.rendererState = "fallback";
      return;
    }
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.setClearColor(0x10120f, 0);

    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 40);
    camera.position.set(0.05, 1.48, 3.25);
    camera.lookAt(0, 1.18, -3.5);

    const pointScene = new THREE.Scene();
    const points = buildPointCloud();
    pointScene.add(points);
    const pointMaterial = points.material as THREE.ShaderMaterial;

    const modelScene = new THREE.Scene();
    modelScene.add(buildRoomModel());
    modelScene.add(new THREE.HemisphereLight(0xf3f1e6, 0x1b1d16, 2.1));
    const keyLight = new THREE.DirectionalLight(0xffffff, 1.6);
    keyLight.position.set(2.4, 4, 3.2);
    modelScene.add(keyLight);

    const render = () => {
      const bounds = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(bounds.width));
      const height = Math.max(1, Math.round(bounds.height));
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
      renderer.setSize(width, height, false);
      renderer.setScissorTest(true);

      const sideBySide = width >= height;
      const halfW = sideBySide ? Math.round(width / 2) : width;
      const halfH = sideBySide ? height : Math.round(height / 2);
      camera.aspect = halfW / halfH;
      camera.updateProjectionMatrix();
      pointMaterial.uniforms.viewportHeight.value = halfH;

      const drawPoints = () => renderer.render(pointScene, camera);
      const drawModel = () => renderer.render(modelScene, camera);

      if (sideBySide) {
        renderer.setViewport(0, 0, halfW, height);
        renderer.setScissor(0, 0, halfW, height);
        drawPoints();
        renderer.setViewport(halfW, 0, width - halfW, height);
        renderer.setScissor(halfW, 0, width - halfW, height);
        drawModel();
      } else {
        renderer.setViewport(0, halfH, width, height - halfH);
        renderer.setScissor(0, halfH, width, height - halfH);
        drawPoints();
        renderer.setViewport(0, 0, width, halfH);
        renderer.setScissor(0, 0, width, halfH);
        drawModel();
      }
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
      renderer.dispose();
      renderer.forceContextLoss();
    };
  }, []);

  return (
    <div className="room-comparison" aria-hidden="true">
      <canvas ref={canvasRef} />
      <span className="room-comparison__label room-comparison__label--points">point cloud</span>
      <span className="room-comparison__label room-comparison__label--model">3d model</span>
      <div className="room-comparison__divider" />
    </div>
  );
}
