# Downloads real market data, scores the Buy Scale factors and writes live-data.js.
# Runs automatically on GitHub every few hours (.github/workflows/update-data.yml).
# To run it on this computer instead, double-click update-data.bat.
#
# Sources:
#   Yahoo Finance (no key): gold & silver COMEX futures, US Dollar Index
#   FRED API (free key): real interest rates, inflation expectations,
#   manufacturing output. The key comes from the FRED_API_KEY environment
#   variable (a GitHub secret) or, on this computer, from config.json.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $PSScriptRoot
$ua = @{ 'User-Agent' = 'Mozilla/5.0' }
$TenYears = 2520   # about 10 years of trading days
$inv = [Globalization.CultureInfo]::InvariantCulture

# --- Settings ---
$fredKey = $null
$configPath = Join-Path $root 'config.json'
if ($env:FRED_API_KEY) { $fredKey = $env:FRED_API_KEY.Trim() }
elseif (Test-Path $configPath) {
  $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
  if ($cfg.fredApiKey -and $cfg.fredApiKey -notmatch 'PASTE') { $fredKey = $cfg.fredApiKey.Trim() }
}

# --- Helpers ---
function Fmt([string]$format) { [string]::Format($inv, $format, [object[]]$args) }

function Get-Yahoo([string]$symbol) {
  $url = "https://query1.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($symbol))?range=10y&interval=1d"
  $res = (Invoke-RestMethod -Uri $url -Headers $ua -TimeoutSec 60).chart.result[0]
  $closes = $res.indicators.quote[0].close
  $series = [ordered]@{}
  for ($i = 0; $i -lt $res.timestamp.Count; $i++) {
    if ($null -ne $closes[$i]) {
      $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$res.timestamp[$i]).UtcDateTime.ToString('yyyy-MM-dd')
      $series[$date] = [double]$closes[$i]
    }
  }
  $series
}

function Get-Fred([string]$id, [int]$years) {
  $start = (Get-Date).AddYears(-$years).ToString('yyyy-MM-dd')
  $url = "https://api.stlouisfed.org/fred/series/observations?series_id=$id&api_key=$fredKey&file_type=json&observation_start=$start"
  $obs = (Invoke-RestMethod -Uri $url -TimeoutSec 60).observations
  $values = New-Object System.Collections.Generic.List[double]
  foreach ($o in $obs) { if ($o.value -ne '.') { $values.Add([double]::Parse($o.value, $inv)) } }
  , $values.ToArray()
}

# Share of past readings that are below the current one, 0-100.
function Get-Percentile([double[]]$history, [double]$current) {
  $below = 0
  foreach ($v in $history) { if ($v -lt $current) { $below++ } }
  [int][Math]::Round(100 * $below / $history.Count)
}

function Get-Last([double[]]$values, [int]$n) {
  $start = [Math]::Max(0, $values.Count - $n)
  , [double[]]($values[$start..($values.Count - 1)])
}

# How far each day's price was above (+) or below (-) its 200-day average.
function Get-Stretch([double[]]$values) {
  $out = New-Object System.Collections.Generic.List[double]
  $sum = 0.0
  for ($i = 0; $i -lt $values.Count; $i++) {
    $sum += $values[$i]
    if ($i -ge 200) { $sum -= $values[$i - 200] }
    if ($i -ge 199) { $out.Add($values[$i] / ($sum / 200) - 1) }
  }
  , $out.ToArray()
}

function New-Factor([int]$score, [string]$reading) { [ordered]@{ score = $score; reading = $reading } }

$factors = [ordered]@{ gold = [ordered]@{}; silver = [ordered]@{} }
$missing = New-Object System.Collections.Generic.List[string]

# --- Gold & silver prices (required) ---
Write-Host 'Downloading gold and silver prices...'
$gold = Get-Yahoo 'GC=F'
$silver = Get-Yahoo 'SI=F'
$dates = @($gold.Keys | Where-Object { $silver.Contains($_) })
$goldVals = [double[]]@($dates | ForEach-Object { $gold[$_] })
$silverVals = [double[]]@($dates | ForEach-Object { $silver[$_] })
$ratioVals = New-Object double[] $dates.Count
for ($i = 0; $i -lt $dates.Count; $i++) { $ratioVals[$i] = $goldVals[$i] / $silverVals[$i] }

# Price vs. 200-day average (value approach: less stretched = more favorable)
foreach ($metal in 'gold', 'silver') {
  $vals = if ($metal -eq 'gold') { $goldVals } else { $silverVals }
  $stretch = Get-Stretch $vals
  $now = $stretch[-1]
  $score = 100 - (Get-Percentile (Get-Last $stretch $TenYears) $now)
  $factors[$metal]['priceTrend'] = New-Factor $score (Fmt '{0:+0.0;-0.0}% vs. 200-day average' ($now * 100))
}

# Gold-to-silver ratio (low favors gold, high favors silver)
$ratioNow = $ratioVals[-1]
$ratioPct = Get-Percentile (Get-Last $ratioVals $TenYears) $ratioNow
$ratioText = Fmt 'Ratio {0:0.0} : 1' $ratioNow
$factors.gold['ratio'] = New-Factor (100 - $ratioPct) $ratioText
$factors.silver['ratio'] = New-Factor $ratioPct $ratioText

# --- US dollar strength (weaker = more favorable) ---
try {
  Write-Host 'Downloading US Dollar Index...'
  $dxy = [double[]]@((Get-Yahoo 'DX-Y.NYB').Values)
  $score = 100 - (Get-Percentile (Get-Last $dxy $TenYears) $dxy[-1])
  $f = New-Factor $score (Fmt 'Dollar index {0:0.0}' $dxy[-1])
  $factors.gold['dollar'] = $f
  $factors.silver['dollar'] = $f
} catch { $missing.Add('US dollar strength') ; Write-Warning "Dollar index failed: $($_.Exception.Message)" }

# --- FRED factors ---
if ($fredKey) {
  try {
    Write-Host 'Downloading real interest rates (FRED)...'
    $real = Get-Fred 'DFII10' 10
    $f = New-Factor (100 - (Get-Percentile $real $real[-1])) (Fmt 'Real 10-year yield {0:0.00}%' $real[-1])
    $factors.gold['realRates'] = $f
    $factors.silver['realRates'] = $f
  } catch { $missing.Add('Real interest rates'); Write-Warning "Real rates failed: $($_.Exception.Message)" }

  try {
    Write-Host 'Downloading inflation expectations (FRED)...'
    $be = Get-Fred 'T5YIE' 10
    $factors.gold['inflation'] = New-Factor (Get-Percentile $be $be[-1]) (Fmt '5-year inflation expectation {0:0.00}%' $be[-1])
  } catch { $missing.Add('Inflation expectations'); Write-Warning "Inflation failed: $($_.Exception.Message)" }

  try {
    Write-Host 'Downloading manufacturing output (FRED)...'
    $ip = Get-Fred 'IPMAN' 11
    $growth = New-Object System.Collections.Generic.List[double]
    for ($i = 12; $i -lt $ip.Count; $i++) { $growth.Add($ip[$i] / $ip[$i - 12] - 1) }
    $g = $growth.ToArray()
    $factors.silver['industrial'] = New-Factor (Get-Percentile (Get-Last $g 120) $g[-1]) (Fmt 'Manufacturing output {0:+0.0;-0.0}% vs. a year ago' ($g[-1] * 100))
  } catch { $missing.Add('Industrial demand'); Write-Warning "Manufacturing failed: $($_.Exception.Message)" }
} else {
  $missing.Add('Real interest rates'); $missing.Add('Inflation expectations'); $missing.Add('Industrial demand')
  Write-Warning 'No FRED key in config.json, so real rates, inflation and manufacturing are skipped.'
}

# --- News headlines (headline + link only; we never copy article text) ---
function Get-Text($node) { if ($node -is [Xml.XmlElement]) { $node.InnerText } else { [string]$node } }
function Get-Feed([string]$url) {
  $r = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $ua -TimeoutSec 30
  ([xml]$r.Content).rss.channel.item
}

$news = New-Object System.Collections.Generic.List[object]
$seen = @{}
# Market news only from these outlets, so we skip local price pages and videos.
$newsSites = 'reuters.com', 'kitco.com', 'cnbc.com', 'bloomberg.com', 'marketwatch.com', 'finance.yahoo.com',
  'fxstreet.com', 'investing.com', 'mining.com', 'barrons.com', 'wsj.com', 'forbes.com', 'ft.com', 'fool.com'
# Skip daily "price today" pages and site index pages that aren't real stories.
$junk = '(?i)(rate|price)s? (today|on )|today.?s (gold|silver) (rate|price)|\|'

function Add-Story($title, $source, $url, $date, $fallbackTag) {
  $t = ($title -replace '\s+', ' ').Trim()
  $k = $t.ToLower() -replace '[^a-z0-9]', ''
  if (-not $t -or $t -match $junk -or $seen.ContainsKey($k)) { return }
  # Market stories must be about metals in the headline itself, not just mention them.
  if ($fallbackTag -ne 'coins' -and $t -notmatch '(?i)\b(gold|silver|precious|bullion)') { return }
  $seen[$k] = $true
  try { $when = [DateTimeOffset]::Parse($date, $inv).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') } catch { return }
  $tags = @()
  if ($fallbackTag -eq 'coins') { $tags = @('coins') }
  else {
    if ($t -match '(?i)\bgold') { $tags += 'gold' }
    if ($t -match '(?i)\bsilver') { $tags += 'silver' }
    if (-not $tags) { $tags = @($fallbackTag) }
  }
  $news.Add([ordered]@{ title = $t; source = $source; url = $url; published = $when; tags = $tags })
}

try {
  Write-Host 'Downloading news headlines...'
  $siteQuery = '(' + (($newsSites | ForEach-Object { "site:$_" }) -join ' OR ') + ')'
  foreach ($metal in 'gold', 'silver') {
    $q = "$metal price $siteQuery when:7d"
    $url = 'https://news.google.com/rss/search?q=' + [uri]::EscapeDataString($q) + '&hl=en-US&gl=US&ceid=US:en'
    foreach ($item in Get-Feed $url) {
      $src = Get-Text $item.source
      $title = Get-Text $item.title
      if ($src -and $title.EndsWith(" - $src")) { $title = $title.Substring(0, $title.Length - $src.Length - 3) }
      Add-Story $title $src (Get-Text $item.link) (Get-Text $item.pubDate) $metal
    }
  }
  foreach ($item in Get-Feed 'https://www.numismaticnews.net/feed') {
    Add-Story (Get-Text $item.title) 'Numismatic News' (Get-Text $item.link) (Get-Text $item.pubDate) 'coins'
  }
} catch { $missing.Add('News'); Write-Warning "News failed: $($_.Exception.Message)" }

# Newest 20 gold, 15 silver and 10 coin stories, so gold doesn't crowd out the rest.
$byDate = @($news | Sort-Object { $_.published } -Descending)
$picked = @(
  @($byDate | Where-Object { $_.tags -contains 'gold' } | Select-Object -First 20) +
  @($byDate | Where-Object { $_.tags -contains 'silver' } | Select-Object -First 15) +
  @($byDate | Where-Object { $_.tags -contains 'coins' } | Select-Object -First 10)
)
$used = @{}
$newsOut = @($picked | Sort-Object { $_.published } -Descending | Where-Object {
  if ($used.ContainsKey($_.title)) { $false } else { $used[$_.title] = $true; $true }
})

# --- A related story for each factor ---
# For each factor we search recent news from the trusted outlets and keep the newest
# headline that is clearly about that topic (checked against the headline itself).
$storySites = $newsSites + @('numismaticnews.net', 'coinweek.com')
$storySiteQuery = '(' + (($storySites | ForEach-Object { "site:$_" }) -join ' OR ') + ')'
$factorTopics = [ordered]@{
  priceTrend = @{ q = '(forecast OR outlook OR technical OR "moving average")'; must = 'forecast|outlook|technical|average|support|resistance|rall|slide|slump|surge|falls|rises|climbs|drops|record|week' }
  dollar     = @{ q = '(dollar OR USD OR DXY)'; must = 'dollar|\bUSD\b|DXY|greenback' }
  realRates  = @{ q = '(yields OR "interest rates" OR Fed OR Treasury)'; must = 'yield|rate|Fed\b|Treasur' }
  inflation  = @{ q = '(inflation OR CPI OR PCE)'; must = 'inflation|CPI|PCE|PPI|prices rise' }
  ratio      = @{ q = '("gold-silver ratio" OR "gold/silver ratio" OR "gold to silver ratio" OR "gold and silver")'; must = 'ratio|gold.{0,12}silver|silver.{0,12}gold' }
  industrial = @{ q = '(industrial OR solar OR demand OR deficit OR supply)'; must = 'industr|solar|demand|deficit|supply|electronics|\bEV' }
}
$metalFactors = @{
  gold   = @('priceTrend', 'dollar', 'realRates', 'inflation', 'ratio')
  silver = @('priceTrend', 'dollar', 'realRates', 'industrial', 'ratio')
}
$factorNews = [ordered]@{ gold = [ordered]@{}; silver = [ordered]@{} }

Write-Host 'Finding related stories for each factor...'
foreach ($metal in 'gold', 'silver') {
  $usedUrls = @{}
  foreach ($key in $metalFactors[$metal]) {
    try {
      $topic = $factorTopics[$key]
      $q = "$metal $($topic.q) $storySiteQuery when:21d"
      $url = 'https://news.google.com/rss/search?q=' + [uri]::EscapeDataString($q) + '&hl=en-US&gl=US&ceid=US:en'
      $candidates = foreach ($item in Get-Feed $url) {
        $src = Get-Text $item.source
        $title = Get-Text $item.title
        if ($src -and $title.EndsWith(" - $src")) { $title = $title.Substring(0, $title.Length - $src.Length - 3) }
        $link = Get-Text $item.link
        try { $when = [DateTimeOffset]::Parse((Get-Text $item.pubDate), $inv).UtcDateTime } catch { continue }
        [pscustomobject]@{ title = ($title -replace '\s+', ' ').Trim(); source = $src; url = $link; published = $when }
      }
      $pick = $candidates |
        Where-Object { $_.title -notmatch $junk -and $_.title -match "(?i)$metal" -and $_.title -match "(?i)$($topic.must)" -and -not $usedUrls.ContainsKey($_.url) } |
        Sort-Object published -Descending | Select-Object -First 1
      if ($pick) {
        $usedUrls[$pick.url] = $true
        $factorNews[$metal][$key] = [ordered]@{
          title = $pick.title; source = $pick.source; url = $pick.url
          published = $pick.published.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
      }
    } catch { Write-Warning "Story search for $metal $key failed: $($_.Exception.Message)" }
  }
}

# --- Write live-data.js ---
$keep = [Math]::Min(400, $dates.Count)   # a bit over a year of trading days for the charts
$from = $dates.Count - $keep
$live = [ordered]@{
  updated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)   # shown in each visitor's time zone
  prices  = [ordered]@{
    dates  = $dates[$from..($dates.Count - 1)]
    gold   = @($goldVals[$from..($dates.Count - 1)] | ForEach-Object { [Math]::Round($_, 2) })
    silver = @($silverVals[$from..($dates.Count - 1)] | ForEach-Object { [Math]::Round($_, 3) })
  }
  factors = $factors
  news    = @($newsOut)
  factorNews = $factorNews
  missing = $missing.ToArray()
}
$json = $live | ConvertTo-Json -Depth 6 -Compress
Set-Content -Path (Join-Path $root 'live-data.js') -Value "window.LIVE = $json;" -Encoding UTF8

Write-Host ''
Write-Host "Done. Gold `$$([Math]::Round($goldVals[-1], 2)), silver `$$([Math]::Round($silverVals[-1], 2)), ratio $([Math]::Round($ratioNow, 1))."
foreach ($metal in 'gold', 'silver') {
  foreach ($k in $factors[$metal].Keys) { Write-Host ("  {0,-7} {1,-11} {2,3}  {3}" -f $metal, $k, $factors[$metal][$k].score, $factors[$metal][$k].reading) }
}
Write-Host "  news: $(@($newsOut).Count) headlines"
foreach ($metal in 'gold', 'silver') {
  foreach ($k in $metalFactors[$metal]) {
    $s = $factorNews[$metal][$k]
    Write-Host ("  story {0,-7} {1,-11} {2}" -f $metal, $k, $(if ($s) { "$($s.title) ($($s.source))" } else { '(none found)' }))
  }
}
if ($missing.Count) { Write-Host "Not connected yet: $($missing -join ', ')" }
