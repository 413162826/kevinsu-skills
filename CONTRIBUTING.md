# 参与贡献

欢迎提交问题和改进。这个仓库优先解决真实、可复现的内容发布工作流，不追求功能数量。

## 开始之前

- Issue 与 PR 中不得出现 AppSecret、access token、Cookie、真实凭据文件或未脱敏账号信息。
- 示例必须使用虚构账号、占位符和可公开的合成素材。
- 微信公众号 Skill 新增接口前先确认它来自微信官方文档，并说明为什么属于“创建和验收草稿”的既有边界。
- 两个微信公众号 Skills 不要增加浏览器控制、RPA、正式发表、群发、删除或静默兜底路径。
- 小红书小工具的浏览器操作只能用于 Builder Hub 上传、模拟器验收和状态回读；用户确认预览前不得上传，发布笔记、挂载、撤回、下架和删除必须单独授权。
- 小红书容器规则以当次上传页提供的官方 Skill 为准，不提交官方 Skill 缓存、浏览器 Profile、Cookie 或登录态文件。

## 修改要求

1. 保持改动小而明确，一个 PR 只解决一个问题。
2. PowerShell 代码以 PowerShell 7.2 为最低版本，并兼容 Windows 10/11。
3. 两个微信公众号 Skill 中的共享微信 API 模块必须保持一致；修改共享逻辑时同步更新并验证。
4. 新行为需要离线测试；错误处理应保留微信原始错误码，并覆盖 `40164 invalid ip`。
5. 任何写入官方 API 的测试都必须由维护者显式触发，默认 CI 不得访问真实公众号。
6. 更新输入结构或行为时，同步修改 `SKILL.md`、素材契约和示例。
7. 修改小红书小工具 Skill 时，同时运行官方 Skill 门禁、本地 ZIP 校验器与手机尺寸预览；CI 只执行不需要登录态的离线部分。

提交 PR 前请至少完成：

```powershell
pwsh -NoProfile -File .\wechat-article-api\scripts\Test-WeChatArticlePackage.ps1 -InputFolder "<文章测试素材目录>"
pwsh -NoProfile -File .\wechat-image-api\scripts\Test-WeChatImagePackage.ps1 -InputFolder "<贴图测试素材目录>"
```

不要为了测试把真实 AppSecret 写入脚本、环境文件、命令参数或仓库历史。无法公开复现的问题，请使用 GitHub 的私密漏洞报告通道。
