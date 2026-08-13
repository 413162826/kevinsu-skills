# 贴图素材包契约

```text
贴图目录/
├── image-post.json
└── images/
    ├── post-01.jpg
    └── post-02.png
```

`image-post.json`：

```json
{
  "schemaVersion": 1,
  "action": "save_draft_only",
  "account": "YOUR_WECHAT_ACCOUNT_NAME",
  "title": "贴图标题",
  "content": "纯文本正文",
  "images": ["images/post-01.jpg", "images/post-02.png"],
  "needOpenComment": 1,
  "onlyFansCanComment": 0
}
```

约束：

- 所有字段都必须显式填写，缺失字段不会使用默认值；把 `account` 替换为目标公众号的准确名称。
- `account` 必须与本机凭据中保存的公众号名称完全一致，否则发布脚本立即停止。
- 所有图片路径必须是素材目录内的相对路径。
- 标题 1–32 字；正文必须是纯文本、少于 20000 字符且小于 1MB。
- 图片数量 1–20 张，顺序即发布顺序，第一张为封面。
- 支持 BMP/PNG/JPG/GIF，单张最大 10MB。
- 图片使用永久素材接口上传；素材库图片总量受微信账号配额限制。
- `needOpenComment=1` 表示开启留言；`onlyFansCanComment=0` 表示所有人可留言。仅关注者可留言时把后者改为 `1`。

运行 `scripts/New-WeChatImagePackageExample.ps1` 可在新目录生成一套带最小 PNG 的完整示例，并立即执行纯离线校验。示例中的账号名称只用于通过结构校验，调用真实 API 前必须替换。

官方 `draft/add` 的 `article_type=newspic` 即图片消息：[新增草稿](https://developers.weixin.qq.com/doc/service/api/draftbox/draftmanage/api_draft_add)、[获取草稿详情](https://developers.weixin.qq.com/doc/service/api/draftbox/draftmanage/api_getdraft)。
