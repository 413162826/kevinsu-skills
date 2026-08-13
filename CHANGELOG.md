# 更新记录

本仓库中的微信公众号 Skills 共用一个版本号，并遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-08-13

首个稳定版本，已通过真实微信公众号草稿端到端验收。

### 新增

- `wechat-article-api`：校验文章素材包，上传正文图片与封面，创建图文草稿并回读验收。
- `wechat-image-api`：校验 1–20 张图片的贴图素材包，创建图片消息草稿并回读验收。
- 使用 Windows DPAPI 在本机独立保存公众号凭据；AppSecret 和 access token 不进入 Skill 或 Git 仓库。
- 素材目录检查点、防重复提交、账号严格核对、留言开关回读及 `40164` IP 白名单提示。
- 公开文件精确白名单、离线契约测试、Gitleaks 完整历史扫描和 GitHub Actions 验证。

### 修复

- 修复 `.NET HttpClient` 默认 multipart 格式导致微信图片上传返回 `41005 media data missing` 的兼容问题。

### 验收

- 从公开 GitHub 仓库全新安装两个 Skill 成功。
- 真实创建并回读普通图文草稿和贴图草稿成功，留言开关回读正确。
- 本机真实 AppID、AppSecret 对当前文件及完整 Git 历史精确扫描均未命中。

[1.0.0]: https://github.com/413162826/kevinsu-skills/releases/tag/v1.0.0
