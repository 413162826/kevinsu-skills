# Kevin Su Skills | 晚序拾光

[中文](./README.md)

A small collection of field-tested, auditable Agent Skills. The first release automates WeChat Official Account drafts through the **official server-side API only**: no browser control, no RPA, and no AppSecret shared with an AI.

> [!IMPORTANT]
> These Skills create and verify drafts only. They never call the publish, mass-send, or delete APIs. An operator must review and publish every draft from the WeChat Official Account console.

## Skills

| Skill | Purpose | Input package |
| --- | --- | --- |
| [`wechat-article-api`](./wechat-article-api/) | Upload body images and a cover, create an `article_type=news` draft, and verify it with `draft/get` | `article.json`, body HTML, cover, and body images |
| [`wechat-image-api`](./wechat-image-api/) | Upload 1–20 permanent images, create an `article_type=newspic` draft, and verify it with `draft/get` | `image-post.json` and 1–20 images |

The two Skills share one locally encrypted credential. Both provide offline package validation, staged checkpoints, duplicate-run protection, and server-side read-back verification. An API failure is reported in place; it never triggers a hidden browser or RPA fallback.

## Requirements

- Windows 10 or 11
- PowerShell 7.2 or later (`pwsh`)
- A WeChat Official Account with the required server-side API permissions
- Its AppID and AppSecret, plus access to the API IP allowlist

API availability depends on the account type and verification status. This project cannot bypass WeChat-side permission restrictions.

## Install

On Windows, the recommended setup keeps a single working copy: clone the repository once, then expose both Skills to Codex through directory junctions. Future updates require only `git pull`.

Run in PowerShell 7:

```powershell
$repoRoot = Join-Path $env:USERPROFILE ".codex\repos\kevinsu-skills"
$skillsRoot = if ($env:CODEX_HOME) {
    Join-Path $env:CODEX_HOME "skills"
} else {
    Join-Path $env:USERPROFILE ".codex\skills"
}

New-Item -ItemType Directory -Force -Path (Split-Path $repoRoot) | Out-Null
git clone --depth 1 https://github.com/413162826/kevinsu-skills.git $repoRoot
& "$repoRoot\tools\Install-Skill.ps1" -Name all -DestinationRoot $skillsRoot
```

Update later with:

```powershell
git -C (Join-Path $env:USERPROFILE ".codex\repos\kevinsu-skills") pull --ff-only
```

For other Agent Skills directories, install the two named folders directly. Start a new task after installation so the Agent can discover them.

## First-time configuration

Never paste an AppSecret into a chat, Issue, pull request, log, or screenshot. Enter it locally in an interactive PowerShell session:

```powershell
$skillsRoot = if ($env:CODEX_HOME) {
    Join-Path $env:CODEX_HOME "skills"
} else {
    Join-Path $env:USERPROFILE ".codex\skills"
}

& (Join-Path $skillsRoot "wechat-article-api\scripts\Set-WeChatOfficialAccountCredential.ps1")
& (Join-Path $skillsRoot "wechat-article-api\scripts\Test-WeChatOfficialAccountApi.ps1")
```

The AppSecret is protected with Windows DPAPI for the current Windows user. Both Skills reuse the same local credential.

If WeChat returns `40164 invalid ip`, add the public egress IP shown in the error to the API IP allowlist under the Official Account development settings, then rerun the API test. A proxy, VPN, or network change may also change that IP. The Skills will not switch to a browser fallback.

## Prepare a package and create a draft

Article package:

```text
article-package/
├── article.json
├── body.html
├── cover.png
└── images/
```

Image-post package:

```text
image-post-package/
├── image-post.json
└── images/
```

Generate a complete synthetic package first:

```powershell
& "$skillsRoot\wechat-article-api\scripts\New-WeChatArticleExample.ps1" -OutputFolder "D:\wechat-article-example"
& "$skillsRoot\wechat-image-api\scripts\New-WeChatImagePackageExample.ps1" -OutputFolder "D:\wechat-image-example"
```

Then read the matching Skill's `references/package-contract.md` in full. Run the matching `Test-*Package.ps1`, or add `-DryRun` to a publish script, before explicitly asking an Agent to create the draft.

Article covers and image-post images consume the WeChat account's permanent-material quota. The scripts never delete permanent media automatically. Monitor the quota in the Official Account console and remove only material you have verified is no longer needed.

## Security boundary

- Connects only to the official `api.weixin.qq.com` API.
- Creates drafts and verifies them with `draft/get`; never publishes, mass-sends, or deletes.
- Does not read browser cookies, control the WeChat console, or fall back to browser/RPA automation.
- Never asks for an AppSecret in a conversation.
- Local state and receipt files are for idempotency and verification and must not be committed.

Read [SECURITY.md](./SECURITY.md) before reporting a vulnerability. Never disclose credentials or private account data in a public Issue.

## About

- GitHub: [413162826](https://github.com/413162826)
- Website: [moonsea.kevinsu.xyz](https://moonsea.kevinsu.xyz/)
- WeChat Official Account: **晚序拾光** (QR code to be added)
- Xiaohongshu: to be added
- X: to be added

Released under the [MIT License](./LICENSE). This is an independent community project and is not affiliated with or endorsed by Tencent or WeChat. WeChat names and marks belong to their respective owners.
