(function () {
  const state = {
    passages: [],
    ready: false
  };

  const STOPWORDS = new Set([
    "the", "and", "for", "that", "this", "with", "from", "have", "had", "was", "were",
    "are", "but", "not", "you", "your", "his", "her", "him", "she", "they", "them", "then",
    "than", "there", "their", "what", "when", "where", "which", "who", "whom", "into", "onto",
    "about", "after", "before", "during", "because", "would", "could", "should", "shall", "will",
    "been", "being", "very", "also", "only", "over", "under", "out", "our", "all", "any", "can",
    "did", "does", "done", "get", "got", "one", "two", "three", "four", "five", "six", "seven",
    "eight", "nine", "ten", "chapter", "virgil"
  ]);

  function normalize(text) {
    return String(text || "")
      .toLowerCase()
      .replace(/[\u2018\u2019]/g, "'")
      .replace(/[\u201C\u201D]/g, '"')
      .replace(/[^a-z0-9]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function tokenize(query) {
    return normalize(query)
      .split(" ")
      .filter(Boolean)
      .filter(token => token.length > 2 || /^\d{4}$/.test(token))
      .filter(token => !STOPWORDS.has(token));
  }

  function asText(value) {
    if (Array.isArray(value)) return value.join("; ");
    if (value === null || value === undefined) return "";
    return String(value);
  }

  function splitList(value) {
    const txt = asText(value);
    if (!txt) return [];
    return txt
      .split(/;|,|\|/)
      .map(x => x.trim())
      .filter(Boolean);
  }

  function getCitation(row) {
    if (row.citation_label) return row.citation_label;
    const chapter = row.chapter || "?";
    const title = row.chapter_title || "Untitled chapter";
    const pnum = row.passage_number || row.passage || "?";
    return `Ch. ${chapter}: ${title}, passage ${pnum}`;
  }

  function escapeHtml(text) {
    return String(text || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function snippet(text, terms, length = 520) {
    const raw = String(text || "").replace(/\s+/g, " ").trim();
    if (raw.length <= length) return raw;

    const lower = raw.toLowerCase();
    let bestIndex = -1;
    for (const term of terms) {
      const idx = lower.indexOf(term.toLowerCase());
      if (idx >= 0 && (bestIndex < 0 || idx < bestIndex)) bestIndex = idx;
    }

    if (bestIndex < 0) return raw.slice(0, length).trim() + "...";

    const start = Math.max(0, bestIndex - Math.floor(length / 3));
    const end = Math.min(raw.length, start + length);
    const prefix = start > 0 ? "..." : "";
    const suffix = end < raw.length ? "..." : "";
    return prefix + raw.slice(start, end).trim() + suffix;
  }

  function scorePassage(row, query, terms) {
    const text = asText(row.text);
    const haystack = normalize([
      row.chapter_title,
      row.text,
      row.entities_mentioned,
      row.year_candidates,
      row.citation_label
    ].join(" "));

    if (!terms.length) return 0;

    let score = 0;
    const qNorm = normalize(query);

    if (qNorm.length > 5 && haystack.includes(qNorm)) score += 20;

    for (const term of terms) {
      const re = new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "g");
      const matches = haystack.match(re);
      if (matches) score += matches.length * 2;

      const title = normalize(row.chapter_title);
      if (title.includes(term)) score += 4;

      const entities = normalize(row.entities_mentioned);
      if (entities.includes(term)) score += 5;

      const years = normalize(row.year_candidates);
      if (/^\d{4}$/.test(term) && years.includes(term)) score += 8;
    }

    const wc = Number(row.word_count || 0);
    if (wc > 30 && wc < 450) score += 1;

    return score;
  }

  function search(query, limit) {
    const terms = tokenize(query);
    const scored = state.passages
      .map(row => ({ row, score: scorePassage(row, query, terms) }))
      .filter(x => x.score > 0)
      .sort((a, b) => b.score - a.score || Number(a.row.chapter || 0) - Number(b.row.chapter || 0))
      .slice(0, limit || 8);

    return { terms, results: scored };
  }

  function renderResults(query) {
    const output = document.getElementById("uvbot-output");
    const status = document.getElementById("uvbot-status");
    const limit = Number(document.getElementById("uvbot-limit")?.value || 8);

    if (!output) return;

    if (!state.ready) {
      output.innerHTML = `<div class="uvbot-note">The passage index is still loading. Try again in a second.</div>`;
      return;
    }

    const cleanQuery = String(query || "").trim();
    if (!cleanQuery) {
      output.innerHTML = `<div class="uvbot-note">Type a question or search phrase. Example: <strong>What does Virgil say about the CIA?</strong></div>`;
      return;
    }

    const { terms, results } = search(cleanQuery, limit);

    if (status) {
      status.textContent = `Searched ${state.passages.length} passages using ${terms.length} query terms.`;
    }

    if (!results.length) {
      output.innerHTML = `
        <div class="uvbot-note">
          No strong passage matches found. Try a person, place, organization, year, or shorter phrase.
        </div>
      `;
      return;
    }

    const best = results[0].row;
    const cards = results.map(({ row, score }, idx) => {
      const entities = splitList(row.entities_mentioned).slice(0, 10);
      const years = splitList(row.year_candidates).slice(0, 8);
      const sourcePdf = row.source_pdf ? `<span class="uvbot-pill">Source PDF: ${escapeHtml(row.source_pdf)}</span>` : "";
      const entityPills = entities.map(e => `<span class="uvbot-pill">${escapeHtml(e)}</span>`).join(" ");
      const yearPills = years.map(y => `<span class="uvbot-pill uvbot-year">${escapeHtml(y)}</span>`).join(" ");
      return `
        <article class="uvbot-result">
          <div class="uvbot-result-header">
            <div>
              <h3>${idx + 1}. ${escapeHtml(getCitation(row))}</h3>
              <div class="uvbot-meta">Score ${score} · ${escapeHtml(row.word_count || "?")} words</div>
            </div>
          </div>
          <p class="uvbot-snippet">${escapeHtml(snippet(row.text, terms))}</p>
          <div class="uvbot-pills">${entityPills} ${yearPills} ${sourcePdf}</div>
        </article>
      `;
    }).join("\n");

    output.innerHTML = `
      <section class="uvbot-answer">
        <h2>Retrieval answer</h2>
        <p>This static prototype does not generate prose with an AI model yet. It finds the most relevant citation-ready passages from the memoir index.</p>
        <p><strong>Best match:</strong> ${escapeHtml(getCitation(best))}</p>
      </section>
      <section class="uvbot-results">${cards}</section>
    `;
  }

  async function loadPassages() {
    const output = document.getElementById("uvbot-output");
    const status = document.getElementById("uvbot-status");

    try {
      const response = await fetch("data/public/passage_index.json", { cache: "no-cache" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      state.passages = Array.isArray(data) ? data : [];
      state.ready = true;
      if (status) status.textContent = `Loaded ${state.passages.length} citation-ready passages.`;
      if (output) {
        output.innerHTML = `<div class="uvbot-note">Loaded ${state.passages.length} passages. Ask a question above.</div>`;
      }
    } catch (err) {
      state.ready = false;
      if (status) status.textContent = "Could not load passage index.";
      if (output) {
        output.innerHTML = `
          <div class="uvbot-note uvbot-error">
            Could not load <code>data/public/passage_index.json</code>. Rebuild with <code>Rscript R/render_all.R</code>.
            <br>Error: ${escapeHtml(err.message)}
          </div>
        `;
      }
    }
  }

  function bindEvents() {
    const form = document.getElementById("uvbot-form");
    const input = document.getElementById("uvbot-query");
    const examples = document.querySelectorAll("[data-uvbot-example]");

    if (form && input) {
      form.addEventListener("submit", event => {
        event.preventDefault();
        renderResults(input.value);
      });
    }

    examples.forEach(button => {
      button.addEventListener("click", () => {
        if (!input) return;
        input.value = button.getAttribute("data-uvbot-example") || "";
        renderResults(input.value);
      });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    bindEvents();
    loadPassages();
  });
})();
