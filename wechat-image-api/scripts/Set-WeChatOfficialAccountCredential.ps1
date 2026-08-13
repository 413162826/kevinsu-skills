param(
    [string]$AppId,
    [string]$AccountName,
    [string]$CredentialFile
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WeChatOfficialApi.psm1') -Force
Assert-WeChatRuntime
if ([string]::IsNullOrWhiteSpace($CredentialFile)) {
    $CredentialFile = Get-WeChatDefaultCredentialPath
}

if ([string]::IsNullOrWhiteSpace($AppId)) { $AppId = Read-Host '请输入公众号 AppID' }
if ($AppId -notmatch '^wx[0-9A-Za-z]{16}$') { throw 'AppID 格式应为 wx 开头加 16 位字符。' }
if ([string]::IsNullOrWhiteSpace($AccountName)) { $AccountName = Read-Host '请输入公众号名称（用于防止发错账号）' }
if ([string]::IsNullOrWhiteSpace($AccountName)) { throw '公众号名称不能为空。' }
$AccountName = $AccountName.Trim()
$secret = Read-Host '请输入公众号 AppSecret（输入不可见）' -AsSecureString
if ($secret.Length -lt 16) { throw 'AppSecret 看起来过短，未保存。' }

Write-JsonNoBom -Path $CredentialFile -Value ([ordered]@{
    schemaVersion = 1
    appId = $AppId
    accountName = $AccountName
    appSecretProtected = ConvertFrom-SecureString -SecureString $secret
    createdAt = (Get-Date).ToString('o')
})

"微信公众号 API 凭据已使用 Windows DPAPI 加密保存 | AppID：$($AppId.Substring(0,6))**** | 账号：$AccountName | 文件：$CredentialFile"
