# XHSNativePlus

基于 [huami1314/XHSNative](https://github.com/huami1314/XHSNative)（MIT License）深度定制的 iOS 26+ 小红书原生 Liquid Glass 插件，全部模块编译为**单个统一 `.dylib`**。

## 主要增强特性

- **底部标签栏 & 首页**：原生系统 `UITabBar` 悬浮液态玻璃、可选显示标签文字、可选主题红（`#FF2442`）选中态、标签排序/隐藏、滚动收起、首页频道管理与禁用点点 AI。
- **图文笔记页（POST） & 视频页**：App Store / Telegram 风格顶栏（融合头像 + 昵称液态玻璃胶囊、图标化关注与分享）、底部液态玻璃互动栏（`star` 收藏、图标化评论入口、防误触/防闪烁修复）、双击放大图片。
- **消息主页 & 搜索栏**：消息主页原生透明导航栏 + `softStyle` 顶部渐进模糊 + iOS 原生 `UIRefreshControl` 下拉刷新 + 原生 `UIMenu` 与圆形图标左滑操作；搜索栏全套液态玻璃与圆形放大镜/返回按钮。
- **私聊 / 群聊（iOS 26 iMessage 风格）**：
  - Telegram 风格融合「头像 + 昵称 + 在线状态」顶栏胶囊（「当前在线」高亮小红书主题红 `#FF2442`），移除 emoji 壁纸顶部渐变遮罩并接入系统 `UIScrollEdgeEffect` 渐进模糊；
  - iMessage 双胶囊底栏（左侧独立圆形 `+` 液态玻璃 + 右侧 `[发消息… ☺ 🎤]` 胶囊）、全套原生 SF Symbols 与弹性按压反馈；
  - `+` 按钮改为 iMessage 风格液态玻璃悬浮弹出菜单（动态读取当前会话全部原生功能项）；
  - 长按消息菜单改为 iOS 26 液态玻璃竖排上下文菜单；
  - 文字与语音消息改为 iMessage 尾角气泡（对方毛玻璃通透适配壁纸，己方小红书主题红渐变）。
- **无水印保存 & 容器兼容（合并自上游 1.5）**：支持笔记与评论区的图片/实况/视频无水印保存、解除作者关闭下载的保存限制，兼容 LiveContainer 等容器加载环境。
- **模块化源码结构**：所有功能拆分为 `SingleSource/` 下的独立模块（TabBar / NoteGlass / VideoGlass / ChatGlass / GlassShared / Save / Settings / Config），便于维护与二次开发。

## 构建

```bash
bash build-single.sh
```

产物输出至 `release/XHSNative-1.4-2.dylib`（单文件，自动 ad-hoc 签名并校验）。

## 致谢与协议

本项目基于 [huami1314/XHSNative](https://github.com/huami1314/XHSNative) 二次开发，遵循原项目 [MIT License](LICENSE)。
