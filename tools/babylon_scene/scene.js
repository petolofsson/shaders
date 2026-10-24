"use strict";

// All scene positions, colors, camera poses, and cut frames are deterministic.
// The only live input is elapsed time in play mode. ?frame=N holds an exact pose.
const params = new URLSearchParams(location.search);
const runId = params.get("run") || "manual";
const heldFrame = params.has("frame") ? Math.max(0, Math.min(2639, Number(params.get("frame")) | 0)) : null;
const stopFrame = params.has("stop") ? Math.max(0, Math.min(2639, Number(params.get("stop")) | 0)) : null;
const density = Math.max(0.25, Math.min(2, Number(params.get("density") || 1)));
const FRAMES_PER_SECOND = 60;
const LOOP_FRAMES = 2640;
const CUT_TO_NIGHT = 1440;
const CUT_TO_FOREST = 2160;
const status = document.getElementById("status");
const controlled = params.has("controlled");
let commandedFrame = heldFrame === null ? 0 : heldFrame;
let commandedToken = 0;
let poseAnnouncement = false;
let announcedToken = -1;
let codeCells = [];
if (controlled) {
  status.style.display = "none";
  const strip = document.createElement("div");
  strip.id = "frame-code";
  for (let i = 0; i < 64; i++) {
    const cell = document.createElement("span");
    strip.append(cell);
    codeCells.push(cell);
  }
  document.body.append(strip);
}

function paintFrameCode(frame, token) {
  const checksum = (frame ^ token ^ 0xa5) & 255;
  const payload = (frame | (token << 12) | (checksum << 24)) >>> 0;
  for (let i = 0; i < 32; i++) {
    const bit = (payload >>> i) & 1;
    codeCells[i * 2].style.backgroundColor = bit ? "#fff" : "#000";
    codeCells[i * 2 + 1].style.backgroundColor = bit ? "#000" : "#fff";
  }
}

async function pollControl() {
  if (!controlled) return;
  try {
    const response = await fetch(`/control?run=${encodeURIComponent(runId)}`, { cache: "no-store" });
    const next = await response.json();
    if (!Number.isInteger(next.frame) || next.frame < 0 || next.frame >= LOOP_FRAMES ||
        !Number.isInteger(next.token) || next.token < 0 || next.token > 4095) {
      throw new Error("Invalid controlled pose");
    }
    commandedFrame = next.frame;
    commandedToken = next.token;
  } catch (error) {
    report("error", { message: String(error) });
    return;
  }
  setTimeout(pollControl, 30);
}

function report(stage, extra = {}) {
  const body = { run: runId, stage, time: Date.now(), ...extra };
  navigator.sendBeacon("/report", new Blob([JSON.stringify(body)], { type: "application/json" }));
}

function randomFactory(seed) {
  let state = seed >>> 0;
  return () => {
    state += 0x6D2B79F5;
    let n = state;
    n = Math.imul(n ^ (n >>> 15), n | 1);
    n ^= n + Math.imul(n ^ (n >>> 7), n | 61);
    return ((n ^ (n >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = randomFactory(0x47A1026);
const v3 = (x, y, z) => new BABYLON.Vector3(x, y, z);

function mat(scene, name, hex, options = {}) {
  const material = new BABYLON.StandardMaterial(name, scene);
  material.diffuseColor = BABYLON.Color3.FromHexString(hex);
  material.specularColor = BABYLON.Color3.FromHexString(options.specular || "#161b1f");
  if (options.emissive) material.emissiveColor = BABYLON.Color3.FromHexString(options.emissive);
  return material;
}

function makeGroundTexture(scene) {
  const texture = new BABYLON.DynamicTexture("groundTexture", { width: 512, height: 512 }, scene, false);
  const ctx = texture.getContext();
  ctx.fillStyle = "#4a5a3c";
  ctx.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 17000; i++) {
    const x = rand() * 512, y = rand() * 512;
    const green = 46 + (rand() * 60 | 0);
    ctx.fillStyle = `rgba(${29 + (rand() * 24 | 0)},${green},${20 + (rand() * 24 | 0)},${0.12 + rand() * 0.36})`;
    ctx.fillRect(x, y, 1 + rand() * 5, 1 + rand() * 4);
  }
  texture.update();
  texture.uScale = 14;
  texture.vScale = 14;
  return texture;
}

function makeLeafTexture(scene) {
  const texture = new BABYLON.DynamicTexture("leafTexture", { width: 128, height: 128 }, scene, false);
  const ctx = texture.getContext();
  ctx.clearRect(0, 0, 128, 128);
  for (let i = 0; i < 42; i++) {
    const x = 10 + rand() * 108, y = 9 + rand() * 110;
    const radius = 5 + rand() * 12;
    ctx.fillStyle = `rgba(${35 + (rand() * 30 | 0)},${80 + (rand() * 70 | 0)},${18 + (rand() * 35 | 0)},${0.65 + rand() * 0.35})`;
    ctx.beginPath();
    ctx.ellipse(x, y, radius * 0.55, radius, rand() * Math.PI, 0, Math.PI * 2);
    ctx.fill();
  }
  texture.hasAlpha = true;
  texture.update();
  return texture;
}

function addTreeInstances(scene, sunShadow, count) {
  const trunk = BABYLON.MeshBuilder.CreateCylinder("trunks", { height: 2, diameterTop: 0.32, diameterBottom: 0.52, tessellation: 7 }, scene);
  trunk.material = mat(scene, "bark", "#594733");
  const canopyColors = ["#3a582b", "#4d702f", "#627f38"];
  const canopies = canopyColors.map((color, i) => {
    const mesh = BABYLON.MeshBuilder.CreateIcoSphere(`canopy-${i}`, { radius: 1, subdivisions: 1 }, scene);
    mesh.material = mat(scene, `leaves-${i}`, color);
    return mesh;
  });
  const cards = BABYLON.MeshBuilder.CreatePlane("leafCards", { size: 2.3, sideOrientation: BABYLON.Mesh.DOUBLESIDE }, scene);
  const cardMat = mat(scene, "leafCardMaterial", "#729550");
  cardMat.diffuseTexture = makeLeafTexture(scene);
  cardMat.useAlphaFromDiffuseTexture = true;
  cardMat.transparencyMode = BABYLON.Material.MATERIAL_ALPHATEST;
  cardMat.alphaCutOff = 0.45;
  cardMat.backFaceCulling = false;
  cards.material = cardMat;

  const makeMatrix = (sx, sy, sz, yaw, x, y, z) => BABYLON.Matrix.Compose(
    v3(sx, sy, sz), BABYLON.Quaternion.FromEulerAngles(0, yaw, 0), v3(x, y, z));
  for (let i = 0; i < count; i++) {
    const z = -42 + rand() * 66;
    const side = rand() < 0.5 ? -1 : 1;
    const x = side * (4.2 + rand() * 24);
    const h = 3.3 + rand() * 4.0;
    const crown = 1.2 + rand() * 1.25;
    const yaw = rand() * Math.PI * 2;
    trunk.thinInstanceAdd(makeMatrix(1, h / 2, 1, yaw, x, h / 2, z));
    const crownY = h + crown * 0.38;
    canopies[i % 3].thinInstanceAdd(makeMatrix(crown, crown * 1.12, crown, yaw, x, crownY, z));
    cards.thinInstanceAdd(makeMatrix(crown * 1.1, crown * 1.2, 1, yaw, x, crownY, z));
    cards.thinInstanceAdd(makeMatrix(crown * 1.1, crown * 1.2, 1, yaw + Math.PI / 2, x, crownY, z));
  }
  sunShadow.addShadowCaster(trunk);
  for (const canopy of canopies) sunShadow.addShadowCaster(canopy);
}

function addForestDetails(scene) {
  const rock = BABYLON.MeshBuilder.CreateIcoSphere("rock-source", { radius: 1, subdivisions: 1 }, scene);
  rock.material = mat(scene, "rock", "#73736b");
  for (let i = 0; i < 65; i++) {
    const z = -39 + rand() * 75;
    const x = (rand() < 0.5 ? -1 : 1) * (2.3 + rand() * 21);
    const s = 0.25 + rand() * 1.65;
    rock.thinInstanceAdd(BABYLON.Matrix.Compose(v3(s, s * 0.58, s * 1.2),
      BABYLON.Quaternion.FromEulerAngles(0, rand() * 6.28, 0), v3(x, s * 0.25, z)));
  }
  const path = BABYLON.MeshBuilder.CreateGround("dirtPath", { width: 5.0, height: 78 }, scene);
  path.position.z = -8;
  path.position.y = 0.018;
  path.material = mat(scene, "dirt", "#776e51");
  path.receiveShadows = true;
}

function addClearing(scene) {
  const colors = ["#df3822", "#e88218", "#e8c22c", "#4eb839", "#00b9c5", "#5945d5", "#c343bc"];
  for (let i = 0; i < colors.length; i++) {
    const pillar = BABYLON.MeshBuilder.CreateBox(`color-pillar-${i}`, { width: 1.7, height: 2.5, depth: 0.55 }, scene);
    pillar.position = v3((i - 3) * 2.3, 1.3, 28);
    pillar.material = mat(scene, `pillar-mat-${i}`, colors[i], { specular: "#333333" });
  }
  const neutral = ["#050505", "#303030", "#777777", "#c8c8c8", "#ffffff"];
  for (let i = 0; i < neutral.length; i++) {
    const panel = BABYLON.MeshBuilder.CreateBox(`neutral-panel-${i}`, { width: 1.2, height: 1.5, depth: 0.25 }, scene);
    panel.position = v3((i - 2) * 1.55, 1.0, 33);
    panel.material = mat(scene, `neutral-mat-${i}`, neutral[i], { specular: "#050505" });
  }
  const whiteRock = BABYLON.MeshBuilder.CreateIcoSphere("white-rock", { radius: 2.1, subdivisions: 2 }, scene);
  whiteRock.position = v3(-10, 2.1, 19);
  whiteRock.material = mat(scene, "white-rock-mat", "#eeeeea", { specular: "#555555" });
  const orange = BABYLON.MeshBuilder.CreateSphere("orange-object", { diameter: 3.1, segments: 20 }, scene);
  orange.position = v3(10, 1.7, 17);
  orange.material = mat(scene, "orange-mat", "#e67116", { specular: "#484848" });
}

function addNightArea(scene) {
  const asphalt = BABYLON.MeshBuilder.CreateGround("night-ground", { width: 26, height: 48 }, scene);
  asphalt.position.z = 62;
  asphalt.position.y = 0.04;
  asphalt.material = mat(scene, "asphalt", "#1c232a");
  const wallMat = mat(scene, "dark-wall", "#222932");
  for (const x of [-9, 9]) {
    const wall = BABYLON.MeshBuilder.CreateBox(`night-wall-${x}`, { width: 1.3, height: 8, depth: 48 }, scene);
    wall.position = v3(x, 4, 62);
    wall.material = wallMat;
  }
  const hues = ["#ff3c1d", "#00d8ff", "#ff42c8", "#ffe840"];
  for (let i = 0; i < 12; i++) {
    const z = 45 + i * 3.2;
    const x = i % 2 ? 8.1 : -8.1;
    const color = BABYLON.Color3.FromHexString(hues[i % hues.length]);
    const tube = BABYLON.MeshBuilder.CreateBox(`neon-${i}`, { width: 0.18, height: 2.7, depth: 0.18 }, scene);
    tube.position = v3(x, 3.2, z);
    const tubeMat = new BABYLON.StandardMaterial(`neon-mat-${i}`, scene);
    tubeMat.disableLighting = true;
    tubeMat.emissiveColor = color;
    tube.material = tubeMat;
    const light = new BABYLON.PointLight(`neon-light-${i}`, v3(x * 0.8, 3.2, z), scene);
    light.diffuse = color;
    light.intensity = 2.4;
    light.range = 12;
    const pool = BABYLON.MeshBuilder.CreateDisc(`color-pool-${i}`, { radius: 1.35, tessellation: 24 }, scene);
    pool.rotation.x = Math.PI / 2;
    pool.position = v3(x * 0.7, 0.055, z);
    const poolMat = mat(scene, `color-pool-mat-${i}`, "#141b20");
    poolMat.emissiveColor = color.scale(0.17);
    pool.material = poolMat;
  }
  const blackBox = BABYLON.MeshBuilder.CreateBox("black-box", { size: 3 }, scene);
  blackBox.position = v3(-3, 1.5, 70);
  blackBox.material = mat(scene, "black-box-mat", "#030405");
  const whiteBox = BABYLON.MeshBuilder.CreateBox("white-box", { size: 3 }, scene);
  whiteBox.position = v3(3, 1.5, 70);
  whiteBox.material = mat(scene, "white-box-mat", "#f7f7f7");
}

function installPatches() {
  const colors = ["#000000", "#202020", "#808080", "#e0e0e0", "#ffffff",
    "#ff0000", "#ffa500", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff"];
  const holder = document.getElementById("patches");
  for (const color of colors) {
    const patch = document.createElement("span");
    patch.style.backgroundColor = color;
    holder.append(patch);
  }
}

function stageOf(frame) {
  if (frame < 720) return "forest";
  if (frame < CUT_TO_NIGHT) return "clearing";
  if (frame < CUT_TO_FOREST) return "night";
  return "return";
}

function setPose(frame, camera, sun, ambient, scene) {
  const stage = stageOf(frame);
  const phase = frame / FRAMES_PER_SECOND;
  let z;
  if (stage === "forest") z = -37 + frame / 720 * 28;
  else if (stage === "clearing") z = -9 + (frame - 720) / 720 * 34;
  else if (stage === "night") z = 43 + (frame - CUT_TO_NIGHT) / 720 * 30;
  else z = -33 + (frame - CUT_TO_FOREST) / 480 * 22;
  const night = stage === "night";
  const x = night ? 1.2 * Math.sin(phase * 0.45) : 1.3 * Math.sin(phase * 0.28);
  const y = 2.0 + 0.06 * Math.sin(phase * 7.0);
  camera.position = v3(x, y, z);
  camera.setTarget(v3(x + 0.4 * Math.sin(phase * 0.38), 2.15, z + 11));
  sun.intensity = night ? 0.02 : 2.4;
  ambient.intensity = night ? 0.65 : 0.85;
  scene.clearColor = night ? new BABYLON.Color4(0.014, 0.018, 0.028, 1)
                           : new BABYLON.Color4(0.35, 0.55, 0.78, 1);
  scene.fogColor = night ? new BABYLON.Color3(0.014, 0.018, 0.028)
                         : new BABYLON.Color3(0.35, 0.55, 0.73);
  scene.fogDensity = night ? 0.018 : 0.003;
  return stage;
}

(async () => {
  try {
    installPatches();
    if (!navigator.gpu) throw new Error("Firefox WebGPU unavailable");
    const canvas = document.getElementById("view");
    const engine = new BABYLON.WebGPUEngine(canvas, {
      canvasColorSpace: "srgb", canvasToneMapping: { mode: "standard" }
    });
    await engine.initAsync();
    engine.setHardwareScalingLevel(1);
    const scene = new BABYLON.Scene(engine);
    scene.imageProcessingConfiguration.toneMappingEnabled = false;
    scene.imageProcessingConfiguration.exposure = 1;
    scene.imageProcessingConfiguration.contrast = 1;
    scene.fogMode = BABYLON.Scene.FOGMODE_EXP2;
    const camera = new BABYLON.UniversalCamera("scripted-camera", v3(0, 2, -37), scene);
    camera.minZ = 0.05;
    camera.maxZ = 300;
    camera.fov = 1.05;
    scene.activeCamera = camera;
    const ambient = new BABYLON.HemisphericLight("ambient", v3(0, 1, 0), scene);
    ambient.groundColor = BABYLON.Color3.FromHexString("#253326");
    const sun = new BABYLON.DirectionalLight("sun", v3(-0.55, -0.85, 0.35), scene);
    sun.position = v3(30, 60, -35);
    sun.diffuse = BABYLON.Color3.FromHexString("#fff0ce");
    const shadows = new BABYLON.ShadowGenerator(1024, sun);
    shadows.usePercentageCloserFiltering = true;
    const ground = BABYLON.MeshBuilder.CreateGround("terrain", { width: 90, height: 145 }, scene);
    ground.position.z = 24;
    const groundMat = mat(scene, "grass", "#d9dfcf");
    groundMat.diffuseTexture = makeGroundTexture(scene);
    ground.material = groundMat;
    ground.receiveShadows = true;
    addTreeInstances(scene, shadows, Math.round(150 * density));
    addForestDetails(scene);
    addClearing(scene);
    addNightArea(scene);
    await scene.whenReadyAsync();
    const started = performance.now();
    let lastFrame = -1;
    let lastStage = null;
    let lastReport = performance.now();
    report("ready", { width: engine.getRenderWidth(), height: engine.getRenderHeight(),
      density, heldFrame, stopFrame, loopFrames: LOOP_FRAMES });
    pollControl();
    engine.runRenderLoop(() => {
      const elapsedFrame = Math.floor((performance.now() - started) * FRAMES_PER_SECOND / 1000);
      const frame = controlled ? commandedFrame : heldFrame !== null ? heldFrame : stopFrame !== null ? Math.min(stopFrame, elapsedFrame)
        : elapsedFrame % LOOP_FRAMES;
      const stage = setPose(frame, camera, sun, ambient, scene);
      scene.render();
      if (controlled && announcedToken !== commandedToken && !poseAnnouncement) {
        poseAnnouncement = true;
        const token = commandedToken;
        // This pinned Babylon build exposes its WebGPU device. Wait for this
        // pose's submitted work, then give Firefox two compositing callbacks.
        engine._device.queue.onSubmittedWorkDone().then(() => {
          requestAnimationFrame(() => requestAnimationFrame(() => {
            if (token === commandedToken && frame === commandedFrame) {
              paintFrameCode(frame, token);
              announcedToken = token;
              report("pose", { frame, token, sceneStage: stage });
            }
            poseAnnouncement = false;
          }));
        }).catch(error => report("error", { message: String(error) }));
      }
      if (lastStage !== null && stage !== lastStage && (stage === "night" || stage === "return")) {
        report("cut", { frame, from: lastStage, sceneStage: stage });
      }
      if (frame !== lastFrame && frame === stopFrame) report("stopped", { frame, sceneStage: stage });
      lastFrame = frame;
      lastStage = stage;
      if (performance.now() - lastReport > 2000) {
        lastReport = performance.now();
        if (!controlled) status.textContent = `${stage} · frame ${frame} · ${Math.round(engine.getFps())} fps`;
        report("heartbeat", { frame, sceneStage: stage, fps: engine.getFps() });
      }
    });
    window.addEventListener("resize", () => engine.resize());
  } catch (error) {
    status.textContent = String(error);
    report("error", { message: String(error && error.stack || error) });
  }
})();
