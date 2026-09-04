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

function Assert-ThrowsLike {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string[]]$ExpectedFragments,
        [Parameter(Mandatory)][string]$Because
    )
    try {
        & $ScriptBlock
        throw "预期失败但实际成功：$Because"
    }
    catch {
        $message = $_.Exception.Message
        if ($message -like '预期失败但实际成功*') { throw }
        foreach ($fragment in $ExpectedFragments) {
            Assert-True ($message.Contains($fragment)) "$Because；错误消息缺少片段 [$fragment]：$message"
        }
    }
}

function Write-TinyPng {
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
    [IO.File]::WriteAllBytes($Path, [Convert]::FromBase64String($base64))
}

$root = [IO.Path]::GetFullPath($RepositoryRoot)

# 所有 PowerShell 文件必须先通过 AST 语法解析。
$parseFailures = @()
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ps1', '*.psm1') {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($error in @($errors)) {
        $parseFailures += "$($file.FullName.Substring($root.Length + 1)):$($error.Extent.StartLineNumber) $($error.Message)"
    }
}
Assert-True ($parseFailures.Count -eq 0) "PowerShell AST 语法检查失败：$([Environment]::NewLine)$($parseFailures -join [Environment]::NewLine)"

# 所有公开 Skill 都必须通过统一元数据校验，避免 CI 清单新增 Skill 时漏改 workflow。
$skillValidator = Join-Path $root 'tools/quick_validate.py'
foreach ($skillName in @('wechat-article-api', 'wechat-image-api', 'kevin-xhs-minitool-publisher')) {
    & python -X utf8 $skillValidator (Join-Path $root $skillName) | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "$skillName 元数据校验失败。"
}

# 运行每个 Skill 自带的零网络回归测试。
& (Join-Path $root 'wechat-article-api/scripts/Test-WeChatArticleApiOffline.ps1') | Out-Null
& (Join-Path $root 'wechat-image-api/scripts/Test-WeChatImageApiOffline.ps1') | Out-Null

# 发布模板默认对所有用户开启留言。
foreach ($samplePath in @(
    'wechat-article-api/assets/article.json',
    'wechat-image-api/assets/image-post.json'
)) {
    $sample = Get-Content -LiteralPath (Join-Path $root $samplePath) -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ([int]$sample.needOpenComment -eq 1) "$samplePath 必须默认开启留言（needOpenComment=1）。"
    Assert-True ([int]$sample.onlyFansCanComment -eq 0) "$samplePath 必须允许所有用户留言（onlyFansCanComment=0）。"
    Assert-True ([string]$sample.account -eq 'YOUR_WECHAT_ACCOUNT_NAME') "$samplePath 的 account 必须保留为 YOUR_WECHAT_ACCOUNT_NAME 公开占位符。"
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("kevinsu-skills-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
try {
    # 安装器必须创建单源码目录联接，并在创建前发现冲突，不能覆盖用户现有 Skill。
    $installRoot = Join-Path $temporaryRoot 'installed-skills'
    & (Join-Path $root 'tools/Install-Skill.ps1') -Name 'all' -DestinationRoot $installRoot | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'wechat-article-api/SKILL.md') -PathType Leaf) '安装器未复制文章 Skill。'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'wechat-image-api/SKILL.md') -PathType Leaf) '安装器未复制贴图 Skill。'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'kevin-xhs-minitool-publisher/SKILL.md') -PathType Leaf) '安装器未复制小红书小工具 Skill。'
    foreach ($skillName in @('wechat-article-api', 'wechat-image-api', 'kevin-xhs-minitool-publisher')) {
        $installed = Get-Item -LiteralPath (Join-Path $installRoot $skillName) -Force
        Assert-True ($installed.LinkType -eq 'Junction') "安装器没有为 $skillName 创建 Junction。"
        Assert-True ([string]::Equals(
            $installed.ResolveLinkTarget($true).FullName,
            (Join-Path $root $skillName),
            [StringComparison]::OrdinalIgnoreCase
        )) "安装器为 $skillName 创建了错误的 Junction 目标。"
    }
    Assert-ThrowsLike -ScriptBlock {
        & (Join-Path $root 'tools/Install-Skill.ps1') -Name 'wechat-article-api' -DestinationRoot $installRoot | Out-Null
    } -ExpectedFragments @('目标 Skill 已存在', '不会覆盖') -Because '安装器必须拒绝覆盖已有 Skill'

    # 小红书小工具校验器必须放行离线包，并拒绝外链；官方 Skill 下载器必须先拒绝非官方域名，不能发起网络请求。
    $xhsFixture = Join-Path $temporaryRoot 'xhs-minitool'
    $xhsAssets = Join-Path $xhsFixture 'assets'
    New-Item -ItemType Directory -Path $xhsAssets -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $xhsFixture 'index.html'),
        '<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8"><link rel="stylesheet" href="./assets/app.css"></head><body><main id="app">离线可用</main><script src="./assets/app.js"></script></body></html>',
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText((Join-Path $xhsAssets 'app.css'), 'body { margin: 0; }', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $xhsAssets 'app.js'), 'document.querySelector("#app").dataset.ready = "true";', [Text.UTF8Encoding]::new($false))

    $xhsValidator = Join-Path $root 'kevin-xhs-minitool-publisher/scripts/validate_package.py'
    $validResult = (& python -X utf8 $xhsValidator $xhsFixture | Out-String) | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0 -and $validResult.ok -and [int]$validResult.errors -eq 0) '小红书离线合规样例未通过校验。'

    [IO.File]::WriteAllText((Join-Path $xhsAssets 'app.js'), 'location.href = "https://example.com";', [Text.UTF8Encoding]::new($false))
    $invalidOutput = & python -X utf8 $xhsValidator $xhsFixture 2>&1 | Out-String
    $invalidExit = $LASTEXITCODE
    Assert-True ($invalidExit -eq 1 -and $invalidOutput.Contains('external.url')) '小红书校验器未拒绝站外 URL。'

    $officialFetcher = Join-Path $root 'kevin-xhs-minitool-publisher/scripts/fetch_official_skill.py'
    $rejectedDownloadRoot = Join-Path $temporaryRoot 'rejected-official-skill'
    $fetchOutput = & python -X utf8 $officialFetcher 'https://example.com/fake.skill' --output-dir $rejectedDownloadRoot 2>&1 | Out-String
    $fetchExit = $LASTEXITCODE
    Assert-True ($fetchExit -eq 1 -and $fetchOutput.Contains('不是小红书 CDN 域名')) '官方 Skill 下载器未拒绝非小红书域名。'

    # 公开仓自带的示例生成器必须能从纯文本仓库生成完整素材包。
    $generatedArticlePackage = Join-Path $temporaryRoot 'generated-article'
    $generatedImagePackage = Join-Path $temporaryRoot 'generated-image-post'
    & (Join-Path $root 'wechat-article-api/scripts/New-WeChatArticleExample.ps1') -OutputFolder $generatedArticlePackage | Out-Null
    & (Join-Path $root 'wechat-image-api/scripts/New-WeChatImagePackageExample.ps1') -OutputFolder $generatedImagePackage | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $generatedArticlePackage 'cover.png') -PathType Leaf) '文章示例生成器未生成封面。'
    Assert-True (Test-Path -LiteralPath (Join-Path $generatedImagePackage 'images/post-01.png') -PathType Leaf) '贴图示例生成器未生成图片。'

    $articlePackage = Join-Path $temporaryRoot 'article'
    $imagePackage = Join-Path $temporaryRoot 'image-post'
    Copy-Item -LiteralPath (Join-Path $root 'tests/fixtures/article') -Destination $articlePackage -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'tests/fixtures/image-post') -Destination $imagePackage -Recurse
    Write-TinyPng -Path (Join-Path $articlePackage 'cover.png')
    Write-TinyPng -Path (Join-Path $articlePackage 'images/section-01.png')
    Write-TinyPng -Path (Join-Path $imagePackage 'images/post-01.png')

    $articleValidator = Join-Path $root 'wechat-article-api/scripts/Test-WeChatArticlePackage.ps1'
    $imageValidator = Join-Path $root 'wechat-image-api/scripts/Test-WeChatImagePackage.ps1'
    $articleResult = & $articleValidator -InputFolder $articlePackage -PassThru
    $imageResult = & $imageValidator -InputFolder $imagePackage -PassThru
    Assert-True ($articleResult.Status -eq 'PASS' -and $articleResult.BodyImages.Count -eq 1) '合成文章素材校验未通过。'
    Assert-True ($imageResult.Status -eq 'PASS' -and $imageResult.Images.Count -eq 1) '合成贴图素材校验未通过。'

    # 账号为空时必须在任何 API 操作前拒绝。
    $articleManifestPath = Join-Path $articlePackage 'article.json'
    $articleManifest = Get-Content -LiteralPath $articleManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $articleManifest.account = '   '
    [IO.File]::WriteAllText($articleManifestPath, ($articleManifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Assert-ThrowsLike -ScriptBlock { & $articleValidator -InputFolder $articlePackage -PassThru | Out-Null } -ExpectedFragments @('account', '必须') -Because '文章素材必须拒绝空 account'

    $imageManifestPath = Join-Path $imagePackage 'image-post.json'
    $imageManifest = Get-Content -LiteralPath $imageManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $imageManifest.account = ''
    [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Assert-ThrowsLike -ScriptBlock { & $imageValidator -InputFolder $imagePackage -PassThru | Out-Null } -ExpectedFragments @('account', '必须') -Because '贴图素材必须拒绝空 account'
}
finally {
    $tempFull = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($tempFull.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $tempFull).StartsWith('kevinsu-skills-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $tempFull -Recurse -Force
    }
}

# 两个 Skill 共用的 API 模块必须保持字节级一致，防止修复只落到一边。
$articleModule = Join-Path $root 'wechat-article-api/scripts/WeChatOfficialApi.psm1'
$imageModule = Join-Path $root 'wechat-image-api/scripts/WeChatOfficialApi.psm1'
$articleHash = (Get-FileHash -LiteralPath $articleModule -Algorithm SHA256).Hash
$imageHash = (Get-FileHash -LiteralPath $imageModule -Algorithm SHA256).Hash
Assert-True ($articleHash -eq $imageHash) '两个 Skill 的 WeChatOfficialApi.psm1 已产生差异；请先人工合并审查，不要自动覆盖。'

# 40164 必须告诉用户真实出口 IP、白名单位置，并明确不能转用浏览器/RPA。
$module = Import-Module $articleModule -Force -PassThru
$multipartFixture = Join-Path ([IO.Path]::GetTempPath()) ("kevinsu-skills-multipart-$([Guid]::NewGuid().ToString('N')).png")
try {
    [IO.File]::WriteAllBytes($multipartFixture, [byte[]](1, 2, 3))
    & $module {
        param([string]$FixturePath)

        $multipart = New-WeChatMultipartFormData -File (Get-Item -LiteralPath $FixturePath) -ContentType 'image/png'
        try {
            $contentType = $multipart.Headers.ContentType.ToString()
            $wire = [Text.Encoding]::UTF8.GetString($multipart.ReadAsByteArrayAsync().GetAwaiter().GetResult())
            if ($contentType -match 'boundary="') {
                throw 'multipart 顶层 boundary 不应带引号。'
            }
            if ($wire -notmatch 'Content-Disposition: form-data; name="media"; filename="upload\.png"') {
                throw 'multipart media 部件未使用微信兼容的带引号 Content-Disposition。'
            }
            if ($wire -match 'filename\*=') {
                throw 'multipart media 部件不应包含微信无法识别的 filename*=。'
            }
            if ($wire -notmatch 'Content-Disposition:[^\r\n]+\r?\nContent-Type: image/png') {
                throw 'multipart media 部件应先发送 Content-Disposition，再发送 Content-Type。'
            }
        }
        finally {
            $multipart.Dispose()
        }
    } $multipartFixture
}
finally {
    if (Test-Path -LiteralPath $multipartFixture -PathType Leaf) {
        Remove-Item -LiteralPath $multipartFixture -Force
    }
}
Assert-ThrowsLike -ScriptBlock {
    & $module {
        Assert-WeChatApiResponse -Response ([pscustomobject]@{
            errcode = 40164
            errmsg = 'invalid ip 203.0.113.42, not in whitelist'
            rid = 'offline-test-rid'
        }) -Operation '离线测试'
    } | Out-Null
} -ExpectedFragments @('40164', '203.0.113.42', 'IP 白名单', '禁止改走浏览器或 RPA') -Because '40164 指引必须完整'

# 上面的预期失败用例会把 Python 的退出码 1 留在 LASTEXITCODE；断言全部通过后显式归零，避免 CI 误判。
$global:LASTEXITCODE = 0
"离线测试通过：AST、安装器、公众号素材契约与 API 边界、小红书 ZIP 校验与官方 Skill 来源门禁均符合预期。"
