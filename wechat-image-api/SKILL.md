---
name: wechat-image-api
description: 通过微信官方服务端 API 校验贴图素材包、上传 1–20 张永久图片、创建 article_type=newspic 的公众号图片消息草稿，并用 draft/get 回读验收。Use when the user says“发一篇贴图到公众号草稿”“用 API 创建图片消息草稿”“不要操作浏览器发布贴图”；不用于长图文文章、浏览器 RPA、群发或正式发表。
---

# 微信公众号贴图 API

只使用 `api.weixin.qq.com` 官方接口创建并验收图片消息草稿。不启动浏览器，不调用发布、群发或删除接口，也不提供 RPA 兜底。

## 环境

要求 Windows 与 PowerShell 7.2+。AppSecret 使用当前 Windows 用户的 DPAPI 加密，默认保存到 `$env:CODEX_HOME\secrets`；未设置 `CODEX_HOME` 时使用 `$env:USERPROFILE\.codex\secrets`。网络请求在 PowerShell 进程内完成，不把 access token 传给外部命令。

## 输入与离线校验

执行前完整阅读 [references/package-contract.md](references/package-contract.md)。素材目录必须包含 `image-post.json` 和 1–20 张图片；`account` 必须明确填写，留言字段不得缺省。

先定位 Skill，再离线校验：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$skill = Join-Path $codexHome 'skills\wechat-image-api'
& (Join-Path $skill 'scripts\Test-WeChatImagePackage.ps1') -InputFolder 'D:\贴图素材目录'
```

需要完整示例时，在一个尚未包含示例文件的新目录中生成并校验：

```powershell
& (Join-Path $skill 'scripts\New-WeChatImagePackageExample.ps1') -OutputFolder 'D:\贴图示例'
```

## 首次配置

两个微信 API Skill 可共用同一份 DPAPI 凭据。凭据不存在时，不让用户在聊天中粘贴 AppSecret；运行本机交互式配置：

```powershell
& (Join-Path $skill 'scripts\Set-WeChatOfficialAccountCredential.ps1')
& (Join-Path $skill 'scripts\Test-WeChatOfficialAccountApi.ps1')
```

第二条命令验证 AppID、AppSecret、草稿权限和 IP 白名单。素材包 `account` 必须与配置时保存的公众号名称严格一致。

如果微信返回 `40164 invalid ip`，立即停止并把错误中的公网出口 IP 告诉用户，提醒其进入“设置与开发 → 开发接口管理 → IP 白名单”添加该 IP。用户确认后只重试同一官方 API；禁止改走浏览器、RPA、Cookie Profile 或其他发布通道。

## 创建并验收草稿

只有用户明确要求写入草稿后才运行：

```powershell
& (Join-Path $skill 'scripts\Publish-WeChatImageDraft.ps1') -InputFolder 'D:\贴图素材目录'
```

脚本逐张上传图片到 `material/add_material`，再用 `draft/add` 创建 `newspic` 草稿；第一张由微信作为封面。最后用 `draft/get` 回读并核对账号、标题、正文、图片顺序、留言设置和 `media_id`。

## 幂等与异常边界

- 每个素材目录使用独占锁，同一目录不能并发执行。
- 检查点只在确认收到 `media_id` 后推进；已记录草稿 ID 时，重复执行只回读验收，不重复创建。
- 如果网络或进程中断在图片上传或 `draft/add` 提交阶段，结果可能不确定。后续执行必须停止，禁止自动重试；先人工核对素材库或草稿箱，再使用新目录继续。
- 素材指纹变化但存在旧检查点时停止，不静默清空状态。
- 状态与回执使用同目录临时文件原子替换，避免留下半截 JSON。
- 只有 `draft/get` 回读全部字段通过，才报告“草稿创建并验收通过”；不得报告“已发表”。
- 回执写入 `wechat-image-api-receipt.json`。任一官方 API 失败均原地报告，本 Skill 没有浏览器/RPA 兜底。
