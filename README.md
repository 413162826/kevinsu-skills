<div align="center">

# 📮 Kevin Su Skills

**把成品文章或图片文件夹交给 Agent，一句话写入微信公众号草稿**

[English](./README.en.md)

当前稳定版本：[v1.0.0](https://github.com/413162826/kevinsu-skills/releases/tag/v1.0.0) · [更新记录](./CHANGELOG.md)

</div>

这是我自己正在使用、已经真实跑通的微信公众号 Skills。

只调用微信官方 API，不操作浏览器，也不会替你正式发表。

## 📋 两个 Skill

| Skill | 一句话 |
| --- | --- |
| [`wechat-article-api`](./wechat-article-api/) | 把排版好的图文文章、封面和配图写入公众号草稿箱 |
| [`wechat-image-api`](./wechat-image-api/) | 把 1–20 张图片写成公众号贴图草稿 |

## 📦 安装

Codex 用户且本机可以使用 `npx` 时，一条命令安装两个 Skill：

```powershell
npx -y skills@latest add 413162826/kevinsu-skills --skill wechat-article-api wechat-image-api --agent codex -g -y
```

没有 `npx` 时，先安装最新版 Node.js（当前 CLI 要求 Node.js 22.20 或更高版本）。

命令只安装列出的两个 Skill；以后仓库新增 Skill 不会被自动安装。只需要其中一个时，从命令中删掉另一个名称即可。

也可以在 Codex、Claude Code 等支持 Agent Skills 的工具里直接说：

```text
帮我安装这两个 Skill：

https://github.com/413162826/kevinsu-skills/tree/main/wechat-article-api
https://github.com/413162826/kevinsu-skills/tree/main/wechat-image-api
```

Agent 会自动安装到正确目录，不用你操心下载和路径。安装后新开一个任务即可使用。

## ♻️ 更新

通过上面的命令安装后，后续这样更新两个 Skill：

```powershell
npx -y skills@latest update wechat-article-api wechat-image-api -g -y
```

更新后新开一个任务即可使用新版。只更新其中一个时，从命令中删掉另一个名称即可。更新不会改动保存在本机独立目录中的公众号 AppID 和 AppSecret。

## 🚀 怎么用

发图文文章：

```text
把这个文件夹里的成品文章发到公众号草稿：D:\文章目录
```

发贴图：

```text
把这个文件夹里的图片发成公众号贴图草稿：D:\图片目录
```

第一次使用时，Skill 会引导你在本机安全录入 AppID 和 AppSecret。以后直接说上面两句话就行。

它会自己校验素材、上传图片、创建草稿并回读确认；你最后进入公众号后台检查和发表。

<details>
<summary><strong>第一次配置需要什么？</strong></summary>

- Windows 10/11 和 PowerShell 7.2+
- 公众号 AppID、AppSecret 和相应 API 权限
- 把微信报错 `40164` 中的公网 IP 加入公众号 API 白名单

AppSecret 只在你自己的终端中录入，不要发到聊天、Issue 或截图里。

</details>

<details>
<summary><strong>素材文件夹要怎么准备？</strong></summary>

如果内容 Agent 已经生成完整素材，直接把文件夹路径交给 Skill。格式不对时，它会停止并明确指出缺少什么。

- [文章素材格式](./wechat-article-api/references/package-contract.md)
- [贴图素材格式](./wechat-image-api/references/package-contract.md)

</details>

<details>
<summary><strong>它会不会直接发表？</strong></summary>

不会。两个 Skill 只创建并验收草稿，不调用正式发表、群发或删除接口，也不会失败后改走浏览器或 RPA。

上传的封面和贴图会占用微信公众号永久素材配额。

</details>

## 👋 关于

- 公众号：**晚序拾光**
- 网站：[moonsea.kevinsu.xyz](https://moonsea.kevinsu.xyz/)
- GitHub：[413162826](https://github.com/413162826)

[MIT License](./LICENSE) · [更新记录](./CHANGELOG.md) · [安全说明](./SECURITY.md) · [参与贡献](./CONTRIBUTING.md)
