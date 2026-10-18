// Coin melt value calculator.
// oz = troy ounces of pure metal in one coin (standard mint specifications).
const MELT_COINS = [
  { group: "Silver", metal: "silver", name: "American Silver Eagle (1 oz)", oz: 1 },
  { group: "Silver", metal: "silver", name: "Canadian Silver Maple Leaf (1 oz)", oz: 1 },
  { group: "Silver", metal: "silver", name: "Britannia (1 oz)", oz: 1 },
  { group: "Silver", metal: "silver", name: "Morgan or Peace dollar (1878–1935)", oz: 0.77344 },
  { group: "Silver", metal: "silver", name: "Walking Liberty, Franklin or 1964 Kennedy half (90%)", oz: 0.36169 },
  { group: "Silver", metal: "silver", name: "Kennedy half, 1965–1970 (40%)", oz: 0.14792 },
  { group: "Silver", metal: "silver", name: "Washington quarter, 1964 and earlier (90%)", oz: 0.18084 },
  { group: "Silver", metal: "silver", name: "Roosevelt or Mercury dime, 1964 and earlier (90%)", oz: 0.07234 },
  { group: "Silver", metal: "silver", name: "Jefferson war nickel, 1942–1945 (35%)", oz: 0.05626 },
  { group: "Silver", metal: "silver", name: "$1 face value of 90% silver dimes, quarters or halves", oz: 0.7234 },
  { group: "Gold", metal: "gold", name: "American Gold Eagle (1 oz)", oz: 1 },
  { group: "Gold", metal: "gold", name: "American Gold Eagle (1/2 oz)", oz: 0.5 },
  { group: "Gold", metal: "gold", name: "American Gold Eagle (1/4 oz)", oz: 0.25 },
  { group: "Gold", metal: "gold", name: "American Gold Eagle (1/10 oz)", oz: 0.1 },
  { group: "Gold", metal: "gold", name: "American Gold Buffalo (1 oz)", oz: 1 },
  { group: "Gold", metal: "gold", name: "Canadian Gold Maple Leaf (1 oz)", oz: 1 },
  { group: "Gold", metal: "gold", name: "South African Krugerrand (1 oz)", oz: 1 },
  { group: "Gold", metal: "gold", name: "$20 Double Eagle (pre-1933)", oz: 0.96750 },
  { group: "Gold", metal: "gold", name: "$10 Eagle (pre-1933)", oz: 0.48375 },
  { group: "Gold", metal: "gold", name: "$5 Half Eagle (pre-1929)", oz: 0.24187 },
  { group: "Gold", metal: "gold", name: "British Sovereign", oz: 0.23542 },
];

const usd = (n) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const latest = HISTORY[HISTORY.length - 1];
const spot = { gold: latest.gold, silver: latest.silver };
const meltOf = (coin) => coin.oz * spot[coin.metal];

const select = document.getElementById("melt-coin");
const qty = document.getElementById("melt-qty");

select.innerHTML = ["Silver", "Gold"]
  .map((group) => `<optgroup label="${group}">${MELT_COINS.map((c, i) => c.group === group
    ? `<option value="${i}">${c.name}</option>` : "").join("")}</optgroup>`)
  .join("");

function update() {
  const coin = MELT_COINS[Number(select.value)];
  const n = Math.max(0, Number(qty.value) || 0);
  document.getElementById("melt-total").textContent = usd(meltOf(coin) * n);
  document.getElementById("melt-detail").textContent =
    `${n} × ${coin.oz} oz of ${coin.metal} at ${usd(spot[coin.metal])} per oz`;
}
select.addEventListener("change", update);
qty.addEventListener("input", update);
update();

for (const metal of ["silver", "gold"]) {
  document.getElementById("melt-" + metal).innerHTML = `
    <thead><tr><th>${metal === "gold" ? "Gold" : "Silver"} coin</th><th>Pure metal</th><th>Melt value</th></tr></thead>
    <tbody>${MELT_COINS.filter((c) => c.metal === metal).map((c) => `
      <tr><td>${c.name}</td><td>${c.oz} oz</td><td><strong>${usd(meltOf(c))}</strong></td></tr>`).join("")}
    </tbody>`;
}

document.getElementById("melt-prices").textContent =
  `Using gold at ${usd(spot.gold)} and silver at ${usd(spot.silver)} per troy ounce` +
  (LIVE_UPDATED ? `, as of ${LIVE_UPDATED}.` : " (sample prices).");
