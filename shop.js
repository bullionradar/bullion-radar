// Shop: popular bullion with today's melt value and links to dealers.
// oz = troy ounces of pure metal; q = what to search for on the dealer sites.
const SHOP_ITEMS = [
  { metal: "silver", name: "American Silver Eagle", detail: "1 oz coin", oz: 1, q: "american silver eagle" },
  { metal: "silver", name: "Canadian Silver Maple Leaf", detail: "1 oz coin", oz: 1, q: "silver maple leaf" },
  { metal: "silver", name: "Silver Britannia", detail: "1 oz coin", oz: 1, q: "silver britannia" },
  { metal: "silver", name: "Morgan silver dollar", detail: "Circulated, 1878–1904 and 1921", oz: 0.77344, q: "morgan silver dollar" },
  { metal: "silver", name: "90% silver coins (junk silver)", detail: "Per $1 face value", oz: 0.7234, q: "90% silver coins" },
  { metal: "silver", name: "Silver bar", detail: "10 oz", oz: 10, q: "10 oz silver bar" },
  { metal: "gold", name: "American Gold Eagle", detail: "1 oz coin", oz: 1, q: "1 oz american gold eagle" },
  { metal: "gold", name: "American Gold Eagle", detail: "1/10 oz coin", oz: 0.1, q: "1/10 oz american gold eagle" },
  { metal: "gold", name: "American Gold Buffalo", detail: "1 oz coin", oz: 1, q: "american gold buffalo" },
  { metal: "gold", name: "South African Krugerrand", detail: "1 oz coin", oz: 1, q: "gold krugerrand" },
  { metal: "gold", name: "Canadian Gold Maple Leaf", detail: "1 oz coin", oz: 1, q: "gold maple leaf" },
  { metal: "gold", name: "Gold bar", detail: "1 oz", oz: 1, q: "1 oz gold bar" },
];

const DEALERS = [
  { name: "JM Bullion", search: (q) => `https://www.jmbullion.com/search/?q=${encodeURIComponent(q)}`, template: SITE_CONFIG.jmbullionAffiliate },
  { name: "APMEX", search: (q) => `https://www.apmex.com/search?q=${encodeURIComponent(q)}`, template: SITE_CONFIG.apmexAffiliate },
];

const usd = (n) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const latest = HISTORY[HISTORY.length - 1];
const spot = { gold: latest.gold, silver: latest.silver };

for (const metal of ["silver", "gold"]) {
  document.getElementById("shop-" + metal).innerHTML = SHOP_ITEMS.filter((i) => i.metal === metal)
    .map((item) => `
      <div class="shop-item">
        <div class="shop-name">
          <strong>${item.name}</strong>
          <span>${item.detail}, ${item.oz} oz pure ${metal}</span>
        </div>
        <div class="shop-melt">
          <span>Melt value</span>
          <strong>${usd(item.oz * spot[metal])}</strong>
        </div>
        <div class="shop-buy">
          ${DEALERS.map((d) => `<a class="shop-btn" href="${affiliateLink(d.template, d.search(item.q))}"
            target="_blank" rel="sponsored noopener">${d.name}</a>`).join("")}
        </div>
      </div>`)
    .join("");
}

document.getElementById("shop-prices").textContent =
  `Melt values use gold at ${usd(spot.gold)} and silver at ${usd(spot.silver)} per troy ounce` +
  (LIVE_UPDATED ? `, as of ${LIVE_UPDATED}.` : " (sample prices).");
