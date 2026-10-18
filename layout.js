// Shared header, footer and small building blocks, so every page stays in sync.

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
          ${link("how-it-works.html", "how", "How it works")}
          <a href="#" aria-disabled="true">Shop<span class="soon">soon</span></a>
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
        <p>&copy; ${new Date().getFullYear()} Bullion Radar</p>
      </div>
    </footer>`
  );
})();
