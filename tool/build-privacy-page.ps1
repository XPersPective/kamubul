$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'PRIVACY.md'
$hash = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
$content = (ConvertFrom-Markdown -LiteralPath $source).Html
$page = @"
<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="source-sha256" content="$hash"><title>KamuBul Gizlilik Politikası</title>
<style>body{margin:0;background:#f6f8fb;color:#172638;font:17px/1.7 system-ui,sans-serif}main{max-width:760px;margin:auto;padding:32px 24px}h1{font-size:30px;line-height:1.2}h2{font-size:22px;margin-top:32px}a{color:#174e75;overflow-wrap:anywhere}li{margin:8px 0}@media(prefers-color-scheme:dark){body{background:#0b1520;color:#eaf0f6}a{color:#9acbf1}}</style></head><body><main>$content</main></body></html>
"@
$destination = Join-Path $root 'workers/public/privacy/index.html'
New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
[IO.File]::WriteAllText($destination, $page, [Text.UTF8Encoding]::new($false))
