(function () {
  "use strict";

  const endpoint = window.UNCLE_VIRGIL_MODEL_ENDPOINT || "";

  function $(id) {
    return document.getElementById(id);
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function normalizeList(value) {
    if (!value) return [];
    if (Array.isArray(value)) return value.filter(Boolean).map(String);
    return String(value)
      .split(/[;,|]/)
      .map((x) => x.trim())
      .filter(Boolean);
  }

  function firstNonEmpty(obj, keys, fallback = "") {
    for (const key of keys) {
      if (obj && obj[key] !== undefined && obj[key] !== null && String(obj[key]).trim() !== "") {
        return obj[key];
      }
    }
    return fallback;
  }

  function setStatus(message, kind) {
    const el = $("uv-model-status");
    if (!el) return;
    el.textContent = message;
    el.className = "uv-model-status" + (kind ? " uv-model-status-" + kind : "");
  }

  function renderChips(label, items) {
    const values = normalizeList(items);
    if (!values.length) return "";
    return `
      <div class="uv-model-meta-row">
        <span class="uv-model-meta-label">${escapeHtml(label)}</span>
        <span class="uv-model-chip-list">
          ${values.map((x) => `<span class="uv-model-chip">${escapeHtml(x)}</span>`).join("")}
        </span>
      </div>
    `;
  }

  function sourceTitle(source, index) {
    const citation = firstNonEmpty(source, ["citation_label", "citation", "source", "label"], "");
    const chapter = firstNonEmpty(source, ["chapter_title", "title"], "");
    const passageId = firstNonEmpty(source, ["passage_id", "id"], "");
    if (citation) return citation;
    if (chapter && passageId) return `${chapter} — ${passageId}`;
    if (chapter) return chapter;
    if (passageId) return passageId;
    return `Source ${index + 1}`;
  }

  function sourceText(source) {
    return firstNonEmpty(source, ["text", "passage_text", "excerpt", "content", "snippet"], "");
  }

  function renderSources(sources) {
    const container = $("uv-model-sources");
    if (!container) return;

    if (!sources || !sources.length) {
      container.innerHTML = `<p class="uv-model-muted">No retrieved source passages returned.</p>`;
      return;
    }

    container.innerHTML = sources.map((source, index) => {
      const score = firstNonEmpty(source, ["score", "retrieval_score"], "");
      const text = sourceText(source);
      const passageId = firstNonEmpty(source, ["passage_id", "id"], "");
      const entities = firstNonEmpty(source, ["entities_mentioned", "entities", "entity_mentions"], "");
      const years = firstNonEmpty(source, ["year_candidates", "years", "dates"], "");

      return `
        <article class="uv-model-source-card">
          <div class="uv-model-source-head">
            <h3>${index + 1}. ${escapeHtml(sourceTitle(source, index))}</h3>
            ${score !== "" ? `<span class="uv-model-score">score ${escapeHtml(score)}</span>` : ""}
          </div>
          ${passageId ? `<div class="uv-model-source-id">${escapeHtml(passageId)}</div>` : ""}
          ${text ? `<p class="uv-model-source-text">${escapeHtml(text)}</p>` : ""}
          <div class="uv-model-source-meta">
            ${renderChips("Entities", entities)}
            ${renderChips("Years", years)}
          </div>
        </article>
      `;
    }).join("");
  }

  function renderAnswer(data) {
    const answerEl = $("uv-model-answer");
    if (!answerEl) return;

    if (data.error) {
      answerEl.innerHTML = `<p class="uv-model-error">${escapeHtml(data.error)}</p>`;
      return;
    }

    const answer = firstNonEmpty(data, ["answer", "message", "response", "text"], "No answer text returned.");
    const safeAnswer = escapeHtml(answer).replace(/\n\n+/g, "</p><p>").replace(/\n/g, "<br>");
    answerEl.innerHTML = `<p>${safeAnswer}</p>`;
  }

  function extractSources(data) {
    const candidates = [
      data.sources,
      data.retrieved_sources,
      data.retrieved_passages,
      data.passages,
      data.context,
      data.results
    ];
    for (const item of candidates) {
      if (Array.isArray(item)) return item;
    }
    return [];
  }

  async function askModel() {
    const input = $("uv-model-question");
    const question = input ? input.value.trim() : "";

    if (!endpoint) {
      setStatus("No model endpoint is configured in model_bot.qmd.", "error");
      return;
    }
    if (!question) {
      setStatus("Type a question first.", "error");
      return;
    }

    setStatus("Asking model…", "loading");
    const askButton = $("uv-model-ask");
    if (askButton) askButton.disabled = true;

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ question: question })
      });

      let data;
      try {
        data = await response.json();
      } catch (jsonErr) {
        const text = await response.text();
        throw new Error(`Endpoint returned non-JSON response (${response.status}): ${text.slice(0, 500)}`);
      }

      if (!response.ok) {
        throw new Error(data.error || data.message || `Endpoint returned HTTP ${response.status}`);
      }

      renderAnswer(data);
      renderSources(extractSources(data));
      setStatus("Model response received.", "ok");
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      $("uv-model-answer").innerHTML = `<p class="uv-model-error">Model request failed: ${escapeHtml(message)}</p>`;
      renderSources([]);
      setStatus("Model request failed. Check CORS, Lambda logs, or Bedrock access.", "error");
    } finally {
      if (askButton) askButton.disabled = false;
    }
  }

  function bindEvents() {
    const askButton = $("uv-model-ask");
    const input = $("uv-model-question");

    if (askButton) askButton.addEventListener("click", askModel);
    if (input) {
      input.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
          event.preventDefault();
          askModel();
        }
      });
    }

    document.addEventListener("click", (event) => {
      const button = event.target.closest(".uv-model-example");
      if (!button) return;
      const query = button.getAttribute("data-query") || button.textContent.trim();
      if (input) {
        input.value = query;
        input.focus();
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bindEvents);
  } else {
    bindEvents();
  }
})();
