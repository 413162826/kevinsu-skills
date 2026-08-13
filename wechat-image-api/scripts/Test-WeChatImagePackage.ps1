param(
    [Parameter(Mandatory)][string]$InputFolder,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
Assert-WeChatRuntime

function Get-RequiredManifestValue {
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Manifest.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "image-post.json 缺少必填字段：$Name。"
    }
    return $property.Value
}

$folder = [IO.Path]::GetFullPath($InputFolder)
if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "贴图素材目录不存在：$folder" }
$manifestPath = Join-Path $folder 'image-post.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "缺少 image-post.json：$folder" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json

$schemaVersion = Get-RequiredManifestValue -Manifest $manifest -Name 'schemaVersion'
if ([int]$schemaVersion -ne 1) { throw "不支持的 schemaVersion：$schemaVersion" }
$action = [string](Get-RequiredManifestValue -Manifest $manifest -Name 'action')
if ($action -ne 'save_draft_only') { throw 'action 必须是 save_draft_only。' }
$account = [string](Get-RequiredManifestValue -Manifest $manifest -Name 'account')
if ([string]::IsNullOrWhiteSpace($account)) { throw 'account 必须填写目标公众号的准确名称。' }
if ($account -ne $account.Trim()) { throw 'account 首尾不能包含空白字符。' }
$title = [string](Get-RequiredManifestValue -Manifest $manifest -Name 'title')
if ([string]::IsNullOrWhiteSpace($title) -or $title.Length -gt 32) { throw '标题必须为 1–32 个字符。' }
if ($title -ne $title.Trim()) { throw '标题首尾不能包含空白字符。' }
$content = [string](Get-RequiredManifestValue -Manifest $manifest -Name 'content')
if ([string]::IsNullOrWhiteSpace($content)) { throw '贴图正文不能为空。' }
if ($content -match '<[^>]+>') { throw '贴图正文只接受纯文本，不接受 HTML。' }
if ($content.Length -ge 20000 -or [Text.Encoding]::UTF8.GetByteCount($content) -ge 1MB) { throw '贴图正文必须少于 20000 字符且小于 1MB。' }
$needOpenComment = Get-RequiredManifestValue -Manifest $manifest -Name 'needOpenComment'
$onlyFansCanComment = Get-RequiredManifestValue -Manifest $manifest -Name 'onlyFansCanComment'
if ($needOpenComment -isnot [long] -and $needOpenComment -isnot [int]) { throw 'needOpenComment 必须是数字 0 或 1，不能是字符串或布尔值。' }
if ($onlyFansCanComment -isnot [long] -and $onlyFansCanComment -isnot [int]) { throw 'onlyFansCanComment 必须是数字 0 或 1，不能是字符串或布尔值。' }
if ([int]$needOpenComment -notin @(0,1)) { throw 'needOpenComment 只能是数字 0 或 1。' }
if ([int]$onlyFansCanComment -notin @(0,1)) { throw 'onlyFansCanComment 只能是数字 0 或 1。' }
if ([int]$needOpenComment -eq 0 -and [int]$onlyFansCanComment -eq 1) {
    throw 'needOpenComment 为 0 时，onlyFansCanComment 必须为 0。'
}

$imageEntries = @(Get-RequiredManifestValue -Manifest $manifest -Name 'images')
if ($imageEntries.Count -lt 1 -or $imageEntries.Count -gt 20) { throw '贴图必须包含 1–20 张图片。' }
$images = @()
foreach ($relativePath in $imageEntries) {
    if ([string]::IsNullOrWhiteSpace([string]$relativePath)) { throw 'images 不得包含空路径。' }
    $path = Resolve-SafePackagePath -Root $folder -RelativePath ([string]$relativePath)
    $file = Get-Item -LiteralPath $path
    if ($file.Extension.ToLowerInvariant() -notin @('.bmp','.png','.jpeg','.jpg','.gif')) { throw "贴图格式不支持：$relativePath" }
    if ($file.Length -gt 10MB) { throw "贴图不能超过 10MB：$relativePath" }
    $images += $path
}
if (@($images | Select-Object -Unique).Count -ne $images.Count) { throw 'images 不得重复引用同一文件。' }

$manifest.account = $account
$manifest.title = $title
$manifest.needOpenComment = [int]$needOpenComment
$manifest.onlyFansCanComment = [int]$onlyFansCanComment

$result = [pscustomobject]@{
    Status = 'PASS'
    Folder = $folder
    ManifestPath = $manifestPath
    Manifest = $manifest
    Images = $images
    Fingerprint = Get-WeChatPackageFingerprint -Paths (@($manifestPath) + $images)
}
if ($PassThru) { return $result }
$result | Select-Object Status,Folder,@{N='Title';E={$_.Manifest.title}},@{N='ImageCount';E={$_.Images.Count}},Fingerprint | Format-List
