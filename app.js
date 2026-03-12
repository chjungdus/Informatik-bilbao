/* =========================================================
   IDEA LAB – app.js
   Struktur:
   1. Konstanten & DOM-Referenzen
   2. State-Management (Laden / Speichern aus LocalStorage)
   3. Render-Funktionen
   4. Idee hinzufügen (Formular)
   5. Aktionen: Upvoten | Als erledigt markieren | Löschen
   6. Filter & Sortierung
   7. Dark-Mode-Toggle
   8. Hilfsfunktionen (Toast, Datum)
   9. Initialisierung
   ========================================================= */

/* ---------------------------------------------------------
   1. KONSTANTEN & DOM-REFERENZEN
   --------------------------------------------------------- */
const STORAGE_KEY = 'ideaLab_ideas_v1';

// Formular
const ideaForm        = document.getElementById('idea-form');
const titleInput      = document.getElementById('idea-title');
const descInput       = document.getElementById('idea-desc');
const categoryInput   = document.getElementById('idea-category');
const descCounter     = document.getElementById('desc-counter');

// Fehlerfelder
const titleError    = document.getElementById('title-error');
const descError     = document.getElementById('desc-error');
const categoryError = document.getElementById('category-error');

// Steuerleiste
const filterCategory = document.getElementById('filter-category');
const sortOrder      = document.getElementById('sort-order');
const ideaCountEl    = document.getElementById('idea-count');

// Ausgabe
const ideasContainer = document.getElementById('ideas-container');
const emptyState     = document.getElementById('empty-state');

// Dark-Mode
const themeToggle = document.getElementById('theme-toggle');
const themeIcon   = document.getElementById('theme-icon');

// Toast
const toast = document.getElementById('toast');


/* ---------------------------------------------------------
   2. STATE-MANAGEMENT
   --------------------------------------------------------- */

/**
 * Lädt alle gespeicherten Ideen aus dem LocalStorage.
 * @returns {Array} Array von Ideen-Objekten
 */
function loadIdeas() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  } catch {
    return [];
  }
}

/**
 * Speichert das übergebene Array im LocalStorage.
 * @param {Array} ideas - Array von Ideen-Objekten
 */
function saveIdeas(ideas) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(ideas));
}

/**
 * Gibt die aktuell angezeigten (gefilterten + sortierten) Ideen zurück.
 * @returns {Array}
 */
function getFilteredAndSorted() {
  const all      = loadIdeas();
  const category = filterCategory.value;
  const sort     = sortOrder.value;

  // --- Filtern ---
  const filtered = category === 'all'
    ? all
    : all.filter(idea => idea.category === category);

  // --- Sortieren ---
  const sorted = [...filtered].sort((a, b) => {
    if (sort === 'popular') return b.votes - a.votes;
    if (sort === 'oldest')  return a.timestamp - b.timestamp;
    return b.timestamp - a.timestamp; // 'newest' (default)
  });

  return sorted;
}


/* ---------------------------------------------------------
   3. RENDER-FUNKTIONEN
   --------------------------------------------------------- */

/**
 * Hauptfunktion: Rendert alle sichtbaren Ideen-Karten neu.
 */
function renderIdeas() {
  const ideas = getFilteredAndSorted();

  ideasContainer.innerHTML = '';

  // Leerer Zustand anzeigen oder verstecken
  if (ideas.length === 0) {
    emptyState.hidden = false;
  } else {
    emptyState.hidden = true;
    ideas.forEach(idea => {
      ideasContainer.appendChild(createCard(idea));
    });
  }

  // Anzahl aktualisieren
  const total = loadIdeas().length;
  const shown = ideas.length;
  ideaCountEl.textContent = shown === total
    ? `${total} Idee${total !== 1 ? 'n' : ''}`
    : `${shown} von ${total} Idee${total !== 1 ? 'n' : ''}`;
}

/**
 * Erstellt ein DOM-Element für eine einzelne Ideen-Karte.
 * @param {Object} idea - Ideen-Objekt
 * @returns {HTMLElement}
 */
function createCard(idea) {
  const card = document.createElement('article');
  card.className = `idea-card${idea.done ? ' idea-card--done' : ''}`;
  card.dataset.id = idea.id;

  card.innerHTML = `
    <div class="idea-card__header">
      <h3 class="idea-card__title">${escapeHtml(idea.title)}</h3>
      <span class="badge">${escapeHtml(idea.category)}</span>
    </div>

    <p class="idea-card__desc">${escapeHtml(idea.description)}</p>

    <p class="idea-card__date">
      📅 ${formatDate(idea.timestamp)}
      ${idea.done ? ' · <strong style="color:var(--clr-success)">✔ Umgesetzt</strong>' : ''}
    </p>

    <div class="idea-card__actions">
      <button
        class="btn btn--vote"
        data-action="vote"
        aria-label="Upvoten"
        title="Upvoten"
      >
        👍 <span class="vote-count">${idea.votes}</span>
      </button>

      <button
        class="btn btn--done"
        data-action="done"
        aria-label="${idea.done ? 'Als offen markieren' : 'Als umgesetzt markieren'}"
        title="${idea.done ? 'Als offen markieren' : 'Als umgesetzt markieren'}"
      >
        ${idea.done ? '↩ Offen' : '✔ Umgesetzt'}
      </button>

      <button
        class="btn btn--delete"
        data-action="delete"
        aria-label="Idee löschen"
        title="Idee löschen"
      >
        🗑
      </button>
    </div>
  `;

  // Event-Delegation: alle Aktions-Buttons der Karte
  card.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', () => handleCardAction(btn.dataset.action, idea.id));
  });

  return card;
}


/* ---------------------------------------------------------
   4. IDEE HINZUFÜGEN (FORMULAR)
   --------------------------------------------------------- */

/**
 * Zeichenlängen-Anzeige für das Beschreibungsfeld.
 */
descInput.addEventListener('input', () => {
  descCounter.textContent = `${descInput.value.length} / 300`;
});

/**
 * Formular-Abgabe: Validierung + Idee speichern.
 */
ideaForm.addEventListener('submit', event => {
  event.preventDefault();

  // Felder leeren & neu validieren
  clearErrors();

  const title    = titleInput.value.trim();
  const desc     = descInput.value.trim();
  const category = categoryInput.value;

  let valid = true;

  if (!title) {
    showError(titleInput, titleError, 'Bitte gib einen Titel ein.');
    valid = false;
  }
  if (!desc) {
    showError(descInput, descError, 'Bitte gib eine Beschreibung ein.');
    valid = false;
  }
  if (!category) {
    showError(categoryInput, categoryError, 'Bitte wähle eine Kategorie.');
    valid = false;
  }

  if (!valid) return;

  // Neue Idee anlegen
  const newIdea = {
    id:          Date.now().toString(),   // einfache eindeutige ID
    title,
    description: desc,
    category,
    votes:       0,
    done:        false,
    timestamp:   Date.now(),
  };

  const ideas = loadIdeas();
  ideas.push(newIdea);
  saveIdeas(ideas);

  // Formular zurücksetzen
  ideaForm.reset();
  descCounter.textContent = '0 / 300';

  // Neu rendern & Toast
  renderIdeas();
  showToast('💡 Idee hinzugefügt!');
});


/* ---------------------------------------------------------
   5. AKTIONEN AUF KARTEN
   --------------------------------------------------------- */

/**
 * Verarbeitet Klicks auf Karten-Aktionen (vote | done | delete).
 * @param {string} action - Aktion
 * @param {string} id     - Ideen-ID
 */
function handleCardAction(action, id) {
  const ideas = loadIdeas();
  const index = ideas.findIndex(idea => idea.id === id);
  if (index === -1) return;

  if (action === 'vote') {
    ideas[index].votes += 1;
    showToast('👍 Upvote gezählt!');
  }

  if (action === 'done') {
    ideas[index].done = !ideas[index].done;
    const msg = ideas[index].done ? '✅ Als umgesetzt markiert!' : '↩ Als offen markiert!';
    showToast(msg);
  }

  if (action === 'delete') {
    // Einfache Bestätigung (kann durch Modal ersetzt werden)
    if (!confirm(`Idee „${ideas[index].title}" wirklich löschen?`)) return;
    ideas.splice(index, 1);
    showToast('🗑 Idee gelöscht.');
  }

  saveIdeas(ideas);
  renderIdeas();
}


/* ---------------------------------------------------------
   6. FILTER & SORTIERUNG
   --------------------------------------------------------- */

filterCategory.addEventListener('change', renderIdeas);
sortOrder.addEventListener('change', renderIdeas);


/* ---------------------------------------------------------
   7. DARK-MODE-TOGGLE
   --------------------------------------------------------- */

/**
 * Wechselt zwischen hellem und dunklem Modus.
 * Der gewählte Modus wird im LocalStorage gespeichert.
 */
function applyTheme(isDark) {
  document.body.classList.toggle('dark-mode', isDark);
  document.body.classList.toggle('light-mode', !isDark);
  themeIcon.textContent = isDark ? '☀️' : '🌙';
}

themeToggle.addEventListener('click', () => {
  const isDark = !document.body.classList.contains('dark-mode');
  applyTheme(isDark);
  localStorage.setItem('ideaLab_theme', isDark ? 'dark' : 'light');
});

/** Gespeicherten Modus beim Start laden */
function loadTheme() {
  const saved = localStorage.getItem('ideaLab_theme');
  // Kein gespeicherter Wert → System-Präferenz prüfen
  const prefersDark = saved
    ? saved === 'dark'
    : window.matchMedia('(prefers-color-scheme: dark)').matches;
  applyTheme(prefersDark);
}


/* ---------------------------------------------------------
   8. HILFSFUNKTIONEN
   --------------------------------------------------------- */

/**
 * Zeigt einen kurzen Toast mit einer Nachricht an.
 * @param {string} message
 */
let toastTimer;
function showToast(message) {
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add('show');
  toastTimer = setTimeout(() => toast.classList.remove('show'), 2500);
}

/**
 * Formatiert einen Unix-Timestamp als lesbares Datum.
 * @param {number} timestamp
 * @returns {string}
 */
function formatDate(timestamp) {
  return new Date(timestamp).toLocaleDateString('de-DE', {
    day:   '2-digit',
    month: 'short',
    year:  'numeric',
  });
}

/**
 * Verhindert XSS durch Escapen von HTML-Sonderzeichen.
 * @param {string} str
 * @returns {string}
 */
function escapeHtml(str) {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
  return String(str).replace(/[&<>"']/g, m => map[m]);
}

/**
 * Zeigt eine Fehlermeldung unterhalb eines Formularfeldes an.
 * @param {HTMLElement} field
 * @param {HTMLElement} errorEl
 * @param {string} message
 */
function showError(field, errorEl, message) {
  field.classList.add('invalid');
  errorEl.textContent = message;
}

/**
 * Entfernt alle Fehler-Zustände aus dem Formular.
 */
function clearErrors() {
  [titleInput, descInput, categoryInput].forEach(f => f.classList.remove('invalid'));
  [titleError, descError, categoryError].forEach(e => e.textContent = '');
}

// Fehler-Klasse beim Tippen entfernen
[titleInput, descInput, categoryInput].forEach(field => {
  field.addEventListener('input', () => field.classList.remove('invalid'));
});


/* ---------------------------------------------------------
   9. INITIALISIERUNG
   --------------------------------------------------------- */

/** App starten */
function init() {
  loadTheme();
  renderIdeas();
}

// DOM ist fertig geladen
document.addEventListener('DOMContentLoaded', init);
