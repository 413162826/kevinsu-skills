[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('wechat-article-api', 'wechat-image-api', 'all')]
    [string[]]$Name,

    [string]$DestinationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw '目录联接安装目前仅支持 Windows。'
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $codexRoot = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        $env:CODEX_HOME
    }
    else {
        Join-Path $env:USERPROFILE '.codex'
    }
    $DestinationRoot = Join-Path $codexRoot 'skills'
}
$destinationFull = [IO.Path]::GetFullPath($DestinationRoot)

$selectedNames = if ('all' -in $Name) {
    @('wechat-article-api', 'wechat-image-api')
}
else {
    @($Name | Select-Object -Unique)
}

$installPlan = foreach ($skillName in $selectedNames) {
    $source = Join-Path $repositoryRoot $skillName
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "仓库中缺少 Skill：$skillName"
    }
    [pscustomobject]@{
        Name = $skillName
        Source = $source
        Target = Join-Path $destinationFull $skillName
    }
}

$conflicts = @($installPlan | Where-Object { Test-Path -LiteralPath $_.Target })
if ($conflicts.Count -gt 0) {
    $targets = ($conflicts.Target -join [Environment]::NewLine)
    throw "目标 Skill 已存在，安装已在创建联接前停止；脚本不会覆盖现有内容：$([Environment]::NewLine)$targets"
}

if (-not (Test-Path -LiteralPath $destinationFull -PathType Container)) {
    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
}

$createdLinks = [Collections.Generic.List[object]]::new()
try {
    foreach ($item in $installPlan) {
        New-Item -ItemType Junction -Path $item.Target -Target $item.Source -ErrorAction Stop | Out-Null
        $link = Get-Item -LiteralPath $item.Target -Force
        $resolvedTarget = $link.ResolveLinkTarget($true).FullName
        if ($link.LinkType -ne 'Junction' -or -not [string]::Equals($resolvedTarget, $item.Source, [StringComparison]::OrdinalIgnoreCase)) {
            throw "目录联接验收失败：$($item.Target)"
        }
        $createdLinks.Add($item)
        "已联接 $($item.Name)：$($item.Target) -> $($item.Source)"
    }
}
catch {
    foreach ($item in $createdLinks) {
        $link = Get-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
        if ($link -and $link.LinkType -eq 'Junction' -and
            [string]::Equals($link.ResolveLinkTarget($true).FullName, $item.Source, [StringComparison]::OrdinalIgnoreCase)) {
            [IO.Directory]::Delete($item.Target, $false)
        }
    }
    throw
}
