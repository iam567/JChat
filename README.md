# 💬 JChat — AI 聊天翻译器

一个基于 AI 的双向聊天翻译工具，支持语气选择和一键复制回复建议，专为需要跨语言沟通的场景设计。

## 功能特点

- 🎭 **6种语气风格**：正式敬语 / 普通正常 / 朋友轻松 / 搞笑逗趣 / 老不正经 / 俯视不屑
- 📥 **翻译来信**：将对方说的话翻译成中文，快速理解含义
- 📤 **回复建议**：生成 3 条不同措辞的日语回复，一键复制，直接发送
- 🌍 **多语言支持**：日语、英语、韩语、法语、西班牙语、泰语等
- 🤖 **多 AI 支持**：Claude / OpenAI / Gemini，自由切换
- 💾 **场景管理**：按对话对象新建场景，保存聊天历史

## 在线体验



## 快速开始

### 安装依赖

```bash
pip install flask requests
```

### 启动服务

```bash
python app.py
```

浏览器打开 `http://localhost:8090`

### 配置 API Key

点击右上角 ⚙️ 设置，输入你的 API Key：

- **Claude**：前往 [console.anthropic.com](https://console.anthropic.com) 获取
- **OpenAI**：前往 [platform.openai.com](https://platform.openai.com) 获取
- **Gemini**：前往 [aistudio.google.com](https://aistudio.google.com) 获取

## 使用方法

1. **新建场景**：点右上角 `＋`，填写对方名字、语言和语气风格
2. **翻译对方的话**：点 `📥 对方说了` → 粘贴对方的原文 → 获得中文翻译
3. **生成回复**：点 `📤 我要回复` → 输入你想说的中文 → 获得 3 条回复建议 → 点按钮复制

## 项目结构

```
├── app.py              # Flask 后端
├── templates/
│   └── index.html      # 前端（单页应用）
├── requirements.txt    # 依赖列表
├── .gitignore
└── README.md
```

> ⚠️ `data.json` 为运行时自动生成的数据文件（含 API Key），已加入 `.gitignore`，请勿提交。

## License

MIT
