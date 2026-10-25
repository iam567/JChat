# JChat for iPhone

SwiftUI 原生 iPhone 聊天翻译器，最低支持 iOS 17，无第三方依赖。与仓库现有 Flask 网页版独立运行。

## 日常使用

1. 点右上角设置，输入自己的 OpenAI API Key 并保存。可先用「验证 Key 和模型」检查账号权限。
2. 设置「我的语言」和「对方语言」。默认中文 → 日语。
3. 「我要回复」：输入自己的话，生成 3 条对方语言的回复，可编辑后复制。
4. 「对方说」：粘贴对方原文，翻译成自己的语言，并说明对方的意思。
5. 「翻译最新截图」：读取相册最新截图，在手机上识别文字，自动翻译成自己的语言。也可以用相册按钮手动选图。
6. 理解对方后输入回复，App 会结合本次对话的最近内容来翻译。生成的候选不代表实际已发送给对方。

「翻译最新截图」需要照片的完整访问权限。如果仅授权部分照片或拒绝授权，请使用手动选图，或到系统设置调整权限。App 不会在后台自动扫描相册。

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

通过 HTTPS 直接调用 Responses API，使用结构化输出。API Key 保存在本机 Keychain（仅本设备、解锁可用），不写入历史、不放进源码，也不转交给 VPS。截图原图不上传；本地 OCR 文字和最近对话上下文会发送给 OpenAI 以进行翻译。请求设置 `store: false`。

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
swiftc -parse-as-library iOS/JChat/Models.swift iOS/JChat/Services.swift \
  iOS/Tests/SmokeTests.swift -o /tmp/jchat-smoke
/tmp/jchat-smoke
```

覆盖结构化响应解析、语言方向、自动语气、对话上下文、无效 Key、生成中断、本地历史保存/恢复/删除，以及使用真实 Vision 引擎识别日语图片。

没有内置测试密钥。实际 OpenAI 翻译质量、账号额度和模型可用性需要使用者填入自己的 Key 后在手机上验证。
