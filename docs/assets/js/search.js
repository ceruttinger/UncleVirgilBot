(function () {
  const indexUrl = "data/public/search_index.json";
  let chunks = [];

  function tokenize(text) {
    return (text || "")
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, " ")
      .split(/\s+/)
      .filter(t => t.length > 2);
  }

  function scoreChunk(chunk, queryTokens) {
    const haystack = `${chunk.chapter_title} ${chunk.text}`.toLowerCase();
    let score = 0;
    queryTokens.forEach(token => {
      const hits = haystack.split(token).length - 1;
      score += hits;
      if ((chunk.chapter_title || "").toLowerCase().includes(token)) score += 5;
    });
    return score;
  }

  function renderResults(results, query) {
    const container = document.getElementById("uv-search-results");
    const status = document.getElementById("uv-search-status");
    if (!container) return;

    if (!query.trim()) {
      status.textContent = "Enter a search term.";
      container.innerHTML = "";
      return;
    }

    if (results.length === 0) {
      status.textContent = `No results found for “${query}”.`;
      container.innerHTML = "";
      return;
    }

    status.textContent = `Showing ${results.length} result(s) for “${query}”.`;
    container.innerHTML = results.map(r => `
      <div class="result-card">
        <h3>Chapter ${r.chapter}: ${r.chapter_title}</h3>
        <div class="muted">Score: ${r.score}</div>
        <p class="excerpt">${escapeHtml(r.excerpt)}</p>
      </div>
    `).join("");
  }

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.innerText = text || "";
    return div.innerHTML;
  }

  function runSearch() {
    const input = document.getElementById("uv-search");
    const query = input ? input.value : "";
    const qTokens = tokenize(query);
    const results = chunks
      .map(c => ({ ...c, score: scoreChunk(c, qTokens) }))
      .filter(c => c.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 10);
    renderResults(results, query);
  }

  fetch(indexUrl)
    .then(r => r.json())
    .then(data => {
      chunks = data;
      const status = document.getElementById("uv-search-status");
      if (status) status.textContent = `Loaded ${chunks.length} searchable memoir passages.`;
    })
    .catch(err => {
      const status = document.getElementById("uv-search-status");
      if (status) status.textContent = `Could not load search index: ${err.message}`;
    });

  document.addEventListener("DOMContentLoaded", () => {
    const button = document.getElementById("uv-search-button");
    const input = document.getElementById("uv-search");
    if (button) button.addEventListener("click", runSearch);
    if (input) input.addEventListener("keydown", e => {
      if (e.key === "Enter") runSearch();
    });
  });
})();
