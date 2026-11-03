# DSHMeter

原生 macOS 菜单栏余额工具，自动复用 **DeepSeek Harness（DSH）已登录的 DeepSeek 账号**，显示账户余额。

界面源自 [raycalrui/CodexMeter](https://github.com/raycalrui/CodexMeter) 1.7.0（提交 `4c6baeec0ce3a502d3fbcf833782f823b0c1ec32`）。菜单栏绘制、380 点弹窗、历史窗口、六类设置页、开发者外观编辑器和关于页直接使用该版本的 SwiftUI 源文件；金额显示接入原有指标组件。DSHMeter 是独立社区项目，采用 MIT 许可。

## 下载与安装

系统要求：macOS 13 或更新版本。当前预编译包适用于 Apple Silicon（M 系列芯片）。发行包使用 macOS 27 SDK 构建，在 macOS 27 上采用系统当前的原生外观，较旧系统使用对应版本的系统控件。

1. 前往 [Releases](https://github.com/HY916-cn/DSHMeter/releases) 下载 `DSHMeter-0.1.6-macOS-arm64.zip`。
2. 解压，将 `DSHMeter.app` 拖入“应用程序”文件夹。
3. 打开应用，点击菜单栏的余额金额。

社区构建采用 ad-hoc 签名，尚未经过 Apple 公证。首次打开如被 macOS 阻止，请核对下载来源为本项目发行页面，再按照“系统设置 → 隐私与安全性”中的提示手动允许打开。

## 首次使用

> [!IMPORTANT]
> **在 DSH 登录 DeepSeek 账号后，直接打开 DSHMeter 即可读取余额，无需重复登录或输入密钥。**
>
> 在 DSH → 设置 → 模型中确认“DeepSeek 账号”为“已登录”。DSHMeter 优先复用该登录状态；没有已登录账号时，才使用 DSH 已配置的 DeepSeek API Key。
>
> 默认读取 `~/.dsh/.credentials.yaml`。如使用自定义 DSH 目录，请先按下方“自定义目录”说明保存实际目录，再重启 DSHMeter。目录应包含凭据文件。

### 1. 在 DSH 确认登录

打开 DSH Desktop、DSH NEXT 或 DSH Web，完成 DeepSeek 账号登录。在“设置 → 模型”页面，确认“DeepSeek 账号”显示“已登录”，再打开 DSHMeter。

DSHMeter 只读复用 DSH 保存的登录凭据，DSH 无须一直运行，也无须额外打开终端。登录失效时，请回到 DSH 重新登录。

### 2. 打开 DSHMeter

启动应用后，菜单栏会显示 `¥12.34` 这样的余额金额。点击后可查看：

- 账户总余额；
- 未过期的赠送余额；
- 充值余额；
- 当前余额可用状态；
- 上次成功更新时间。

菜单栏沿用原项目的样式选择，用金额替代百分比文字，较大金额采用 K/M 简写。“仅余额”使用至少 14 点的单行金额，货币符号与数字一同放大，宽度随金额自适应。弹窗沿用两行指标及进度条：第一行显示总余额，第二行显示充值余额，底部显示赠送余额和币种。蓝色条表示充值余额占总余额的比例。

总余额的进度环和第一条进度需要明确的“参考余额”，未设置时按原组件的未知数据状态显示，金额仍正常显示。参考值只用于显示，不限制消费。接口返回多个币种时分别展示；菜单栏来源可在“设置 → 菜单栏与弹窗”中选择。

设置参考余额后，可记录“余额 ÷ 参考余额”的本地历史；修改参考值会分开记录。余额接口没有重置周期，相关区域显示空状态。原项目的定时额度重置通知没有对应的余额事件。

### 3. 配置来源和优先级

每次刷新都重新解析以下来源：

1. 所选 DSH 目录下 `.credentials.yaml` 中的已登录账号：`records.deepseek-account-platform/default`。
2. 未登录账号时，使用同一文件中的 `refs.DEEPSEEK_API_KEY`（兼容早期平铺格式）。
3. DSHMeter 启动时继承的 `DEEPSEEK_API_KEY` 环境变量。
4. 所选 DSH 目录下的 `.env`。

账号凭据存在但损坏、来自其他平台环境或被服务端拒绝时，会明确报错，不切换到另一账户的余额。退出 DSH 账号后，如果配置了备用 API Key，后续刷新将使用该来源，弹窗副标题显示“DeepSeek API”。

目录默认使用 DSHMeter 启动环境中的 `DSH_HOME`，否则使用 `~/.dsh`。从 Finder 启动的应用通常不会继承终端临时 `export` 的变量；使用自定义目录时，请按下方说明保存目录。

登录账号、API Key 或 DSH 目录变化时，会清除原账户余额。进行中的查询若发现登录状态已变化，会丢弃旧结果。DSHMeter 不修改 DSH 文件、不执行登录或退出操作。

### 4. 自定义目录与参考余额

这些可选配置通过 macOS 偏好设置保存。先退出 DSHMeter，在终端运行所需命令，再从“应用程序”打开它。

自定义目录（把路径替换成实际包含 `.credentials.yaml` 的目录）：

```sh
defaults write com.huang.DSHMeter dsh.home -string "/你的/DSH/目录"
```

恢复自动使用 `DSH_HOME` 或 `~/.dsh`：

```sh
defaults delete com.huang.DSHMeter dsh.home
```

例如，将人民币参考余额设为 100 元：

```sh
defaults write com.huang.DSHMeter balance.references -dict-add CNY -string "100"
```

美元使用 `USD` 键。参考余额须为正数；未设置时，应用不会推测余额百分比。删除全部参考余额：

```sh
defaults delete com.huang.DSHMeter balance.references
```

## 刷新与错误处理

- 弹窗打开时每 **10 秒**、后台每 **60 秒**查询；查询至少间隔 10 秒，并防止并发重复请求。
- 打开弹窗或 Mac 唤醒时，已超过最小间隔且不在失败冷却中便刷新。
- 请求失败时保留本次运行中上次成功的余额及时间，并显示“余额可能已过期”。失败按 30、60、120、300 秒退避；接口返回限流时等待五分钟，界面显示自动重试时间。
- 当前金额只保留在内存，重新打开应用时重新查询。配置参考余额后，比例历史保存在 `~/Library/Application Support/DSHMeter/UsageHistory.sqlite`，可通过原项目的历史与备份设置管理。

| 提示 | 处理方式 |
| --- | --- |
| 未找到账号 | 打开 DSH 并完成 DeepSeek 账号登录；确认配置的 DSH 目录正确。 |
| 凭据无法读取或格式错误 | 检查 DSH 目录，在 DSH 中重新保存凭据；损坏的高优先级文件会明确报错。 |
| 凭据权限错误 | 文件须归当前用户所有且权限为 `600`；可使用下面的命令恢复自己文件的权限。 |
| 认证失效或被拒绝 | 在 DSH 中重新登录；使用备用 API Key 时，检查密钥是否已撤销或失效。 |
| 网络错误、超时或限流 | 检查网络及系统代理，按弹窗显示的时间等待重试。 |

默认目录的权限修复命令：

```sh
chmod 600 "$HOME/.dsh/.credentials.yaml"
# 仅在使用 .env 作为凭据来源时执行下一行：
chmod 600 "$HOME/.dsh/.env"
```

自定义 DSH 目录请相应替换路径。凭据文件支持普通文件，链接文件会显示无法读取；应用不会自动修改文件所有权或权限。凭据错误会提示前往 README；“设置 → 关于”中的 GitHub 链接直接打开本教程。

## 数据来源与隐私

已登录账号的余额沿用 [DSH 公开源码中的账号余额协议](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/credentials/deepseek-account-platform/README.md)：`GET https://platform.deepseek.com/api/v0/users/get_user_summary`，使用对应账号登录凭据认证，分别读取充值钱包与赠送钱包并按币种汇总。该协议可能随 DSH 更新而调整。

备用 API Key 方式使用文档化接口 [`GET https://api.deepseek.com/user/balance`](https://api-docs.deepseek.com/api/get-user-balance/)。两类凭据分别发送至各自对应的固定 HTTPS 地址，拒绝 HTTP 重定向；账号凭据的签发平台必须匹配 `https://platform.deepseek.com`。

凭据存储格式参照 [DSH 官方凭据说明](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/credentials/credentials-local/README.md)。应用仅读取所需字段，凭据保留在内存，错误文案不包含原始响应或凭据。账号查询不会读取姓名、手机号或邮箱，也不会触发登录、退出或赠金确认操作。

应用不发送模型请求、不读取会话、不收集遥测。偏好设置保存 DSH 目录和外观、语言、菜单栏、币种、登录启动、通知及历史等选项。配置参考余额后，比例历史保存在本机；不同凭据和目录分别记录。可选远程通知沿用原项目，推送凭据存入 DSHMeter 自己的钥匙串项。

## 构建与验证

使用安装了 Swift 的 macOS 环境。构建脚本使用 `xcrun` 当前选择的 macOS SDK；最新系统外观的发行构建使用 macOS 27 SDK，并将程序的链接 SDK 版本正确写入二进制，最低系统版本保持 13.0。Xcode 可直接打开 `Package.swift`；也可以通过命令行构建应用：

```sh
bash Scripts/test.sh
bash Scripts/build_local.sh
```

产物为 `dist/DSHMeter.app`。命令行构建通过 `ViewState` 类型别名直接使用原生 `SwiftUI.State` 属性包装器，兼容未附带新版 SwiftUI 宏插件的 Command Line Tools。构建通过 Swift Package Manager 下载锁定版本的 [Yams](https://github.com/jpsim/Yams) 用于解析 YAML。完整 Xcode 环境还可运行 `swift test`。

可选的真实余额查询检查，只执行一次官方余额 GET，不打印密钥或余额内容：

```sh
bash Scripts/test.sh --live
```

普通测试只使用临时凭据和模拟 HTTP 响应。应用更新包通过本仓库 Releases 分发。在“设置 → 关于”检查更新，发现新版本后点击“下载更新”打开对应发行页面。当前发行采用手动下载安装；自动安装控件保持禁用。

## 致谢

- [Raycal / CodexMeter](https://github.com/raycalrui/CodexMeter)：原生 macOS 菜单栏与弹窗设计。
- [jpsim / Yams](https://github.com/jpsim/Yams)：YAML 解析，MIT 许可。

原项目版权声明见 [LICENSE](LICENSE)。
