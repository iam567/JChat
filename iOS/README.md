# JChat for iPhone

SwiftUI 原生 iPhone 聊天翻译器，最低支持 iOS 17，无第三方依赖。与仓库现有 Flask 网页版独立运行。界面自动跟随 iPhone 系统的浅色和深色模式。

## 日常使用

1. 点右上角设置，输入自己的 OpenAI API Key 并保存。可先用「验证 Key 和模型」检查账号权限。
2. 设置「我的语言」和「对方语言」。默认中文 → 日语。
3. 「我要回复」：输入自己的话，生成 3 条对方语言的回复，可编辑后复制。
   原文下方可点「复制原文」或「编辑并重新翻译」。编辑会自动带回输入框，修改后发送生成新结果；旧版本保留在历史中，后续上下文使用修正后的文字。
4. 「对方说」：粘贴对方原文，翻译成自己的语言，并说明对方的意思。
5. 「翻译最新截图」：读取相册最新截图，自动翻译成自己的语言。相册按钮支持同时选择最多 10 张图；选图编号后可在确认页调整顺序，再把整段对话一起分析。分析会区分左侧对方、右侧本人，说明对话主题、对方意思和接下来可以怎样回应。
6. 理解对方后输入回复，App 会结合本次对话的最近内容来翻译。生成的候选不代表实际已发送给对方。

「翻译最新截图」需要照片的完整访问权限。如果仅授权部分照片或拒绝授权，请使用手动选图，或到系统设置调整权限。App 不会在后台自动扫描相册。

## 语音翻译

底部中间的「语音翻译」使用 iOS 26+ 的 SpeechAnalyzer / SpeechTranscriber；旧系统仍可使用文字和截图功能。

- 选对方语言 → 开始语音翻译 → 允许麦克风和语音识别。首次使用某种语言可能下载系统识别模型。
- 在本机持续识别，显示未完成的原文；最终识别文字按句号、明显停顿或长句分段翻译成「我的语言」。译文按原句顺序排列，网络处理会有延迟。
- 单次上限 60 分钟。准备和收音期间禁用系统自动锁屏，停止、异常或取消后恢复原来的自动锁屏状态。
- 切走语音页、进入后台、来电或麦克风断开时停止收音，保留已有内容。手动锁屏无法被 App 禁止。
- 收音和翻译异步并行；翻译积压过多会暂停收音并继续处理已识别内容。失败的句子可单独重试。
- 对话文字和译文保存到翻译历史。不保存原始录音，音频由系统在本机识别，只把文字发送到 OpenAI。

## 语气

保留上级尊敬、朋友轻松、下级命令、泡妞调情、地痞流氓、高情商优化六种模式，新增默认的「AI 自动判断」。自动模式结合措辞和对话背景选择语气；关系不明时采用稳妥的中性礼貌表达。手动选择的模式优先。

## 翻译历史

- 成功的翻译自动按对话保存到本机，包括原文、翻译、回复候选和截图缩略图。
- 冷启动开启新对话；切换到 LINE 再回到 App 时保留当前对话。
- 底部「翻译历史」可重新打开对话继续回复，左滑删除，右上角垃圾桶清空全部。
- 左上角新建按钮随时开启新对话。
- 历史对话保留原来的语言设置，设置页里的语言变化用于新对话。

## OpenAI

默认模型是 `gpt-6.1-sol`，同时提供 `gpt-6-astra`、`gpt-6-luna` 和手动填写模型 ID 的入口，实际可用性取决于个人账号权限。型号不会未经确认自动替换。

通过 HTTPS 直接调用 Responses API，使用结构化输出。API Key 保存在本机 Keychain（仅本设备、解锁可用），不写入历史、不放进源码，也不转交给 VPS。截图会缩放压缩后连同本地 OCR 文字、最近对话上下文一起发送给 OpenAI，用于判断气泡归属和理解整段对话。多图按用户确认的顺序发送，重叠消息由模型合并分析。请求设置 `store: false`。

参考：[模型说明](https://developers.openai.com/api/docs/models/gpt-6.1-sol)、[Responses 文本生成](https://developers.openai.com/api/docs/guides/text?api-mode=responses)。

## 打开与安装

1. 用 Xcode 打开 `iOS/JChat.xcodeproj`。
2. 选中 JChat target，在 Signing & Capabilities 中选择自己的开发者 Team。项目当前使用原作者的 Team ID；其他开发者需要更换 Team 和唯一 Bundle Identifier。
3. 连接并解锁 iPhone，启用开发者模式，在 Xcode 选择该设备，运行。
4. 安装后在手机里的设置页输入自己的 API Key。

构建模拟器：

```sh
xcodebuild -project iOS/JChat.xcodeproj -scheme JChat \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

签名真机：

```sh
xcodebuild -project iOS/JChat.xcodeproj -scheme JChat \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath build -allowProvisioningUpdates build
```

## 验证

在 macOS 上运行无真实 API 请求的冒烟测试：

```sh
swiftc -parse-as-library iOS/JChat/Models.swift iOS/JChat/Services.swift iOS/JChat/SpeechSegments.swift \
  iOS/Tests/SmokeTests.swift -o /tmp/jchat-smoke
/tmp/jchat-smoke
```

覆盖结构化响应解析、语言方向、自动语气、对话上下文、无效 Key、生成中断、本地历史保存/恢复/删除，以及使用真实 Vision 引擎识别日语图片；另覆盖语音断句、句尾刷新、60 分钟边界、多图请求顺序和语音译文解析。

没有内置测试密钥。实际 OpenAI 翻译质量、账号额度和模型可用性需要使用者填入自己的 Key 后在手机上验证。
