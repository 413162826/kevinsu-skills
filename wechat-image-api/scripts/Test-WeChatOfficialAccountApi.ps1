param(
    [string]$CredentialFile
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
Assert-WeChatRuntime
if ([string]::IsNullOrWhiteSpace($CredentialFile)) {
    $CredentialFile = Get-WeChatDefaultCredentialPath
}

$credential = Get-WeChatOfficialCredential -CredentialFile $CredentialFile
try {
    $token = Get-WeChatAccessToken -Credential $credential -ForceRefresh
    $count = Get-WeChatDraftCount -AccessToken $token
    "微信公众号 API 已连通 | AppID：$($credential.AppId.Substring(0,6))**** | 账号：$($credential.AccountName) | 草稿数：$($count.total_count)"
}
catch {
    $message = $_.Exception.Message
    if ($message -match '40164') { $message += '。当前出口 IP 未加入公众号 API IP 白名单。' }
    elseif ($message -match '40125') { $message += '。AppSecret 无效，请在公众号开发设置中重置后重新录入。' }
    elseif ($message -match '48001|api unauthorized') { $message += '。当前账号没有草稿接口权限。' }
    throw $message
}
finally {
    $token = $null
    if ($credential) { $credential.AppSecret = $null }
}
