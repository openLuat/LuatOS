# LuatOS Code MCP Server - 快速启动指南

## 已完成 ✅

LuatOS MCP 服务器 `luatos-code` 已成功实现，提供以下功能：

### 📁 文件结构
```
LuatOS/mcp/
├── mcp_server.py          # 主服务器文件 (1,148 行)
├── requirements.txt       # Python 依赖
├── luatos_code_dict.txt   # 自定义词典
├── README.md              # 完整文档
├── test_server.py         # 功能测试脚本
└── QUICKSTART.md          # 本文件
```

### 🚀 快速启动

#### 1. stdio 模式（本地 AI 工具）
```bash
cd /opt/sda2/LuatOS/mcp
source /opt/sda2/luatos-docs-v2/.venv/bin/activate
python mcp_server.py --transport stdio
```

#### 2. SSE 模式（端口 8100）
```bash
cd /opt/sda2/LuatOS/mcp
source /opt/sda2/luatos-docs-v2/.venv/bin/activate
python mcp_server.py --transport sse --port 8100
```

访问地址: `http://127.0.0.1:8100/sse`

### 🛠️ 提供的工具 (7 个)

| 工具名 | 功能 | 示例 |
|--------|------|------|
| `list_libs()` | 列出所有扩展库 | 37 个库 |
| `get_lib(name)` | 获取库详情和代码 | `get_lib("libnet")` |
| `list_modules()` | 列出所有模块型号 | 5 个模块 |
| `list_demos(module)` | 列出模块 Demo | `list_demos("Air780EPM")` |
| `get_demo(module, demo_name)` | 获取 Demo 代码 | `get_demo("Air780EPM", "gpio")` |
| `search_code(query, scope)` | 智能搜索 | `search_code("MQTT", "all")` |
| `resolve_module(query)` | 识别模块型号 | `resolve_module("Air8000 GPIO")` |
| `server_stats()` | 服务器统计 | 索引状态、查询统计 |

### 📊 索引统计

- **扩展库**: 37 个 Lua 库（script/libs/）
- **模块型号**: 5 个（Air1601, Air780EHM, Air780EPM, Air8000, Air8101）
- **Demo 文件**: 2,257 个
- **索引块**: 10,952 个
  - 库代码块: 1,151
  - Demo 代码块: 9,801

### 🔌 客户端配置示例

#### Claude Desktop
```json
{
  "mcpServers": {
    "luatos-code": {
      "command": "python",
      "args": ["/opt/sda2/LuatOS/mcp/mcp_server.py", "--transport", "stdio"],
      "env": {"LUATOS_CODE_ROOT": "/opt/sda2/LuatOS"}
    }
  }
}
```

#### Cline / Continue (SSE)
```json
{
  "mcpServers": {
    "luatos-code": {
      "url": "http://127.0.0.1:8100/sse"
    }
  }
}
```

### 🔍 使用示例

AI 工具现在可以询问：

1. **"LuatOS 有哪些网络库？"** → `list_libs()` → 显示 libnet, httpplus 等
2. **"给我 libnet 的详细文档"** → `get_lib("libnet")` → 完整 API 文档和代码
3. **"Air780EPM 有哪些 GPIO demo？"** → `list_demos("Air780EPM")` → 列出所有 GPIO 相关 demo
4. **"搜索 MQTT 相关代码"** → `search_code("MQTT", "all")` → 跨库和 demo 搜索

### 🧪 测试

```bash
cd /opt/sda2/LuatOS/mcp
source /opt/sda2/luatos-docs-v2/.venv/bin/activate
python test_server.py
```

预期输出: 所有测试通过 ✓

### 📝 技术特性

- ✅ **双模式**: stdio (本地) + SSE (远程，端口 8100)
- ✅ **混合搜索**: 关键词 + 向量语义搜索 (ChromaDB)
- ✅ **Lua 文档解析**: 自动提取 `@module`, `@api`, `@param` 注释
- ✅ **实时更新**: mtime 检测，自动重建索引
- ✅ **模块识别**: 自动识别 air780epm, air8000 等型号
- ✅ **容错处理**: ChromaDB 可选，降级到纯关键词搜索

### 🐛 故障排查

```bash
# 测试依赖
source /opt/sda2/luatos-docs-v2/.venv/bin/activate
python -c "import mcp, chromadb; print('OK')"

# 测试服务器启动
timeout 3 python mcp_server.py --transport sse --port 8100

# 查看索引统计
python -c "from mcp_server import _build_index; print(len(_build_index('/opt/sda2/LuatOS')[0]), 'chunks')"
```

---

**状态**: ✅ 全部完成，已测试，可投入使用
