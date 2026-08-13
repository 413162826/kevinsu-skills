$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
Assert-WeChatRuntime

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "离线自检失败：$Message" }
}

$tempBase = [IO.Path]::GetFullPath($env:TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar)
$testRoot = Join-Path $tempBase ('wechat-image-api-offline-' + [Guid]::NewGuid().ToString('N'))
$oldCodexHome = $env:CODEX_HOME
$firstLock = $null

try {
    & (Join-Path $PSScriptRoot 'New-WeChatImagePackageExample.ps1') -OutputFolder $testRoot | Out-Null
    $validated = & (Join-Path $PSScriptRoot 'Test-WeChatImagePackage.ps1') -InputFolder $testRoot -PassThru
    Assert-True ($validated.Status -eq 'PASS') '完整示例未通过素材包校验。'
    Assert-True ($validated.Manifest.needOpenComment -eq 1) '示例未默认开启留言。'
    Assert-True ($validated.Manifest.onlyFansCanComment -eq 0) '示例留言范围不是所有人。'

    $manifestPath = Join-Path $testRoot 'image-post.json'
    $originalManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
    $missingField = $originalManifest | ConvertFrom-Json -AsHashtable
    $missingField.Remove('needOpenComment')
    Write-JsonNoBom -Path $manifestPath -Value $missingField
    $missingRejected = $false
    try {
        & (Join-Path $PSScriptRoot 'Test-WeChatImagePackage.ps1') -InputFolder $testRoot -PassThru | Out-Null
    }
    catch {
        $missingRejected = $_.Exception.Message -match '缺少必填字段：needOpenComment'
    }
    Assert-True $missingRejected '缺失 needOpenComment 时没有明确拒绝。'
    [IO.File]::WriteAllText($manifestPath, $originalManifest, [Text.UTF8Encoding]::new($false))

    $fakeCredentialPath = Join-Path $testRoot 'fake-credential.dpapi.json'
    Write-JsonNoBom -Path $fakeCredentialPath -Value ([ordered]@{
        schemaVersion = 1
        appId = 'wx' + ('0' * 16)
        accountName = 'DIFFERENT_ACCOUNT'
        appSecretProtected = Protect-WeChatSecret -PlainText ('offline-test-' + [Guid]::NewGuid().ToString('N'))
    })
    $accountRejected = $false
    try {
        & (Join-Path $PSScriptRoot 'Publish-WeChatImageDraft.ps1') -InputFolder $testRoot -CredentialFile $fakeCredentialPath | Out-Null
    }
    catch {
        $accountRejected = $_.Exception.Message -match '必须与凭据中的公众号名称严格一致'
    }
    Assert-True $accountRejected '素材包 account 与凭据账号不一致时没有在 API 调用前停止。'

    $env:CODEX_HOME = Join-Path $testRoot 'custom-codex-home'
    $expectedCredential = Join-Path ([IO.Path]::GetFullPath($env:CODEX_HOME)) 'secrets\wechat-official-account.dpapi.json'
    Assert-True ((Get-WeChatDefaultCredentialPath) -eq $expectedCredential) '凭据路径没有遵循 CODEX_HOME。'

    $atomicPath = Join-Path $testRoot 'atomic.json'
    Write-JsonNoBom -Path $atomicPath -Value ([ordered]@{ ok = $true })
    $bytes = [IO.File]::ReadAllBytes($atomicPath)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'JSON 带有 UTF-8 BOM。'
    Assert-True ((Get-Content -LiteralPath $atomicPath -Raw -Encoding utf8 | ConvertFrom-Json).ok) '原子写入的 JSON 无法回读。'

    $firstLock = Enter-WeChatPackageLock -Folder $testRoot
    $lockRejected = $false
    try { Enter-WeChatPackageLock -Folder $testRoot | Out-Null }
    catch { $lockRejected = $_.Exception.Message -match '另一个发布进程占用' }
    Assert-True $lockRejected '同一素材目录没有拒绝并发锁。'
    $firstLock.Dispose()
    $firstLock = $null

    $ipRejected = $false
    try {
        Assert-WeChatApiResponse -Response ([pscustomobject]@{
            errcode = 40164
            errmsg = 'invalid ip 203.0.113.10, not in whitelist'
            rid = 'offline-test-rid'
        }) -Operation '离线模拟' | Out-Null
    }
    catch {
        $ipRejected = $_.Exception.Data['WeChatErrCode'] -eq 40164 -and
            $_.Exception.Data['WeChatApiResponseReceived'] -eq $true -and
            $_.Exception.Data['RequiresIpWhitelist'] -eq $true -and
            $_.Exception.Data['DetectedPublicIp'] -eq '203.0.113.10'
    }
    Assert-True $ipRejected '40164 没有携带白名单与公网 IP 结构化信息。'

    [pscustomobject]@{
        Status = 'PASS'
        Checks = 8
        ApiCalls = 0
        Message = '贴图 Skill 离线自检通过。'
    } | Format-List
}
finally {
    if ($firstLock) { $firstLock.Dispose() }
    $env:CODEX_HOME = $oldCodexHome
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $safePrefix = $tempBase + [IO.Path]::DirectorySeparatorChar + 'wechat-image-api-offline-'
    if ((Test-Path -LiteralPath $resolvedTestRoot -PathType Container) -and $resolvedTestRoot.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($resolvedTestRoot, $true)
    }
}
