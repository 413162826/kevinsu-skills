<div align="center">

# 📮 Kevin Su Skills

**Give an Agent a finished article or image folder and create a WeChat draft in one sentence**

[中文](./README.md)

</div>

These are field-tested WeChat Official Account Skills that I use myself.

They call only the official WeChat API, never control a browser, and never publish on your behalf.

## 📋 Skills

| Skill | What it does |
| --- | --- |
| [`wechat-article-api`](./wechat-article-api/) | Sends a formatted article, cover, and inline images to the draft box |
| [`wechat-image-api`](./wechat-image-api/) | Creates an image-post draft from 1–20 images |

## 📦 Install

In Codex, Claude Code, or another Agent Skills-compatible tool, say:

```text
Install these two Skills:

https://github.com/413162826/kevinsu-skills/tree/main/wechat-article-api
https://github.com/413162826/kevinsu-skills/tree/main/wechat-image-api
```

The Agent handles the download and install path. Start a new task after installation.

## 🚀 Use

Create an article draft:

```text
Send the finished article in this folder to my WeChat draft box: D:\article-folder
```

Create an image-post draft:

```text
Create a WeChat image-post draft from this folder: D:\image-folder
```

On first use, the Skill guides you through entering the AppID and AppSecret safely on your own machine. After that, use either sentence above.

The Skill validates the package, uploads the images, creates the draft, and reads it back for verification. You review and publish it from the WeChat console.

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

No. Both Skills create and verify drafts only. They never call publish, mass-send, or delete APIs, and never fall back to browser or RPA automation.

Uploaded covers and image-post images consume permanent-material quota in WeChat.

</details>

## 👋 About

- WeChat Official Account: **晚序拾光**
- Website: [moonsea.kevinsu.xyz](https://moonsea.kevinsu.xyz/)
- GitHub: [413162826](https://github.com/413162826)

[MIT License](./LICENSE) · [Security](./SECURITY.md) · [Contributing](./CONTRIBUTING.md)
