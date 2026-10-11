const destinations = {
  library: {
    label: "Library entrance",
    route: "M 91 338 L 91 274 L 182 274 L 182 202 L 314 202 L 314 116 L 430 116",
    steps: [
      "Walk straight ahead for about 20 feet. The hallway opens on your right at 2 o'clock. Turn right.",
      "Continue past the drinking fountain on your left. The library entrance is ahead at 12 o'clock.",
      "You have arrived at the library entrance. The door is on your right."
    ],
    duration: "About 2 minutes",
    distance: "Around 85 feet",
    marker: { x: 430, y: 116 },
    accessible: true
  },
  restroom: {
    label: "Accessible restroom",
    route: "M 91 338 L 91 274 L 182 274 L 182 202 L 314 202 L 314 268 L 424 268",
    steps: [
      "Walk straight ahead for about 20 feet. Turn right at the hallway opening at 2 o'clock.",
      "Continue past the drinking fountain. The accessible restroom is on your left at 10 o'clock.",
      "You have arrived at the accessible restroom. The door is on your left."
    ],
    duration: "About 2 minutes",
    distance: "Around 74 feet",
    marker: { x: 424, y: 268 },
    accessible: true
  },
  elevator: {
    label: "Elevator",
    route: "M 91 338 L 91 274 L 182 274 L 182 202 L 180 116 L 267 116",
    steps: [
      "Walk straight ahead for about 20 feet. Turn right at the hallway opening at 2 o'clock.",
      "The elevator is ahead at 12 o'clock, beside the north corridor. Stop at the tactile floor marker.",
      "You have arrived at the elevator. The call buttons are on your right."
    ],
    duration: "About 2 minutes",
    distance: "Around 62 feet",
    marker: { x: 267, y: 116 },
    accessible: true
  },
  cafe: {
    label: "Cafeteria",
    route: "M 91 338 L 91 274 L 182 274 L 182 202 L 314 202 L 430 202 L 430 337 L 485 337",
    steps: [
      "Walk straight ahead for about 20 feet. Turn right at the hallway opening at 2 o'clock.",
      "Follow the corridor past two doorways. The cafeteria entrance is ahead at 12 o'clock.",
      "You have arrived at the cafeteria. The entrance is directly in front of you."
    ],
    duration: "About 3 minutes",
    distance: "Around 110 feet",
    marker: { x: 485, y: 337 },
    accessible: false
  }
};

const state = {
  page: "navigate",
  destination: "library",
  active: false,
  completed: false,
  paused: false,
  step: 0,
  hazard: false,
  focus: false,
  settings: readSettings()
};

const main = document.querySelector("#main");
const announcer = document.querySelector("#live-announcer");
const urgentAnnouncer = document.querySelector("#urgent-announcer");
let lastTouchX = null;
let voices = [];

function readSettings() {
  try {
    return {
      speech: localStorage.getItem("blindspot-speech") !== "false",
      haptics: localStorage.getItem("blindspot-haptics") !== "false",
      largeText: localStorage.getItem("blindspot-large-text") === "true",
      contrast: localStorage.getItem("blindspot-contrast") === "true",
      voice: localStorage.getItem("blindspot-voice") || ""
    };
  } catch (error) {
    console.warn("Accessibility preferences could not be loaded.", error);
    return { speech: true, haptics: true, largeText: false, contrast: false, voice: "" };
  }
}

function saveSetting(key, value) {
  state.settings[key] = value;
  try {
    localStorage.setItem(`blindspot-${key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`, String(value));
  } catch (error) {
    announce("This preference could not be saved. It will last for this visit.");
    console.warn("Accessibility preference could not be saved.", error);
  }
  applySettings();
}

function applySettings() {
  document.documentElement.dataset.contrast = state.settings.contrast ? "high" : "standard";
  document.documentElement.dataset.largeText = String(state.settings.largeText);
}

function announce(message) {
  announcer.textContent = "";
  window.setTimeout(() => { announcer.textContent = message; }, 30);
}

function vibrate(pattern) {
  if (!state.settings.haptics) return;
  if (!("vibrate" in navigator)) {
    announce("Haptics are not available in this browser. Spoken and on-screen guidance are still available.");
    return;
  }
  navigator.vibrate(pattern);
}

function selectedDestination() {
  return destinations[state.destination];
}

function speak(text, urgent = false) {
  if (urgent) urgentAnnouncer.textContent = text;
  if (!state.settings.speech) {
    if (!urgent) announce(text);
    return;
  }
  if (!("speechSynthesis" in window)) {
    if (urgent) urgentAnnouncer.textContent = `${text} Speech playback is not supported in this browser.`;
    else announce(`${text} Speech playback is not supported in this browser.`);
    return;
  }
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  const chosenVoice = voices.find((voice) => voice.voiceURI === state.settings.voice);
  if (chosenVoice) utterance.voice = chosenVoice;
  utterance.rate = 0.92;
  utterance.pitch = 1;
  utterance.onend = () => { if (urgent) urgentAnnouncer.textContent = ""; };
  window.speechSynthesis.speak(utterance);
}

function formatDestinationOptions() {
  return Object.entries(destinations).map(([key, item]) =>
    `<option value="${key}" ${state.destination === key ? "selected" : ""}>${item.label}</option>`
  ).join("");
}

function renderMap() {
  const destination = selectedDestination();
  return `
    <section class="panel map-panel" aria-labelledby="map-title">
      <div class="map-header">
        <h2 id="map-title">Cedar Hall, Level 1</h2>
        <label class="sr-only" for="floor-picker">Choose floor</label>
        <select class="floor-picker" id="floor-picker" aria-label="Choose floor">
          <option selected>Level 1</option>
          <option disabled>Level 2 · Map not available</option>
        </select>
      </div>
      <div class="map-canvas">
        <svg class="floor-plan" viewBox="0 0 560 430" role="img" aria-labelledby="floor-title floor-description">
          <title id="floor-title">Sample floor plan for Cedar Hall Level 1</title>
          <desc id="floor-description">A route runs from the west entrance through the central hallway to ${destination.label}. The map is a sample and may not match your building.</desc>
          <rect class="floor-wall" x="48" y="69" width="464" height="303" rx="2"/>
          <rect class="floor-inner" x="49" y="70" width="130" height="134"/>
          <rect class="floor-inner" x="180" y="70" width="136" height="134"/>
          <rect class="floor-inner" x="317" y="70" width="194" height="134"/>
          <rect class="floor-inner" x="317" y="205" width="194" height="84"/>
          <rect class="floor-inner" x="317" y="290" width="194" height="81"/>
          <rect class="floor-inner" x="49" y="275" width="131" height="96"/>
          <path d="M180 70 V370 M316 70 V371 M48 205 H512 M316 290 H512" fill="none" stroke="var(--ink-soft)" stroke-width="4"/>
          <path d="M48 330 H66 M48 350 H66 M179 102 V136 M316 102 V136 M316 228 V259 M316 312 V345" fill="none" stroke="var(--surface)" stroke-width="7"/>
          <text class="floor-label" x="74" y="133">West entrance</text>
          <text class="floor-sub-label" x="74" y="151">Starting point</text>
          <text class="floor-label" x="214" y="125">Main hall</text>
          <text class="floor-label" x="204" y="311">Study room</text>
          <text class="floor-label" x="352" y="133">${destination.label}</text>
          <text class="floor-sub-label" x="352" y="152">Destination</text>
          <text class="floor-label" x="351" y="241">Restroom</text>
          <text class="floor-label" x="351" y="334">Cafeteria</text>
          <text class="floor-label" x="96" y="308">Lobby</text>
          <path id="route-line" class="route-line ${state.active ? "is-active" : ""}" d="${destination.route}"/>
          <circle class="you-point" cx="91" cy="338" r="10"/>
          <circle class="map-point" cx="${destination.marker.x}" cy="${destination.marker.y}" r="10"/>
        </svg>
      </div>
      <div class="map-legend" aria-label="Map legend">
        <span class="legend-item"><span class="you-point legend-swatch" aria-hidden="true"></span>Your starting point</span>
        <span class="legend-item"><span class="legend-route" aria-hidden="true"></span>Suggested route</span>
        <span class="legend-item"><span class="legend-swatch" aria-hidden="true"></span>Destination</span>
      </div>
      <p class="map-note">Illustrative sample map only. Always follow spoken directions and use your usual mobility aids.</p>
    </section>`;
}

function renderNavigation() {
  const destination = selectedDestination();
  const currentStep = destination.steps[state.step];
  const stepCount = destination.steps.length;
  const progress = state.active ? Math.round(((state.step + 1) / stepCount) * 100) : 0;
  return `
    <div class="page-intro">
      <h1>Where would you like to go?</h1>
      <p>Choose a destination. BlindSpot will guide you with spoken directions you can replay at any time.</p>
    </div>
    <div class="navigation-layout" id="gesture-surface" role="group" aria-label="Navigation controls. Swipe left for the next direction or right to repeat." tabindex="0">
      <section class="panel route-panel" aria-labelledby="route-title">
        <h2 class="panel-heading" id="route-title">Plan a route</h2>
        <label class="field-label" for="start-location">Starting point</label>
        <div class="location-field" id="start-location"><span>West entrance</span><span class="field-dot" aria-hidden="true"></span></div>
        <label class="field-label" for="destination">Where to?</label>
        <select class="select-field" id="destination">${formatDestinationOptions()}</select>
        <p class="helper-text">Using the sample map for Cedar Hall, Level 1.</p>
        <p class="helper-text route-access-note"><strong>Step-free route.</strong> All sample destinations are on this level. Stairs are not part of these routes.</p>
        <button class="primary-button route-primary" id="start-route" type="button">${state.active ? "Restart directions" : "Start directions"} <span aria-hidden="true">→</span></button>
        <div class="route-state ${state.active || state.completed ? "active" : ""}" aria-label="Current direction">
          <p class="state-label">${state.completed ? "Route complete" : state.active ? (state.paused ? "Guidance paused" : `Direction ${state.step + 1} of ${stepCount}`) : "Ready when you are"}</p>
          <p class="instruction" id="current-instruction">${state.completed ? `You have arrived at ${destination.label}.` : state.active ? currentStep : "Your next step will be spoken aloud."}</p>
          <p class="instruction-meta">${state.active ? `${destination.duration} · ${destination.distance}` : state.completed ? "Directions have ended." : "Audio begins only when you start a route."}</p>
          ${state.active ? `<div class="progress-wrap"><div class="progress-label"><span>Route progress</span><span>${progress}%</span></div><div class="progress-track" role="progressbar" aria-label="Route progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${progress}"><div class="progress-fill" style="width:${progress}%"></div></div></div>` : ""}
        </div>
        ${state.active ? `
          <div class="route-controls" aria-label="Guidance controls">
            <button class="secondary-button" id="repeat-direction" type="button" aria-label="Repeat current direction">↺ <span>Repeat</span></button>
            <button class="secondary-button" id="pause-route" type="button">${state.paused ? "▶ Resume" : "Ⅱ Pause"}</button>
            <button class="secondary-button" id="next-direction" type="button">Next direction <span aria-hidden="true">→</span></button>
            <button class="secondary-button" id="end-route" type="button">End directions</button>
          </div>
          <button class="hazard-preview" id="hazard-preview" type="button"><span aria-hidden="true">!</span> Preview an obstacle alert</button>
          ${state.hazard ? `<div class="hazard-state" role="status">Sample alert: obstacle detected ahead. Stop and wait for a clear path. This browser demo does not use live LiDAR.</div>` : ""}
          <p class="route-disclaimer">Sample directions only. Live location, obstacle detection and route accuracy require a supported iPhone and a mapped space.</p>
        ` : ""}
      </section>
      ${renderMap()}
    </div>
    <div class="below-grid">
      <section class="panel landmark-panel" aria-labelledby="landmarks-title">
        <h2 id="landmarks-title">Landmarks along this sample route</h2>
        <ul class="landmark-list">
          <li class="landmark-item"><strong>Drinking fountain</strong><span>Left side of main hall</span></li>
          <li class="landmark-item"><strong>Study room</strong><span>Across from the corridor</span></li>
          <li class="landmark-item"><strong>${destination.label}</strong><span>${destination.accessible ? "Step-free entrance" : "Entrance on this level"}</span></li>
        </ul>
      </section>
      <section class="panel audio-panel" aria-labelledby="audio-title">
        <h2 id="audio-title">Audio guidance</h2>
        <div class="audio-row">
          <div class="audio-copy"><strong>Spoken directions</strong><span>Uses the voice available on this device.</span></div>
          <button class="toggle" type="button" role="switch" aria-checked="${state.settings.speech}" aria-label="Spoken directions" data-setting="speech"></button>
        </div>
        <button class="text-link" id="open-settings" type="button">Adjust accessibility settings</button>
      </section>
    </div>`;
}

function renderSpaces() {
  return `
    <div class="page-intro">
      <h1>Spaces you can navigate</h1>
      <p>Choose a mapped place. Maps in this demo are stored locally and clearly marked as samples.</p>
    </div>
    <div class="content-grid">
      <article class="panel space-card">
        <div class="space-card-top"><h2>Cedar Hall</h2><span class="tag">Sample map</span></div>
        <p>Level 1 · West entrance, main hall, study room, accessible restroom, elevator and cafeteria.</p>
        <button class="secondary-button" type="button" data-open-space="navigate">Navigate Cedar Hall</button>
      </article>
      <article class="panel space-card">
        <div class="space-card-top"><h2>Add a mapped space</h2><span class="tag">iPhone required</span></div>
        <p>Indoor capture needs a LiDAR-capable iPhone and a native mapper. This web demo cannot scan a building.</p>
        <a class="secondary-button" href="https://github.com/mukundgaur/gnarly" target="_blank" rel="noreferrer">View the Gnarly foundation</a>
      </article>
    </div>
    <section class="panel notice-panel">
      <h2>How mapping works</h2>
      <p>BlindSpot is designed around the same spatial workflow as Gnarly: capture indoor geometry and landmarks on-device, store routes as ordered spatial waypoints, then use the map for navigation. This prototype demonstrates the accessible guidance interface with sample data. It does not perform RoomPlan capture, ARKit relocalization, live LiDAR obstacle detection or ElevenLabs synthesis.</p>
    </section>`;
}

function renderSettings() {
  return `
    <div class="page-intro">
      <h1>Make guidance work for you</h1>
      <p>These controls are available before and during a route. Your choices are saved on this device.</p>
    </div>
    <section class="panel route-panel" aria-label="Accessibility preferences">
      <div class="settings-list">
        <div class="setting-row"><div class="setting-copy"><strong>Spoken directions</strong><span>Read each turn aloud using a voice installed on this device.</span></div><button class="toggle" type="button" role="switch" aria-checked="${state.settings.speech}" aria-label="Spoken directions" data-setting="speech"></button></div>
        <div class="setting-row"><div class="setting-copy"><strong>Haptic cues</strong><span>Use short vibration patterns for turns and route events when supported.</span></div><button class="toggle" type="button" role="switch" aria-checked="${state.settings.haptics}" aria-label="Haptic cues" data-setting="haptics"></button></div>
        <div class="setting-row"><div class="setting-copy"><strong>Larger text</strong><span>Increase the size of directions, labels and supporting information.</span></div><button class="toggle" type="button" role="switch" aria-checked="${state.settings.largeText}" aria-label="Larger text" data-setting="largeText"></button></div>
        <div class="setting-row"><div class="setting-copy"><strong>High contrast</strong><span>Use stronger text and boundary contrast throughout the interface.</span></div><button class="toggle" type="button" role="switch" aria-checked="${state.settings.contrast}" aria-label="High contrast" data-setting="contrast"></button></div>
        <div class="setting-row"><div class="setting-copy"><strong>Navigation voice</strong><span>Choose a voice installed by your device. Voice availability depends on your browser.</span></div><label class="sr-only" for="voice-picker">Navigation voice</label><select class="select-setting" id="voice-picker"><option value="">Device default</option>${voices.map((voice) => `<option value="${escapeHtml(voice.voiceURI)}" ${state.settings.voice === voice.voiceURI ? "selected" : ""}>${escapeHtml(voice.name)}${voice.lang ? ` (${escapeHtml(voice.lang)})` : ""}</option>`).join("")}</select></div>
      </div>
      <div class="notice-panel">
        <h2>About audio in this prototype</h2>
        <p>Spoken cues use your browser's built-in speech engine. ElevenLabs voice synthesis is not connected in this demo. No microphone or location permission is requested.</p>
      </div>
    </section>`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[character]);
}

function render() {
  applySettings();
  const focusedElement = document.activeElement instanceof HTMLElement && main.contains(document.activeElement)
    ? { id: document.activeElement.id, setting: document.activeElement.dataset.setting }
    : null;
  const pages = { navigate: renderNavigation, spaces: renderSpaces, settings: renderSettings };
  main.innerHTML = pages[state.page]();
  document.querySelectorAll(".nav-link").forEach((button) => {
    const current = button.dataset.page === state.page;
    button.classList.toggle("is-active", current);
    if (current) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });
  bindPageEvents();
  if (focusedElement) {
    const replacement = focusedElement.id
      ? document.getElementById(focusedElement.id)
      : main.querySelector(`[data-setting="${focusedElement.setting}"]`);
    replacement?.focus({ preventScroll: true });
  }
}

function setPage(page) {
  state.page = page;
  render();
  main.focus({ preventScroll: true });
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function beginRoute() {
  state.active = true;
  state.completed = false;
  state.paused = false;
  state.step = 0;
  state.hazard = false;
  render();
  speak(selectedDestination().steps[state.step]);
  vibrate([45, 35, 45]);
  announce(`Directions started. ${selectedDestination().steps[state.step]}`);
}

function repeatDirection() {
  if (!state.active) return;
  const message = selectedDestination().steps[state.step];
  speak(message);
  vibrate([35]);
  announce(`Repeating direction ${state.step + 1}.`);
}

function nextDirection() {
  if (!state.active) return;
  const steps = selectedDestination().steps;
  if (state.step < steps.length - 1) {
    state.step += 1;
    state.hazard = false;
    render();
    speak(steps[state.step]);
    vibrate([45, 35, 45]);
    announce(`Direction ${state.step + 1} of ${steps.length}. ${steps[state.step]}`);
  } else {
    state.active = false;
    state.completed = true;
    state.hazard = false;
    if ("speechSynthesis" in window) window.speechSynthesis.cancel();
    render();
    speak(`You have arrived at ${selectedDestination().label}.`);
    vibrate([50, 60, 150]);
  }
}

function togglePause() {
  if (!state.active) return;
  state.paused = !state.paused;
  if (state.paused && "speechSynthesis" in window) window.speechSynthesis.cancel();
  render();
  announce(state.paused ? "Guidance paused." : "Guidance resumed.");
  if (!state.paused) speak(selectedDestination().steps[state.step]);
  vibrate([35]);
}

function previewHazard() {
  state.hazard = true;
  render();
  const message = "Sample obstacle alert. Stop and wait. An obstacle is ahead on your right. This browser demo does not use live LiDAR.";
  speak(message, true);
  vibrate([180, 80, 180]);
}

function bindPageEvents() {
  main.querySelector("#destination")?.addEventListener("change", (event) => {
    state.destination = event.target.value;
    state.step = 0;
    state.active = false;
    state.completed = false;
    state.hazard = false;
    if ("speechSynthesis" in window) window.speechSynthesis.cancel();
    render();
    announce(`Destination changed to ${selectedDestination().label}.`);
  });
  main.querySelector("#start-route")?.addEventListener("click", beginRoute);
  main.querySelector("#repeat-direction")?.addEventListener("click", repeatDirection);
  main.querySelector("#next-direction")?.addEventListener("click", nextDirection);
  main.querySelector("#pause-route")?.addEventListener("click", togglePause);
  main.querySelector("#end-route")?.addEventListener("click", () => {
    state.active = false;
    state.completed = false;
    state.paused = false;
    state.hazard = false;
    if ("speechSynthesis" in window) window.speechSynthesis.cancel();
    render();
    announce("Directions ended.");
  });
  main.querySelector("#hazard-preview")?.addEventListener("click", previewHazard);
  main.querySelector("#open-settings")?.addEventListener("click", () => setPage("settings"));
  main.querySelectorAll("[data-setting]").forEach((button) => {
    button.addEventListener("click", () => {
      const key = button.dataset.setting;
      saveSetting(key, !state.settings[key]);
      const messages = {
        speech: `Spoken directions ${state.settings.speech ? "on" : "off"}.`,
        haptics: `Haptic cues ${state.settings.haptics ? "on" : "off"}.`,
        largeText: `Larger text ${state.settings.largeText ? "on" : "off"}.`,
        contrast: `High contrast ${state.settings.contrast ? "on" : "off"}.`
      };
      announce(messages[key]);
      render();
    });
  });
  main.querySelector("#voice-picker")?.addEventListener("change", (event) => {
    state.settings.voice = event.target.value;
    saveSetting("voice", event.target.value);
    announce("Navigation voice preference updated.");
  });
  main.querySelector('[data-open-space="navigate"]')?.addEventListener("click", () => setPage("navigate"));

  const gestureSurface = main.querySelector("#gesture-surface");
  gestureSurface?.addEventListener("touchstart", (event) => {
    lastTouchX = event.changedTouches[0]?.clientX ?? null;
  }, { passive: true });
  gestureSurface?.addEventListener("touchend", (event) => {
    if (lastTouchX === null || !state.active) return;
    const delta = event.changedTouches[0].clientX - lastTouchX;
    if (Math.abs(delta) > 70) {
      if (delta < 0) nextDirection();
      else repeatDirection();
    }
    lastTouchX = null;
  }, { passive: true });
}

document.querySelectorAll(".nav-link").forEach((button) => {
  button.addEventListener("click", () => setPage(button.dataset.page));
});
document.querySelector("#focus-toggle").addEventListener("click", (event) => {
  state.focus = !state.focus;
  document.body.classList.toggle("focus-mode", state.focus);
  const button = event.currentTarget;
  button.setAttribute("aria-pressed", String(state.focus));
  button.setAttribute("aria-label", state.focus ? "Exit eyes-free focus mode" : "Enter eyes-free focus mode");
  button.querySelector(".focus-button-label").textContent = state.focus ? "Exit focus" : "Focus mode";
  announce(state.focus ? "Eyes-free focus mode on. Swipe left for the next direction or right to repeat." : "Eyes-free focus mode off.");
});
document.addEventListener("keydown", (event) => {
  if (!state.active || event.altKey || event.ctrlKey || event.metaKey || /INPUT|SELECT|TEXTAREA|BUTTON/.test(document.activeElement.tagName)) return;
  if (event.key === "ArrowRight") { event.preventDefault(); nextDirection(); }
  if (event.key === "ArrowLeft") { event.preventDefault(); repeatDirection(); }
  if (event.key === "Escape" && state.focus) document.querySelector("#focus-toggle").click();
});

if ("speechSynthesis" in window) {
  voices = window.speechSynthesis.getVoices();
  window.speechSynthesis.addEventListener("voiceschanged", () => {
    voices = window.speechSynthesis.getVoices();
    if (state.page === "settings") render();
  });
}
applySettings();
render();
