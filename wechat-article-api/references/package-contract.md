# 文章素材包契约

```text
文章目录/
├── article.json
├── body.html
├── cover.png
└── images/
    ├── section-01.png
    └── section-02.png
```

`article.json`：

```json
{
  "schemaVersion": 1,
  "action": "save_draft_only",
  "account": "YOUR_WECHAT_ACCOUNT_NAME",
  "title": "文章标题",
  "author": "",
  "digest": "转发摘要",
  "contentSourceUrl": "",
  "bodyHtml": "body.html",
  "cover": "cover.png",
  "bodyImages": [
    {"marker": "section-01", "path": "images/section-01.png"}
  ],
  "needOpenComment": 1,
  "onlyFansCanComment": 0
}
```

正文图片在 HTML 中使用唯一占位段落：

```html
<p data-wechat-image="section-01">【图片：section-01】</p>
```

约束：

- 所有路径必须是素材目录内的相对路径。
- `account` 必填，且必须与本机加密凭据中的公众号名称逐字一致；示例占位符必须改掉才能创建草稿。
- 标题 1–32 字，作者不超过 16 字，摘要不超过 120 字。
- `contentSourceUrl` 可留空；非空时必须是无用户名密码的绝对 `http` 或 `https` URL。
- 正文少于 20000 字符且小于 1MB；禁止脚本、事件属性和 `javascript:`。
- 正文图仅 JPG/PNG，单张小于 1MB；每个 marker 恰好出现一次。
- 封面支持 BMP/PNG/JPG/GIF，最大 10MB；官方 API 要求永久图片 `media_id`。
- 微信会过滤正文外链图片，必须由脚本先调用 `media/uploadimg` 替换为微信 URL。

`assets/` 中是文本模板，不直接附带二进制图片。运行
`scripts/New-WeChatArticleExample.ps1` 可在指定目录生成带合成图片的完整示例包，随后可用
`Test-WeChatArticlePackage.ps1` 完成全离线校验；生成示例只用于验证目录契约，不应提交到真实公众号。

官方接口：[新增草稿](https://developers.weixin.qq.com/doc/service/api/draftbox/draftmanage/api_draft_add)、[获取草稿详情](https://developers.weixin.qq.com/doc/service/api/draftbox/draftmanage/api_getdraft)、[上传永久素材](https://developers.weixin.qq.com/doc/service/api/material/permanent/api_addmaterial)。
