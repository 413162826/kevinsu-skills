# Kevin Su Skills｜晚序拾光

[English](./README.en.md)

一组真实跑通过、可以审计的 Agent Skills。首批开放的是微信公众号草稿 API：**不用浏览器，不用 RPA，不把 AppSecret 交给 AI**，只通过微信官方服务端 API 创建草稿并回读验收。

> [!IMPORTANT]
> 本项目只创建并验收公众号草稿，不调用正式发表、群发或删除接口。草稿仍需运营者进入公众号后台检查后自行发表。

## Skills

| Skill | 用途 | 素材要求 |
| --- | --- | --- |
| [`wechat-article-api`](./wechat-article-api/) | 上传正文图片与封面，创建 `article_type=news` 图文文章草稿并回读验收 | `article.json`、正文 HTML、封面及正文图片 |
| [`wechat-image-api`](./wechat-image-api/) | 上传 1–20 张永久图片，创建 `article_type=newspic` 图片消息草稿并回读验收 | `image-post.json` 及 1–20 张图片 |

两个 Skill 共用同一份本机加密凭据，均具备离线素材校验、阶段检查点、重复执行保护和 `draft/get` 回读验收。任一官方接口失败都会原地报告，不会悄悄切换到浏览器或 RPA。

## 运行要求

- Windows 10/11
- PowerShell 7.2 或更高版本（命令为 `pwsh`）
- 具备相应服务端 API 权限的微信公众号
- 公众号 AppID、AppSecret，以及可配置的 API IP 白名单

接口权限由微信根据账号类型及认证状态决定。本项目无法绕过微信侧权限限制。

## 安装

推荐只保留一份源码：把仓库克隆到本机源码目录，再通过 Windows 目录联接挂到 Codex 的 Skills 目录。以后执行 `git pull` 即可同步更新，不需要维护两份文件。

在 PowerShell 7 中执行：

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

更新：

```powershell
git -C (Join-Path $env:USERPROFILE ".codex\repos\kevinsu-skills") pull --ff-only
```

如果你的 Agent 使用其他 Skills 目录，也可以直接安装仓库中的两个同名文件夹。安装后重新开启一个任务，让 Agent 重新发现 Skill。

## 首次配置

不要把 AppSecret 粘贴到聊天、Issue、PR、日志或截图里。请在你自己的交互式 PowerShell 中录入：

```powershell
$skillsRoot = if ($env:CODEX_HOME) {
    Join-Path $env:CODEX_HOME "skills"
} else {
    Join-Path $env:USERPROFILE ".codex\skills"
}

& (Join-Path $skillsRoot "wechat-article-api\scripts\Set-WeChatOfficialAccountCredential.ps1")
& (Join-Path $skillsRoot "wechat-article-api\scripts\Test-WeChatOfficialAccountApi.ps1")
```

AppSecret 使用当前 Windows 用户的 DPAPI 加密后保存在本机，两个 Skill 共用这份凭据。

如果返回 `40164 invalid ip`，错误中的 IP 是微信看到的公网出口 IP。把它加入公众号后台“设置与开发 → 开发接口管理 → IP 白名单”，然后重新执行 API 测试。使用代理、VPN 或会更换出口 IP 的网络时，白名单也需要随之更新；本项目不会因此改走浏览器兜底。

## 准备素材并创建草稿

文章素材包：

```text
文章目录/
├── article.json
├── body.html
├── cover.png
└── images/
```

贴图素材包：

```text
贴图目录/
├── image-post.json
└── images/
```

先运行对应的示例生成器，获得一份可直接通过离线校验的合成素材包：

```powershell
& "$skillsRoot\wechat-article-api\scripts\New-WeChatArticleExample.ps1" -OutputFolder "D:\公众号文章示例"
& "$skillsRoot\wechat-image-api\scripts\New-WeChatImagePackageExample.ps1" -OutputFolder "D:\公众号贴图示例"
```

随后完整阅读对应 Skill 的 `references/package-contract.md`。建议先运行 `Test-*Package.ps1` 或给发布脚本添加 `-DryRun`，确认素材通过离线校验后，再明确要求 Agent 创建草稿。

文章封面和贴图图片会占用微信公众号永久素材配额。脚本不会自动删除永久素材；长期使用时请在公众号后台关注配额，并人工清理确认无用的素材。

## 安全边界

- 仅请求 `api.weixin.qq.com` 官方接口。
- 仅创建草稿并通过 `draft/get` 回读，不会正式发表、群发或删除。
- 不读取浏览器 Cookie，不控制微信后台，不提供浏览器/RPA 兜底。
- 不要求用户在对话中提供 AppSecret。
- 状态文件和回执只用于本地幂等与验收，不应提交到 Git。

发现安全问题请阅读 [SECURITY.md](./SECURITY.md)，不要在公开 Issue 中提交密钥或账号隐私。

## 关于

- GitHub：[413162826](https://github.com/413162826)
- 网站：[moonsea.kevinsu.xyz](https://moonsea.kevinsu.xyz/)
- 微信公众号：**晚序拾光**（二维码待补）
- 小红书：待补充
- X：待补充

本项目采用 [MIT License](./LICENSE)，由社区独立维护，与腾讯、微信无隶属或官方合作关系。“微信”及相关标识归其权利人所有。
