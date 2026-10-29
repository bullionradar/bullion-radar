// Shared header, footer and small building blocks, so every page stays in sync.

// Accounts for outside services. Leave a value empty to turn that feature off.
const SITE_CONFIG = {
  buttondownUsername: "bullionradar", // email alerts: the last part of your buttondown.com/... address
  goatcounterCode: "bullionradar", // visitor counter: the "code" part of code.goatcounter.com
  showVisitorCount: false, // show the total in the footer (turn on "Allow using the visitor counter" in GoatCounter first)

  // Shop: affiliate link templates from Awin (JM Bullion) and Impact (APMEX).
  // {url} is replaced with the dealer page. Empty = plain links that earn nothing.
  jmbullionAffiliate: "",
  apmexAffiliate: "",
};

// Turn a dealer page address into an affiliate link (or leave it plain if not set up).
function affiliateLink(template, url) {
  return template ? template.replace("{url}", encodeURIComponent(url)) : url;
}

// Coin photos (transparent PNGs cut out of product photos).
const COIN_IMAGES = { gold: "images/gold-eagle.png", silver: "images/silver-eagle.png" };
const coinImg = (metal, cls = "") =>
  `<img class="coin-img ${cls}" src="${COIN_IMAGES[metal]}" alt="">`;

// Periodic-table style element tile, drawn in the site's own style.
const ELEMENTS = {
  gold: { z: 79, sym: "Au", mass: "196.97" },
  silver: { z: 47, sym: "Ag", mass: "107.87" },
};
const elementTile = (metal) => {
  const e = ELEMENTS[metal];
  return `<span class="element ${metal}" aria-hidden="true">
    <span class="z">${e.z}</span><span class="sym">${e.sym}</span><span class="mass">${e.mass}</span>
  </span>`;
};

const RADAR_MARK = `
<svg viewBox="0 0 40 40" aria-hidden="true">
  <circle cx="20" cy="20" r="18.5" fill="none" stroke="#d4af5a" stroke-width="1.6"/>
  <circle cx="20" cy="20" r="11.5" fill="none" stroke="#d4af5a" stroke-width="1" opacity="0.55"/>
  <circle cx="20" cy="20" r="4.5" fill="none" stroke="#d4af5a" stroke-width="1" opacity="0.4"/>
  <path d="M20,20 L20,1.5 A18.5,18.5 0 0 1 35.5,10 Z" fill="#d4af5a" opacity="0.35"/>
  <line x1="20" y1="20" x2="35.5" y2="10" stroke="#f3dc97" stroke-width="1.6" stroke-linecap="round"/>
  <circle cx="29" cy="13.5" r="2.2" fill="#f3dc97"/>
</svg>`;

(function () {
  const page = document.body.dataset.page;
  const link = (href, name, label) =>
    `<a href="${href}" class="${page === name ? "active" : ""}"${page === name ? ' aria-current="page"' : ""}>${label}</a>`;

  document.body.insertAdjacentHTML(
    "afterbegin",
    `<header class="site-header">
      <div class="container">
        <a class="brand" href="index.html">${RADAR_MARK}<span>BULLION <span class="gold-word">RADAR</span></span></a>
        <nav class="nav" aria-label="Main">
          ${link("index.html", "home", `Today<span class="long">'s reading</span>`)}
          ${link("news.html", "news", "News")}
          ${link("melt.html", "melt", "Melt values")}
          ${link("how-it-works.html", "how", "How it works")}
          ${link("shop.html", "shop", "Shop")}
        </nav>
      </div>
    </header>
    ${window.LIVE ? "" : `<div class="notice">Preview: prices, scores and news are sample data until update-data.bat is run.</div>`}`
  );

  // Sub-pages put a coin photo in their title band.
  document.querySelectorAll("[data-hero-coin]").forEach((el) => {
    el.insertAdjacentHTML("afterbegin", coinImg(el.dataset.heroCoin, "hero-coin"));
  });

  document.body.insertAdjacentHTML(
    "beforeend",
    `<footer class="site-footer">
      <div class="container">
        <div class="brand">${RADAR_MARK}<span>BULLION <span class="gold-word">RADAR</span></span></div>
        <p><strong>Not financial advice.</strong> The Bullion Radar scale is an educational tool
        that sums up current market conditions. It isn't a recommendation to buy or sell, and
        metal prices can fall as well as rise. Do your own research before you buy.</p>
        <p class="footer-disclosure">Bullion Radar earns a commission on purchases made through
        links in our <a href="shop.html">shop</a>. This never affects the buy scale.</p>
        <p class="footer-meta">
          <span>&copy; ${new Date().getFullYear()} Bullion Radar</span>
          <a href="privacy.html">Privacy</a>
          <span id="visitor-count" hidden></span>
        </p>
      </div>
    </footer>`
  );

  // Visitor counter (GoatCounter: no cookies, no personal data).
  const gc = SITE_CONFIG.goatcounterCode;
  if (gc) {
    const s = document.createElement("script");
    s.async = true;
    s.src = "https://gc.zgo.at/count.js";
    s.dataset.goatcounter = `https://${gc}.goatcounter.com/count`;
    document.body.appendChild(s);

    if (SITE_CONFIG.showVisitorCount) {
      fetch(`https://${gc}.goatcounter.com/counter/TOTAL.json`)
        .then((r) => (r.ok ? r.json() : null))
        .then((data) => {
          if (!data || !data.count) return;
          const el = document.getElementById("visitor-count");
          el.textContent = `${data.count} visitors`;
          el.hidden = false;
        })
        .catch(() => {});
    }
  }
})();
