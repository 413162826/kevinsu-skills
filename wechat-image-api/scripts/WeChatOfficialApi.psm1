Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-WeChatRuntime {
    if ($PSVersionTable.PSVersion -lt [Version]'7.2') {
        throw "微信公众号 API Skill 需要 PowerShell 7.2 或更高版本；当前版本为 $($PSVersionTable.PSVersion)。"
    }
    if (-not $IsWindows) {
        throw '微信公众号 API Skill 使用 Windows DPAPI 保存 AppSecret，目前仅支持 Windows。'
    }
}

function Get-CodexHomePath {
    $codexHome = [string]$env:CODEX_HOME
    if ([string]::IsNullOrWhiteSpace($codexHome)) {
        if ([string]::IsNullOrWhiteSpace([string]$env:USERPROFILE)) {
            throw '无法确定凭据目录：CODEX_HOME 与 USERPROFILE 均未设置。'
        }
        $codexHome = Join-Path $env:USERPROFILE '.codex'
    }
    return [IO.Path]::GetFullPath($codexHome)
}

function Get-WeChatDefaultCredentialPath {
    Join-Path (Get-CodexHomePath) 'secrets\wechat-official-account.dpapi.json'
}

function Write-JsonNoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)

    $target = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $target
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($target) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $target, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Protect-WeChatSecret {
    param([Parameter(Mandatory)][string]$PlainText)

    Assert-WeChatRuntime
    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secure
}

function Unprotect-WeChatSecret {
    param([Parameter(Mandatory)][string]$ProtectedText)

    Assert-WeChatRuntime
    $secure = ConvertTo-SecureString -String $ProtectedText
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Get-WeChatOfficialCredential {
    param([string]$CredentialFile)

    Assert-WeChatRuntime
    if ([string]::IsNullOrWhiteSpace($CredentialFile)) {
        $CredentialFile = Get-WeChatDefaultCredentialPath
    }
    $CredentialFile = [IO.Path]::GetFullPath($CredentialFile)
    if (-not (Test-Path -LiteralPath $CredentialFile -PathType Leaf)) {
        throw "缺少微信公众号 API 凭据：$CredentialFile。请先运行 Set-WeChatOfficialAccountCredential.ps1。"
    }
    $stored = Get-Content -LiteralPath $CredentialFile -Raw -Encoding utf8 | ConvertFrom-Json
    if ([int]$stored.schemaVersion -ne 1) { throw "不支持的凭据版本：$($stored.schemaVersion)" }
    if ([string]$stored.appId -notmatch '^wx[0-9A-Za-z]{16}$') { throw '凭据文件中的 AppID 格式无效。' }
    if ([string]::IsNullOrWhiteSpace([string]$stored.accountName)) { throw '凭据文件缺少公众号名称。' }
    if ([string]::IsNullOrWhiteSpace([string]$stored.appSecretProtected)) { throw '凭据文件缺少加密 AppSecret。' }

    [pscustomobject]@{
        AppId = [string]$stored.appId
        AccountName = ([string]$stored.accountName).Trim()
        AppSecret = Unprotect-WeChatSecret -ProtectedText ([string]$stored.appSecretProtected)
        CredentialFile = $CredentialFile
    }
}

function Get-WeChatTokenCachePath {
    param([Parameter(Mandatory)][string]$AppId)

    Join-Path (Get-CodexHomePath) "cache\wechat-official-$AppId-token.dpapi.json"
}

function Assert-WeChatApiResponse {
    param(
        [Parameter(Mandatory)][object]$Response,
        [Parameter(Mandatory)][string]$Operation
    )

    if ($null -ne $Response.PSObject.Properties['errcode'] -and [int]$Response.errcode -ne 0) {
        $rid = if ($null -ne $Response.PSObject.Properties['rid']) { " rid=$($Response.rid)" } else { '' }
        if ([int]$Response.errcode -eq 40164) {
            $ipMatch = [regex]::Match([string]$Response.errmsg, '(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])')
            $ipHint = if ($ipMatch.Success) { "微信识别到的公网出口 IP 为 $($ipMatch.Value)。" } else { '' }
            $exception = [InvalidOperationException]::new("微信 API $Operation 失败：errcode=40164 errmsg=$($Response.errmsg)$rid。${ipHint}请进入[设置与开发 → 开发接口管理 → IP 白名单]添加该 IP，确认后重试同一官方 API；禁止改走浏览器或 RPA 兜底。")
            $exception.Data['WeChatApiResponseReceived'] = $true
            $exception.Data['WeChatErrCode'] = 40164
            $exception.Data['RequiresIpWhitelist'] = $true
            if ($ipMatch.Success) { $exception.Data['DetectedPublicIp'] = $ipMatch.Value }
            if ($null -ne $Response.PSObject.Properties['rid']) { $exception.Data['WeChatRid'] = [string]$Response.rid }
            throw $exception
        }
        $exception = [InvalidOperationException]::new("微信 API $Operation 失败：errcode=$($Response.errcode) errmsg=$($Response.errmsg)$rid")
        $exception.Data['WeChatApiResponseReceived'] = $true
        $exception.Data['WeChatErrCode'] = [int]$Response.errcode
        if ($null -ne $Response.PSObject.Properties['rid']) { $exception.Data['WeChatRid'] = [string]$Response.rid }
        throw $exception
    }
    return $Response
}

function Get-WeChatAccessToken {
    param(
        [Parameter(Mandatory)][object]$Credential,
        [switch]$ForceRefresh
    )

    $cachePath = Get-WeChatTokenCachePath -AppId $Credential.AppId
    if (-not $ForceRefresh -and (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        try {
            $cache = Get-Content -LiteralPath $cachePath -Raw -Encoding utf8 | ConvertFrom-Json
            if ([string]$cache.appId -eq $Credential.AppId -and
                [DateTimeOffset]::Parse([string]$cache.expiresAt) -gt [DateTimeOffset]::UtcNow.AddMinutes(2)) {
                return Unprotect-WeChatSecret -ProtectedText ([string]$cache.accessTokenProtected)
            }
        }
        catch {
            # 损坏或过期缓存直接废弃，凭据本身不受影响。
        }
    }

    $escapedAppId = [Uri]::EscapeDataString($Credential.AppId)
    $escapedSecret = [Uri]::EscapeDataString($Credential.AppSecret)
    $uri = "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=$escapedAppId&secret=$escapedSecret"
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 30
    }
    catch {
        $message = $_.Exception.Message.Replace($Credential.AppSecret, '***').Replace($escapedSecret, '***')
        $exception = [Net.Http.HttpRequestException]::new("获取微信 access_token 的网络请求失败：$message", $_.Exception)
        $exception.Data['WeChatApiResponseReceived'] = $false
        throw $exception
    }
    Assert-WeChatApiResponse -Response $response -Operation '获取 access_token' | Out-Null
    if ([string]::IsNullOrWhiteSpace([string]$response.access_token)) { throw '微信未返回 access_token。' }

    $expiresIn = if ([int]$response.expires_in -gt 300) { [int]$response.expires_in - 120 } else { [int]$response.expires_in }
    Write-JsonNoBom -Path $cachePath -Value ([ordered]@{
        schemaVersion = 1
        appId = $Credential.AppId
        accessTokenProtected = Protect-WeChatSecret -PlainText ([string]$response.access_token)
        expiresAt = [DateTimeOffset]::UtcNow.AddSeconds($expiresIn).ToString('o')
    })
    return [string]$response.access_token
}

function Invoke-WeChatJsonApi {
    param(
        [Parameter(Mandatory)][ValidateSet('Get','Post')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AccessToken,
        [object]$Body,
        [Parameter(Mandatory)][string]$Operation
    )

    $uri = "https://api.weixin.qq.com$Path" + ($(if ($Path.Contains('?')) { '&' } else { '?' })) + "access_token=$([Uri]::EscapeDataString($AccessToken))"
    try {
        if ($Method -eq 'Get') {
            $response = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 40
        }
        else {
            $json = $Body | ConvertTo-Json -Depth 30 -Compress
            $bytes = [Text.Encoding]::UTF8.GetBytes($json)
            $response = Invoke-RestMethod -Method Post -Uri $uri -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 60
        }
    }
    catch {
        $message = $_.Exception.Message.Replace($AccessToken, '***')
        $exception = [Net.Http.HttpRequestException]::new("微信 API $Operation 网络请求失败：$message", $_.Exception)
        $exception.Data['WeChatApiResponseReceived'] = $false
        throw $exception
    }
    return Assert-WeChatApiResponse -Response $response -Operation $Operation
}

function New-WeChatMultipartFormData {
    param(
        [Parameter(Mandatory)][IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$ContentType
    )

    $boundary = '------------------------' + [Guid]::NewGuid().ToString('N')
    $multipart = [Net.Http.MultipartFormDataContent]::new($boundary)
    try {
        # MultipartFormDataContent 默认会给 boundary 加引号；微信旧解析器只稳定接受 curl 风格的裸 boundary。
        $boundaryParameter = @($multipart.Headers.ContentType.Parameters | Where-Object Name -eq 'boundary')[0]
        $boundaryParameter.Value = $boundary

        $stream = $File.OpenRead()
        $fileContent = [Net.Http.StreamContent]::new($stream)

        # 显式生成 curl 兼容的 Content-Disposition。HttpClient 的三参数 Add 会去掉字段引号并
        # 添加 filename*=，微信会因此把已经发送的文件误判为 41005 media data missing。
        $disposition = [Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
        $disposition.Name = '"media"'
        $disposition.FileName = '"upload' + $File.Extension.ToLowerInvariant() + '"'
        $disposition.FileNameStar = $null
        $fileContent.Headers.ContentDisposition = $disposition
        $fileContent.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new($ContentType)
        $multipart.Add($fileContent)
        return ,$multipart
    }
    catch {
        $multipart.Dispose()
        throw
    }
}

function Invoke-WeChatMultipartUpload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$Operation
    )

    $contentTypes = @{
        '.bmp'  = 'image/bmp'
        '.gif'  = 'image/gif'
        '.jpg'  = 'image/jpeg'
        '.jpeg' = 'image/jpeg'
        '.png'  = 'image/png'
    }
    $extension = $File.Extension.ToLowerInvariant()
    if (-not $contentTypes.ContainsKey($extension)) { throw "$Operation 不支持文件格式：$extension" }

    $client = $null
    $multipart = $null
    $httpResponse = $null
    try {
        $client = [Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds(120)
        $multipart = New-WeChatMultipartFormData -File $File -ContentType $contentTypes[$extension]
        $httpResponse = $client.PostAsync($Uri, $multipart).GetAwaiter().GetResult()
        $responseText = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $httpResponse.IsSuccessStatusCode) {
            throw "HTTP $([int]$httpResponse.StatusCode) $($httpResponse.ReasonPhrase)"
        }
        if ([string]::IsNullOrWhiteSpace($responseText)) {
            throw "微信 API $Operation 返回空响应。"
        }
        try {
            $response = $responseText | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "微信 API $Operation 返回了无法解析的响应。"
        }
        return Assert-WeChatApiResponse -Response $response -Operation $Operation
    }
    catch {
        $caught = $_.Exception
        if ($caught.Data.Contains('WeChatApiResponseReceived')) {
            throw $caught
        }
        $message = $caught.Message.Replace($AccessToken, '***')
        $exception = [Net.Http.HttpRequestException]::new("$Operation 失败：$message", $caught)
        $exception.Data['WeChatApiResponseReceived'] = $false
        throw $exception
    }
    finally {
        if ($httpResponse) { $httpResponse.Dispose() }
        if ($multipart) { $multipart.Dispose() }
        if ($client) { $client.Dispose() }
    }
}

function Enter-WeChatPackageLock {
    param([Parameter(Mandatory)][string]$Folder)

    $lockPath = Join-Path ([IO.Path]::GetFullPath($Folder)) '.wechat-official-api.lock'
    try {
        $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $stream.SetLength(0)
        $lockInfo = [Text.Encoding]::UTF8.GetBytes("pid=$PID`nstartedAt=$([DateTimeOffset]::Now.ToString('o'))`n")
        $stream.Write($lockInfo, 0, $lockInfo.Length)
        $stream.Flush($true)
        return $stream
    }
    catch [IO.IOException] {
        throw "微信公众号素材目录正被另一个发布进程占用：$lockPath。请等待该进程结束后再重试。"
    }
}

function Add-WeChatPermanentImage {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $extension = $file.Extension.ToLowerInvariant()
    if ($extension -notin @('.bmp','.png','.jpeg','.jpg','.gif')) { throw "永久图片素材格式不支持：$extension" }
    if ($file.Length -gt 10MB) { throw "永久图片素材超过 10MB：$($file.FullName)" }
    $uri = "https://api.weixin.qq.com/cgi-bin/material/add_material?access_token=$([Uri]::EscapeDataString($AccessToken))&type=image"
    $response = Invoke-WeChatMultipartUpload -Uri $uri -File $file -AccessToken $AccessToken -Operation '上传永久图片素材'
    if ([string]::IsNullOrWhiteSpace([string]$response.media_id)) { throw '微信未返回永久图片 media_id。' }
    return [pscustomobject]@{ mediaId = [string]$response.media_id; url = [string]$response.url }
}

function Add-WeChatArticleImage {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Extension.ToLowerInvariant() -notin @('.png','.jpeg','.jpg')) { throw "正文图片只支持 JPG/PNG：$($file.Extension)" }
    if ($file.Length -ge 1MB) { throw "正文图片必须小于 1MB：$($file.FullName)" }
    $uri = "https://api.weixin.qq.com/cgi-bin/media/uploadimg?access_token=$([Uri]::EscapeDataString($AccessToken))"
    $response = Invoke-WeChatMultipartUpload -Uri $uri -File $file -AccessToken $AccessToken -Operation '上传图文正文图片'
    if ([string]::IsNullOrWhiteSpace([string]$response.url)) { throw '微信未返回正文图片 URL。' }
    return [string]$response.url
}

function Add-WeChatDraft {
    param(
        [Parameter(Mandatory)][object]$Articles,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $response = Invoke-WeChatJsonApi -Method Post -Path '/cgi-bin/draft/add' -AccessToken $AccessToken -Body @{ articles = @($Articles) } -Operation '新增草稿'
    if ([string]::IsNullOrWhiteSpace([string]$response.media_id)) { throw '微信新增草稿未返回 media_id。' }
    return [string]$response.media_id
}

function Get-WeChatDraft {
    param(
        [Parameter(Mandatory)][string]$MediaId,
        [Parameter(Mandatory)][string]$AccessToken
    )

    Invoke-WeChatJsonApi -Method Post -Path '/cgi-bin/draft/get' -AccessToken $AccessToken -Body @{ media_id = $MediaId } -Operation '获取草稿详情'
}

function Get-WeChatDraftCount {
    param([Parameter(Mandatory)][string]$AccessToken)
    Invoke-WeChatJsonApi -Method Get -Path '/cgi-bin/draft/count' -AccessToken $AccessToken -Operation '获取草稿总数'
}

function Resolve-SafePackagePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) { throw "素材路径必须是相对路径：$RelativePath" }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "素材路径越出输入目录：$RelativePath" }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "素材文件不存在：$RelativePath" }
    return $full
}

function Get-WeChatPackageFingerprint {
    param([Parameter(Mandatory)][string[]]$Paths)

    $records = foreach ($path in ($Paths | Sort-Object -Unique)) {
        $full = [IO.Path]::GetFullPath($path)
        "$full|$((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash)"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

Export-ModuleMember -Function Assert-WeChatRuntime,Get-CodexHomePath,Get-WeChatDefaultCredentialPath,Write-JsonNoBom,Protect-WeChatSecret,Get-WeChatOfficialCredential,Get-WeChatAccessToken,Assert-WeChatApiResponse,Invoke-WeChatJsonApi,Add-WeChatPermanentImage,Add-WeChatArticleImage,Add-WeChatDraft,Get-WeChatDraft,Get-WeChatDraftCount,Enter-WeChatPackageLock,Resolve-SafePackagePath,Get-WeChatPackageFingerprint
