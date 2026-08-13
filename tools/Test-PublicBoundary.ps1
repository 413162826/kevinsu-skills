[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$manifestPath = Join-Path $root 'public-export.json'
Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) '缺少 public-export.json。'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
Assert-True ([int]$manifest.schemaVersion -eq 1) '不支持的 public-export.json 版本。'
Assert-True ([string]$manifest.policy -eq 'deny-by-default') '公开边界必须采用 deny-by-default。'

$allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($manifest.allowedFiles)) {
    $normalized = ([string]$entry).Replace('\', '/').TrimStart('/')
    Assert-True (-not [string]::IsNullOrWhiteSpace($normalized)) '公开白名单包含空路径。'
    Assert-True (-not [IO.Path]::IsPathRooted($normalized)) "公开白名单不得包含绝对路径：$normalized"
    Assert-True (-not $normalized.Contains('../')) "公开白名单不得越出仓库：$normalized"
    Assert-True ($allowed.Add($normalized)) "公开白名单路径重复：$normalized"
}

$actualFiles = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -Force |
        Where-Object { $_.FullName -notlike (Join-Path $root '.git\*') } |
        ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
        Sort-Object
)
$reparsePoints = @(
    Get-ChildItem -LiteralPath $root -Recurse -Force |
        Where-Object {
            $_.FullName -notlike (Join-Path $root '.git\*') -and
            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        } |
        ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') }
)
Assert-True ($reparsePoints.Count -eq 0) "公开仓库不得包含符号链接、Junction 或其他重解析点：$([Environment]::NewLine)$($reparsePoints -join [Environment]::NewLine)"

$unexpected = @($actualFiles | Where-Object { -not $allowed.Contains($_) })
Assert-True ($unexpected.Count -eq 0) "发现未经审查、未列入白名单的文件：$([Environment]::NewLine)$($unexpected -join [Environment]::NewLine)"

$missing = @($allowed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) } | Sort-Object)
Assert-True ($missing.Count -eq 0) "公开白名单中的文件缺失：$([Environment]::NewLine)$($missing -join [Environment]::NewLine)"

$forbiddenNames = @(
    'common-context.txt',
    'auth.json',
    '*.dpapi.json',
    '*-state.json',
    '*-receipt.json',
    '*.sqlite',
    '*.sqlite3',
    '.env',
    '.env.*'
)
foreach ($relativePath in $actualFiles) {
    $leaf = Split-Path -Leaf $relativePath
    foreach ($pattern in $forbiddenNames) {
        Assert-True (-not ($leaf -like $pattern)) "禁止公开运行态、凭据或私有上下文文件：$relativePath"
    }
}

$textExtensions = @('.md', '.json', '.yaml', '.yml', '.ps1', '.psm1', '.py', '.toml', '.html', '.txt')
foreach ($relativePath in $actualFiles) {
    $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    if ($extension -notin $textExtensions) { continue }
    $fullPath = Join-Path $root $relativePath
    $content = Get-Content -LiteralPath $fullPath -Raw -Encoding utf8
    Assert-True ($content -notmatch '(?i)C:\\Users\\') "发现固定的本机用户路径：$relativePath"
    Assert-True ($content -notmatch '\bwx[0-9A-Za-z]{16}\b') "发现疑似真实微信公众号 AppID：$relativePath"
    Assert-True ($content -notmatch '(?i)(app[_-]?secret|access[_-]?token)\s*[:=]\s*["''][0-9A-Za-z_-]{20,}["'']') "发现疑似真实 AppSecret 或 access token：$relativePath"
    if ($relativePath -like 'wechat-article-api/*' -or $relativePath -like 'wechat-image-api/*') {
        Assert-True ($content -notmatch '晚序拾光') "Skill 内不得写入作者自己的公众号名称，请保留为公开占位符：$relativePath"
    }
}

$scriptFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $root 'wechat-article-api') -Recurse -File -Include '*.ps1', '*.psm1'
    Get-ChildItem -LiteralPath (Join-Path $root 'wechat-image-api') -Recurse -File -Include '*.ps1', '*.psm1'
)
$forbiddenApiPatterns = @(
    '/cgi-bin/freepublish/',
    '/cgi-bin/message/mass/',
    '/cgi-bin/draft/delete',
    '/cgi-bin/material/del_material',
    '/cgi-bin/media/uploadvideo',
    '(?i)\bagent-browser\b',
    '(?i)\b(playwright|selenium|puppeteer)\b',
    '(?i)Start-Process[^\r\n]*(chrome|msedge|yingdao|影刀)'
)
foreach ($file in $scriptFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    foreach ($pattern in $forbiddenApiPatterns) {
        Assert-True ($content -notmatch $pattern) "发现正式发表、群发、删除或浏览器/RPA 调用：$($file.FullName.Substring($root.Length + 1))"
    }
    foreach ($urlMatch in [regex]::Matches($content, '(?<scheme>https?)://(?<host>[A-Za-z0-9.-]+)')) {
        $scheme = $urlMatch.Groups['scheme'].Value
        $hostName = $urlMatch.Groups['host'].Value
        Assert-True ($scheme -eq 'https' -and $hostName -eq 'api.weixin.qq.com') "Skill 脚本只允许连接 https://api.weixin.qq.com：$($urlMatch.Value)"
    }
}

"公开边界检查通过：$($actualFiles.Count) 个文件全部在精确白名单内。"
