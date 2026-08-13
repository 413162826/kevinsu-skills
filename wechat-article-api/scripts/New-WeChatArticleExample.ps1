param(
    [Parameter(Mandatory)][string]$OutputFolder
)

$ErrorActionPreference = 'Stop'
$folder = [IO.Path]::GetFullPath($OutputFolder)
if (Test-Path -LiteralPath $folder) {
    if (@(Get-ChildItem -LiteralPath $folder -Force).Count -gt 0) {
        throw "示例输出目录必须不存在或为空：$folder"
    }
}
else {
    New-Item -ItemType Directory -Path $folder | Out-Null
}

$assets = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets'
$imagesFolder = Join-Path $folder 'images'
New-Item -ItemType Directory -Path $imagesFolder -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $assets 'article.json') -Destination (Join-Path $folder 'article.json')
Copy-Item -LiteralPath (Join-Path $assets 'body.html') -Destination (Join-Path $folder 'body.html')

# 1×1 像素的合成 PNG，仅用于离线验证素材包契约。
$pngBytes = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAE/wJ/lkiU2QAAAABJRU5ErkJggg==')
[IO.File]::WriteAllBytes((Join-Path $folder 'cover.png'), $pngBytes)
[IO.File]::WriteAllBytes((Join-Path $imagesFolder 'section-01.png'), $pngBytes)

& (Join-Path $PSScriptRoot 'Test-WeChatArticlePackage.ps1') -InputFolder $folder
