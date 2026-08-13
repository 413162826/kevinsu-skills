---
name: wechat-article-api
description: 通过微信官方服务端 API 校验文章素材包、上传正文图片与封面、创建 article_type=news 的公众号图文文章草稿，并用 draft/get 回读验收。Use when the user says“把成品文章通过 API 发到公众号草稿”“不要操作浏览器发布公众号文章”“素材在这个文件夹，创建微信文章草稿”；不用于贴图、浏览器 RPA、群发或正式发表。
---

# 微信公众号文章 API

只使用 `api.weixin.qq.com` 官方接口，不启动或操作浏览器。只创建草稿，不调用发布、群发或删除接口。

## 运行条件

- Windows 与 PowerShell 7.2+（`pwsh`）。
- 公众号已获得草稿接口权限，当前公网出口 IP 已加入公众号 API 白名单。
- AppSecret 只由用户在本机交互式终端输入；不要要求用户在聊天中粘贴。

命令中的 Codex 主目录按 `CODEX_HOME` 环境变量解析；未设置时使用
`%USERPROFILE%\.codex`：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skillRoot = Join-Path $codexHome 'skills\wechat-article-api'
```

## 输入

执行前完整阅读 [references/package-contract.md](references/package-contract.md)。素材目录必须包含 `article.json`、正文 HTML、封面和正文图片。
`account` 必填，并且必须与加密凭据中的公众号名称逐字一致。模板默认开启所有用户留言：
`needOpenComment=1`、`onlyFansCanComment=0`。

先离线校验：

```powershell
& (Join-Path $skillRoot 'scripts\Test-WeChatArticlePackage.ps1') -InputFolder "D:\成品文章目录"
```

需要检查素材契约时，可生成一个不会连接微信的完整合成示例包：

```powershell
& (Join-Path $skillRoot 'scripts\New-WeChatArticleExample.ps1') -OutputFolder "D:\wechat-article-example"
```

## 首次配置

打开本机交互式 `pwsh`，让用户录入 AppID、公众号名称和 AppSecret：

```powershell
& (Join-Path $skillRoot 'scripts\Set-WeChatOfficialAccountCredential.ps1')
```

凭据使用当前 Windows 用户的 DPAPI 加密，默认保存到
`$CODEX_HOME\secrets\wechat-official-account.dpapi.json`；未设置 `CODEX_HOME` 时保存到
`%USERPROFILE%\.codex\secrets\wechat-official-account.dpapi.json`。该文件只能由同一台 Windows
计算机上的同一用户解密，不得提交到代码仓。

配置后先验证权限和 IP 白名单：

```powershell
& (Join-Path $skillRoot 'scripts\Test-WeChatOfficialAccountApi.ps1')
```

如果微信返回 `40164 invalid ip`，立即停止并把错误中的公网出口 IP 告诉用户，提醒其进入“设置与开发 → 开发接口管理 → IP 白名单”添加该 IP。用户确认后只重试同一官方 API；禁止改走浏览器、RPA、Cookie Profile 或其他发布通道。

## 创建草稿

用户明确要求写入草稿后运行：

```powershell
& (Join-Path $skillRoot 'scripts\Publish-WeChatArticleDraft.ps1') -InputFolder "D:\成品文章目录"
```

使用 `-DryRun` 只做离线校验。脚本上传正文图片到 `media/uploadimg`，封面到 `material/add_material`，用 `draft/add` 创建 `news` 草稿，再用 `draft/get` 回读标题、封面和正文图片。

## 重复提交保护与结果

- 同一素材目录使用独占锁，禁止两个进程并发创建草稿。
- 在素材目录原子写入 `wechat-article-api-state.json`，逐张记录图片 URL、封面 `media_id` 和草稿 `media_id`。
- 已保存草稿 `media_id` 时，同一素材指纹重复执行只回读该草稿，不再次调用 `draft/add`。
- 调用 `draft/add` 前先记录 `draft_submitting`。若网络中断等原因导致服务端结果无法确认，保留不确定状态并禁止自动重试；要求用户先人工核对草稿箱，不能承诺“绝不重复”。
- 微信明确返回错误码时允许修正问题后重试；正文图片或封面上传遇到不确定网络失败时，重试可能产生未引用的重复素材，但不会自动越过不确定的草稿提交状态。
- 素材变化但存在旧检查点时停止，要求使用新目录；不得静默重置。
- 只有 `draft/get` 回读验收通过，才报告成功。
- 回执原子写入 `wechat-article-api-receipt.json`。报告账号、标题、`media_id`、图片数、阶段与微信原始错误码；不得报告“已发表”。
- 任一官方 API 失败均原地报告并保留检查点；本 Skill 没有浏览器/RPA 兜底。
