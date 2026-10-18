const money = (n, digits = 2) =>
  "$" + n.toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });

const last = HISTORY[HISTORY.length - 1];
const prev = HISTORY[HISTORY.length - 2];
const pctChange = (now, before) => ((now - before) / before) * 100;

// --- Coins in the hero background ---
// x/y are % of the hero, s is size in px, r is rotation, b is blur, o is opacity.
// x/y are % of the hero, s is size in px, o is opacity. Kept quiet and to the edges.
const COINS = [
  { metal: "gold", x: -7, y: 18, s: 260, o: 0.35 },
  { metal: "silver", x: 88, y: 30, s: 260, o: 0.3 },
];

document.getElementById("coin-field").innerHTML = COINS.map(
  (c) => `<img src="${COIN_IMAGES[c.metal]}" alt=""
    style="left:${c.x}%;top:${c.y}%;--s:${c.s};--o:${c.o}">`
).join("");

// --- Gauges ---
// Half-circle scale: 0 (risky) on the left, 100 (very favorable) on the right.
function pointAt(score, r) {
  const t = Math.PI * (1 - score / 100);
  return [100 + r * Math.cos(t), 100 - r * Math.sin(t)];
}

function arc(from, to, r) {
  const [x0, y0] = pointAt(from, r);
  const [x1, y1] = pointAt(to, r);
  return `M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 0 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

function renderDial(el, metal) {
  const label = metal === "gold" ? "Gold" : "Silver";
  const symbol = metal === "gold" ? "XAU/USD" : "XAG/USD";
  const score = overallScore(SCALE[metal]);
  const band = bandFor(score);

  let start = 0;
  const segments = BANDS.map((b) => {
    const path = `<path d="${arc(start + 0.4, b.max - 0.4, 80)}" stroke="${b.color}" stroke-width="12" fill="none" />`;
    start = b.max;
    return path;
  }).join("");

  const ticks = [0, 25, 50, 75, 100]
    .map((s) => {
      const [x0, y0] = pointAt(s, 88);
      const [x1, y1] = pointAt(s, 93);
      return `<line x1="${x0.toFixed(1)}" y1="${y0.toFixed(1)}" x2="${x1.toFixed(1)}" y2="${y1.toFixed(1)}" stroke="#6b6b6b" stroke-width="1"/>`;
    })
    .join("");

  const price = last[metal];
  const change = pctChange(price, prev[metal]);
  const sign = change >= 0 ? "+" : "−";

  el.className = `quote-panel ${metal}`;
  el.innerHTML = `
    <div class="qp-head">
      <span class="qp-name">${label}</span>
      <span class="qp-sym">${symbol}</span>
    </div>
    <div class="qp-price">
      <strong>${money(price)}</strong>
      <span class="qp-change ${change >= 0 ? "up" : "down"}">${sign}${Math.abs(change).toFixed(2)}%</span>
    </div>
    <div class="qp-sub">Spot price per troy ounce</div>
    <div class="gauge">
      <svg viewBox="0 0 200 106" role="img"
        aria-label="${label} buy scale: ${score} out of 100, ${band.label}.">
        ${segments}
        ${ticks}
        <line x1="100" y1="100" x2="30" y2="100" stroke="#e6e6e6" stroke-width="2.5" stroke-linecap="round"
          transform="rotate(${(score * 1.8).toFixed(1)} 100 100)" />
        <circle cx="100" cy="100" r="5" fill="#e6e6e6" />
      </svg>
      <div class="gauge-ends"><span>Risky buy</span><span>Very favorable</span></div>
    </div>
    <div class="qp-foot">
      <span>Buy scale</span>
      <strong>${score} of 100, <span style="color:${band.color}">${band.label}</span></strong>
    </div>`;
}

renderDial(document.getElementById("dial-gold"), "gold");
renderDial(document.getElementById("dial-silver"), "silver");

document.getElementById("hero-strip").innerHTML = `
  <span>Gold-to-silver ratio <strong>${last.ratio.toFixed(1)} : 1</strong></span>
  <span>${LIVE_DATA ? `Data as of <strong>${LIVE_DATA.updated}</strong>` : "<strong>Sample data</strong>"}</span>`;

// --- Factor breakdown ---
function renderFactors(el, metal) {
  const label = metal === "gold" ? "Gold" : "Silver";
  const score = overallScore(SCALE[metal]);
  el.innerHTML = `
    <div class="col-head">
      ${coinImg(metal)}
      <h3>${label}</h3>
      <span class="total" style="color:${scaleColor(score)}">${score}</span>
    </div>
    ${SCALE[metal].map((f) => factorRow(f, metal)).join("")}`;
}

// Each factor links to a recent related story and to the data behind it.
function factorRow(f, metal) {
  const off = f.score == null;
  const c = off ? "transparent" : scaleColor(f.score);
  const story = LIVE_DATA && LIVE_DATA.factorNews && LIVE_DATA.factorNews[metal]
    ? LIVE_DATA.factorNews[metal][f.key]
    : null;

  const dataUrl = f.dataUrl;
  const external = dataUrl.startsWith("http");
  const ext = 'target="_blank" rel="noopener"';

  return `
    <div class="frow${off ? " off" : ""}">
      <span class="fname">${f.name}<span class="fweight">${f.weight}%</span></span>
      <span class="freading">${f.reading || f.favorable}</span>
      <span class="fscore" style="color:${off ? "var(--muted)" : c}">${off ? "–" : f.score}</span>
      <span class="fbar"><span style="width:${f.score ?? 0}%;background:${c}"></span></span>
      <span class="flinks">
        ${story ? `
        <span class="flink">
          <span class="flabel">Story</span>
          <span><a href="${escapeHtml(story.url)}" ${ext}>${escapeHtml(story.title)}</a>
            <span class="fsrc">${escapeHtml(story.source)}, ${timeAgo(new Date(story.published))}</span></span>
        </span>` : ""}
        <span class="flink">
          <span class="flabel">Data</span>
          <span><a href="${dataUrl}" ${external ? ext : ""}>${f.dataLabel}</a></span>
        </span>
      </span>
    </div>`;
}

renderFactors(document.getElementById("factors-gold"), "gold");
renderFactors(document.getElementById("factors-silver"), "silver");

// --- Charts ---
Chart.defaults.font.family = "'IBM Plex Sans', system-ui, sans-serif";
Chart.defaults.color = "#5b6676";
const GRID = "#dde1e6";
const fmtDate = (d) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" });

const baseOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: "index", intersect: false },
  elements: { point: { radius: 0, hoverRadius: 4 }, line: { borderWidth: 2, tension: 0.2 } },
  scales: { x: { grid: { display: false }, ticks: { maxTicksLimit: 6 } } },
};

const priceChart = new Chart(document.getElementById("price-chart"), {
  type: "line",
  data: {
    labels: [],
    datasets: [
      { label: "Gold", data: [], borderColor: "#c49a3c", backgroundColor: "#c49a3c", yAxisID: "y" },
      { label: "Silver", data: [], borderColor: "#6f7987", backgroundColor: "#6f7987", yAxisID: "y1" },
    ],
  },
  options: {
    ...baseOptions,
    plugins: {
      legend: { position: "top", align: "end", labels: { boxWidth: 10, boxHeight: 10, usePointStyle: true } },
      tooltip: { callbacks: { label: (c) => `${c.dataset.label}: ${money(c.parsed.y)}` } },
    },
    scales: {
      ...baseOptions.scales,
      y: { position: "left", grid: { color: GRID }, ticks: { callback: (v) => "$" + v.toLocaleString() } },
      y1: { position: "right", grid: { display: false }, ticks: { callback: (v) => "$" + v } },
    },
  },
});

const ratioChart = new Chart(document.getElementById("ratio-chart"), {
  type: "line",
  data: { labels: [], datasets: [{ label: "Ratio", data: [], borderColor: "#111111" }] },
  options: {
    ...baseOptions,
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: (c) => `${c.parsed.y.toFixed(1)} : 1` } },
    },
    scales: { ...baseOptions.scales, y: { grid: { color: GRID } } },
  },
});

function showRange(days) {
  const cutoff = new Date(last.date);
  cutoff.setDate(cutoff.getDate() - days);
  const slice = HISTORY.filter((p) => p.date >= cutoff);
  const labels = slice.map((p) => fmtDate(p.date));
  priceChart.data.labels = labels;
  priceChart.data.datasets[0].data = slice.map((p) => p.gold);
  priceChart.data.datasets[1].data = slice.map((p) => p.silver);
  ratioChart.data.labels = labels;
  ratioChart.data.datasets[0].data = slice.map((p) => p.ratio);
  priceChart.update();
  ratioChart.update();
}

document.getElementById("ranges").addEventListener("click", (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  document.querySelectorAll("#ranges button").forEach((b) => b.classList.toggle("active", b === btn));
  showRange(Number(btn.dataset.days));
});

showRange(365);

// --- News preview ---
document.getElementById("news-preview").innerHTML = newsHighlights().map(newsCard).join("");
