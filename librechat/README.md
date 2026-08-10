# LibreChat 🚀

> **The Open-Source AI Platform** — Bring all your AI conversations together in a unified, customizable, and privacy-focused interface.

---

## 🌟 Key Features

* **Multi-Provider Support:** Seamlessly connect and switch between OpenAI, Anthropic (Claude), Google Vertex/Gemini, Azure, AWS Bedrock, Ollama, Groq, DeepSeek, OpenRouter, and any OpenAI-compatible custom endpoint.
* **Advanced Agents & MCP:** Create custom AI agents, leverage Model Context Protocol (MCP) support, and use sub-agents for specialized workflows.
* **Code Interpreter:** Secure, sandboxed execution for Python, JavaScript, Go, Rust, and more with integrated file handling.
* **Conversation Management:** Features conversation branching/forking, full message history search, and customizable presets.
* **Secure Multi-User Auth:** Built-in authentication supporting OAuth2 (Google, GitHub, etc.), LDAP, and standard email login.
* **Admin Panel:** Browser-based GUI for managing users, roles, and live configuration limits without redeploying.

---

## 🛠️ Quick Start (Docker)

The easiest way to run LibreChat locally or on a server is via Docker Compose:

1. Clone the repository:
   ```bash
   git clone https://github.com
   cd LibreChat
   ```
2. Copy and configure your environment variables:
   ```bash
   cp .env.example .env
   # Edit .env and set your MONGO_URI and API keys
   ```
3. Start the application:
   ```bash
   docker compose up -d
   ```

---

## 📚 Resources

* **Website:** [librechat.ai](https://www.librechat.ai/)
* **Documentation:** [librechat.ai/docs](https://www.librechat.ai/docs)
* **GitHub Repository:** [danny-avila/LibreChat](https://github.com/danny-avila/LibreChat)
