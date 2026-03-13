/* =============================================================
   CYBER NEXUS – app.js
   Three.js 3D Scene + GSAP Animations + Particle Trail
   ============================================================= */

(function () {
  'use strict';

  /* ─────────────────────────────────────────────
     1. THREE.JS BACKGROUND SCENE
  ───────────────────────────────────────────── */
  const bgCanvas = document.getElementById('bg-canvas');
  const renderer = new THREE.WebGLRenderer({ canvas: bgCanvas, antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);

  const scene  = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 1000);
  camera.position.z = 5;

  /* ── Lighting ── */
  const ambientLight = new THREE.AmbientLight(0x001122, 2);
  scene.add(ambientLight);

  const pointLight1 = new THREE.PointLight(0x00ffff, 4, 20);
  pointLight1.position.set(3, 3, 3);
  scene.add(pointLight1);

  const pointLight2 = new THREE.PointLight(0xff00ff, 3, 20);
  pointLight2.position.set(-3, -3, 2);
  scene.add(pointLight2);

  /* ── Central Icosahedron (Solid) ── */
  const icoGeo = new THREE.IcosahedronGeometry(1.4, 1);
  const icoMat = new THREE.MeshPhongMaterial({
    color: 0x001833,
    emissive: 0x003344,
    specular: 0x00ffff,
    shininess: 120,
    transparent: true,
    opacity: 0.85,
  });
  const icoMesh = new THREE.Mesh(icoGeo, icoMat);
  scene.add(icoMesh);

  /* ── Central Icosahedron (Wireframe over solid) ── */
  const wireGeo = new THREE.IcosahedronGeometry(1.42, 1);
  const wireMat = new THREE.MeshBasicMaterial({
    color: 0x00ffff,
    wireframe: true,
    transparent: true,
    opacity: 0.6,
  });
  const wireMesh = new THREE.Mesh(wireGeo, wireMat);
  scene.add(wireMesh);

  /* ── Outer Ring Torus ── */
  const torusGeo = new THREE.TorusGeometry(2.4, 0.03, 8, 80);
  const torusMat = new THREE.MeshBasicMaterial({ color: 0xff00ff, transparent: true, opacity: 0.5 });
  const torusMesh = new THREE.Mesh(torusGeo, torusMat);
  torusMesh.rotation.x = Math.PI / 2.5;
  scene.add(torusMesh);

  const torus2Geo = new THREE.TorusGeometry(2.0, 0.02, 8, 80);
  const torus2Mat = new THREE.MeshBasicMaterial({ color: 0x7700ff, transparent: true, opacity: 0.4 });
  const torus2Mesh = new THREE.Mesh(torus2Geo, torus2Mat);
  torus2Mesh.rotation.x = Math.PI / 4;
  torus2Mesh.rotation.z = Math.PI / 6;
  scene.add(torus2Mesh);

  /* ── Particle Field (3000 points) ── */
  const PARTICLE_COUNT = 3000;
  const positions = new Float32Array(PARTICLE_COUNT * 3);
  const pColors   = new Float32Array(PARTICLE_COUNT * 3);

  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const i3 = i * 3;
    // spread particles in a sphere-ish volume
    const r     = 4 + Math.random() * 20;
    const theta = Math.random() * Math.PI * 2;
    const phi   = Math.acos(2 * Math.random() - 1);
    positions[i3]     = r * Math.sin(phi) * Math.cos(theta);
    positions[i3 + 1] = r * Math.sin(phi) * Math.sin(theta);
    positions[i3 + 2] = r * Math.cos(phi);

    // cyan to magenta gradient
    const t = Math.random();
    pColors[i3]     = t;            // R
    pColors[i3 + 1] = 1 - t;       // G
    pColors[i3 + 2] = 1;           // B
  }

  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  pGeo.setAttribute('color',    new THREE.BufferAttribute(pColors, 3));

  const pMat = new THREE.PointsMaterial({
    size: 0.06,
    vertexColors: true,
    transparent: true,
    opacity: 0.85,
    sizeAttenuation: true,
  });

  const particles = new THREE.Points(pGeo, pMat);
  scene.add(particles);

  /* ─────────────────────────────────────────────
     2. MOUSE PARALLAX
  ───────────────────────────────────────────── */
  const mouse = { x: 0, y: 0 };
  const target = { x: 0, y: 0 };

  document.addEventListener('mousemove', (e) => {
    mouse.x = (e.clientX / window.innerWidth  - 0.5) * 2;
    mouse.y = (e.clientY / window.innerHeight - 0.5) * 2;
  });

  /* ─────────────────────────────────────────────
     3. THREE.JS ANIMATION LOOP
  ───────────────────────────────────────────── */
  let clock = 0;

  function animateScene() {
    requestAnimationFrame(animateScene);
    clock += 0.005;

    // Smooth mouse follow
    target.x += (mouse.x - target.x) * 0.04;
    target.y += (mouse.y - target.y) * 0.04;

    camera.position.x = target.x * 0.8;
    camera.position.y = -target.y * 0.8;
    camera.lookAt(scene.position);

    // Rotate main objects
    icoMesh.rotation.x += 0.004;
    icoMesh.rotation.y += 0.007;
    wireMesh.rotation.x += 0.004;
    wireMesh.rotation.y += 0.007;

    torusMesh.rotation.z += 0.006;
    torusMesh.rotation.y += 0.003;
    torus2Mesh.rotation.x += 0.005;
    torus2Mesh.rotation.z -= 0.004;

    // Slowly rotate particle field
    particles.rotation.y += 0.0008;
    particles.rotation.x += 0.0003;

    // Pulsing light
    pointLight1.intensity = 4 + Math.sin(clock * 2.5) * 2;
    pointLight2.intensity = 3 + Math.cos(clock * 1.8) * 1.5;

    // Scale pulse on icosahedron
    const pulse = 1 + Math.sin(clock * 1.5) * 0.04;
    icoMesh.scale.setScalar(pulse);
    wireMesh.scale.setScalar(pulse);

    renderer.render(scene, camera);
  }

  animateScene();

  /* ─────────────────────────────────────────────
     4. MOUSE TRAIL CANVAS
  ───────────────────────────────────────────── */
  const trailCanvas = document.getElementById('trail-canvas');
  const ctx = trailCanvas.getContext('2d');
  trailCanvas.width  = window.innerWidth;
  trailCanvas.height = window.innerHeight;

  const trail = [];
  const TRAIL_LENGTH = 40;

  document.addEventListener('mousemove', (e) => {
    trail.push({ x: e.clientX, y: e.clientY, age: 0 });
    if (trail.length > TRAIL_LENGTH) trail.shift();
  });

  function animateTrail() {
    requestAnimationFrame(animateTrail);
    ctx.clearRect(0, 0, trailCanvas.width, trailCanvas.height);

    for (let i = 0; i < trail.length; i++) {
      const p = trail[i];
      p.age++;
      const alpha = Math.max(0, 1 - p.age / TRAIL_LENGTH);
      const size  = (1 - i / trail.length) * 8 + 1;

      ctx.beginPath();
      ctx.arc(p.x, p.y, size, 0, Math.PI * 2);

      // alternate cyan/magenta
      const color = i % 2 === 0 ? `rgba(0,255,255,${alpha * 0.8})` : `rgba(255,0,255,${alpha * 0.6})`;
      ctx.fillStyle = color;
      ctx.shadowBlur   = 12;
      ctx.shadowColor  = i % 2 === 0 ? '#00ffff' : '#ff00ff';
      ctx.fill();
    }
  }

  animateTrail();

  /* ─────────────────────────────────────────────
     5. RESIZE HANDLER
  ───────────────────────────────────────────── */
  window.addEventListener('resize', () => {
    const w = window.innerWidth;
    const h = window.innerHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    trailCanvas.width  = w;
    trailCanvas.height = h;
  });

  /* ─────────────────────────────────────────────
     6. GSAP ENTRANCE ANIMATIONS
  ───────────────────────────────────────────── */
  if (typeof gsap !== 'undefined') {
    // Register ScrollTrigger
    if (typeof ScrollTrigger !== 'undefined') {
      gsap.registerPlugin(ScrollTrigger);
    }

    // Hero content fade-in
    gsap.to('.hero-content', {
      opacity: 1,
      y: 0,
      duration: 1.4,
      ease: 'power3.out',
      delay: 0.3,
    });

    gsap.from('.title', {
      y: 60,
      opacity: 0,
      duration: 1.2,
      ease: 'power4.out',
      delay: 0.5,
    });

    gsap.from('.subtitle', {
      y: 30,
      opacity: 0,
      duration: 1,
      ease: 'power3.out',
      delay: 0.9,
    });

    gsap.from('.cta-row', {
      y: 30,
      opacity: 0,
      duration: 1,
      ease: 'power3.out',
      delay: 1.2,
    });

    gsap.from('.scroll-hint', {
      opacity: 0,
      duration: 1,
      delay: 1.8,
    });

    // Stat cards stagger on scroll
    gsap.from('.stat-card', {
      scrollTrigger: {
        trigger: '.stats-section',
        start: 'top 80%',
      },
      y: 60,
      opacity: 0,
      duration: 0.8,
      stagger: 0.15,
      ease: 'power3.out',
    });

    // Section title
    gsap.from('.section-title', {
      scrollTrigger: {
        trigger: '.cards-section',
        start: 'top 85%',
      },
      y: 40,
      opacity: 0,
      duration: 0.9,
      ease: 'power3.out',
    });

    // Cards stagger
    gsap.from('.card-3d', {
      scrollTrigger: {
        trigger: '.cards-grid',
        start: 'top 85%',
      },
      y: 80,
      opacity: 0,
      rotationX: 30,
      duration: 1,
      stagger: 0.2,
      ease: 'power3.out',
    });
  }

  /* ─────────────────────────────────────────────
     7. STAT COUNTER ANIMATION
  ───────────────────────────────────────────── */
  function animateCounter(el) {
    const target = parseInt(el.dataset.target, 10);
    const duration = 1800;
    const start    = performance.now();

    function update(now) {
      const elapsed  = now - start;
      const progress = Math.min(elapsed / duration, 1);
      // ease out
      const eased    = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(eased * target).toLocaleString();
      if (progress < 1) requestAnimationFrame(update);
    }
    requestAnimationFrame(update);
  }

  const statNumbers = document.querySelectorAll('.stat-number');
  const statsSection = document.getElementById('stats');
  let countersStarted = false;

  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting && !countersStarted) {
        countersStarted = true;
        statNumbers.forEach(animateCounter);
      }
    });
  }, { threshold: 0.3 });

  if (statsSection) io.observe(statsSection);

  /* ─────────────────────────────────────────────
     8. 3D CARD TILT ON MOUSE MOVE
  ───────────────────────────────────────────── */
  document.querySelectorAll('.card-3d').forEach((card) => {
    card.addEventListener('mousemove', (e) => {
      const rect = card.getBoundingClientRect();
      const cx   = rect.left + rect.width  / 2;
      const cy   = rect.top  + rect.height / 2;
      const dx   = (e.clientX - cx) / (rect.width  / 2);
      const dy   = (e.clientY - cy) / (rect.height / 2);
      const inner = card.querySelector('.card-inner');
      inner.style.transform = `rotateY(${dx * 15}deg) rotateX(${-dy * 15}deg) translateZ(10px)`;
      inner.style.boxShadow = `${dx * -10}px ${dy * -10}px 40px rgba(0,255,255,0.25)`;
    });

    card.addEventListener('mouseleave', () => {
      const inner = card.querySelector('.card-inner');
      inner.style.transform = '';
      inner.style.boxShadow = '';
    });
  });

  /* ─────────────────────────────────────────────
     9. BUTTON INTERACTIONS
  ───────────────────────────────────────────── */
  const btnExplore = document.getElementById('btn-explore');
  const btnConnect = document.getElementById('btn-connect');

  if (btnExplore) {
    btnExplore.addEventListener('click', () => {
      document.getElementById('stats').scrollIntoView({ behavior: 'smooth' });
    });
  }
  if (btnConnect) {
    btnConnect.addEventListener('click', () => {
      document.getElementById('cards').scrollIntoView({ behavior: 'smooth' });
    });
  }

}());
