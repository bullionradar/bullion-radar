// Real prices, factor scores and news come from live-data.js,
// which update-data.bat creates. Without it, the site falls back to the
// sample values in this file.
const LIVE_DATA = window.LIVE || null;

// When the data was last updated, in the visitor's own time zone.
const LIVE_UPDATED = LIVE_DATA
  ? new Date(LIVE_DATA.updated).toLocaleString("en-US", {
      month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short",
    })
  : null;

// --- Scale factors ---
// Each factor is scored 0-100 (higher = more favorable for buying) by comparing
// today's reading with the last 10 years (percentile). Weights add up to 100.
// The scores here are sample values, replaced by live-data.js when it exists.
const PRICE_SOURCE = "COMEX futures via Yahoo Finance";
const SCALE = {
  gold: [
    { key: "priceTrend", name: "Price vs. 200-day average", weight: 26, score: 41,
      favorable: "Price is near or below its long-term average (not stretched)", source: PRICE_SOURCE },
    { key: "dollar", name: "US dollar strength", weight: 26, score: 63,
      favorable: "The dollar is weak or weakening", source: "US Dollar Index via Yahoo Finance" },
    { key: "realRates", name: "Real interest rates", weight: 21, score: 52,
      favorable: "Rates after inflation are low or falling", source: "FRED (10-year TIPS yield)" },
    { key: "inflation", name: "Inflation expectations", weight: 16, score: 71,
      favorable: "Expected inflation is rising", source: "FRED (5-year breakeven)" },
    { key: "ratio", name: "Gold-to-silver ratio", weight: 11, score: 22,
      favorable: "Ratio is low, so gold is cheap compared to silver", source: PRICE_SOURCE },
  ],
  silver: [
    { key: "ratio", name: "Gold-to-silver ratio", weight: 31, score: 84,
      favorable: "Ratio is high, so silver is cheap compared to gold", source: PRICE_SOURCE },
    { key: "priceTrend", name: "Price vs. 200-day average", weight: 21, score: 47,
      favorable: "Price is near or below its long-term average (not stretched)", source: PRICE_SOURCE },
    { key: "dollar", name: "US dollar strength", weight: 21, score: 63,
      favorable: "The dollar is weak or weakening", source: "US Dollar Index via Yahoo Finance" },
    { key: "industrial", name: "Industrial demand", weight: 16, score: 77,
      favorable: "Manufacturing output is growing", source: "FRED (manufacturing output)" },
    { key: "realRates", name: "Real interest rates", weight: 11, score: 52,
      favorable: "Rates after inflation are low or falling", source: "FRED (10-year TIPS yield)" },
  ],
};

// Where visitors can see the data behind each factor for themselves.
const DATA_LINKS = {
  priceTrend: {
    gold: ["Gold price chart (Yahoo Finance)", "https://finance.yahoo.com/quote/GC%3DF/"],
    silver: ["Silver price chart (Yahoo Finance)", "https://finance.yahoo.com/quote/SI%3DF/"],
  },
  dollar: ["US Dollar Index (Yahoo Finance)", "https://finance.yahoo.com/quote/DX-Y.NYB/"],
  realRates: ["10-year real yield (FRED)", "https://fred.stlouisfed.org/series/DFII10"],
  inflation: ["5-year inflation expectation (FRED)", "https://fred.stlouisfed.org/series/T5YIE"],
  industrial: ["US manufacturing output (FRED)", "https://fred.stlouisfed.org/series/IPMAN"],
  ratio: ["Gold-to-silver ratio chart", "#history"],
};
for (const metal of ["gold", "silver"]) {
  for (const f of SCALE[metal]) {
    const link = DATA_LINKS[f.key];
    [f.dataLabel, f.dataUrl] = Array.isArray(link) ? link : link[metal];
  }
}

// The five bands of the scale, from worst to best.
// Colors run from tarnish red to verdigris green, the patina old coins take on.
const BANDS = [
  { max: 20, label: "Risky buy", color: "#b5483a" },
  { max: 40, label: "Cautious", color: "#c4763c" },
  { max: 60, label: "Neutral", color: "#c49b3c" },
  { max: 80, label: "Favorable", color: "#7c9c58" },
  { max: 100, label: "Very favorable", color: "#3d8a6c" },
];

function bandFor(score) {
  return BANDS.find((b) => score <= b.max) || BANDS[BANDS.length - 1];
}

// Smooth color for any score, blending between the band colors.
function scaleColor(score) {
  const stops = BANDS.map((b) => b.color);
  const t = (Math.max(0, Math.min(100, score)) / 100) * (stops.length - 1);
  const i = Math.min(stops.length - 2, Math.floor(t));
  const f = t - i;
  const a = parseInt(stops[i].slice(1), 16);
  const b = parseInt(stops[i + 1].slice(1), 16);
  const ch = (shift) => Math.round(((a >> shift) & 255) * (1 - f) + ((b >> shift) & 255) * f);
  return `rgb(${ch(16)}, ${ch(8)}, ${ch(0)})`;
}

// Factors that aren't connected yet (score null) are left out, and the
// remaining weights are scaled up to fill in.
function overallScore(factors) {
  const used = factors.filter((f) => f.score != null);
  const total = used.reduce((sum, f) => sum + f.weight, 0);
  return Math.round(used.reduce((sum, f) => sum + f.score * f.weight, 0) / total);
}

// --- Daily one-sentence summary ---
// Phrases for when a factor is helping (score 60+) or holding the score back (40 or less).
const SUMMARY_PHRASES = {
  priceTrend: {
    help: (m) => `${m} isn't stretched above its long-term average`,
    hurt: (m) => `${m} has run well above its long-term average`,
  },
  dollar: { help: () => "the US dollar is weaker than usual", hurt: () => "the US dollar is strong" },
  realRates: { help: () => "real interest rates are low", hurt: () => "real interest rates are unusually high" },
  inflation: { help: () => "inflation expectations are elevated", hurt: () => "inflation expectations are subdued" },
  industrial: { help: () => "manufacturing output is growing", hurt: () => "manufacturing output is weak" },
  ratio: {
    help: (m, other) => `${m} is cheap compared to ${other}`,
    hurt: (m, other) => `${m} is expensive compared to ${other}`,
  },
};

function joinPhrases(list) {
  return list.length === 1 ? list[0] : `${list[0]} and ${list[1]}`;
}

function dailySummary(metal) {
  const m = metal === "gold" ? "gold" : "silver";
  const other = metal === "gold" ? "silver" : "gold";
  const Label = metal === "gold" ? "Gold" : "Silver";
  const factors = SCALE[metal].filter((f) => f.score != null);
  // Rank by how much each factor pushes the score up or down, weighted by importance.
  const pull = (f) => (f.score - 50) * f.weight;
  const helps = factors.filter((f) => f.score >= 60).sort((a, b) => pull(b) - pull(a)).slice(0, 2)
    .map((f) => SUMMARY_PHRASES[f.key].help(m, other));
  const hurts = factors.filter((f) => f.score <= 40).sort((a, b) => pull(a) - pull(b)).slice(0, 2)
    .map((f) => SUMMARY_PHRASES[f.key].hurt(m, other));
  const band = bandFor(overallScore(SCALE[metal])).label;

  if (helps.length && hurts.length) {
    return `${Label} reads ${band}: it helps that ${joinPhrases(helps)}, but ${joinPhrases(hurts)}.`;
  }
  if (helps.length) return `${Label} reads ${band}, mainly because ${joinPhrases(helps)}.`;
  if (hurts.length) return `${Label} reads ${band}, mainly because ${joinPhrases(hurts)}.`;
  return `${Label} reads ${band}, with no signal far from its usual range.`;
}

if (LIVE_DATA) {
  for (const metal of ["gold", "silver"]) {
    for (const f of SCALE[metal]) {
      const live = LIVE_DATA.factors[metal][f.key];
      f.score = live ? live.score : null;
      f.reading = live ? live.reading : "Not connected yet";
    }
  }
}

// --- Sample price history (generated, not real) ---
function makeSampleHistory(days) {
  // Small seeded random generator so the sample looks the same on every load.
  let seed = 20261017;
  const rand = () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  let gold = 3050;
  let silver = 33.5;
  const out = [];
  const today = new Date();
  for (let i = days - 1; i >= 0; i--) {
    const shared = rand() - 0.5;
    gold *= 1 + 0.0004 + 0.016 * shared + 0.006 * (rand() - 0.5);
    silver *= 1 + 0.0006 + 0.024 * shared + 0.014 * (rand() - 0.5);
    const d = new Date(today);
    d.setDate(today.getDate() - i);
    out.push({ date: d, gold, silver, ratio: gold / silver });
  }
  return out;
}

const HISTORY = LIVE_DATA
  ? LIVE_DATA.prices.dates.map((d, i) => {
      const gold = LIVE_DATA.prices.gold[i];
      const silver = LIVE_DATA.prices.silver[i];
      return { date: new Date(d + "T12:00:00"), gold, silver, ratio: gold / silver };
    })
  : makeSampleHistory(365);

// --- News ---
// Real headlines come from live-data.js. These made-up ones are only a fallback.
const SAMPLE_NEWS = [
  {
    metal: "gold",
    title: "Sample headline: Central bank gold buying stays strong this quarter",
    summary: "Placeholder summary. Real stories will appear here with a link to the original source.",
    source: "Sample Source",
    hoursAgo: 2,
  },
  {
    metal: "silver",
    title: "Sample headline: Solar panel demand keeps silver supply tight",
    summary: "Placeholder summary about industrial demand and what it could mean for silver buyers.",
    source: "Sample Source",
    hoursAgo: 5,
  },
  {
    metal: "gold",
    title: "Sample headline: Mint announces new 2027 bullion coin designs",
    summary: "Placeholder summary of a story collectors would care about, like new designs and mintages.",
    source: "Sample Source",
    hoursAgo: 9,
  },
  {
    metal: "silver",
    title: "Sample headline: Gold-to-silver ratio drifts lower as silver rallies",
    summary: "Placeholder summary explaining a move in the ratio and why it matters.",
    source: "Sample Source",
    hoursAgo: 20,
  },
  {
    metal: "gold",
    title: "Sample headline: Central banks keep adding to gold reserves",
    summary: "Placeholder summary about official sector gold buying.",
    source: "Sample Source",
    hoursAgo: 28,
  },
  {
    metal: "silver",
    title: "Sample headline: Low-mintage silver rounds draw collector interest",
    summary: "Placeholder summary of a numismatic story focused on rarity and grading.",
    source: "Sample Source",
    hoursAgo: 46,
  },
];

const NEWS = LIVE_DATA && LIVE_DATA.news && LIVE_DATA.news.length
  ? LIVE_DATA.news.map((n) => ({ ...n, tags: [].concat(n.tags), published: new Date(n.published) }))
  : SAMPLE_NEWS.map((n) => ({
      ...n,
      tags: [n.metal],
      published: new Date(Date.now() - n.hoursAgo * 3600000),
    }));

const TAG_LABELS = { gold: "Gold", silver: "Silver", coins: "Coins" };

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]
  );
}

function timeAgo(date) {
  const minutes = Math.max(0, Math.round((Date.now() - date) / 60000));
  if (minutes < 60) return minutes + "m ago";
  const hours = Math.round(minutes / 60);
  if (hours < 24) return hours + "h ago";
  const days = Math.round(hours / 24);
  return days + (days === 1 ? " day ago" : " days ago");
}

function newsCard(item) {
  const tags = item.tags.map((t) => `<span class="tag ${t}">${TAG_LABELS[t] || t}</span>`).join("");
  const body = `
      <span class="news-tags">${tags}</span>
      <span class="news-title">${escapeHtml(item.title)}</span>
      <span class="news-src">${escapeHtml(item.source)}, ${timeAgo(item.published)}</span>`;
  return item.url
    ? `<a class="news-row" href="${escapeHtml(item.url)}" target="_blank" rel="noopener">${body}</a>`
    : `<div class="news-row">${body}</div>`;
}

// Newest story for each tag, for the home page preview.
function newsHighlights() {
  const picks = [];
  for (const tag of ["gold", "silver", "coins"]) {
    const story = NEWS.find((n) => n.tags.includes(tag) && !picks.includes(n));
    if (story) picks.push(story);
  }
  return picks.length >= 3 ? picks : NEWS.slice(0, 3);
}
