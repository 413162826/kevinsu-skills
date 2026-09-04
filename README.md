<div align="center">

# 📮 Kevin Su Skills

**把内容或网页项目交给 Agent，完成公众号草稿与小红书小工具发布流程**

[English](./README.en.md)

当前稳定版本：[v1.0.0](https://github.com/413162826/kevinsu-skills/releases/tag/v1.0.0) · [更新记录](./CHANGELOG.md)

</div>

这是我自己正在使用、已经真实跑通的内容发布 Skills。

公众号 Skills 只调用微信官方 API；小红书 Skill 在用户确认预览后操作 Builder Hub，并在发布前加载平台当期官方 Skill 做双重检查。

## 📋 三个 Skill

| Skill | 一句话 |
| --- | --- |
| [`wechat-article-api`](./wechat-article-api/) | 把排版好的图文文章、封面和配图写入公众号草稿箱 |
| [`wechat-image-api`](./wechat-image-api/) | 把 1–20 张图片写成公众号贴图草稿 |
| [`kevin-xhs-minitool-publisher`](./kevin-xhs-minitool-publisher/) | 把网页或交互项目改造成离线小红书小工具，预览确认后检查、上传并回读审核状态 |

## 📦 安装

Codex 用户且本机可以使用 `npx` 时，一条命令安装三个 Skill：

```powershell
npx -y skills@latest add 413162826/kevinsu-skills --skill wechat-article-api wechat-image-api kevin-xhs-minitool-publisher --agent codex -g -y
```

没有 `npx` 时，先安装最新版 Node.js（当前 CLI 要求 Node.js 22.20 或更高版本）。

命令只安装列出的三个 Skill；以后仓库新增 Skill 不会被自动安装。只需要其中一个时，只保留对应名称即可。

也可以在 Codex、Claude Code 等支持 Agent Skills 的工具里直接说：

```text
帮我安装这些 Skill：

https://github.com/413162826/kevinsu-skills/tree/main/wechat-article-api
https://github.com/413162826/kevinsu-skills/tree/main/wechat-image-api
https://github.com/413162826/kevinsu-skills/tree/main/kevin-xhs-minitool-publisher
```

Agent 会自动安装到正确目录，不用你操心下载和路径。安装后新开一个任务即可使用。

## ♻️ 更新

通过上面的命令安装后，后续这样更新三个 Skill：

```powershell
npx -y skills@latest update wechat-article-api wechat-image-api kevin-xhs-minitool-publisher -g -y
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

制作并发布小红书小工具：

```text
用 $kevin-xhs-minitool-publisher 把当前项目做成小红书小工具，满意后发布。
```

公众号 Skill 第一次使用时会引导你在本机安全录入 AppID 和 AppSecret。小红书 Skill 会先询问影响上线的必要问题，给出手机预览，用户满意后再进入 Builder Hub。

它们会完成能自动完成的校验、上传和状态回读；登录、验证码与平台协议仍由用户本人完成。

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

两个公众号 Skill 只创建并验收草稿，不调用正式发表、群发或删除接口，也不会失败后改走浏览器或 RPA。

小红书 Skill 只有在用户确认预览并明确同意发布后，才上传或提交审核；发布笔记、挂载组件、撤回、下架和删除需要单独授权。

上传的封面和贴图会占用微信公众号永久素材配额。

</details>

## 👋 关于

- 公众号：**晚序拾光**
- 网站：[moonsea.kevinsu.xyz](https://moonsea.kevinsu.xyz/)
- GitHub：[413162826](https://github.com/413162826)

[MIT License](./LICENSE) · [更新记录](./CHANGELOG.md) · [安全说明](./SECURITY.md) · [参与贡献](./CONTRIBUTING.md)
