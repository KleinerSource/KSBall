# KSBall

KSBall 是一个仅面向 TrollStore 的 iPhone 全局快捷启动器。启动 KSBall 后，它会以 UIKit 插件模式运行独立 HUD 子进程，并通过 SpringBoard accessibility window hosting 在屏幕边缘内侧 10pt 处显示一条细短悬浮条。

从悬浮条向内滑动即围绕悬浮条一圈一圈地展开最多 48 个应用的扇形菜单，每圈按屏幕可显示的范围放下尽可能多的图标。滑到图标上会放大预览、显示应用名称并触发一次 Taptic Engine 震动，松手启动该应用，在空白处松手则取消。长按后拖动可调整位置（可拖到四个角落），长按不移动则进入配置页；锁屏界面自动隐藏悬浮条。

配置页可以调整：悬浮条样式（自动/亮色/暗色/隐藏）与触摸半径、毛玻璃样式（自动/亮色/暗色/无）与模糊程度、图标大小、同圈间距与圈间距。快捷应用可按用户应用、巨魔应用、系统应用分类逐个添加，并在全屏的扇形预览中长按拖动调整顺序。调整时悬浮条会实时预览效果。

## 悬浮分屏

在配置页打开某个快捷应用右侧的开关后，从扇形菜单选中它会以悬浮窗打开，而不是全屏启动。菜单中的这类图标带有窗口角标。

- 悬浮窗按全屏尺寸运行应用并等比缩小显示。拖动顶部标题条可移动窗口，拖右下角可缩放；标题条上有关闭、收起（−）和全屏打开三个按钮。
- 把窗口拖出屏幕左右边缘或点“−”，窗口会收进该侧的收纳区，变成实时缩略图。点缩略图恢复窗口，向屏幕外侧甩出则关闭。
- 最多同时悬浮 3 个应用，锁屏时自动隐藏。
- 应用未运行时由 KSBall 在后台启动，关闭悬浮窗时一并结束；应用已在运行时直接附加一个悬浮场景，关闭悬浮窗不会结束它。
- “全屏打开”只收回悬浮场景、不结束进程，再交给 SpringBoard 全屏显示。

实现方式参考 [FrontBoardAppLauncher](https://github.com/khanhduytran0/FrontBoardAppLauncher)：HUD 子进程启动时调用 `FBSystemShellInitialize` 成为 FrontBoard 场景宿主，用 `FBSceneManager` 为目标应用创建场景，再把 `_UIScenePresenter` 的画面嵌入悬浮窗。这一步只在至少有一个应用开启悬浮窗时执行，开关由无变有或由有变无时 HUD 会自动重建。宿主状态显示在配置页“系统能力 → 悬浮分屏”一行。

## 能力边界

- 支持 iOS 15 起的系统；实际安装前应确认设备系统受当前 TrollStore 版本支持。
- 全局 HUD 依赖 SpringBoard accessibility window hosting 私有接口和 TrollStore 权限，不可通过 App Store 发布。HUD 子进程沿用 TrollSpeed 的插件模式启动方式，不使用 UIScene。
- 注销 SpringBoard（respring）后悬浮条会自动重新注册并恢复；设备重启或用户在应用切换器中强制结束 KSBall 后，需要从主屏重新打开一次。
- HUD 窗口固定为竖屏坐标系，横屏时悬浮条仍位于竖屏方向的左右边缘。
- 主屏上隐藏或禁止启动的系统应用不会列出；可手动输入 Bundle ID 添加未枚举到的入口。
- 悬浮分屏依赖 FrontBoard / RunningBoard 私有接口，下面几点是已知限制：
  - 只支持竖屏。
  - 悬浮应用里的键盘可能弹不出来，或位置不对。
  - 多数 iPhone 应用只支持单个场景：如果应用已在运行，附加的悬浮场景可能是空白的。这时先在应用切换器中结束它，再从菜单以悬浮窗打开。
  - 悬浮期间从主屏再次打开同一个应用，可能与悬浮场景冲突。
  - respring、HUD 重建或 KSBall 被结束后，悬浮窗会关闭。

## 构建与安装

1. 在 macOS 上使用 Xcode 打开 `KSBall.xcodeproj`，选择 `KSBall` scheme。
2. 用 iPhoneOS SDK 构建 Release 产物。普通开发签名不应嵌入私有 entitlement。
3. 使用你的 TrollStore 签名流程为最终 `.app` 注入 `KSBall/KSBall.entitlements`，再打包 IPA 并在 TrollStore 安装。
4. 首次打开后，在 KSBall 配置页添加快捷应用；从悬浮条向内滑动展开菜单，滑到图标上松手启动，长按后拖动可保存位置，长按不移动可回到配置页。

## 测试

`KSBallTests` 覆盖设置 JSON 回退、48 项上限、图标尺寸、两种间距、外观选项、排序持久化、每个应用的悬浮窗开关、扇形几何（边界、间距、每圈容量、展开方向）、悬浮窗几何（缩放范围、宽高比、安全区限制、收起判定、收纳区排列）、版本比较与 Release 解析和桥接层 mock。SpringBoard 窗口注册、LaunchServices 启动行为、悬浮分屏的场景托管与触摸以及 TrollStore 在线安装必须在真机上验证。版本递增策略的测试用 `python3 -m unittest discover -s Scripts` 运行，CI 每次构建前也会执行。

应用图标由 `Scripts/generate_app_icon.py`（仅依赖 Python 标准库）生成，修改图案后重新运行即可覆盖 `KSBall/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。

## 版本号

版本号形如 `x.y.z+build`，`x.y.z` 与 `build` 分别写在 `KSBall/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`。每次构建时，`Scripts/bump_version.py --auto` 读取上一次 CI 版本递增之后的全部提交，按提交标题取其中最大的递增类型：

| 提交 | 递增方式 |
| --- | --- |
| 新增、删除或增强功能：`feat` / `feature` / `add` / `enhance` / `remove` / `delete`，或没有类型前缀但含“新增、添加、支持、实现、引入、删除、移除、增强”等字样 | 次版本号 +1，补丁号归零 |
| 优化、修复或改进既有行为：`fix`、`refactor`、`perf` 及其它提交 | 补丁号 +1 |
| 构建、CI、文档与测试（`build` / `ci` / `chore` / `docs` / `test`），涉及编译、构建、打包、签名的修复，或标题带 `[build-fix]` / `[no-version]` | 只增加 build |

build 号每次构建都 +1。本地运行 `python3 Scripts/bump_version.py` 可查看当前版本，也可以用 `--feature`、`--bug-fix`、`--build-only` 或 `--set x.y.z+build` 手动调整。

## GitHub Actions

推送、拉取请求和手动触发都会运行 `.github/workflows/build-ios.yml`：先测试版本策略并计算本次版本号，再用 macOS runner 构建未签名的 TrollStore `.tipa`，上传 `KSBall_<版本>.tipa`、SHA-256、导出的 entitlements 和 `xcodebuild.log` 工件；最终 TrollStore 签名仍在下载工件后执行。

main 分支的推送与手动运行在构建成功后还会：

1. 以 `chore: bump build metadata to <版本> [skip ci]` 提交写回 `Info.plist` 并推送到 main。因此本地再次推送前需要先 `git pull --rebase`。
2. 删除并重建滚动预发布 `latest`，上传安装包、SHA-256 与构建日志；说明由 `Scripts/generate_release_notes.sh` 生成，列出上一次发布以来的提交。

其它分支与拉取请求只产出 Actions 工件，不写回版本号，也不更新 Release。失败或被取消的构建不会写回版本号，其中的提交会并入下一次成功发布的说明。

## 检查更新

配置页“软件更新”分区通过 GitHub API 读取 `KleinerSource/KSBall` 的 `latest` 预发布，按 `x.y.z+build` 与当前版本比较：

- 开启“自动检查更新”（默认开启）时，打开 KSBall 或回到前台会静默检查，成功后 6 小时内不再重复请求；发现未忽略的新版本时弹窗显示更新内容。
- 点“检查更新”立即检查，即使该版本已被忽略也会提示，失败时显示原因。
- “立即更新”通过 `apple-magnifier://install?url=…` 交给 TrollStore 下载安装；TrollStore 不响应时改为打开发布页。安装完成后需要再打开一次 KSBall 以恢复悬浮条。
