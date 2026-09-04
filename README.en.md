<div align="center">

# 📮 Kevin Su Skills

**Give an Agent content or a web project and complete WeChat draft or Xiaohongshu mini-tool publishing workflows**

[中文](./README.md)

Current stable release: [v1.0.0](https://github.com/413162826/kevinsu-skills/releases/tag/v1.0.0) · [Changelog](./CHANGELOG.md)

</div>

These are field-tested publishing Skills that I use myself.

The WeChat Skills call only the official WeChat API. The Xiaohongshu Skill uses Builder Hub after preview approval and runs the platform's current official Skill before upload.

## 📋 Skills

| Skill | What it does |
| --- | --- |
| [`wechat-article-api`](./wechat-article-api/) | Sends a formatted article, cover, and inline images to the draft box |
| [`wechat-image-api`](./wechat-image-api/) | Creates an image-post draft from 1–20 images |
| [`kevin-xhs-minitool-publisher`](./kevin-xhs-minitool-publisher/) | Converts a web or interactive project into an offline Xiaohongshu mini tool, then previews, audits, uploads, and reads back review status |

## 📦 Install

Codex users with `npx` available can install all three Skills with one command:

```powershell
npx -y skills@latest add 413162826/kevinsu-skills --skill wechat-article-api wechat-image-api kevin-xhs-minitool-publisher --agent codex -g -y
```

If `npx` is unavailable, install the latest Node.js first (the current CLI requires Node.js 22.20 or later).

The command installs only the three listed Skills. Skills added later are not installed automatically. To install only one, keep only its name.

Alternatively, tell Codex, Claude Code, or another Agent Skills-compatible tool:

```text
Install these Skills:

https://github.com/413162826/kevinsu-skills/tree/main/wechat-article-api
https://github.com/413162826/kevinsu-skills/tree/main/wechat-image-api
https://github.com/413162826/kevinsu-skills/tree/main/kevin-xhs-minitool-publisher
```

The Agent handles the download and install path. Start a new task after installation.

## ♻️ Update

After installing with the command above, update all three Skills with:

```powershell
npx -y skills@latest update wechat-article-api wechat-image-api kevin-xhs-minitool-publisher -g -y
```

Start a new task after updating. To update only one Skill, remove the other name from the command. Updating does not modify the WeChat AppID or AppSecret stored separately on your machine.

## 🚀 Use

Create an article draft:

```text
Send the finished article in this folder to my WeChat draft box: D:\article-folder
```

Create an image-post draft:

```text
Create a WeChat image-post draft from this folder: D:\image-folder
```

Build and publish a Xiaohongshu mini tool:

```text
Use $kevin-xhs-minitool-publisher to turn the current project into a Xiaohongshu mini tool and publish it after I approve the preview.
```

On first use, the WeChat Skills guide you through entering the AppID and AppSecret safely on your own machine. The Xiaohongshu Skill asks only the decisions that affect acceptance, then shows mobile previews before entering Builder Hub.

The Skills automate validation, upload, and status verification where possible. Login, verification codes, and platform agreements remain user actions.

<details>
<summary><strong>What is required for first-time setup?</strong></summary>

- Windows 10/11 and PowerShell 7.2+
- A WeChat Official Account AppID, AppSecret, and the required API permissions
- If WeChat returns `40164`, add the public IP shown in the error to the API allowlist

Enter the AppSecret only in your own terminal. Never paste it into a chat, issue, or screenshot.

</details>

<details>
<summary><strong>How should the package folder be prepared?</strong></summary>

If a content Agent has already generated the finished package, simply provide its folder path. The Skill stops and names any missing requirement instead of guessing.

- [Article package format](./wechat-article-api/references/package-contract.md)
- [Image-post package format](./wechat-image-api/references/package-contract.md)

</details>

<details>
<summary><strong>Can it publish automatically?</strong></summary>

The two WeChat Skills create and verify drafts only. They never call publish, mass-send, or delete APIs, and never fall back to browser or RPA automation.

The Xiaohongshu Skill uploads or submits only after preview approval and explicit publishing intent. Publishing a note, attaching the mini tool, withdrawing, unpublishing, or deleting requires separate authorization.

Uploaded covers and image-post images consume permanent-material quota in WeChat.

</details>

## 👋 About

- WeChat Official Account: **晚序拾光**
- Website: [moonsea.kevinsu.xyz](https://moonsea.kevinsu.xyz/)
- GitHub: [413162826](https://github.com/413162826)

[MIT License](./LICENSE) · [Changelog](./CHANGELOG.md) · [Security](./SECURITY.md) · [Contributing](./CONTRIBUTING.md)
