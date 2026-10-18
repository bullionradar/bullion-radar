// Builds the daily Bullion Radar email and (with --send) sends it through Buttondown.
// Runs on GitHub every weekday morning (.github/workflows/daily-newsletter.yml).
//
//   node newsletter.js          -> prints the email, sends nothing (safe test)
//   node newsletter.js --send   -> sends it to every subscriber (needs BUTTONDOWN_API_KEY)
//
// It loads the site's own live-data.js and data.js, so the scores and summary
// sentences in the email are worked out exactly the same way as on the website.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SITE_URL = "https://bullionradar.github.io/bullion-radar/";
const MAX_DATA_AGE_HOURS = 18;

// Run the site's scripts in a sandbox that looks enough like a browser for them.
const context = vm.createContext({ window: {}, console, Date, Math, Intl });
for (const file of ["live-data.js", "data.js"]) {
  vm.runInContext(fs.readFileSync(path.join(__dirname, file), "utf8"), context, { filename: file });
}
const site = vm.runInContext(
  "({ LIVE_DATA, SCALE, HISTORY, overallScore, bandFor, dailySummary, newsHighlights })", context);

if (!site.LIVE_DATA) throw new Error("live-data.js has no data.");
const ageHours = (Date.now() - new Date(site.LIVE_DATA.updated)) / 3600000;
if (ageHours > MAX_DATA_AGE_HOURS) {
  throw new Error(`Data is ${ageHours.toFixed(1)} hours old, so no newsletter is sent today.`);
}

const money = (n) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const last = site.HISTORY[site.HISTORY.length - 1];
const prev = site.HISTORY[site.HISTORY.length - 2];
const change = (metal) => {
  const pct = ((last[metal] - prev[metal]) / prev[metal]) * 100;
  return `${pct >= 0 ? "+" : "−"}${Math.abs(pct).toFixed(2)}%`;
};
const reading = (metal) => {
  const score = site.overallScore(site.SCALE[metal]);
  return { score, band: site.bandFor(score).label };
};
// Square brackets would break Markdown links, so swap them for parentheses.
const safe = (text) => String(text).replace(/\[/g, "(").replace(/\]/g, ")");

const gold = reading("gold");
const silver = reading("silver");
const day = new Date().toLocaleDateString("en-US", {
  weekday: "short", month: "short", day: "numeric", timeZone: "America/New_York",
});

const subject = `Bullion Radar, ${day}: Gold ${gold.score} ${gold.band}, Silver ${silver.score} ${silver.band}`;

const stories = site.newsHighlights()
  .map((n) => `- [${safe(n.title)}](${n.url || SITE_URL}) (${safe(n.source)})`)
  .join("\n");

const body = `**Gold: ${money(last.gold)}** (${change("gold")})
Buy scale **${gold.score} of 100, ${gold.band}**

${site.dailySummary("gold")}

**Silver: ${money(last.silver)}** (${change("silver")})
Buy scale **${silver.score} of 100, ${silver.band}**

${site.dailySummary("silver")}

Gold-to-silver ratio: ${last.ratio.toFixed(1)} : 1

### Top stories

${stories}

[See today's full reading, charts and history](${SITE_URL})

---

*Prices are COMEX futures. Not financial advice: the buy scale sums up current market conditions, and prices can still fall. You're getting this because you signed up at Bullion Radar.*
`;

async function main() {
  console.log(`SUBJECT: ${subject}\n\n${body}`);
  if (!process.argv.includes("--send")) {
    console.log("\n(Test only: nothing was sent. Use --send to send it.)");
    return;
  }
  const key = process.env.BUTTONDOWN_API_KEY;
  if (!key) throw new Error("BUTTONDOWN_API_KEY is missing, so nothing was sent.");
  const res = await fetch("https://api.buttondown.com/v1/emails", {
    method: "POST",
    headers: {
      Authorization: `Token ${key}`,
      "Content-Type": "application/json",
      "X-Buttondown-Live-Dangerously": "true",
    },
    body: JSON.stringify({ subject, body, status: "about_to_send" }),
  });
  if (!res.ok) throw new Error(`Buttondown refused the email: ${res.status} ${await res.text()}`);
  const email = await res.json();
  console.log(`\nSent: email ${email.id} (${email.status}).`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
