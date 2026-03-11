import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";

const TITLE_WORDS = ["PROOF", "OF", "NET", "ECONOMIC", "CONTRIBUTION"];
const SUBTITLE = "Decentralized Behavioral Mining Protocol";

const VERT = `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

const FRAG = `
uniform sampler2D uColorMap;
uniform sampler2D uDepthMap;
uniform vec2 uPointer;
uniform float uProgress;
varying vec2 vUv;

vec3 blendScreen(vec3 base, vec3 blend) {
  return 1.0 - (1.0 - base) * (1.0 - blend);
}

float hash(float n) { return fract(sin(n) * 43758.5453123); }

void main() {
  float strength = 0.012;
  vec4 depth = texture2D(uDepthMap, vUv);

  // Mouse parallax via depth
  vec2 offset = depth.r * uPointer * strength;
  vec4 color = texture2D(uColorMap, vUv + offset);

  // Tiled dot-matrix overlay
  vec2 tiling = vec2(120.0);
  vec2 tiledUv = mod(vUv * tiling, 2.0) - 1.0;
  float dist = length(tiledUv);
  float cellId = floor(vUv.x * tiling.x) + floor(vUv.y * tiling.y) * tiling.x;
  float brightness = hash(cellId);
  float dotVal = smoothstep(0.5, 0.49, dist) * brightness;

  // Scan-line flow mask — only fires where depth map has content (depth.r > 0.05)
  // This prevents the dot grid from lighting up on flat black background areas
  float flow = 1.0 - smoothstep(0.0, 0.025, abs(depth.r - uProgress));
  float depthPresence = smoothstep(0.05, 0.2, depth.r); // fade out in empty areas
  vec3 scanMask = dotVal * flow * depthPresence * vec3(12.0, 0.0, 0.0);

  // Blend screen combine
  vec3 final = blendScreen(color.rgb, scanMask);

  gl_FragColor = vec4(final, 1.0);
}
`;

export function FuturisticHero() {
  const mountRef = useRef<HTMLDivElement>(null);
  const [visibleWords, setVisibleWords] = useState(0);
  const [subtitleVisible, setSubtitleVisible] = useState(false);

  // Word-by-word title reveal
  useEffect(() => {
    if (visibleWords < TITLE_WORDS.length) {
      const t = setTimeout(() => setVisibleWords((v) => v + 1), 550);
      return () => clearTimeout(t);
    } else {
      const t = setTimeout(() => setSubtitleVisible(true), 700);
      return () => clearTimeout(t);
    }
  }, [visibleWords]);

  // Three.js canvas
  useEffect(() => {
    const el = mountRef.current;
    if (!el) return;

    const scene = new THREE.Scene();

    // Account for viewport aspect ratio so the square plane renders undistorted
    const aspect = el.clientWidth / el.clientHeight;
    const camera = new THREE.OrthographicCamera(
      -aspect * 0.5, aspect * 0.5,
       0.5, -0.5,
       0, 10
    );
    camera.position.z = 1;

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setSize(el.clientWidth, el.clientHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    el.appendChild(renderer.domElement);

    // Postprocessing
    const composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    const bloomPass = new UnrealBloomPass(
      new THREE.Vector2(el.clientWidth, el.clientHeight),
      0.8, // strength
      0.5, // radius
      0.85 // threshold
    );
    composer.addPass(bloomPass);

    // Uniforms
    const uniforms = {
      uColorMap: { value: null as THREE.Texture | null },
      uDepthMap: { value: null as THREE.Texture | null },
      uPointer: { value: new THREE.Vector2(0, 0) },
      uProgress: { value: 0.0 },
    };

    // Load textures
    const loader = new THREE.TextureLoader();
    Promise.all([
      loader.loadAsync("https://i.postimg.cc/XYwvXN8D/img-4.png"),
      loader.loadAsync("https://i.postimg.cc/2SHKQh2q/raw-4.webp"),
    ]).then(([colorTex, depthTex]) => {
      uniforms.uColorMap.value = colorTex;
      uniforms.uDepthMap.value = depthTex;
    });

    // Plane geometry — SQUARE matches the square texture (300x300)
    // Camera is aspect-corrected so this renders as a true square on any screen
    // scaleFactor 0.65 = 65% of viewport height → prominent but not full-bleed
    const scaleFactor = 0.65;
    const geo = new THREE.PlaneGeometry(scaleFactor, scaleFactor);
    const mat = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms,
      transparent: false,
    });
    const mesh = new THREE.Mesh(geo, mat);
    scene.add(mesh);

    // Animate
    let animId: number;
    const clock = new THREE.Clock();

    function animate() {
      animId = requestAnimationFrame(animate);
      const t = clock.getElapsedTime();
      uniforms.uProgress.value = Math.sin(t * 0.5) * 0.5 + 0.5;
      composer.render();
    }
    animate();

    // Mouse pointer
    const onMouse = (e: MouseEvent) => {
      uniforms.uPointer.value.set(
        (e.clientX / window.innerWidth - 0.5) * 2,
        -(e.clientY / window.innerHeight - 0.5) * 2
      );
    };
    window.addEventListener("mousemove", onMouse);

    // Resize — update camera aspect ratio too
    const onResize = () => {
      const nw = el.clientWidth;
      const nh = el.clientHeight;
      const newAspect = nw / nh;
      camera.left   = -newAspect * 0.5;
      camera.right  =  newAspect * 0.5;
      camera.updateProjectionMatrix();
      renderer.setSize(nw, nh);
      composer.setSize(nw, nh);
      bloomPass.setSize(nw, nh);
    };
    window.addEventListener("resize", onResize);

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener("mousemove", onMouse);
      window.removeEventListener("resize", onResize);
      renderer.dispose();
      if (el.contains(renderer.domElement)) el.removeChild(renderer.domElement);
    };
  }, []);

  return (
    <div className="relative h-screen overflow-hidden bg-[#0C0C0E]">
      {/* Three.js canvas fills entire viewport */}
      <div ref={mountRef} className="absolute inset-0" />

      {/* Text overlay — centered */}
      <div className="absolute inset-0 z-50 flex flex-col items-center justify-center pointer-events-none px-8">
        <div className="flex flex-wrap justify-center gap-x-3 gap-y-1 text-2xl sm:text-4xl md:text-5xl xl:text-6xl 2xl:text-7xl font-display font-extrabold text-white uppercase">
          {TITLE_WORDS.map((word, i) => (
            <span
              key={i}
              className={i < visibleWords ? "word-reveal" : "opacity-0"}
              style={{ animationDelay: `${i * 0.13}s` }}
            >
              {word}
            </span>
          ))}
        </div>
        <div
          className={`mt-2 text-xs sm:text-sm md:text-xl xl:text-2xl font-semibold text-white/80 tracking-widest uppercase transition-opacity duration-700 ${
            subtitleVisible ? "opacity-100" : "opacity-0"
          }`}
        >
          {SUBTITLE}
        </div>
      </div>

      {/* Scroll CTA */}
      <div className="scroll-btn">
        <span>Scroll to explore</span>
        <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
          <path
            d="M11 5V17"
            stroke="white"
            strokeWidth="2"
            strokeLinecap="round"
          />
          <path
            d="M6 12L11 17L16 12"
            stroke="white"
            strokeWidth="2"
            strokeLinecap="round"
          />
        </svg>
      </div>
    </div>
  );
}
