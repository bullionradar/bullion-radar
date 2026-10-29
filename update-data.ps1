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
  # 15 years of daily closes: 10 years for today's comparison plus room for the score history.
  $to = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $from = [DateTimeOffset]::UtcNow.AddYears(-15).ToUnixTimeSeconds()
  $url = "https://query1.finance.yahoo.com/v8/finance/chart/$([uri]::EscapeDataString($symbol))?period1=$from&period2=$to&interval=1d"
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

# Same as Get-Fred, but keeps the dates (date -> value), for the score history.
function Get-FredSeries([string]$id, [int]$years) {
  $start = (Get-Date).AddYears(-$years).ToString('yyyy-MM-dd')
  $url = "https://api.stlouisfed.org/fred/series/observations?series_id=$id&api_key=$fredKey&file_type=json&observation_start=$start"
  $obs = (Invoke-RestMethod -Uri $url -TimeoutSec 60).observations
  $series = [ordered]@{}
  foreach ($o in $obs) { if ($o.value -ne '.') { $series[$o.date] = [double]::Parse($o.value, $inv) } }
  $series
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

# --- Scale history ---
# Weekly factor scores for the last 3 years, worked out with the same rules as today's
# scores. Each past score only uses data that was available on that date (a trailing
# 10-year comparison, and monthly figures only from about when they were published).
# The site combines these into the overall score using the weights in data.js.
Write-Host 'Working out the scale history...'

# Line a series (date -> value) up with the trading days, carrying the last known value
# forward. lagDays delays each value to roughly when it was published.
function Align-ToDates($series, [string[]]$days, [int]$lagDays = 0) {
  $keys = @($series.Keys)
  $out = New-Object double[] $days.Count
  $k = -1
  for ($i = 0; $i -lt $days.Count; $i++) {
    while ($k + 1 -lt $keys.Count -and ([datetime]$keys[$k + 1]).AddDays($lagDays).ToString('yyyy-MM-dd') -le $days[$i]) { $k++ }
    $out[$i] = if ($k -ge 0) { $series[$keys[$k]] } else { [double]::NaN }
  }
  , $out
}

# Percentile of day i against the 10 years before it (skipping days with no data).
function Get-HistPercentile([double[]]$arr, [int]$i) {
  $cur = $arr[$i]
  if ([double]::IsNaN($cur)) { return $null }
  $below = 0; $n = 0
  for ($k = [Math]::Max(0, $i - $TenYears + 1); $k -le $i; $k++) {
    $v = $arr[$k]
    if (-not [double]::IsNaN($v)) { $n++; if ($v -lt $cur) { $below++ } }
  }
  if ($n -lt 500) { return $null }   # not enough history yet to judge
  [int][Math]::Round(100 * $below / $n)
}

$raw = @{}
foreach ($metal in 'gold', 'silver') {
  $vals = if ($metal -eq 'gold') { $goldVals } else { $silverVals }
  $s = Get-Stretch $vals
  $aligned = New-Object double[] $dates.Count
  for ($i = 0; $i -lt $dates.Count; $i++) { $aligned[$i] = if ($i -ge 199) { $s[$i - 199] } else { [double]::NaN } }
  $raw["stretch-$metal"] = $aligned
}
$raw['ratio'] = $ratioVals
try { $raw['dollar'] = Align-ToDates (Get-Yahoo 'DX-Y.NYB') $dates } catch { Write-Warning "Dollar history failed: $($_.Exception.Message)" }
if ($fredKey) {
  try { $raw['realRates'] = Align-ToDates (Get-FredSeries 'DFII10' 14) $dates 1 } catch { Write-Warning "Real rate history failed: $($_.Exception.Message)" }
  try { $raw['inflation'] = Align-ToDates (Get-FredSeries 'T5YIE' 14) $dates 1 } catch { Write-Warning "Inflation history failed: $($_.Exception.Message)" }
  try {
    $ipSeries = Get-FredSeries 'IPMAN' 15
    $ipKeys = @($ipSeries.Keys)
    $growth = [ordered]@{}
    for ($i = 12; $i -lt $ipKeys.Count; $i++) { $growth[$ipKeys[$i]] = $ipSeries[$ipKeys[$i]] / $ipSeries[$ipKeys[$i - 12]] - 1 }
    $raw['industrial'] = Align-ToDates $growth $dates 45
  } catch { Write-Warning "Manufacturing history failed: $($_.Exception.Message)" }
}

# Which raw series each factor uses, and whether a higher reading is better (+1) or worse (-1).
$historyFactors = @{
  gold   = [ordered]@{ priceTrend = @('stretch-gold', -1); dollar = @('dollar', -1); realRates = @('realRates', -1); inflation = @('inflation', 1); ratio = @('ratio', -1) }
  silver = [ordered]@{ priceTrend = @('stretch-silver', -1); dollar = @('dollar', -1); realRates = @('realRates', -1); industrial = @('industrial', 1); ratio = @('ratio', 1) }
}

# One point a week (every 5 trading days) for the last 3 years, always ending on the latest day.
$points = New-Object System.Collections.Generic.List[int]
for ($i = $dates.Count - 1; $i -ge [Math]::Max(0, $dates.Count - 756); $i -= 5) { $points.Insert(0, $i) }

$scoreHistory = [ordered]@{
  dates  = @($points | ForEach-Object { $dates[$_] })
  prices = [ordered]@{
    gold   = @($points | ForEach-Object { [Math]::Round($goldVals[$_], 2) })
    silver = @($points | ForEach-Object { [Math]::Round($silverVals[$_], 3) })
  }
  gold   = [ordered]@{}
  silver = [ordered]@{}
}
foreach ($metal in 'gold', 'silver') {
  foreach ($key in $historyFactors[$metal].Keys) {
    $name, $direction = $historyFactors[$metal][$key]
    $arr = $raw[$name]
    $scoreHistory[$metal][$key] = @(foreach ($i in $points) {
      if ($null -eq $arr) { $null; continue }
      $p = Get-HistPercentile $arr $i
      if ($null -eq $p) { $null } elseif ($direction -gt 0) { $p } else { 100 - $p }
    })
  }
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

# --- Silver alert email ---
# When silver's overall score moves up into Favorable (61+), email the alert subscribers
# once through Buttondown. It re-arms only after the score drops back to 55 or below, so
# a score hovering around 60 doesn't send an email every few hours.
# The weights are read from data.js so they always match the site.
$alertStatePath = Join-Path $root 'alert-state.json'
try {
  $dataJs = Get-Content (Join-Path $root 'data.js') -Raw
  $silverBlock = [regex]::Match($dataJs, '(?s)silver: \[(.*?)\],').Groups[1].Value
  $weights = @{}
  foreach ($m in [regex]::Matches($silverBlock, 'key: "(\w+)"[^}]*?weight: (\d+)')) { $weights[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
  $sum = 0; $wsum = 0
  foreach ($k in $weights.Keys) { if ($factors.silver.Contains($k)) { $sum += $factors.silver[$k].score * $weights[$k]; $wsum += $weights[$k] } }
  if ($wsum -eq 0) { throw 'no silver factors to score' }
  $silverScore = [int][Math]::Round($sum / $wsum)

  $firstRun = -not (Test-Path $alertStatePath)
  $state = if ($firstRun) { [pscustomobject]@{ silverFavorable = $false; lastAlert = $null } } else { Get-Content $alertStatePath -Raw | ConvertFrom-Json }
  $wasFavorable = [bool]$state.silverFavorable
  $nowFavorable = if ($silverScore -ge 61) { $true } elseif ($silverScore -le 55) { $false } else { $wasFavorable }
  Write-Host "Silver alert: score $silverScore, favorable before=$wasFavorable now=$nowFavorable"

  if ($nowFavorable -and -not $wasFavorable -and -not $firstRun) {
    if ($env:BUTTONDOWN_API_KEY) {
      $names = @{ ratio = 'Gold-to-silver ratio'; priceTrend = 'Price vs. 200-day average'; dollar = 'US dollar strength'; industrial = 'Industrial demand'; realRates = 'Real interest rates' }
      $helping = @($factors.silver.Keys | Where-Object { $factors.silver[$_].score -ge 60 } |
        ForEach-Object { "- **$($names[$_])** ($($factors.silver[$_].score)/100): $($factors.silver[$_].reading)" }) -join "`n"
      $body = @"
Silver just moved to **Favorable** on the Bullion Radar buy scale, with a score of **$silverScore out of 100**.

Silver is at **`$$([Math]::Round($silverVals[-1], 2))** per ounce.

What's helping the score:
$helping

[See today's full reading](https://bullionreads.com/)

*Not financial advice. The buy scale sums up current market conditions; prices can still fall.*
"@
      $payload = @{ subject = "Silver just moved to Favorable ($silverScore/100)"; body = $body; status = 'about_to_send' } | ConvertTo-Json
      $headers = @{ Authorization = "Token $($env:BUTTONDOWN_API_KEY)"; 'X-Buttondown-Live-Dangerously' = 'true' }
      Invoke-RestMethod -Method Post -Uri 'https://api.buttondown.com/v1/emails' -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 60 | Out-Null
      Write-Host 'Silver alert email sent.'
      $state.lastAlert = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', $inv)
    } else {
      Write-Warning 'Silver moved to Favorable, but there is no BUTTONDOWN_API_KEY, so no email was sent.'
    }
  }
  $state.silverFavorable = $nowFavorable
  $state | ConvertTo-Json | Set-Content -Path $alertStatePath -Encoding UTF8
} catch { Write-Warning "Silver alert check failed: $($_.Exception.Message)" }

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
  scoreHistory = $scoreHistory
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
