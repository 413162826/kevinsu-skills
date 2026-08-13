param(
    [Parameter(Mandatory)][string]$InputFolder,
    [string]$CredentialFile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$currentStage = '校验贴图素材包'
$package = & (Join-Path $PSScriptRoot 'Test-WeChatImagePackage.ps1') -InputFolder $InputFolder -PassThru
if ($DryRun) {
    $package | Select-Object Status,Folder,@{N='Account';E={$_.Manifest.account}},@{N='Title';E={$_.Manifest.title}},@{N='ImageCount';E={$_.Images.Count}},@{N='Comments';E={"needOpenComment=$($_.Manifest.needOpenComment), onlyFansCanComment=$($_.Manifest.onlyFansCanComment)"}},Fingerprint | Format-List
    return
}

Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
Assert-WeChatRuntime
if ([string]::IsNullOrWhiteSpace($CredentialFile)) {
    $CredentialFile = Get-WeChatDefaultCredentialPath
}

$statePath = Join-Path $package.Folder 'wechat-image-api-state.json'
$receiptPath = Join-Path $package.Folder 'wechat-image-api-receipt.json'
$state = $null
$credential = $null
$accessToken = $null
$lockStream = Enter-WeChatPackageLock -Folder $package.Folder

function Save-State {
    $state.updatedAt = (Get-Date).ToString('o')
    Write-JsonNoBom -Path $statePath -Value $state
}

function Get-RequiredDraftItemValue {
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Item.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "回读草稿缺少字段：$Name。"
    }
    return $property.Value
}

try {
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        if ([int]$state.schemaVersion -ne 2) { throw '检查点版本不兼容；请使用新的素材目录，避免误重试旧流程。' }
        if ([string]$state.fingerprint -ne $package.Fingerprint) { throw '贴图素材已变化，但目录中存在旧 API 检查点；请使用新的素材目录，避免创建重复草稿。' }
        if ([string]$state.stage -in @('image_upload_submitting','draft_submitting') -and [string]::IsNullOrWhiteSpace([string]$state.draftMediaId)) {
            throw "上次执行中断在 $($state.stage)，微信是否已接收请求无法确定。为防止重复上传或重复创建草稿，本 Skill 不会自动重试；请先在公众号素材库/草稿箱人工核对，再使用新的素材目录继续。"
        }
    }
    else {
        $state = [ordered]@{
            schemaVersion = 2
            type = 'newspic'
            fingerprint = $package.Fingerprint
            stage = 'validated'
            pendingImageIndex = $null
            imageMediaIds = @()
            draftMediaId = $null
            createdAt = (Get-Date).ToString('o')
            updatedAt = (Get-Date).ToString('o')
        }
        Save-State
    }

    if (@($state.imageMediaIds).Count -gt $package.Images.Count) {
        throw '检查点中的已上传图片数量超过素材包图片数量，已停止。'
    }

    $currentStage = '读取凭据并获取 access_token'
    $credential = Get-WeChatOfficialCredential -CredentialFile $CredentialFile
    $manifestAccount = ([string]$package.Manifest.account).Trim()
    if (-not [string]::Equals($manifestAccount, [string]$credential.AccountName, [StringComparison]::Ordinal)) {
        throw "素材包 account 必须与凭据中的公众号名称严格一致：素材包=$manifestAccount，凭据=$($credential.AccountName)。"
    }
    $accessToken = Get-WeChatAccessToken -Credential $credential

    if ([string]$state.draftMediaId) {
        $currentStage = '回读已创建贴图草稿'
        $draft = Get-WeChatDraft -MediaId ([string]$state.draftMediaId) -AccessToken $accessToken
    }
    else {
        $currentStage = '上传贴图永久素材'
        $uploaded = @($state.imageMediaIds).Count
        for ($index = $uploaded; $index -lt $package.Images.Count; $index++) {
            $state.stage = 'image_upload_submitting'
            $state.pendingImageIndex = $index
            Save-State

            $result = Add-WeChatPermanentImage -Path $package.Images[$index] -AccessToken $accessToken
            $state.imageMediaIds = @($state.imageMediaIds) + @([string]$result.mediaId)
            $state.pendingImageIndex = $null
            $state.stage = 'images_uploading'
            Save-State
        }

        $imageList = @($state.imageMediaIds | ForEach-Object { [ordered]@{ image_media_id = [string]$_ } })
        $article = [ordered]@{
            article_type = 'newspic'
            title = [string]$package.Manifest.title
            content = [string]$package.Manifest.content
            need_open_comment = [int]$package.Manifest.needOpenComment
            only_fans_can_comment = [int]$package.Manifest.onlyFansCanComment
            image_info = [ordered]@{ image_list = $imageList }
        }

        $currentStage = '调用 draft/add 创建贴图草稿'
        $state.stage = 'draft_submitting'
        Save-State
        $draftMediaId = Add-WeChatDraft -Articles @($article) -AccessToken $accessToken
        $state.draftMediaId = $draftMediaId
        $state.stage = 'draft_created'
        Save-State

        $currentStage = '调用 draft/get 回读验收'
        $draft = Get-WeChatDraft -MediaId ([string]$state.draftMediaId) -AccessToken $accessToken
    }

    $items = @($draft.news_item)
    if ($items.Count -ne 1) { throw "回读图片消息数量不是 1：$($items.Count)" }
    if ([string](Get-RequiredDraftItemValue -Item $items[0] -Name 'article_type') -ne 'newspic') { throw "回读 article_type 不正确：$($items[0].article_type)" }
    if ([string](Get-RequiredDraftItemValue -Item $items[0] -Name 'title') -ne [string]$package.Manifest.title) { throw '回读标题与素材包不一致。' }
    if ([string](Get-RequiredDraftItemValue -Item $items[0] -Name 'content') -ne [string]$package.Manifest.content) { throw '回读贴图正文与素材包不一致。' }

    $returnedNeedOpenComment = Get-RequiredDraftItemValue -Item $items[0] -Name 'need_open_comment'
    $returnedOnlyFansCanComment = Get-RequiredDraftItemValue -Item $items[0] -Name 'only_fans_can_comment'
    if ([int]$returnedNeedOpenComment -ne [int]$package.Manifest.needOpenComment) { throw '回读留言开关 need_open_comment 与素材包不一致。' }
    if ([int]$returnedOnlyFansCanComment -ne [int]$package.Manifest.onlyFansCanComment) { throw '回读留言范围 only_fans_can_comment 与素材包不一致。' }

    $imageInfo = Get-RequiredDraftItemValue -Item $items[0] -Name 'image_info'
    $imageListProperty = $imageInfo.PSObject.Properties['image_list']
    if ($null -eq $imageListProperty -or $null -eq $imageListProperty.Value) { throw '回读草稿缺少 image_info.image_list。' }
    $returnedIds = @($imageListProperty.Value | ForEach-Object { [string]$_.image_media_id })
    if ($returnedIds.Count -ne @($state.imageMediaIds).Count) { throw '回读贴图数量不一致。' }
    for ($index = 0; $index -lt $returnedIds.Count; $index++) {
        if ($returnedIds[$index] -ne [string]$state.imageMediaIds[$index]) { throw "回读第 $($index + 1) 张图片 media_id 不一致。" }
    }

    $state.stage = 'reopened_verified'
    Save-State
    $receipt = [ordered]@{
        status = 'PASS'
        action = 'save_draft_only'
        articleType = 'newspic'
        account = $credential.AccountName
        title = [string]$package.Manifest.title
        mediaId = [string]$state.draftMediaId
        imageCount = $package.Images.Count
        needOpenComment = [int]$returnedNeedOpenComment
        onlyFansCanComment = [int]$returnedOnlyFansCanComment
        verifiedAt = (Get-Date).ToString('o')
        durationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        fingerprint = $package.Fingerprint
    }
    Write-JsonNoBom -Path $receiptPath -Value $receipt
    "微信公众号贴图草稿 API 创建并回读验收通过 | 标题：$($receipt.title) | media_id：$($receipt.mediaId) | 图片：$($receipt.imageCount) | 留言：$($receipt.needOpenComment)"
}
catch {
    $exception = $_.Exception
    $receivedApiResponse = $exception.Data.Contains('WeChatApiResponseReceived') -and [bool]$exception.Data['WeChatApiResponseReceived']
    if ($state -and $receivedApiResponse) {
        try {
            if ([string]$state.stage -eq 'draft_submitting' -and [string]::IsNullOrWhiteSpace([string]$state.draftMediaId)) {
                $state.stage = 'images_uploaded'
                Save-State
            }
            elseif ([string]$state.stage -eq 'image_upload_submitting') {
                $state.pendingImageIndex = $null
                $state.stage = 'images_uploading'
                Save-State
            }
        }
        catch {
            # 保留原始微信 API 错误；下次执行仍会依据 submitting 状态阻断不确定重试。
        }
    }
    $failure = [ordered]@{
        status = 'FAIL'
        action = 'save_draft_only'
        articleType = 'newspic'
        stage = $currentStage
        error = $exception.Message
        failedAt = (Get-Date).ToString('o')
        fingerprint = $package.Fingerprint
    }
    if ($exception.Data.Contains('WeChatErrCode')) { $failure.errorCode = [int]$exception.Data['WeChatErrCode'] }
    if ($exception.Data.Contains('RequiresIpWhitelist')) { $failure.requiresIpWhitelist = [bool]$exception.Data['RequiresIpWhitelist'] }
    if ($exception.Data.Contains('DetectedPublicIp')) { $failure.detectedPublicIp = [string]$exception.Data['DetectedPublicIp'] }
    if ($exception.Data.Contains('WeChatRid')) { $failure.weChatRid = [string]$exception.Data['WeChatRid'] }
    Write-JsonNoBom -Path $receiptPath -Value $failure
    throw "贴图草稿 API 创建失败 [$currentStage]：$($exception.Message)"
}
finally {
    $accessToken = $null
    if ($credential) { $credential.AppSecret = $null }
    if ($lockStream) { $lockStream.Dispose() }
}
