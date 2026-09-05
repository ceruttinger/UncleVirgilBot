(function () {
  const GRAPH_DIV_ID = "uvEntityGraph";
  const NODES_URL = "data/public/graph_nodes.json";
  const EDGES_URL = "data/public/graph_edges.json";
  const POSITION_KEY = "uncleVirgilBot.entityGraph.nodePositions.v2";

  let allNodes = [];
  let allEdges = [];
  let network = null;

  const graphEl = document.getElementById(GRAPH_DIV_ID);
  const chapterFilter = document.getElementById("uvChapterFilter");
  const typeFilter = document.getElementById("uvTypeFilter");
  const minMentions = document.getElementById("uvMinMentions");
  const hideChapterLinks = document.getElementById("uvHideChapterLinks");
  const saveLayout = document.getElementById("uvSaveLayout");
  const clearLayout = document.getElementById("uvClearLayout");
  const statsEl = document.getElementById("uvGraphStats");

  if (!graphEl) return;

  function cleanText(value) {
    return String(value ?? "")
      .replace(/<br\s*\/?\s*>/gi, "\n")
      .replace(/<\/?strong>/gi, "")
      .replace(/<[^>]*>/g, "")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .trim();
  }

  function firstValue(obj, keys, fallback = "") {
    for (const key of keys) {
      if (obj[key] !== undefined && obj[key] !== null && obj[key] !== "") return obj[key];
    }
    return fallback;
  }

  function asNumber(value, fallback = 1) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function nodeType(rawNode) {
    const id = String(firstValue(rawNode, ["id", "node_id", "entity_id"], ""));
    const explicit = firstValue(rawNode, ["node_type", "entity_type", "group", "type"], "");
    if (explicit) return String(explicit);
    if (/^chapter/i.test(id)) return "Chapter";
    return "Entity";
  }

  function normalizeNode(rawNode) {
    const id = String(firstValue(rawNode, ["id", "node_id", "entity_id", "chapter_id"], ""));
    const label = cleanText(firstValue(rawNode, ["label", "canonical_entity", "chapter_title", "name"], id));
    const type = nodeType(rawNode);
    const totalMentions = asNumber(firstValue(rawNode, ["total_mentions", "total_count", "mentions", "value", "count"], 1), 1);
    const reviewStatus = cleanText(firstValue(rawNode, ["review_status"], ""));
    const chapters = cleanText(firstValue(rawNode, ["chapters", "chapter"], ""));
    const rawTitle = firstValue(rawNode, ["title", "tooltip"], "");
    const title = rawTitle
      ? cleanText(rawTitle)
      : [
          label,
          `Type: ${type}`,
          reviewStatus ? `Review status: ${reviewStatus}` : "",
          `Total mentions: ${totalMentions}`,
          chapters ? `Chapters: ${chapters}` : ""
        ].filter(Boolean).join("\n");

    return {
      ...rawNode,
      id,
      label,
      title,
      group: type,
      node_type: type,
      entity_type: type === "Chapter" ? "Chapter" : type,
      value: Math.max(4, Math.sqrt(totalMentions) * 5),
      total_mentions: totalMentions,
      shape: type === "Chapter" ? "box" : "dot",
      font: { size: type === "Chapter" ? 18 : 13, multi: false },
      margin: type === "Chapter" ? 12 : undefined
    };
  }

  function normalizeEdge(rawEdge) {
    const from = String(firstValue(rawEdge, ["from", "source", "source_id", "from_id"], ""));
    const to = String(firstValue(rawEdge, ["to", "target", "target_id", "to_id"], ""));
    const relationship = cleanText(firstValue(rawEdge, ["relationship", "edge_type", "type", "label"], ""));
    const weight = asNumber(firstValue(rawEdge, ["weight", "mentions", "value", "count"], 1), 1);

    return {
      ...rawEdge,
      from,
      to,
      label: relationship === "MENTIONS" ? "" : relationship,
      relationship,
      weight,
      value: weight,
      width: Math.max(1, Math.min(8, Math.sqrt(weight))),
      title: cleanText(firstValue(rawEdge, ["title", "tooltip"], `${relationship || "Link"}\nWeight: ${weight}`)),
      arrows: relationship === "MENTIONS" ? "to" : ""
    };
  }

  function isChapterNode(node) {
    return node.node_type === "Chapter" || /^chapter/i.test(String(node.id));
  }

  function chapterSortValue(node) {
    const text = `${node.id} ${node.label}`;
    const match = text.match(/(?:chapter|ch\.?)[_:\s-]*(\d+)/i) || text.match(/\b(\d+)\b/);
    return match ? Number(match[1]) : 999;
  }

  function loadPositions() {
    try {
      return JSON.parse(localStorage.getItem(POSITION_KEY) || "{}");
    } catch (err) {
      return {};
    }
  }

  function savePositionsForVisibleNodes() {
    if (!network) return;
    const saved = loadPositions();
    const positions = network.getPositions();
    Object.entries(positions).forEach(([id, pos]) => {
      saved[id] = { x: pos.x, y: pos.y };
    });
    localStorage.setItem(POSITION_KEY, JSON.stringify(saved));
  }

  function applySavedPositions(nodes) {
    const saved = loadPositions();
    return nodes.map((node) => {
      if (saved[node.id]) {
        return {
          ...node,
          x: saved[node.id].x,
          y: saved[node.id].y,
          fixed: { x: true, y: true }
        };
      }
      return node;
    });
  }

  function populateFilters() {
    const chapters = allNodes
      .filter(isChapterNode)
      .sort((a, b) => chapterSortValue(a) - chapterSortValue(b));

    chapters.forEach((chapter) => {
      const option = document.createElement("option");
      option.value = chapter.id;
      option.textContent = chapter.label;
      chapterFilter.appendChild(option);
    });

    const types = Array.from(
      new Set(allNodes.filter((n) => !isChapterNode(n)).map((n) => n.entity_type || n.node_type || n.group).filter(Boolean))
    ).sort();

    types.forEach((type) => {
      const option = document.createElement("option");
      option.value = type;
      option.textContent = type;
      typeFilter.appendChild(option);
    });
  }

  function selectedGraph() {
    const selectedChapter = chapterFilter.value;
    const selectedType = typeFilter.value;
    const threshold = Math.max(1, asNumber(minMentions.value, 1));
    const shouldHideChapterLinks = hideChapterLinks.checked;

    const nodeById = new Map(allNodes.map((node) => [node.id, node]));
    const allowedNodeIds = new Set();
    const filteredEdges = [];

    allEdges.forEach((edge) => {
      const fromNode = nodeById.get(edge.from);
      const toNode = nodeById.get(edge.to);
      if (!fromNode || !toNode) return;

      const fromIsChapter = isChapterNode(fromNode);
      const toIsChapter = isChapterNode(toNode);

      if (shouldHideChapterLinks && fromIsChapter && toIsChapter) return;
      if (edge.weight < threshold) return;

      if (selectedChapter !== "all" && edge.from !== selectedChapter && edge.to !== selectedChapter) return;

      const entityNode = fromIsChapter ? toNode : fromNode;
      const entityType = entityNode.entity_type || entityNode.node_type || entityNode.group;
      if (selectedType !== "all" && entityType !== selectedType) return;

      filteredEdges.push(edge);
      allowedNodeIds.add(edge.from);
      allowedNodeIds.add(edge.to);
    });

    if (selectedChapter !== "all") allowedNodeIds.add(selectedChapter);

    const filteredNodes = allNodes.filter((node) => allowedNodeIds.has(node.id));
    return { nodes: applySavedPositions(filteredNodes), edges: filteredEdges };
  }

  function renderGraph() {
    const graph = selectedGraph();
    const nodes = new vis.DataSet(graph.nodes);
    const edges = new vis.DataSet(graph.edges);

    const data = { nodes, edges };
    const options = {
      autoResize: true,
      interaction: {
        hover: true,
        tooltipDelay: 120,
        navigationButtons: true,
        keyboard: true,
        dragNodes: true,
        dragView: true,
        zoomView: true
      },
      physics: {
        enabled: true,
        solver: "forceAtlas2Based",
        stabilization: { enabled: true, iterations: 220, updateInterval: 20 },
        forceAtlas2Based: {
          gravitationalConstant: -55,
          centralGravity: 0.012,
          springLength: 155,
          springConstant: 0.05,
          avoidOverlap: 0.6
        }
      },
      nodes: {
        borderWidth: 1,
        shadow: true
      },
      edges: {
        smooth: { type: "continuous" },
        color: { opacity: 0.45 },
        shadow: false
      },
      groups: {
        Chapter: { shape: "box" },
        Person: { shape: "dot" },
        Place: { shape: "dot" },
        Organization: { shape: "dot" },
        "Organization/Place": { shape: "dot" },
        Date: { shape: "diamond" },
        Event: { shape: "triangle" }
      }
    };

    if (network) network.destroy();
    network = new vis.Network(graphEl, data, options);

    network.once("stabilizationIterationsDone", function () {
      network.setOptions({ physics: false });
    });

    network.on("dragEnd", function (params) {
      if (!params.nodes || params.nodes.length === 0) return;
      const positions = network.getPositions(params.nodes);
      const saved = loadPositions();
      params.nodes.forEach((id) => {
        if (positions[id]) saved[id] = positions[id];
        nodes.update({ id, fixed: { x: true, y: true } });
      });
      localStorage.setItem(POSITION_KEY, JSON.stringify(saved));
    });

    statsEl.textContent = `${graph.nodes.length.toLocaleString()} nodes and ${graph.edges.length.toLocaleString()} edges shown`;
  }

  function wireControls() {
    [chapterFilter, typeFilter, minMentions, hideChapterLinks].forEach((control) => {
      control.addEventListener("change", renderGraph);
      control.addEventListener("input", renderGraph);
    });

    saveLayout.addEventListener("click", function () {
      savePositionsForVisibleNodes();
      statsEl.textContent = `${statsEl.textContent} — layout saved`;
    });

    clearLayout.addEventListener("click", function () {
      localStorage.removeItem(POSITION_KEY);
      renderGraph();
    });
  }

  async function loadGraph() {
    try {
      const [nodeResponse, edgeResponse] = await Promise.all([fetch(NODES_URL), fetch(EDGES_URL)]);
      if (!nodeResponse.ok) throw new Error(`Could not load ${NODES_URL}`);
      if (!edgeResponse.ok) throw new Error(`Could not load ${EDGES_URL}`);

      const rawNodes = await nodeResponse.json();
      const rawEdges = await edgeResponse.json();

      allNodes = rawNodes.map(normalizeNode).filter((node) => node.id);
      allEdges = rawEdges.map(normalizeEdge).filter((edge) => edge.from && edge.to);

      populateFilters();
      wireControls();
      renderGraph();
    } catch (err) {
      console.error(err);
      statsEl.textContent = `Graph failed to load: ${err.message}`;
    }
  }

  loadGraph();
})();
