param(
    [Parameter(Mandatory)][string]$InputFolder,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force

$folder = [IO.Path]::GetFullPath($InputFolder)
if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "文章素材目录不存在：$folder" }
$manifestPath = Join-Path $folder 'article.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "缺少 article.json：$folder" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json

$requiredFields = @('schemaVersion','action','account','title','bodyHtml','cover','bodyImages','needOpenComment','onlyFansCanComment')
foreach ($field in $requiredFields) {
    if ($field -notin $manifest.PSObject.Properties.Name) { throw "article.json 缺少必填字段：$field" }
}
if ([int]$manifest.schemaVersion -ne 1) { throw "不支持的 schemaVersion：$($manifest.schemaVersion)" }
if ([string]$manifest.action -ne 'save_draft_only') { throw 'action 必须是 save_draft_only。' }
$account = [string]$manifest.account
if ([string]::IsNullOrWhiteSpace($account)) { throw 'account 必填，且必须填写凭据对应的公众号名称。' }
if ($account -ne $account.Trim()) { throw 'account 不能包含首尾空白。' }
$title = [string]$manifest.title
if ([string]::IsNullOrWhiteSpace($title) -or $title.Length -gt 32) { throw '标题必须为 1–32 个字符。' }
$author = [string]$manifest.author
if ($author.Length -gt 16) { throw '作者不能超过 16 个字符。' }
$digest = [string]$manifest.digest
if ($digest.Length -gt 120) { throw '摘要不能超过 120 个字符。' }
if ([int]$manifest.needOpenComment -notin @(0,1)) { throw 'needOpenComment 只能是 0 或 1。' }
if ([int]$manifest.onlyFansCanComment -notin @(0,1)) { throw 'onlyFansCanComment 只能是 0 或 1。' }
$contentSourceUrl = [string]$manifest.contentSourceUrl
if (-not [string]::IsNullOrWhiteSpace($contentSourceUrl)) {
    $sourceUri = $null
    if (-not [Uri]::TryCreate($contentSourceUrl, [UriKind]::Absolute, [ref]$sourceUri) -or
        $sourceUri.Scheme -notin @('http','https') -or
        [string]::IsNullOrWhiteSpace($sourceUri.Host) -or
        -not [string]::IsNullOrEmpty($sourceUri.UserInfo)) {
        throw 'contentSourceUrl 必须是无用户名密码的绝对 http 或 https URL，也可以留空。'
    }
}

if ([string]::IsNullOrWhiteSpace([string]$manifest.bodyHtml)) { throw 'bodyHtml 必须指向素材目录内的正文 HTML。' }
if ([string]::IsNullOrWhiteSpace([string]$manifest.cover)) { throw 'cover 必须指向素材目录内的封面图片。' }

$bodyPath = Resolve-SafePackagePath -Root $folder -RelativePath ([string]$manifest.bodyHtml)
$coverPath = Resolve-SafePackagePath -Root $folder -RelativePath ([string]$manifest.cover)
$cover = Get-Item -LiteralPath $coverPath
if ($cover.Extension.ToLowerInvariant() -notin @('.bmp','.png','.jpeg','.jpg','.gif')) { throw '封面只支持 BMP/PNG/JPG/GIF。' }
if ($cover.Length -gt 10MB) { throw '封面不能超过 10MB。' }

$bodyHtml = Get-Content -LiteralPath $bodyPath -Raw -Encoding utf8
if ([string]::IsNullOrWhiteSpace($bodyHtml)) { throw 'body.html 不能为空。' }
if ($bodyHtml.Length -ge 20000) { throw '正文 HTML 必须少于 20000 个字符。' }
if ([Text.Encoding]::UTF8.GetByteCount($bodyHtml) -ge 1MB) { throw '正文 HTML 必须小于 1MB。' }
if ($bodyHtml -match '<script\b|javascript:|\son\w+\s*=') { throw '正文 HTML 禁止脚本、javascript URL 和事件属性。' }

$images = @()
$markers = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($item in @($manifest.bodyImages)) {
    if ($null -eq $item) { throw 'bodyImages 不能包含空项。' }
    $marker = [string]$item.marker
    if ([string]::IsNullOrWhiteSpace($marker)) { throw '正文图片 marker 不能为空。' }
    if (-not $markers.Add($marker)) { throw "正文图片 marker 重复：$marker" }
    $pattern = 'data-wechat-image\s*=\s*["'']' + [regex]::Escape($marker) + '["'']'
    if ([regex]::Matches($bodyHtml, $pattern, 'IgnoreCase').Count -ne 1) { throw "正文 marker 必须恰好出现一次：$marker" }
    if ([string]::IsNullOrWhiteSpace([string]$item.path)) { throw "正文图片路径不能为空：$marker" }
    $path = Resolve-SafePackagePath -Root $folder -RelativePath ([string]$item.path)
    $file = Get-Item -LiteralPath $path
    if ($file.Extension.ToLowerInvariant() -notin @('.png','.jpeg','.jpg')) { throw "正文图片只支持 JPG/PNG：$($item.path)" }
    if ($file.Length -ge 1MB) { throw "正文图片必须小于 1MB：$($item.path)" }
    $images += [pscustomobject]@{ Marker = $marker; Path = $path }
}

foreach ($match in [regex]::Matches($bodyHtml, 'data-wechat-image\s*=\s*["''](?<marker>[^"'']+)["'']', 'IgnoreCase')) {
    if (-not $markers.Contains($match.Groups['marker'].Value)) {
        throw "正文存在未在 bodyImages 声明的 marker：$($match.Groups['marker'].Value)"
    }
}

$paths = @($manifestPath, $bodyPath, $coverPath) + @($images.Path)
$result = [pscustomobject]@{
    Status = 'PASS'
    Folder = $folder
    ManifestPath = $manifestPath
    Manifest = $manifest
    BodyPath = $bodyPath
    BodyHtml = $bodyHtml
    CoverPath = $coverPath
    BodyImages = $images
    Fingerprint = Get-WeChatPackageFingerprint -Paths $paths
}
if ($PassThru) { return $result }
$result | Select-Object Status,Folder,@{N='Title';E={$_.Manifest.title}},@{N='BodyImageCount';E={$_.BodyImages.Count}},Fingerprint | Format-List
