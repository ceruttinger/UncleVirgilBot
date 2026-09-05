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

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.innerText = text || "";
    return div.innerHTML;
  }

  async function askBackend(question, sources) {
    const url = window.UNCLE_VIRGILBOT_API_ENDPOINT || window.UNCLE_VIRGIL_API_URL || "";
    if (!url) return null;
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question, limit: 5 })
    });
    if (!response.ok) throw new Error(`API returned ${response.status}`);
    return await response.json();
  }

  function localAnswer(question, sources) {
    if (sources.length === 0) {
      return "I could not find a strong match in the memoir text. Try a person, place, organization, or event name.";
    }
    const chapters = [...new Set(sources.map(s => `Chapter ${s.chapter}: ${s.chapter_title}`))];
    return `I found relevant passages in ${chapters.join("; ")}. The local-only version does not yet synthesize a full AI answer, but the source passages below are ready to send to the future AWS/model endpoint.`;
  }

  async function runChat() {
    const input = document.getElementById("uv-chat-input");
    const question = input ? input.value.trim() : "";
    const status = document.getElementById("uv-chat-status");
    const answer = document.getElementById("uv-chat-answer");
    const sourceDiv = document.getElementById("uv-chat-sources");
    if (!question) {
      status.textContent = "Ask a question first.";
      return;
    }

    const qTokens = tokenize(question);
    const sources = chunks
      .map(c => ({ ...c, score: scoreChunk(c, qTokens) }))
      .filter(c => c.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 5);

    status.textContent = "Searching memoir passages...";
    let response = null;
    try {
      response = await askBackend(question, sources);
    } catch (err) {
      status.textContent = `Backend unavailable; using local retrieval. ${err.message}`;
    }

    const answerText = response && response.answer ? response.answer : localAnswer(question, sources);
    const responseSources = response && response.citations ? response.citations : sources;
    answer.innerHTML = `<h2>Answer</h2><p>${escapeHtml(answerText)}</p>`;
    sourceDiv.innerHTML = `<h2>Sources</h2>` + responseSources.map(s => `
      <div class="source-card">
        <h3>${escapeHtml(s.source_label || `Chapter ${s.chapter}: ${s.chapter_title}`)}</h3>
        <div class="muted">${escapeHtml(s.id || "")}; score ${escapeHtml(String(s.score || ""))}</div>
        <p class="excerpt">${escapeHtml(s.excerpt)}</p>
      </div>
    `).join("");
    if (!status.textContent.includes("Backend")) status.textContent = `Retrieved ${sources.length} source passage(s).`;
  }

  fetch(indexUrl)
    .then(r => r.json())
    .then(data => {
      chunks = data;
      const status = document.getElementById("uv-chat-status");
      if (status) status.textContent = `Loaded ${chunks.length} memoir passages for retrieval.`;
    })
    .catch(err => {
      const status = document.getElementById("uv-chat-status");
      if (status) status.textContent = `Could not load search index: ${err.message}`;
    });

  document.addEventListener("DOMContentLoaded", () => {
    const button = document.getElementById("uv-chat-button");
    if (button) button.addEventListener("click", runChat);
  });
})();
