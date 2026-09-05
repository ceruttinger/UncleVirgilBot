(function () {
  'use strict';

  const TOPICS = {
    cia: {
      label: 'CIA / Cold War',
      suggestions: [
        'Central Intelligence Agency',
        'CIA Soviet Union',
        'State Department',
        'Clandestine Services',
        'Soviet Embassy',
        'Strategic Services'
      ]
    },
    family: {
      label: 'Family',
      suggestions: [
        'Marion',
        'Richard',
        'Martin',
        'Loverna',
        'Ila Rose',
        'Children'
      ]
    },
    places: {
      label: 'Places',
      suggestions: [
        'Idaho Falls',
        'Idaho Falls childhood',
        'Idaho',
        'Salt Lake City',
        'Washington',
        'McLean Virginia',
        'New York',
        'Rio De Janeiro',
        'Montevideo Uruguay'
      ]
    },
    wwii: {
      label: 'World War II',
      suggestions: [
        'World War II',
        'USS Wasp',
        'Pearl Harbor',
        'U.S. Navy',
        'Philippine Islands',
        'South China Sea'
      ]
    },
    'south-america': {
      label: 'South America posts',
      suggestions: [
        'Rio De Janeiro',
        'Montevideo Uruguay',
        'American Embassy',
        'Brazil post',
        'Uruguay post',
        'Foreign Service South America'
      ]
    },
    college: {
      label: 'College years',
      suggestions: [
        'Brigham Young University',
        'Columbia University',
        'BYU college years',
        'Salt Lake City college',
        'International Affairs'
      ]
    }
  };

  let passages = [];
  let activeTopic = null;

  function $(id) {
    return document.getElementById(id);
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function normalizeText(value) {
    return String(value ?? '')
      .toLowerCase()
      .replace(/[\u2018\u2019]/g, "'")
      .replace(/[\u201c\u201d]/g, '"')
      .replace(/[^a-z0-9]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function splitList(value) {
    if (Array.isArray(value)) {
      return value.map(String).map(x => x.trim()).filter(Boolean);
    }
    if (value === null || value === undefined) return [];
    const text = String(value).trim();
    if (!text || text.toLowerCase() === 'na') return [];
    return text
      .split(/\s*;\s*|\s*\|\s*|\s*,\s*/)
      .map(x => x.replace(/\s+/g, ' ').trim())
      .filter(Boolean);
  }

  function unique(values) {
    return Array.from(new Set(values.filter(Boolean)));
  }

  function getPassageText(p) {
    return String(p.text || p.passage_text || p.chunk_text || p.excerpt || '');
  }

  function getCitation(p) {
    if (p.citation_label) return String(p.citation_label);
    const chapter = p.chapter || p.chapter_number || '';
    const title = p.chapter_title || '';
    const passageNum = p.passage_number || p.passage || '';
    if (chapter && title && passageNum) return `Ch. ${chapter}: ${title}, passage ${passageNum}`;
    if (chapter && title) return `Ch. ${chapter}: ${title}`;
    return p.passage_id || 'Passage';
  }

  function getPassageId(p) {
    return String(p.passage_id || p.chunk_id || '').trim();
  }

  function getEntities(p) {
    return unique(splitList(p.entities_mentioned || p.entities || p.top_entities || p.entity_list));
  }

  function getYears(p) {
    return unique(splitList(p.year_candidates || p.years || p.dates).filter(x => /^\d{4}$/.test(x)));
  }

  function buildSearchBlob(p) {
    return normalizeText([
      getCitation(p),
      getPassageId(p),
      getPassageText(p),
      getEntities(p).join(' '),
      getYears(p).join(' '),
      p.chapter_title || '',
      p.chapter || ''
    ].join(' '));
  }

  function scorePassage(p, query) {
    const q = normalizeText(query);
    if (!q) return 0;

    const blob = buildSearchBlob(p);
    const terms = unique(q.split(' ').filter(term => term.length > 1));
    let score = 0;

    if (blob.includes(q)) score += 12;

    for (const term of terms) {
      const re = new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'g');
      const matches = blob.match(re);
      if (matches) score += matches.length * 3;
    }

    const entityBlob = normalizeText(getEntities(p).join(' '));
    if (entityBlob.includes(q)) score += 10;
    for (const term of terms) {
      if (entityBlob.includes(term)) score += 4;
    }

    const yearBlob = getYears(p).join(' ');
    for (const term of terms) {
      if (/^\d{4}$/.test(term) && yearBlob.includes(term)) score += 8;
    }

    return score;
  }

  function truncateText(text, limit) {
    const clean = String(text || '').replace(/\s+/g, ' ').trim();
    if (clean.length <= limit) return clean;
    return clean.slice(0, limit).replace(/\s+\S*$/, '') + '...';
  }

  function chips(values, emptyText) {
    const clean = unique(values).slice(0, 12);
    if (!clean.length) return `<span class="uvbot-muted">${escapeHtml(emptyText || 'None detected')}</span>`;
    return clean.map(value => `<span class="uvbot-chip">${escapeHtml(value)}</span>`).join('');
  }

  function setStatus(query, count) {
    const status = $('uvbot-result-status');
    if (!status) return;
    const indexText = passages.length ? `${passages.length} citation-ready passages` : 'Loading passage index...';
    status.innerHTML = `
      <div class="uvbot-stat-card"><span class="uvbot-stat-label">Search</span><strong class="uvbot-stat-value">${escapeHtml(query || 'None yet')}</strong></div>
      <div class="uvbot-stat-card"><span class="uvbot-stat-label">Matches</span><strong class="uvbot-stat-value">${Number(count || 0)}</strong></div>
      <div class="uvbot-stat-card"><span class="uvbot-stat-label">Index</span><strong class="uvbot-stat-value">${escapeHtml(indexText)}</strong></div>
      <div class="uvbot-stat-card"><span class="uvbot-stat-label">Reminder</span><strong class="uvbot-stat-value">Suggestions are editable before search.</strong></div>
    `;
  }

  function renderResults(matches, query) {
    const results = $('uvbot-results');
    if (!results) return;

    if (!query) {
      results.innerHTML = '';
      setStatus('', 0);
      return;
    }

    setStatus(query, matches.length);

    if (!matches.length) {
      results.innerHTML = `
        <div class="uvbot-empty">
          <strong>No passage matches yet.</strong>
          <p>Try a broader search, a person name, a place, a year, or one of the suggested search buttons.</p>
        </div>
      `;
      return;
    }

    results.innerHTML = matches.slice(0, 8).map((item, index) => {
      const p = item.passage;
      const citation = getCitation(p);
      const id = getPassageId(p);
      const text = truncateText(getPassageText(p), 900);
      const entities = getEntities(p);
      const years = getYears(p);

      return `
        <article class="uvbot-result-card">
          <div class="uvbot-result-heading">
            <h3>${index + 1}. ${escapeHtml(citation)}</h3>
            <span class="uvbot-score">score ${item.score}</span>
          </div>
          ${id ? `<div class="uvbot-passage-id">${escapeHtml(id)}</div>` : ''}
          <p class="uvbot-passage-text">${escapeHtml(text)}</p>
          <div class="uvbot-result-meta">
            <div class="uvbot-meta-row">
              <span class="uvbot-meta-label">Entities</span>
              <div class="uvbot-chip-list">${chips(entities, 'No entities detected')}</div>
            </div>
            <div class="uvbot-meta-row">
              <span class="uvbot-meta-label">Years</span>
              <div class="uvbot-chip-list">${chips(years, 'No years detected')}</div>
            </div>
          </div>
        </article>
      `;
    }).join('');
  }

  function runSearch() {
    const input = $('uvbot-question');
    const query = input ? input.value.trim() : '';
    if (!query) {
      renderResults([], '');
      if (input) input.focus();
      return;
    }

    const matches = passages
      .map(p => ({ passage: p, score: scorePassage(p, query) }))
      .filter(x => x.score > 0)
      .sort((a, b) => b.score - a.score || getCitation(a.passage).localeCompare(getCitation(b.passage)));

    renderResults(matches, query);
  }

  function renderSuggestions(topicKey) {
    const box = $('uvbot-suggestions');
    if (!box) return;
    const topic = TOPICS[topicKey];
    if (!topic) {
      box.hidden = true;
      box.innerHTML = '';
      return;
    }

    activeTopic = topicKey;
    document.querySelectorAll('.uvbot-topic-button').forEach(btn => {
      btn.classList.toggle('is-active', btn.dataset.topic === topicKey);
    });

    box.hidden = false;
    box.innerHTML = `
      <div class="uvbot-suggestion-title">${escapeHtml(topic.label)}: suggested searches</div>
      <div class="uvbot-suggestion-row">
        ${topic.suggestions.map(query => `
          <button type="button" class="uvbot-suggestion-button" data-query="${escapeHtml(query)}">${escapeHtml(query)}</button>
        `).join('')}
      </div>
      <p class="uvbot-suggestion-note">Click a suggestion to place it in the search box. You can edit the wording before searching.</p>
    `;
  }

  function clearSearch() {
    const input = $('uvbot-question');
    if (input) {
      input.value = '';
      input.focus();
    }
    renderResults([], '');
  }

  function bindEvents() {
    document.addEventListener('click', function (event) {
      const topicButton = event.target.closest('.uvbot-topic-button');
      if (topicButton) {
        event.preventDefault();
        renderSuggestions(topicButton.dataset.topic);
        return;
      }

      const suggestionButton = event.target.closest('.uvbot-suggestion-button');
      if (suggestionButton) {
        event.preventDefault();
        const input = $('uvbot-question');
        if (input) {
          input.value = suggestionButton.dataset.query || suggestionButton.textContent.trim();
          input.focus();
          input.select();
        }
        return;
      }

      if (event.target.closest('#uvbot-search')) {
        event.preventDefault();
        runSearch();
        return;
      }

      if (event.target.closest('#uvbot-clear')) {
        event.preventDefault();
        clearSearch();
      }
    });

    const input = $('uvbot-question');
    if (input) {
      input.addEventListener('keydown', function (event) {
        if (event.key === 'Enter') {
          event.preventDefault();
          runSearch();
        }
      });
    }
  }

  async function loadPassages() {
    try {
      const response = await fetch('data/public/passage_index.json', { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      passages = Array.isArray(data) ? data : (data.passages || data.data || []);
      setStatus('', 0);
    } catch (error) {
      const status = $('uvbot-result-status');
      if (status) {
        status.innerHTML = `
          <div class="uvbot-stat-card uvbot-stat-error">
            <span class="uvbot-stat-label">Error</span>
            <strong class="uvbot-stat-value">Could not load data/public/passage_index.json</strong>
          </div>
        `;
      }
      console.error('Uncle Virgil Bot failed to load passage index:', error);
    }
  }

  function init() {
    if (!$('uvbot-page')) return;
    bindEvents();
    loadPassages();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
