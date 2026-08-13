param(
    [Parameter(Mandatory)][string]$InputFolder,
    [string]$CredentialFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$currentStage = '校验文章素材包'
$package = & (Join-Path $PSScriptRoot 'Test-WeChatArticlePackage.ps1') -InputFolder $InputFolder -PassThru
if ($DryRun) {
    $package | Select-Object Status,Folder,@{N='Title';E={$_.Manifest.title}},@{N='BodyImageCount';E={$_.BodyImages.Count}},Fingerprint | Format-List
    return
}

Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
if ([string]::IsNullOrWhiteSpace($CredentialFile)) { $CredentialFile = Get-WeChatDefaultCredentialPath }
$statePath = Join-Path $package.Folder 'wechat-article-api-state.json'
$receiptPath = Join-Path $package.Folder 'wechat-article-api-receipt.json'
$lockPath = Join-Path $package.Folder '.wechat-official-api.lock'
$state = $null
$credential = $null
$accessToken = $null
$lockStream = $null

function Exit-PackageLock {
    param([IO.FileStream]$Stream, [Parameter(Mandatory)][string]$Path)

    if ($null -ne $Stream) { $Stream.Dispose() }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Save-State {
    $state.updatedAt = (Get-Date).ToString('o')
    Write-JsonNoBom -Path $statePath -Value $state
}

function Get-WeChatImageAssetKey {
    param([Parameter(Mandatory)][string]$Url)

    try { $uri = [Uri]([Net.WebUtility]::HtmlDecode($Url)) }
    catch { throw "无法解析微信图片 URL：$Url" }
    $path = $uri.AbsolutePath.TrimEnd('/')
    $lastSlash = $path.LastIndexOf('/')
    if ($lastSlash -le 0) { throw "微信图片 URL 缺少素材路径：$Url" }
    return ($uri.Host.ToLowerInvariant() + $path.Substring(0, $lastSlash))
}

$currentStage = '获取素材目录互斥锁'
$lockStream = Enter-WeChatPackageLock -Folder $package.Folder
try {
    $currentStage = '读取凭据并核对公众号账号'
    $credential = Get-WeChatOfficialCredential -CredentialFile $CredentialFile
    $manifestAccount = [string]$package.Manifest.account
    if (-not [string]::Equals($manifestAccount, [string]$credential.AccountName, [StringComparison]::Ordinal)) {
        throw "素材包账号为 $manifestAccount，凭据账号为 $($credential.AccountName)，已停止。"
    }

    $currentStage = '读取文章 API 检查点'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        if ([string]$state.fingerprint -ne $package.Fingerprint) { throw '文章素材已变化，但目录中存在旧 API 检查点；请使用新的素材目录，避免创建重复草稿。' }
    }
    else {
        $state = [ordered]@{
            schemaVersion = 1
            type = 'news'
            fingerprint = $package.Fingerprint
            stage = 'validated'
            bodyImageUrls = [ordered]@{}
            coverMediaId = $null
            draftMediaId = $null
            submissionStartedAt = $null
            createdAt = (Get-Date).ToString('o')
            updatedAt = (Get-Date).ToString('o')
        }
        Save-State
    }

    if ([string]$state.stage -eq 'draft_submitting' -and [string]::IsNullOrWhiteSpace([string]$state.draftMediaId)) {
        throw '上次 draft/add 在提交后未能确认结果，当前状态不确定。为避免重复草稿，本 Skill 禁止自动重试；请先按标题和提交时间人工核对公众号草稿箱，再决定如何处置该素材目录。'
    }

    $currentStage = '获取 access_token'
    $accessToken = Get-WeChatAccessToken -Credential $credential

    if ([string]$state.draftMediaId) {
        $currentStage = '回读已创建草稿'
        $draft = Get-WeChatDraft -MediaId ([string]$state.draftMediaId) -AccessToken $accessToken
    }
    else {
        $currentStage = '上传正文图片'
        foreach ($image in $package.BodyImages) {
            if (-not $state.bodyImageUrls.Contains([string]$image.Marker)) {
                $url = Add-WeChatArticleImage -Path $image.Path -AccessToken $accessToken
                $state.bodyImageUrls[[string]$image.Marker] = $url
                $state.stage = 'body_images_uploading'
                Save-State
            }
        }

        $content = [string]$package.BodyHtml
        foreach ($image in $package.BodyImages) {
            $marker = [string]$image.Marker
            $url = [string]$state.bodyImageUrls[$marker]
            $pattern = '(?is)<p\b[^>]*data-wechat-image\s*=\s*["'']' + [regex]::Escape($marker) + '["''][^>]*>.*?</p>'
            $replacement = '<p style="margin:18px 0;text-align:center;"><img src="' + $url + '" style="max-width:100%;height:auto;" /></p>'
            $content = [regex]::Replace($content, $pattern, $replacement)
        }
        if ($content -match 'data-wechat-image') { throw '仍有正文图片占位符未替换。' }

        $currentStage = '上传封面永久素材'
        if (-not [string]$state.coverMediaId) {
            $cover = Add-WeChatPermanentImage -Path $package.CoverPath -AccessToken $accessToken
            $state.coverMediaId = $cover.mediaId
            $state.stage = 'cover_uploaded'
            Save-State
        }

        $article = [ordered]@{
            article_type = 'news'
            title = [string]$package.Manifest.title
            author = [string]$package.Manifest.author
            digest = [string]$package.Manifest.digest
            content = $content
            thumb_media_id = [string]$state.coverMediaId
            need_open_comment = [int]$package.Manifest.needOpenComment
            only_fans_can_comment = [int]$package.Manifest.onlyFansCanComment
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$package.Manifest.contentSourceUrl)) {
            $article['content_source_url'] = [string]$package.Manifest.contentSourceUrl
        }

        $currentStage = '调用 draft/add 创建文章草稿'
        $state.stage = 'draft_submitting'
        $state['submissionStartedAt'] = (Get-Date).ToString('o')
        Save-State
        try {
            $draftMediaId = Add-WeChatDraft -Articles @($article) -AccessToken $accessToken
        }
        catch {
            if ($_.Exception.Data['WeChatApiResponseReceived']) {
                $state.stage = 'cover_uploaded'
                $state['submissionStartedAt'] = $null
                Save-State
            }
            throw
        }
        $state.draftMediaId = $draftMediaId
        $state.stage = 'draft_created'
        $state['submissionStartedAt'] = $null
        Save-State

        $currentStage = '调用 draft/get 回读验收'
        $draft = Get-WeChatDraft -MediaId ([string]$state.draftMediaId) -AccessToken $accessToken
    }

    $items = @($draft.news_item)
    if ($items.Count -ne 1) { throw "回读草稿文章数量不是 1：$($items.Count)" }
    if ([string]$items[0].article_type -ne 'news') { throw "回读 article_type 不正确：$($items[0].article_type)" }
    if ([string]$items[0].title -ne [string]$package.Manifest.title) { throw '回读标题与素材包不一致。' }
    if ([string]$items[0].thumb_media_id -ne [string]$state.coverMediaId) { throw '回读封面 media_id 不一致。' }
    if ([int]$items[0].need_open_comment -ne [int]$package.Manifest.needOpenComment) { throw '回读留言开关与素材包不一致。' }
    if ([int]$items[0].only_fans_can_comment -ne [int]$package.Manifest.onlyFansCanComment) { throw '回读留言范围与素材包不一致。' }
    $storedImageKeys = @(
        [regex]::Matches([string]$items[0].content, '(?is)\b(?:data-src|src)\s*=\s*["''](?<url>https?://[^"'']+)') |
            ForEach-Object { Get-WeChatImageAssetKey -Url $_.Groups['url'].Value } |
            Select-Object -Unique
    )
    foreach ($url in $state.bodyImageUrls.Values) {
        $expectedKey = Get-WeChatImageAssetKey -Url ([string]$url)
        if ($expectedKey -notin $storedImageKeys) { throw '回读正文缺少已上传的微信图片素材。' }
    }

    $state.stage = 'reopened_verified'
    Save-State
    $receipt = [ordered]@{
        status = 'PASS'
        action = 'save_draft_only'
        articleType = 'news'
        account = $credential.AccountName
        title = [string]$package.Manifest.title
        mediaId = [string]$state.draftMediaId
        bodyImageCount = $package.BodyImages.Count
        verifiedAt = (Get-Date).ToString('o')
        durationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        fingerprint = $package.Fingerprint
    }
    Write-JsonNoBom -Path $receiptPath -Value $receipt
    "微信公众号文章草稿 API 创建并回读验收通过 | 标题：$($receipt.title) | media_id：$($receipt.mediaId) | 正文图片：$($receipt.bodyImageCount)"
}
catch {
    $wechatErrCode = if ($null -ne $_.Exception.Data['WeChatErrCode']) { [int]$_.Exception.Data['WeChatErrCode'] } else { $null }
    $failure = [ordered]@{
        status = 'FAIL'
        action = 'save_draft_only'
        articleType = 'news'
        stage = $currentStage
        wechatErrCode = $wechatErrCode
        error = $_.Exception.Message
        failedAt = (Get-Date).ToString('o')
        fingerprint = $package.Fingerprint
    }
    Write-JsonNoBom -Path $receiptPath -Value $failure
    throw "文章草稿 API 发布失败 [$currentStage]：$($_.Exception.Message)"
}
finally {
    $accessToken = $null
    if ($credential) { $credential.AppSecret = $null }
    Exit-PackageLock -Stream $lockStream -Path $lockPath
}
