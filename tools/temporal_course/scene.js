"use strict";

// Isolated source fixture. Production shaders and the original course stay intact.
const query = new URLSearchParams(location.search);
const runId = query.get("run") || "temporal";
const sourceTimes = window.TEMPORAL_CONFIG.sourceTimes;
const sourceRate = window.TEMPORAL_CONFIG.sourceFps;
let command = {frame: 0, token: 0, mode: 0};
let announced = -1;
let pending = false;
const cells = [];
for (let i = 0; i < 64; i++) {
  const cell = document.createElement("span");
  document.getElementById("frame-code").append(cell);
  cells.push(cell);
}
function report(stage, extra = {}) {
  navigator.sendBeacon("/report", new Blob([JSON.stringify({run:runId,stage,...extra})],
    {type:"application/json"}));
}
function paint(frame, token) {
  const payload = (frame | (token << 12) | (((frame ^ token ^ 0xa5) & 255) << 24)) >>> 0;
  for (let i = 0; i < 32; i++) {
    const bit = (payload >>> i) & 1;
    cells[2*i].style.backgroundColor = bit ? "#fff" : "#000";
    cells[2*i+1].style.backgroundColor = bit ? "#000" : "#fff";
  }
}
async function poll() {
  try {
    const next = await (await fetch(`/control?run=${encodeURIComponent(runId)}`,{cache:"no-store"})).json();
    if (!Number.isInteger(next.frame) || next.frame < 0 || next.frame >= sourceTimes.length ||
        !Number.isInteger(next.token) || ![0,1].includes(next.mode || 0)) throw Error("Bad source command");
    command = {frame:next.frame,token:next.token,mode:next.mode || 0};
    setTimeout(poll,20);
  } catch (error) {report("error",{message:String(error)});}
}

BABYLON.ShaderStore.ShadersStoreWGSL.temporalVertexShader = `
attribute position : vec3<f32>;
attribute uv : vec2<f32>;
uniform worldViewProjection : mat4x4<f32>;
varying vUV : vec2<f32>;
@vertex fn main(input : VertexInputs) -> FragmentInputs {
  vertexOutputs.position = uniforms.worldViewProjection * vec4<f32>(vertexInputs.position,1.0);
  vertexOutputs.vUV = vertexInputs.uv;
}`;
BABYLON.ShaderStore.ShadersStoreWGSL.temporalFragmentShader = `
varying vUV : vec2<f32>;
var materialTextureSampler : sampler;
var materialTexture : texture_2d<f32>;
uniform settings : vec4<f32>;
@fragment fn main(input : FragmentInputs) -> FragmentOutputs {
  let source = textureSample(materialTexture,materialTextureSampler,fragmentInputs.vUV).rgb;
  let linear = select(pow((source+vec3<f32>(0.055))/1.055,vec3<f32>(2.4)),source/12.92,source<=vec3<f32>(0.04045));
  let lit = max(linear*uniforms.settings.z,vec3<f32>(0.0));
  let encoded = select(1.055*pow(lit,vec3<f32>(1.0/2.4))-vec3<f32>(0.055),12.92*lit,lit<=vec3<f32>(0.0031308));
  let identity = vec3<f32>(uniforms.settings.y,0.0,0.0);
  fragmentOutputs.color = vec4<f32>(mix(encoded,identity,uniforms.settings.x),1.0);
}`;

async function start() {
  if (!navigator.gpu) throw Error("WebGPU unavailable; no fallback");
  const canvas = document.getElementById("view");
  const engine = new BABYLON.WebGPUEngine(canvas,{antialias:false,canvasColorSpace:"srgb",canvasToneMapping:{mode:"standard"}});
  await engine.initAsync();
  engine.setHardwareScalingLevel(1);
  const scene = new BABYLON.Scene(engine);
  scene.clearColor = new BABYLON.Color4(0,0,0,1);
  const camera = new BABYLON.UniversalCamera("camera",new BABYLON.Vector3(0,0,-8),scene);
  camera.fov = 0.65;
  camera.minZ = 0.05;
  scene.activeCamera = camera;
  const objects = [];
  function plane(id,name,asset,width,height,x,y,z,rx=0,ry=0) {
    const mesh = BABYLON.MeshBuilder.CreatePlane(name,{width,height,sideOrientation:BABYLON.Mesh.DOUBLESIDE},scene);
    mesh.position.set(x,y,z);mesh.rotation.set(rx,ry,0);
    const material = new BABYLON.ShaderMaterial(name+"-material",scene,
      {vertex:"temporal",fragment:"temporal"},
      {attributes:["position","uv"],uniforms:["worldViewProjection","settings"],samplers:["materialTexture"],shaderLanguage:BABYLON.ShaderLanguage.WGSL});
    const texture = new BABYLON.Texture(`/assets/${asset}.png`,scene,true,true,BABYLON.Texture.BILINEAR_SAMPLINGMODE);
    texture.gammaSpace = false;
    material.setTexture("materialTexture",texture);
    material.setVector4("settings",new BABYLON.Vector4(0,id*16/255,1,0));
    material.backFaceCulling = false;
    mesh.material = material;
    objects.push({id,name,mesh,material,width,height,asset});
    return mesh;
  }
  plane(1,"timber","timber",5.3,4,-2.6,0,3.5,0,.12);
  plane(2,"metal","metal",5.3,4,2.6,0,5,0,-.18);
  plane(3,"floor","cloth",14,10,0,-2.05,5,Math.PI/2,0);
  const occluder = plane(4,"occluder","cloth",1.35,2.5,0,-.15,.5);
  plane(5,"thin-light","light",.025,2.8,1.3,0,1.2);
  plane(6,"black","black",.65,.5,-3.2,1.25,1);
  plane(7,"near-black","near_black",.65,.5,-3.2,.6,1);
  plane(8,"code-eight","code_eight",.65,.5,-3.2,-.05,1);
  await scene.whenReadyAsync();
  await Promise.all(objects.map(o=>o.material.forceCompilationAsync(o.mesh)));
  function state(frame,mode) {
    const sourceTimeSeconds = sourceTimes[frame];
    const index = sourceTimeSeconds*30;
    let phase = "stationary";
    let cx = 0,cy = 0,cz = -8;
    if (index>=16) {
      phase = index<48 ? "camera_motion" : index<64 ? "occlusion" : index<80 ? "lighting" : "cut";
      const t=(Math.min(index,79)-16)/30;
      cx=.45*Math.sin(t*1.8);cy=.12*Math.sin(t*2.1);cz=-8+.3*Math.sin(t);
    }
    if (index>=80) {cx=-.9;cy=.2;cz=-6.7;}
    camera.position.set(cx,cy,cz);
    camera.setTarget(new BABYLON.Vector3(cx*.15,cy*.1,4));
    occluder.position.x=index<48 ? -.9 : -.9+1.8*Math.sin((index-48)/16*Math.PI/2);
    const lighting=index>=64&&index<80 ? Math.pow(2,(index-64)/15*.35) : 1;
    for (const o of objects) o.material.setVector4("settings",new BABYLON.Vector4(mode,o.id*16/255,o.id<5?lighting:1,0));
    return {phase,lighting,cameraPosition:[cx,cy,cz],sourceTimeSeconds,sourceFps:sourceRate};
  }
  function metadata(frame,mode,base) {
    const viewport=camera.viewport.toGlobal(engine.getRenderWidth(),engine.getRenderHeight());
    const records=objects.map(o=> {
      const corners=[[-o.width/2,o.height/2], [o.width/2,o.height/2], [o.width/2,-o.height/2], [-o.width/2,-o.height/2]];
      const projected=corners.map(([x,y])=> {
        const p=BABYLON.Vector3.Project(new BABYLON.Vector3(x,y,0),o.mesh.getWorldMatrix(),scene.getTransformMatrix(),viewport);
        return [p.x,p.y,p.z];
      });
      return {id:o.id,name:o.name,asset:o.asset,world:Array.from(o.mesh.getWorldMatrix().m),corners:projected};
    });
    return {frame,mode,...base,viewProjection:Array.from(scene.getTransformMatrix().m),objects:records};
  }
  report("ready",{width:engine.getRenderWidth(),height:engine.getRenderHeight(),fixture:"temporal-v1"});
  poll();
  engine.runRenderLoop(()=> {
    const {frame,token,mode}=command;
    const base=state(frame,mode);
    scene.render();
    if (token!==announced&&!pending) {
      pending=true;
      const pose=metadata(frame,mode,base);
      engine._device.queue.onSubmittedWorkDone().then(()=>requestAnimationFrame(()=>requestAnimationFrame(()=> {
        if (command.token===token) {paint(frame,token);announced=token;report("pose",{frame,token,pose});}
        pending=false;
      }))).catch(error=>report("error",{message:String(error)}));
    }
  });
}
start().catch(error=>report("error",{message:String(error.stack || error)}));
