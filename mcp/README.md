# LuatOS Code MCP Server (luatos-code)

为 AI 工具提供 LuatOS 代码库访问能力的 MCP 服务器。

## 功能特性

- **扩展库查询**: 访问 `script/libs/` 目录下的 37 个 Lua 扩展库
- **模块 Demo 查询**: 访问 `module/` 目录下各型号的演示代码
- **智能搜索**: 支持关键词 + 向量混合检索（RRF 融合排序）
- **Lua 文档解析**: 自动解析 Lua 文件中的 `@module`, `@api`, `@param` 等文档注释
- **双模式支持**: 支持 stdio 和 SSE 两种传输模式

## 安装

### 环境要求

- Python 3.10+
- 依赖包: `mcp>=1.26.0`, `chromadb>=0.5.0`

### 安装步骤

```bash
cd /opt/sda2/LuatOS/mcp

# 创建虚拟环境（推荐）
python3 -m venv .venv
source .venv/bin/activate  # Linux/macOS
# 或: .venv\Scripts\activate  # Windows

# 安装依赖
pip install -r requirements.txt
```

## 使用方法

### 1. stdio 模式（默认）

适用于本地 AI 工具（如 Claude Desktop、Cline 等）:

```bash
python mcp_server.py --transport stdio
```

### 2. SSE 模式（端口 8100）

适用于远程访问或 Web 应用:

```bash
# 基本启动
python mcp_server.py --transport sse --port 8100

# 配置环境变量
export LUATOS_CODE_ROOT=/opt/sda2/LuatOS
export MCP_PORT=8100
python mcp_server.py --transport sse
```

## 工具列表

### `list_libs()`
列出所有可用的扩展库。

**返回示例:**
```json
{
  "count": 37,
  "libraries": [
    {
      "name": "libnet",
      "file": "libnet.lua",
      "summary": "在socket库基础上的同步阻塞api",
      "version": "1.0",
      "author": "lisiqi",
      "api_count": 12
    }
  ]
}
```

### `get_lib(name)`
获取指定库的完整内容和 API 文档。

**参数:**
- `name`: 库文件名（如 "libnet" 或 "libnet.lua"）

**返回:**
- 库元数据（名称、简介、版本、作者）
- 所有 API 列表（含参数、返回值）
- 完整的 Lua 源代码

### `list_modules()`
列出所有支持的模块型号。

**返回示例:**
```json
{
  "count": 5,
  "modules": [
    {"name": "Air780EPM", "demo_count": 42},
    {"name": "Air8000", "demo_count": 38}
  ]
}
```

### `list_demos(module)`
列出指定模块的所有 Demo。

**参数:**
- `module`: 模块型号（如 "Air780EPM"）

### `get_demo(module, demo_name)`
获取指定 Demo 的完整代码。

**参数:**
- `module`: 模块型号
- `demo_name`: Demo 名称（如 "gpio"）

### `search_code(query, scope, top_k)`
跨库和 Demo 进行智能搜索。

**参数:**
- `query`: 搜索关键词（支持中英文）
- `scope`: 搜索范围 - `"all"`（全部）, `"libs"`（仅库）, `"demos"`（仅 Demo）
- `top_k`: 返回结果数量（默认 8，最大 20）

**示例:**
```json
{
  "query": "MQTT 连接",
  "scope": "all",
  "result_count": 8,
  "results": [
    {
      "score": 0.85,
      "type": "lib",
      "module": "libnet",
      "file_path": "script/libs/libnet.lua",
      "title": "libnet",
      "snippet": "function libnet.connect(...)"
    }
  ]
}
```

### `resolve_module(query)`
从查询中识别模块型号。

**说明:**
- 自动识别查询中的型号（如 "air780epm", "air8000"）
- 未识别时默认返回 "air780epm"
- 返回检测到的模块及是否为默认值

### `server_stats()`
返回服务器运行统计信息。

## 配置示例

### Claude Desktop 配置

在 `claude_desktop_config.json` 中添加:

```json
{
  "mcpServers": {
    "luatos-code": {
      "command": "python",
      "args": [
        "/opt/sda2/LuatOS/mcp/mcp_server.py",
        "--transport",
        "stdio"
      ],
      "env": {
        "LUATOS_CODE_ROOT": "/opt/sda2/LuatOS"
      }
    }
  }
}
```

### SSE 模式客户端配置

```json
{
  "mcpServers": {
    "luatos-code": {
      "url": "http://127.0.0.1:8100/sse"
    }
  }
}
```

## 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `LUATOS_CODE_ROOT` | LuatOS 代码根目录 | `/opt/sda2/LuatOS` |
| `MCP_TRANSPORT` | 传输模式: `stdio` 或 `sse` | `stdio` |
| `MCP_PORT` | SSE 模式监听端口 | `8100` |
| `MCP_ALLOWED_HOSTS` | SSE 允许的 Host 白名单 | 空 |
| `MCP_ALLOWED_ORIGINS` | SSE 允许的 Origin 白名单 | 空 |

## 技术架构

### 索引系统

- **文件发现**: 自动扫描 `script/libs/*.lua` 和 `module/*/demo/*.lua`
- **文档解析**: 解析 Lua 注释中的 `@module`, `@api`, `@param`, `@return` 标签
- **向量索引**: 使用 ChromaDB 存储文本向量（支持语义搜索）
- **混合检索**: 关键词匹配 + 向量相似度，RRF 融合排序

### 缓存机制

- 文件修改时间 (mtime) 检测，自动重建索引
- 内存缓存分词结果和向量索引
- ChromaDB 持久化存储在项目根目录 `.chroma_code/`

## 故障排查

### 启动失败

```bash
# 检查依赖
pip list | grep -E "mcp|chromadb"

# 检查代码根目录
ls -la $LUATOS_CODE_ROOT/script/libs/
```

### 向量搜索未生效

- 首次启动需要下载 embedding 模型（约 90MB），请耐心等待
- 检查 ChromaDB 状态: `server_stats()` 返回 `chroma_indexed_count`

### 端口占用

```bash
# 更换端口
python mcp_server.py --transport sse --port 8101
```

## 开发说明

### 添加新的库文件

将 `.lua` 文件放入 `script/libs/` 目录，按以下格式添加文档注释:

```lua
--[[
@module mylibrary
@summary 库的简介说明
@version 1.0
@date    2024.01.01
@author  作者名
]]

--[[
函数说明
@api mylibrary.function_name(param)
@string param 参数说明
@return boolean 返回值说明
]]
function mylibrary.function_name(param)
    -- 实现
end
```

### 索引热更新

服务器每小时自动检查文件修改，无需重启即可加载新代码。

## 许可证

MIT License - 详见 LuatOS 项目 LICENSE 文件

---

**LuatOS MCP Server** - 让 AI 更好地理解 LuatOS 代码
