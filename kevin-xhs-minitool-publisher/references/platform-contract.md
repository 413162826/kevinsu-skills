# 小红书小工具运行与审核边界

本页只记录会改变实现方式的规则。每次发布前重新打开 Builder Hub 的“小工具开发者文档”和上传表单；页面当前值优先于历史经验。

上传页还会给出一条下载当期官方构建 Skill 的完整口令。每次发布都读取当前口令并执行当期官方 Skill；它是版本化的交付规则，不能永久写死某个下载地址或版本。2026-09-04 实测页面提供的是 `minitool-zip-builder` 1.6.0，仅作为历史证据，不作为以后发布的固定依赖。

## 当前权威入口

- 创作服务平台 `https://creator.xiaohongshu.com/`
- Builder Hub 菜单 `小工具`
- 小工具开发者文档 `https://fe-video-qc.xhscdn.com/fe-platform-file/104101b8324ihuc967a06277180ac7t8006ptl0fm199r4.html`
- 小工具服务协议 `https://agree.xiaohongshu.com/h5/terms/ZXXY20260630004/-1`

2026-09-04 实测上传页显示 ZIP 单文件最大 10MB。其他“小组件”文档曾出现 2MB，不要混用；每次以当前 Builder Hub 小工具上传表单为准。项目可以把 2MB 设成更严格的内部性能预算，但不能把它写成 Builder Hub 当前平台上限。

## 纯离线

小工具是纯本地运行的 Web 应用。HTML、CSS、JavaScript、图片和字体全部放进 ZIP，不能依赖服务端、CDN、远程字体、远程图片或运行时配置。

静态内容更新只能随新版本重新打包上传。必须实时联网才成立的产品不适合直接改造成小工具。

## 明确禁用

上传前必须清零以下能力：

- `fetch`、`XMLHttpRequest`、外部资源加载和其他联网请求
- `target="_blank"`、`window.open`、站外跳转和小工具之间跳转
- `<iframe>`、表单跳转提交
- WebSocket、EventSource、WebRTC
- Web Worker、SharedWorker、Service Worker
- WebAssembly
- `eval`、`new Function`
- `navigator.clipboard`、复制粘贴命令
- `navigator.geolocation`、蓝牙、USB、HID、串口、传感器
- `requestFullscreen`、屏幕共享、媒体设备枚举
- `a[download]`、Blob 下载
- WebAuthn、`navigator.credentials`、Web Locks

普通 `<a href="https://...">` 即使在桌面模拟器里能显示，也属于站外跳转风险。最终 ZIP 不保留 http 或 https URL；来源可以显示为“官网 · 2026-09-03”一类纯文字。官网域名可以显示为纯文字，但不能包装成可点击链接。

二维码本身是本地图片，不属于网络请求。二维码若编码微信、站外网址或其他平台入口，仍可能触发内容审核中的站外导流判断。发布前必须实际解码、确认目的地、向用户报告风险并取得继续提交的明确意见；不要把“技术上能显示”写成“平台允许导流”。

W3C SVG/HTML 命名空间是代码常量，不是联网行为。校验脚本允许 `http://www.w3.org/1999/xhtml`、`http://www.w3.org/2000/svg` 和 `http://www.w3.org/1998/Math/MathML`。

## HTML 与打包

- ZIP 根目录必须有 `index.html`，不能再包一层目录。
- 资源路径使用 `./` 相对路径。
- 禁止内联 `<script>`、行内事件和 `javascript:` URL。
- 禁止 `<base>` 改写路径。
- 生产包关闭 sourcemap，不把源码、密钥、日志或开发文件打进去。
- 图标使用方形 PNG/JPG；封面按上传页实际要求准备，封面通常不放入运行 ZIP。
- 只声明真实需要的权限。默认“不需要权限”。

## 当前允许的端能力

开发文档当前列出的端能力只有：

- `postNote` 唤起笔记发布页
- `saveImageToPhotosAlbum` 保存本地图片
- `writeTempFile` 将 base64 写成容器内临时文件

调用前判空 `window.xhs && window.xhs.miniTool`，并只在用户主动点击后调用。媒体字段只接受 data URL 或本地文件路径，不接受网络 URL。

## 内容与权利

- 不收集用户信息；确有需要时必须另做隐私说明和授权。
- 不上传无权使用的代码、字体、图片、音视频或品牌素材。
- 小工具详情要写清主要功能、适用范围和限制。
- AI 生成素材遵守相应服务条款并保存来源记录。
- 模拟器通过只代表包能运行，不代表内容、外链、版权和权限审核通过。
