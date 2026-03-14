// ============================================================
// PLANET DESTROYER: GOD OF CATASTROPHES
// Complete HTML5/Three.js Game Engine
// ============================================================
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ============================================================
// 1. CONSTANTS & ABILITY DEFINITIONS
// ============================================================
const PLANET_RADIUS = 8;
const INITIAL_CITIES = 8;
const MAX_CITIES = 50;

const ABILITIES = {
  METEOR_STRIKE:     { name: 'Meteor Strike',     icon: '\u2604', cost: 20,  cooldown: 5,   color: '#ff6611', desc: 'Hurl a meteor at the planet surface.' },
  VOLCANIC_ERUPTION: { name: 'Volcanic Eruption',  icon: '\uD83C\uDF0B', cost: 30,  cooldown: 8,   color: '#ff3300', desc: 'Trigger catastrophic volcanic activity.' },
  EARTHQUAKE:        { name: 'Earthquake',          icon: '\uD83C\uDF0A', cost: 25,  cooldown: 6,   color: '#cc9933', desc: 'Shatter tectonic plates and damage cities.' },
  CLIMATE_SHIFT:     { name: 'Climate Shift',       icon: '\uD83C\uDF21', cost: 35,  cooldown: 12,  color: '#33aaff', desc: 'Drastically alter planetary temperature.' },
  ICE_AGE:           { name: 'Ice Age',              icon: '\u2744', cost: 60,  cooldown: 25,  color: '#aaddff', desc: 'Plunge the world into glacial darkness.' },
  SOLAR_FLARE:       { name: 'Solar Flare',          icon: '\u2600', cost: 45,  cooldown: 15,  color: '#ffee33', desc: 'Unleash radiation that cripples tech.' },
  BLACK_HOLE:        { name: 'Black Hole',            icon: '\u26AB', cost: 80,  cooldown: 30,  color: '#8800ff', desc: 'Spawn a gravitational singularity.' },
  PLANET_CRACK:      { name: 'Planet Crack',          icon: '\uD83D\uDCA5', cost: 200, cooldown: 120, color: '#ff0000', desc: 'ULTIMATE \u2014 Tear the planet asunder.' }
};

const CITY_NAMES_A = ['Al','Bri','Cor','Dor','El','Far','Gor','Hal','Ir','Jer','Kal','Lor','Mor','Nor','Or','Pel','Ros','Sol','Tar','Ul','Ver','Wyr','Xan','Yor','Zan'];
const CITY_NAMES_B = ['ath','bor','dan','eth','fen','gor','hel','ian','jon','kin','lon','mir','noth','oth','por','rath','ston','than','ule','ven','woth','xia','yon','zen'];

// ============================================================
// 2. GAME STATE
// ============================================================
const state = {
  // Planet
  planetHealth: 100,
  atmosphere: 100,
  temperature: 15,
  biosphere: 75,
  tectonics: 20,
  isDestroyed: false,

  // Player
  energy: 100,
  maxEnergy: 100,
  energyRegen: 4,

  // Game
  speed: 1,
  paused: false,
  targeting: false,
  selectedAbility: null,
  cooldowns: {},      // key -> remaining seconds
  gameTime: 0,

  // Cities
  cities: [],
  expansionTimer: 0,

  // Effects
  effects: [],
};

// Initialize cooldowns
for (const key of Object.keys(ABILITIES)) state.cooldowns[key] = 0;

// ============================================================
// 3. THREE.JS SETUP
// ============================================================
const canvas = document.getElementById('game-canvas');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x050510);

const camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.1, 500);
camera.position.set(0, 8, 22);

const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.minDistance = 12;
controls.maxDistance = 50;
controls.target.set(0, 0, 0);

// Lighting
const sun = new THREE.DirectionalLight(0xfff8e0, 2.0);
sun.position.set(15, 10, 20);
sun.castShadow = false;
scene.add(sun);

const fill = new THREE.DirectionalLight(0x334466, 0.4);
fill.position.set(-10, -5, -15);
scene.add(fill);

const ambient = new THREE.AmbientLight(0x111122, 0.3);
scene.add(ambient);

// Stars
const starGeo = new THREE.BufferGeometry();
const starVerts = [];
for (let i = 0; i < 2000; i++) {
  const r = 80 + Math.random() * 120;
  const theta = Math.random() * Math.PI * 2;
  const phi = Math.acos(2 * Math.random() - 1);
  starVerts.push(Math.sin(phi) * Math.cos(theta) * r, Math.cos(phi) * r, Math.sin(phi) * Math.sin(theta) * r);
}
starGeo.setAttribute('position', new THREE.Float32BufferAttribute(starVerts, 3));
const starMat = new THREE.PointsMaterial({ color: 0xffffff, size: 0.3, sizeAttenuation: true });
scene.add(new THREE.Points(starGeo, starMat));

// ============================================================
// 4. PLANET — Procedural Sphere with Custom Shader
// ============================================================
const planetVertShader = `
varying vec3 vNormal;
varying vec3 vWorldPos;
void main() {
  vNormal = normalize(normalMatrix * normal);
  vWorldPos = (modelMatrix * vec4(position, 1.0)).xyz;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const planetFragShader = `
uniform float healthLevel;
uniform float crackCount;
uniform float noiseSeed;
uniform vec3 damageTint;

varying vec3 vNormal;
varying vec3 vWorldPos;

// Hash and noise functions
vec3 hash33(vec3 p) {
  p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
           dot(p, vec3(269.5, 183.3, 246.1)),
           dot(p, vec3(113.5, 271.9, 124.6)));
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float vnoise(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(dot(hash33(i), f),
            dot(hash33(i + vec3(1,0,0)), f - vec3(1,0,0)), u.x),
        mix(dot(hash33(i + vec3(0,1,0)), f - vec3(0,1,0)),
            dot(hash33(i + vec3(1,1,0)), f - vec3(1,1,0)), u.x), u.y),
    mix(mix(dot(hash33(i + vec3(0,0,1)), f - vec3(0,0,1)),
            dot(hash33(i + vec3(1,0,1)), f - vec3(1,0,1)), u.x),
        mix(dot(hash33(i + vec3(0,1,1)), f - vec3(0,1,1)),
            dot(hash33(i + vec3(1,1,1)), f - vec3(1,1,1)), u.x), u.y),
    u.z);
}

float fbm(vec3 p) {
  float v = 0.0, a = 0.5, s = 1.0;
  for (int i = 0; i < 5; i++) { v += a * vnoise(p * s); s *= 2.1; a *= 0.48; }
  return v;
}

void main() {
  vec3 n = normalize(vNormal);
  vec3 p = n * 2.2 + vec3(noiseSeed * 0.013, noiseSeed * 0.007, noiseSeed * 0.019);
  float h = fbm(p);
  float t = clamp((h + 1.0) * 0.5, 0.0, 1.0);
  float lat = n.y;
  float absLat = abs(lat);

  // Biome colors
  vec3 deepOcean = vec3(0.04, 0.14, 0.50);
  vec3 ocean     = vec3(0.08, 0.25, 0.65);
  vec3 shore     = vec3(0.72, 0.68, 0.45);
  vec3 grass     = vec3(0.22, 0.55, 0.18);
  vec3 forest    = vec3(0.08, 0.38, 0.10);
  vec3 desert    = vec3(0.85, 0.73, 0.38);
  vec3 mountain  = vec3(0.50, 0.45, 0.38);
  vec3 snowCap   = vec3(0.90, 0.95, 1.00);
  vec3 iceSheet  = vec3(0.75, 0.88, 1.00);
  vec3 lavaRock  = vec3(0.25, 0.05, 0.02);
  vec3 lavaGlow  = vec3(1.00, 0.22, 0.00);

  vec3 col;
  if (absLat > 0.82) col = snowCap;
  else if (absLat > 0.70) col = mix(iceSheet, snowCap, smoothstep(0.70, 0.82, absLat));
  else if (t < 0.32) col = mix(deepOcean, ocean, smoothstep(0.18, 0.32, t));
  else if (t < 0.36) col = mix(ocean, shore, smoothstep(0.32, 0.36, t));
  else if (absLat < 0.18 && t < 0.60) col = mix(shore, desert, smoothstep(0.36, 0.56, t));
  else if (t < 0.52) col = mix(grass, forest, smoothstep(0.40, 0.52, t));
  else if (t < 0.68) col = mix(forest, mountain, smoothstep(0.52, 0.68, t));
  else if (t < 0.78) col = mix(mountain, snowCap, smoothstep(0.68, 0.78, t));
  else { float lt = smoothstep(0.78, 1.0, t); col = mix(lavaRock, lavaGlow, lt * lt); }

  // Damage effects
  float damage = 1.0 - healthLevel;
  if (damage > 0.01) {
    float cn = vnoise(n * 10.0 + vec3(crackCount * 0.17));
    cn = clamp((cn + 1.0) * 0.5, 0.0, 1.0);
    float threshold = 1.0 - damage * 0.75;
    float crackFactor = smoothstep(threshold, threshold - 0.06, cn);
    vec3 lavaCrack = mix(vec3(0.5, 0.02, 0.0), vec3(1.0, 0.25, 0.0), cn);
    col = mix(col, lavaCrack, crackFactor * damage);
    col = mix(col, vec3(0.08, 0.00, 0.00), damage * 0.45);
  }

  col *= damageTint;

  // Simple directional lighting
  vec3 lightDir = normalize(vec3(0.6, 0.4, 0.8));
  float diff = max(dot(n, lightDir), 0.0) * 0.7 + 0.3;
  col *= diff;

  gl_FragColor = vec4(col, 1.0);
}`;

const planetMat = new THREE.ShaderMaterial({
  vertexShader: planetVertShader,
  fragmentShader: planetFragShader,
  uniforms: {
    healthLevel: { value: 1.0 },
    crackCount:  { value: 0.0 },
    noiseSeed:   { value: Math.random() * 100 },
    damageTint:  { value: new THREE.Vector3(1, 1, 1) }
  }
});

const planetGeo = new THREE.SphereGeometry(PLANET_RADIUS, 64, 32);
const planetMesh = new THREE.Mesh(planetGeo, planetMat);
scene.add(planetMesh);

// Atmosphere shell
const atmoVertShader = `
varying vec3 vViewNormal;
void main() {
  vViewNormal = normalize(normalMatrix * normal);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

const atmoFragShader = `
uniform float atmosphereLevel;
uniform vec3 atmoColor;
varying vec3 vViewNormal;
void main() {
  float rim = 1.0 - abs(dot(vViewNormal, vec3(0.0, 0.0, 1.0)));
  float alpha = pow(rim, 2.8) * atmosphereLevel * 0.7;
  alpha = clamp(alpha, 0.0, 0.75);
  float depletion = 1.0 - atmosphereLevel;
  vec3 col = mix(atmoColor, vec3(0.8, 0.3, 0.1), depletion * 0.6);
  gl_FragColor = vec4(col, alpha);
}`;

const atmoMat = new THREE.ShaderMaterial({
  vertexShader: atmoVertShader,
  fragmentShader: atmoFragShader,
  uniforms: {
    atmosphereLevel: { value: 1.0 },
    atmoColor: { value: new THREE.Vector3(0.3, 0.6, 1.0) }
  },
  transparent: true,
  side: THREE.BackSide,
  depthWrite: false
});

const atmoMesh = new THREE.Mesh(new THREE.SphereGeometry(PLANET_RADIUS * 1.06, 48, 24), atmoMat);
scene.add(atmoMesh);

// Planet rotation group (cities rotate with it)
const planetGroup = new THREE.Group();
scene.add(planetGroup);

// ============================================================
// 5. CITY SYSTEM
// ============================================================
function randomSpherePoint(radius) {
  const theta = Math.random() * Math.PI * 2;
  const phi = Math.acos(2 * Math.random() - 1);
  return new THREE.Vector3(
    Math.sin(phi) * Math.cos(theta) * radius,
    Math.cos(phi) * radius,
    Math.sin(phi) * Math.sin(theta) * radius
  );
}

function isLand(pos) {
  // Use the same noise as the shader to determine if a position is land
  const n = pos.clone().normalize();
  const absLat = Math.abs(n.y);
  if (absLat > 0.75) return false; // ice cap
  // Simple noise approximation (matches shader logic approximately)
  const seed = planetMat.uniforms.noiseSeed.value;
  const px = n.x * 2.2 + seed * 0.013;
  const py = n.y * 2.2 + seed * 0.007;
  const pz = n.z * 2.2 + seed * 0.019;
  // Simple hash-based noise approximation
  const h = Math.sin(px * 127.1 + py * 311.7 + pz * 74.7) * 43758.5453;
  const t = (Math.sin(h) * 0.5 + 0.5);
  return t > 0.35; // above ocean level
}

function generateCityName() {
  const a = CITY_NAMES_A[Math.floor(Math.random() * CITY_NAMES_A.length)];
  const b = CITY_NAMES_B[Math.floor(Math.random() * CITY_NAMES_B.length)];
  return a + b;
}

function spawnCity(position) {
  if (state.cities.length >= MAX_CITIES) return null;

  const city = {
    name: generateCityName(),
    position: position.clone(),
    normal: position.clone().normalize(),
    population: 800 + Math.floor(Math.random() * 1200),
    techLevel: 1.0,
    defenseLevel: 1.0,
    cultureLevel: 1.0,
    growthRate: 0.015 + Math.random() * 0.008,
    isCollapsed: false,
    rebuildTimer: 0,
    rebuildTime: 30 + Math.random() * 15,
    hasShield: false,
    hasSatellite: false,
    hasDefenseGun: false,
    mesh: null,
    light: null,
    shieldMesh: null
  };

  // City visual — small glowing cube
  const size = 0.12;
  const geo = new THREE.BoxGeometry(size, size, size);
  const mat = new THREE.MeshStandardMaterial({
    color: 0xe8e080,
    emissive: 0xe8e080,
    emissiveIntensity: 0.6,
    metalness: 0.1,
    roughness: 0.4
  });
  city.mesh = new THREE.Mesh(geo, mat);
  city.mesh.position.copy(position).multiplyScalar(1.005); // slightly above surface

  // Orient cube to face outward
  city.mesh.lookAt(new THREE.Vector3(0, 0, 0));

  // Point light
  city.light = new THREE.PointLight(0xffee88, 0.8, 2.5);
  city.light.position.copy(city.mesh.position);
  planetGroup.add(city.mesh);
  planetGroup.add(city.light);

  state.cities.push(city);
  notify(`City founded: ${city.name}`, '#66ff88');
  return city;
}

function spawnInitialCities() {
  let spawned = 0;
  let attempts = 0;
  while (spawned < INITIAL_CITIES && attempts < 500) {
    attempts++;
    const pos = randomSpherePoint(PLANET_RADIUS);
    if (!isLand(pos)) continue;

    // Check min distance to other cities
    let tooClose = false;
    for (const c of state.cities) {
      if (c.position.distanceTo(pos) < 3.0) { tooClose = true; break; }
    }
    if (tooClose) continue;

    spawnCity(pos);
    spawned++;
  }
}

function updateCities(dt) {
  let totalPop = 0;
  let activeCount = 0;
  let totalTech = 0;

  for (const city of state.cities) {
    if (city.isCollapsed) {
      city.rebuildTimer += dt;
      if (city.rebuildTimer >= city.rebuildTime) {
        city.isCollapsed = false;
        city.rebuildTimer = 0;
        city.population = 50 + Math.floor(Math.random() * 200);
        city.techLevel = Math.max(1.0, city.techLevel * 0.4);
        city.growthRate = 0.015;
        city.mesh.material.color.set(0xe8e080);
        city.mesh.material.emissive.set(0xe8e080);
        city.mesh.material.emissiveIntensity = 0.6;
        city.light.color.set(0xffee88);
        city.light.intensity = 0.8;
        notify(`${city.name} rebuilt!`, '#88ff88');
      }
      continue;
    }

    // Growth
    city.population = Math.min(100_000_000, Math.floor(city.population * (1 + city.growthRate * dt)));
    city.techLevel = Math.min(100, city.techLevel + 0.0008 * dt);
    city.defenseLevel = Math.min(100, city.defenseLevel + 0.0004 * dt);
    city.cultureLevel = Math.min(100, city.cultureLevel + 0.0006 * dt);

    // Tech milestones
    if (city.techLevel >= 20 && city.population > 10000 && !city.hasSatellite) {
      city.hasSatellite = true;
      notify(`${city.name}: Satellite launched!`, '#aaddff');
    }
    if (city.techLevel >= 35 && city.population > 50000 && !city.hasShield) {
      city.hasShield = true;
      buildShieldVisual(city);
      notify(`${city.name}: Shield activated!`, '#66ccff');
    }
    if (city.techLevel >= 50 && city.population > 100000 && !city.hasDefenseGun) {
      city.hasDefenseGun = true;
      notify(`${city.name}: Defense cannon built!`, '#88aaff');
    }

    // Update visual scale based on population tier
    const tier = city.population >= 5_000_000 ? 3 : city.population >= 500_000 ? 2 : city.population >= 50_000 ? 1 : 0;
    const scale = [0.10, 0.16, 0.22, 0.30][tier] / 0.12;
    city.mesh.scale.setScalar(scale);
    city.light.intensity = 0.6 + tier * 0.5;
    city.light.distance = 1.5 + tier * 0.8;

    // Pulse
    const pulse = Math.sin(state.gameTime * 2.0 + city.position.x) * 0.15 + 0.85;
    city.mesh.material.emissiveIntensity = 0.4 + tier * 0.2 + pulse * 0.2;

    totalPop += city.population;
    activeCount++;
    totalTech += city.techLevel;
  }

  // Update UI
  document.getElementById('pop-val').textContent = formatNumber(totalPop);
  document.getElementById('city-val').textContent = `${activeCount} / ${state.cities.length}`;
  document.getElementById('tech-val').textContent = state.cities.length > 0 ? (totalTech / state.cities.length).toFixed(1) : '0.0';

  // AI expansion
  state.expansionTimer += dt;
  if (state.expansionTimer > 20) {
    state.expansionTimer = 0;
    tryExpandCities();
  }
}

function tryExpandCities() {
  for (const city of state.cities) {
    if (city.isCollapsed || city.population < 200000 || city.techLevel < 5) continue;
    if (state.cities.length >= MAX_CITIES) break;

    let attempts = 0;
    while (attempts < 20) {
      attempts++;
      const offset = randomSpherePoint(PLANET_RADIUS);
      // Bias toward parent city
      const candidate = city.position.clone().lerp(offset, 0.3 + Math.random() * 0.4).normalize().multiplyScalar(PLANET_RADIUS);
      if (!isLand(candidate)) continue;

      let tooClose = false;
      for (const c of state.cities) {
        if (c.position.distanceTo(candidate) < 2.5) { tooClose = true; break; }
      }
      if (!tooClose) {
        const newCity = spawnCity(candidate);
        if (newCity && Math.random() < 0.3) {
          newCity.name = 'New ' + city.name.split(' ').pop();
        }
        break;
      }
    }
    break; // max 1 expansion per tick
  }
}

function buildShieldVisual(city) {
  if (city.shieldMesh) return;
  const geo = new THREE.SphereGeometry(0.35, 16, 8);
  const mat = new THREE.MeshStandardMaterial({
    color: 0x3388ff,
    emissive: 0x3388ff,
    emissiveIntensity: 0.3,
    transparent: true,
    opacity: 0.15,
    side: THREE.DoubleSide,
    depthWrite: false
  });
  city.shieldMesh = new THREE.Mesh(geo, mat);
  city.shieldMesh.position.copy(city.mesh.position);
  planetGroup.add(city.shieldMesh);
}

function collapseCity(city) {
  if (city.isCollapsed) return;
  city.isCollapsed = true;
  city.rebuildTimer = 0;
  city.population = 0;
  city.hasShield = false;
  city.hasDefenseGun = false;
  city.mesh.material.color.set(0x440000);
  city.mesh.material.emissive.set(0x220000);
  city.mesh.material.emissiveIntensity = 0.2;
  city.light.color.set(0x440000);
  city.light.intensity = 0.3;
  if (city.shieldMesh) {
    planetGroup.remove(city.shieldMesh);
    city.shieldMesh.geometry.dispose();
    city.shieldMesh.material.dispose();
    city.shieldMesh = null;
  }
  notify(`${city.name} COLLAPSED!`, '#ff4422');
}

// ============================================================
// 6. DISASTER SYSTEM
// ============================================================
function triggerDisaster(abilityKey, worldPos) {
  const a = ABILITIES[abilityKey];
  notify(`UNLEASHING: ${a.name}`, a.color);

  switch (abilityKey) {
    case 'METEOR_STRIKE':     doMeteor(worldPos); break;
    case 'VOLCANIC_ERUPTION': doVolcano(worldPos); break;
    case 'EARTHQUAKE':        doEarthquake(worldPos); break;
    case 'CLIMATE_SHIFT':     doClimateShift(); break;
    case 'ICE_AGE':           doIceAge(); break;
    case 'SOLAR_FLARE':       doSolarFlare(); break;
    case 'BLACK_HOLE':        doBlackHole(worldPos); break;
    case 'PLANET_CRACK':      doPlanetCrack(worldPos); break;
  }
}

function damageZone(worldPos, radius, damageRatio, disasterType) {
  for (const city of state.cities) {
    if (city.isCollapsed) continue;
    const dist = city.position.distanceTo(worldPos);
    if (dist > radius) continue;

    const intensity = 1 - dist / radius;
    let defReduction = Math.min(0.8, city.defenseLevel / 100);
    if (city.hasShield) defReduction = Math.min(0.95, defReduction + 0.25);

    const effectiveDmg = damageRatio * intensity * (1 - defReduction);
    const killed = Math.floor(city.population * effectiveDmg);
    city.population = Math.max(0, city.population - killed);

    if (disasterType === 'SOLAR_FLARE') {
      city.techLevel = Math.max(1, city.techLevel * 0.5);
      city.hasSatellite = false;
    }
    if (disasterType === 'ICE_AGE') {
      city.growthRate = Math.max(0.001, city.growthRate * 0.3);
    }

    if (city.population <= 0 || effectiveDmg > 0.85) {
      collapseCity(city);
    }
  }
}

function doMeteor(pos) {
  state.planetHealth = Math.max(0, state.planetHealth - 8);
  state.atmosphere = Math.max(0, state.atmosphere - 2);
  state.tectonics = Math.min(100, state.tectonics + 5);
  planetMat.uniforms.crackCount.value += 1;
  damageZone(pos, 2.5, 0.6, 'METEOR_STRIKE');
  spawnExplosion(pos, 0xff6611, 2.5, 1.5);
  spawnCraterLight(pos);
  triggerShake(0.7, 0.8);
}

function doVolcano(pos) {
  state.planetHealth = Math.max(0, state.planetHealth - 6);
  state.atmosphere = Math.max(0, state.atmosphere - 5);
  state.temperature += 3;
  damageZone(pos, 3, 0.5, 'VOLCANIC_ERUPTION');
  spawnExplosion(pos, 0xff2200, 3, 1.0);
  spawnLavaPool(pos);
  triggerShake(0.5, 1.5);
}

function doEarthquake(pos) {
  state.planetHealth = Math.max(0, state.planetHealth - 5);
  state.tectonics = Math.min(100, state.tectonics + 15);
  damageZone(pos, 4, 0.4, 'EARTHQUAKE');
  spawnShockwave(pos, 0xcc9933, 5);
  triggerShake(1.2, 3.0);
}

function doClimateShift() {
  const delta = state.temperature > 20 ? -10 : 10;
  state.temperature += delta;
  state.biosphere = Math.max(0, state.biosphere - 5);
  state.planetHealth = Math.max(0, state.planetHealth - 3);
}

function doIceAge() {
  state.temperature -= 30;
  state.biosphere = Math.max(0, state.biosphere - 30);
  state.planetHealth = Math.max(0, state.planetHealth - 15);
  for (const city of state.cities) {
    if (!city.isCollapsed) {
      city.population = Math.floor(city.population * 0.7);
      if (city.population <= 0) collapseCity(city);
    }
  }
  // Ice tint atmosphere
  atmoMat.uniforms.atmoColor.value.set(0.7, 0.9, 1.0);
  setTimeout(() => { atmoMat.uniforms.atmoColor.value.set(0.3, 0.6, 1.0); }, 15000);
  triggerShake(0.3, 0.5);
}

function doSolarFlare() {
  state.atmosphere = Math.max(0, state.atmosphere - 10);
  state.biosphere = Math.max(0, state.biosphere - 8);
  state.planetHealth = Math.max(0, state.planetHealth - 5);
  for (const city of state.cities) {
    if (!city.isCollapsed && city.techLevel > 10) {
      city.techLevel = Math.max(1, city.techLevel * 0.5);
      city.hasSatellite = false;
    }
  }
  // Flash
  const flashLight = new THREE.PointLight(0xffee66, 15, 100);
  flashLight.position.set(20, 10, 20);
  scene.add(flashLight);
  addEffect(flashLight, 3, () => { scene.remove(flashLight); flashLight.dispose(); });
}

function doBlackHole(pos) {
  state.planetHealth = Math.max(0, state.planetHealth - 20);
  state.atmosphere = Math.max(0, state.atmosphere - 15);
  damageZone(pos, 5, 0.8, 'BLACK_HOLE');
  spawnBlackHoleEffect(pos);
  triggerShake(0.8, 2.0);
}

function doPlanetCrack(pos) {
  state.planetHealth = Math.max(0, state.planetHealth - 60);
  state.atmosphere = Math.max(0, state.atmosphere - 40);
  state.biosphere = Math.max(0, state.biosphere - 30);
  state.tectonics = Math.min(100, state.tectonics + 50);
  planetMat.uniforms.crackCount.value += 8;
  damageZone(pos, 20, 1.0, 'PLANET_CRACK');
  // Multiple explosions
  for (let i = 0; i < 8; i++) {
    const offset = randomSpherePoint(PLANET_RADIUS).multiplyScalar(0.8);
    setTimeout(() => {
      spawnExplosion(offset, 0xff0000, 3.5, 4.0);
      spawnCraterLight(offset);
    }, i * 400);
  }
  triggerShake(2.5, 5.0);
}

// ============================================================
// 7. VISUAL EFFECTS
// ============================================================
function addEffect(obj, duration, onComplete) {
  state.effects.push({ obj, timer: duration, onComplete: onComplete || (() => {}) });
}

function updateEffects(dt) {
  for (let i = state.effects.length - 1; i >= 0; i--) {
    state.effects[i].timer -= dt;
    if (state.effects[i].timer <= 0) {
      state.effects[i].onComplete();
      state.effects.splice(i, 1);
    }
  }
}

function spawnExplosion(pos, color, radius, duration) {
  const geo = new THREE.SphereGeometry(0.3, 16, 8);
  const mat = new THREE.MeshStandardMaterial({
    color, emissive: color, emissiveIntensity: 5,
    transparent: true, opacity: 0.9
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(pos);
  scene.add(mesh);

  const light = new THREE.PointLight(color, 10, radius * 3);
  light.position.copy(pos);
  scene.add(light);

  const startTime = state.gameTime;
  const totalDur = duration;

  addEffect(mesh, duration, () => {
    scene.remove(mesh); scene.remove(light);
    mesh.geometry.dispose(); mat.dispose(); light.dispose();
  });

  // Animate scale and opacity
  const originalUpdate = mesh.onBeforeRender;
  mesh.userData.animUpdate = () => {
    const elapsed = state.gameTime - startTime;
    const t = Math.min(elapsed / totalDur, 1);
    const s = radius * Math.pow(t, 0.3);
    mesh.scale.setScalar(s);
    mat.opacity = Math.max(0, 1 - t);
    light.intensity = 10 * (1 - t);
  };
}

function spawnCraterLight(pos) {
  const light = new THREE.PointLight(0xff3300, 3, 4);
  light.position.copy(pos).multiplyScalar(1.02);
  planetGroup.add(light);
  addEffect(light, 60, () => { planetGroup.remove(light); light.dispose(); });
}

function spawnLavaPool(pos) {
  const geo = new THREE.SphereGeometry(1.5, 16, 8);
  const mat = new THREE.MeshStandardMaterial({
    color: 0xff2200, emissive: 0xff4400, emissiveIntensity: 3,
    transparent: true, opacity: 0.7
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(pos);
  scene.add(mesh);

  const light = new THREE.PointLight(0xff3300, 5, 6);
  light.position.copy(pos);
  scene.add(light);

  addEffect(mesh, 40, () => {
    scene.remove(mesh); scene.remove(light);
    mesh.geometry.dispose(); mat.dispose(); light.dispose();
  });
}

function spawnShockwave(pos, color, radius) {
  const geo = new THREE.TorusGeometry(0.5, 0.08, 8, 32);
  const mat = new THREE.MeshStandardMaterial({
    color, emissive: color, emissiveIntensity: 3,
    transparent: true, opacity: 0.8
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(pos);
  mesh.lookAt(0, 0, 0);
  scene.add(mesh);

  const startTime = state.gameTime;
  mesh.userData.animUpdate = () => {
    const t = Math.min((state.gameTime - startTime) / 2, 1);
    mesh.scale.setScalar(1 + t * radius);
    mat.opacity = Math.max(0, 1 - t);
  };

  addEffect(mesh, 2, () => {
    scene.remove(mesh); mesh.geometry.dispose(); mat.dispose();
  });
}

function spawnBlackHoleEffect(pos) {
  const light = new THREE.PointLight(0x6600ff, 15, 10);
  light.position.copy(pos);
  scene.add(light);

  const geo = new THREE.SphereGeometry(0.4, 16, 8);
  const mat = new THREE.MeshStandardMaterial({
    color: 0x110022, emissive: 0x4400aa, emissiveIntensity: 2
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(pos);
  scene.add(mesh);

  const startTime = state.gameTime;
  mesh.userData.animUpdate = () => {
    const t = (state.gameTime - startTime);
    light.intensity = 12 + Math.sin(t * 4) * 6;
  };

  addEffect(mesh, 10, () => {
    scene.remove(mesh); scene.remove(light);
    mesh.geometry.dispose(); mat.dispose(); light.dispose();
  });
}

// Screen shake
let shakeIntensity = 0, shakeDuration = 0, shakeTimer = 0;
function triggerShake(intensity, duration) {
  shakeIntensity = intensity;
  shakeDuration = duration;
  shakeTimer = duration;
}

// ============================================================
// 8. UI SYSTEM
// ============================================================
function buildAbilityButtons() {
  const row = document.getElementById('abilities-row');
  let index = 1;
  for (const [key, ab] of Object.entries(ABILITIES)) {
    const btn = document.createElement('div');
    btn.className = 'ability-btn';
    btn.dataset.ability = key;
    btn.innerHTML = `
      <span class="ability-key">${index}</span>
      <span class="ability-icon">${ab.icon}</span>
      <span class="ability-name">${ab.name}</span>
      <span class="ability-cost">${ab.cost}E</span>
      <div class="ability-cooldown-bar" style="width:100%"></div>
      <div class="tooltip">
        <div class="tooltip-title">${ab.name}</div>
        <div class="tooltip-desc">${ab.desc}</div>
        <div class="tooltip-stats">Cost: ${ab.cost} | CD: ${ab.cooldown}s</div>
      </div>
    `;
    btn.addEventListener('click', () => selectAbility(key));
    row.appendChild(btn);
    index++;
  }
}

function selectAbility(key) {
  if (!canUse(key)) return;
  state.selectedAbility = key;
  state.targeting = true;
  document.body.classList.add('targeting');
  document.getElementById('targeting-label').classList.remove('hidden');

  // Highlight active button
  document.querySelectorAll('.ability-btn').forEach(b => b.classList.remove('active'));
  const activeBtn = document.querySelector(`.ability-btn[data-ability="${key}"]`);
  if (activeBtn) activeBtn.classList.add('active');
}

function cancelTargeting() {
  state.selectedAbility = null;
  state.targeting = false;
  document.body.classList.remove('targeting');
  document.getElementById('targeting-label').classList.add('hidden');
  document.querySelectorAll('.ability-btn').forEach(b => b.classList.remove('active'));
}

function canUse(key) {
  if (state.energy < ABILITIES[key].cost) return false;
  if (state.cooldowns[key] > 0) return false;
  return true;
}

function updateUI() {
  // Planet stats
  document.getElementById('health-bar').style.width = state.planetHealth + '%';
  document.getElementById('health-val').textContent = Math.round(state.planetHealth);
  document.getElementById('atmo-bar').style.width = state.atmosphere + '%';
  document.getElementById('atmo-val').textContent = Math.round(state.atmosphere);
  document.getElementById('bio-bar').style.width = state.biosphere + '%';
  document.getElementById('bio-val').textContent = Math.round(state.biosphere);
  document.getElementById('energy-bar').style.width = (state.energy / state.maxEnergy * 100) + '%';
  document.getElementById('energy-val').textContent = Math.round(state.energy);

  // Temperature
  const tempEl = document.getElementById('temp-val');
  tempEl.textContent = state.temperature.toFixed(1) + '\u00B0C';
  tempEl.className = state.temperature > 50 ? 'hot' : state.temperature < -10 ? 'cold' : '';

  // Ability cooldowns
  for (const [key, ab] of Object.entries(ABILITIES)) {
    const btn = document.querySelector(`.ability-btn[data-ability="${key}"]`);
    if (!btn) continue;
    const cdBar = btn.querySelector('.ability-cooldown-bar');
    const frac = state.cooldowns[key] > 0 ? (1 - state.cooldowns[key] / ab.cooldown) : 1;
    cdBar.style.width = (frac * 100) + '%';
    if (canUse(key)) {
      btn.classList.remove('disabled');
    } else {
      btn.classList.add('disabled');
    }
  }

  // Planet shader
  planetMat.uniforms.healthLevel.value = state.planetHealth / 100;
  const dmg = 1 - state.planetHealth / 100;
  planetMat.uniforms.damageTint.value.set(1, 1 - dmg * 0.4, 1 - dmg * 0.5);
  atmoMat.uniforms.atmosphereLevel.value = state.atmosphere / 100;

  // Health bar color change
  const hBar = document.getElementById('health-bar');
  if (state.planetHealth < 30) {
    hBar.className = 'bar bar-red';
  } else {
    hBar.className = 'bar bar-green';
  }
}

// Notifications
function notify(message, color = '#ccddee') {
  const container = document.getElementById('notifications');
  const el = document.createElement('div');
  el.className = 'notification';
  el.textContent = '> ' + message;
  el.style.borderLeftColor = color;
  el.style.color = color;
  container.appendChild(el);

  // Remove after animation
  setTimeout(() => { if (el.parentNode) el.parentNode.removeChild(el); }, 4000);

  // Limit to 6
  while (container.children.length > 6) {
    container.removeChild(container.firstChild);
  }
}

function formatNumber(n) {
  if (n >= 1_000_000_000) return (n / 1_000_000_000).toFixed(1) + 'B';
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
  return String(n);
}

// Speed controls
document.querySelectorAll('.speed-btn[data-speed]').forEach(btn => {
  btn.addEventListener('click', () => {
    state.speed = parseFloat(btn.dataset.speed);
    state.paused = false;
    document.querySelectorAll('.speed-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('pause-btn').classList.remove('active');
  });
});

document.getElementById('pause-btn').addEventListener('click', () => {
  state.paused = !state.paused;
  document.getElementById('pause-btn').classList.toggle('active', state.paused);
  if (state.paused) notify('PAUSED', '#ffcc00');
});

// ============================================================
// 9. INPUT HANDLING
// ============================================================
const raycaster = new THREE.Raycaster();
const mouse = new THREE.Vector2();

canvas.addEventListener('click', (e) => {
  if (!state.targeting) return;

  mouse.x = (e.clientX / window.innerWidth) * 2 - 1;
  mouse.y = -(e.clientY / window.innerHeight) * 2 + 1;
  raycaster.setFromCamera(mouse, camera);

  const hits = raycaster.intersectObject(planetMesh);
  if (hits.length > 0) {
    const hitPoint = hits[0].point;
    const key = state.selectedAbility;

    // Consume energy and set cooldown
    state.energy -= ABILITIES[key].cost;
    state.cooldowns[key] = ABILITIES[key].cooldown;

    triggerDisaster(key, hitPoint);
    cancelTargeting();

    // Check planet death
    if (state.planetHealth <= 0 && !state.isDestroyed) {
      state.isDestroyed = true;
      setTimeout(() => {
        document.getElementById('game-over').classList.remove('hidden');
      }, 2000);
    }
  }
});

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
  const abilityKeys = Object.keys(ABILITIES);
  const num = parseInt(e.key);
  if (num >= 1 && num <= 8) {
    e.preventDefault();
    selectAbility(abilityKeys[num - 1]);
  }
  if (e.key === 'Escape') {
    cancelTargeting();
  }
  if (e.key === ' ') {
    e.preventDefault();
    state.paused = !state.paused;
    document.getElementById('pause-btn').classList.toggle('active', state.paused);
    if (state.paused) notify('PAUSED', '#ffcc00');
  }
  if (e.key === '+' || e.key === '=') {
    state.speed = Math.min(state.speed * 2, 8);
  }
  if (e.key === '-') {
    state.speed = Math.max(state.speed * 0.5, 0.25);
  }
});

// ============================================================
// 10. GAME LOOP
// ============================================================
const clock = new THREE.Clock();

function animate() {
  requestAnimationFrame(animate);

  const rawDelta = clock.getDelta();
  const dt = state.paused ? 0 : rawDelta * state.speed;
  state.gameTime += dt;

  // Energy regen
  if (!state.paused) {
    state.energy = Math.min(state.maxEnergy, state.energy + state.energyRegen * dt);

    // Cooldowns
    for (const key of Object.keys(state.cooldowns)) {
      if (state.cooldowns[key] > 0) {
        state.cooldowns[key] = Math.max(0, state.cooldowns[key] - dt);
      }
    }
  }

  // Planet rotation
  planetMesh.rotation.y += 0.015 * dt;
  atmoMesh.rotation.y += 0.012 * dt;
  planetGroup.rotation.y = planetMesh.rotation.y;

  // Update systems
  if (!state.paused) {
    updateCities(dt);
    updateEffects(dt);
  }

  // Animate effects
  scene.traverse((obj) => {
    if (obj.userData && obj.userData.animUpdate) {
      obj.userData.animUpdate();
    }
  });

  // Camera shake
  if (shakeTimer > 0) {
    shakeTimer -= rawDelta;
    const intensity = shakeIntensity * (shakeTimer / shakeDuration);
    camera.position.x += (Math.random() - 0.5) * intensity * 0.5;
    camera.position.y += (Math.random() - 0.5) * intensity * 0.5;
  }

  updateUI();
  controls.update();
  renderer.render(scene, camera);
}

// ============================================================
// 11. INITIALIZATION
// ============================================================
window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

buildAbilityButtons();
spawnInitialCities();
notify('Planet generated. Civilizations emerging...', '#88ccff');
notify('Select a cosmic power and click the planet.', '#aaaacc');
animate();
