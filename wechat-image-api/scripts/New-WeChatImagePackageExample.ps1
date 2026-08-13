param(
    [Parameter(Mandatory)][string]$OutputFolder
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
Assert-WeChatRuntime

$output = [IO.Path]::GetFullPath($OutputFolder)
$manifestTarget = Join-Path $output 'image-post.json'
$imageFolder = Join-Path $output 'images'
$imageTarget = Join-Path $imageFolder 'post-01.png'
if (Test-Path -LiteralPath $manifestTarget -PathType Leaf) { throw "目标目录已包含 image-post.json，不会覆盖：$manifestTarget" }
if (Test-Path -LiteralPath $imageTarget -PathType Leaf) { throw "目标目录已包含示例图片，不会覆盖：$imageTarget" }

New-Item -ItemType Directory -Force -Path $imageFolder | Out-Null
$assetRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets'))
Copy-Item -LiteralPath (Join-Path $assetRoot 'image-post.json') -Destination $manifestTarget
$encoded = (Get-Content -LiteralPath (Join-Path $assetRoot 'images\post-01.png.base64') -Raw -Encoding utf8).Trim()
[IO.File]::WriteAllBytes($imageTarget, [Convert]::FromBase64String($encoded))

& (Join-Path $PSScriptRoot 'Test-WeChatImagePackage.ps1') -InputFolder $output
