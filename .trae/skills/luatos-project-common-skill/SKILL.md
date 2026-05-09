---
name: luatos-project-common-skill
description: "LuatOS项目开发公共逻辑：新建/修改LuatOS项目时调用。提供MCP服务器检查、demo分析、代码解耦设计、require验证、文件名规范等通用能力，被new-project和update-project技能引用。"
---

# LuatOS项目开发公共技能

## 概述

本技能提供LuatOS项目开发中的通用逻辑，被以下技能引用：
- luatos-new-project-skill（新建项目）
- luatos-update-project-skill（修改项目）

**注意：** 本技能不单独使用，而是作为公共模块被其他技能调用。

## 公共流程

### 公共流程1：MCP服务器状态检查 ⚠️ 强制

```
1. 尝试调用 mcp_luatos-code_server_stats 检查 luatos-code 服务器状态
2. 尝试调用 mcp_luatos-docs_search_docs (任意查询) 检查 luatos-docs 服务器状态
3. IF 任一服务器无响应 THEN
       输出：MCP服务器连接异常
       使用 AskUserQuestion 询问用户：是否已手动重启 MCP 开关（设置->MCP->找到luatos-docs和luatos-code右方的开关，点击关闭再打开）？
       IF 用户确认已重启 THEN
           再次尝试步骤1-2
           IF 仍然失败 THEN
               输出：MCP服务器仍无法连接，请尝试重启Trae IDE
               RETURN false
           END
       ELSE
           输出：请先重启MCP开关后再继续
           RETURN false
       END
   END
4. RETURN true  // 返回成功状态
```

### 公共流程2：确定参考Demo范围

| 功能类型 | 推荐核心库 | 推荐扩展库 | 参考Demo |
|----------|------------|------------|----------|
| UI设计 | airui | exwin | airui相关demo |
| 网络驱动 | - | exnetif | netdrv_device.lua相关demo |
| 其他功能 | - | - | 按需求匹配 |

### 公共流程3：分析相关Demo

```
1. 调用 mcp_luatos-code_list_demos(module=<产品型号>) 获取该型号所有demo
2. 调用 mcp_luatos-code_search_code(query=<功能关键字>, scope="demos", top_k=10) 搜索相关demo
3. 分析demo时优先参考与需求最接近的demo（如mqtt需求→文件名含mqtt的demo）
4. 理解demo的：代码结构、注释规范、命名规范、解耦设计
```

### 公共流程4：解耦化设计规范 ⚠️ 强制

**功能模块创建规则（强制）：**
- 所有功能逻辑都必须创建独立的功能模块
- main.lua中只负责require功能模块，不包含任何功能代码
- 即使是简单的功能（如定时打印），也应该创建独立模块

**main.lua代码规范（强制）：**
- main.lua中不允许包含功能代码
- 只允许require语句和sys.run()
- 所有功能逻辑通过require加载的功能模块实现

**模块通信方式（强制）：**
- sys.publish() / sys.subscribe() - 发布/订阅模式
- sys.sendMsg() / sys.waitMsg() - 消息队列模式

**文件命名规则（强制）：**
| 规则 | 说明 |
|------|------|
| 优先复用 | 能复用demo中的文件名则复用，不修改 |
| 避免重名 | 不与Lua标准库、LuatOS核心库、扩展库重名 |
| 长度限制 | 完整文件名长度 ≤ 23字节 |
| 无目录路径 | require时不含目录路径，如 `require "http_app"` |

**代码复用规则（强制）：**
| 规则 | 说明 |
|------|------|
| 直接复用 | demo中有的代码直接复用，不修改 |
| 不删除 | 有现成的可以用就不删除或组合 |
| 不require核心库 | 核心库API直接使用，无需require |
| 优先扩展库 | 优先使用扩展库API |

**代码结构规则（强制）：**
| 规则 | 说明 |
|------|------|
| 模块化 | 功能模块之间必须解耦 |
| 详细注释 | 符合LuatOS代码规范，参考demo注释格式 |
| 禁止匿名函数 | 除main.lua外，其他文件不允许使用匿名函数 |
| return语句 | 无外部接口的lua文件，末尾不需要return {} |

**return语句判断规则（强制）：**
```
IF 模块有非local的函数/变量需要外部访问 THEN
    return {暴露的函数/变量}
ELSE
    不需要return语句
END
```

**有外部接口的模块示例：**
```lua
local mymodule = {}

function mymodule.func1() end
function mymodule.func2() end

return mymodule  -- 需要return
```

**无外部接口的模块示例：**
```lua
local function internal_func() end
sys.timerLoopStart(internal_func, 1000)
-- 不需要return
```

**资源文件路径规范（强制，烧录场景、模拟器场景）：**
| 规范 | 说明 |
|------|------|
| 路径格式 | 使用 `/luadb/*.*` 格式，其中 `*.*` 表示具体文件名 |
| 资源目录 | 烧录的资源文件放置在 `luadb` 目录下，代码中引用时使用完整路径 |
| 常见资源 | 图片(.png/.jpg)、字体(.bin)、音频(.mp3/.wav)、配置文件(.json)等 |

正确的资源文件路径API用法：
```lua
-- 设置字体文件
lcd.setFontFile("/luadb/customer_font_22.bin")

-- 使用airui库显示图片（通过airui.image组件）
local img = airui.image({src = "/luadb/logo.jpg", x = 100, y = 100})
```

### 公共流程5：Require验证

```
FOR EACH require语句 IN 生成的代码 DO
    1. 调用 mcp_luatos-docs_search_docs 查询该模块是否为核心库
    2. 调用 mcp_luatos-code_list_libs 查询该模块是否为扩展库

    IF 模块属于 Lua标准库 OR LuatOS核心库 THEN
        删除该require语句  // 这两类库不需要require
    ELSIF 模块属于 LuatOS扩展库 THEN
        保留require语句
    ELSE
        确保文件已创建  // 自定义模块必须创建文件
    END
END
```

### 公共流程6：API正确性验证

```
1. 调用 mcp_luatos-docs_search_docs(query="<API函数名>", module=<产品型号>) 验证API存在
2. 检查参数个数、参数类型、返回值是否与文档一致
3. 检查参数时，注意文档描述的可选参数，如果实际使用时，此可选参数后面还有其他参数，则可选参数必须设置
4. 若API调用不正确，修正代码
```

### 公共流程6.1：资源文件路径验证 ⚠️ 必须

**判断依据：** 当代码中需要使用自带的图片、字体、音频等资源文件时

**验证步骤：**
```
FOR EACH 资源文件引用 IN 生成的代码 DO
    1. 检查路径是否以 "/luadb/" 开头（烧录和模拟器使用自带的资源文件的场景）
    2. 检查文件扩展名是否为支持的类型（.png/.jpg/.bin/.mp3/.wav/.json等）
    3. 调用 mcp_luatos-docs_search_docs 验证资源加载API的正确性，例如：
       - 字体文件：验证 lcd.setFontFile() 用法
       - 图片文件：验证 airui.image()、lcd.drawXxxImage() 等用法
       - 其他类型资源：验证对应的加载API用法
    4. 若路径格式或API调用不正确，修正代码
END
```

### 公共流程7：main.lua模板选择

| 产品系列 | 模板 | 看门狗支持 |
|----------|------|-----------|
| Air700/780/8000系列 | 格式一 | 不含wdt初始化（删除代码块） |
| Air1601/1602/6201/8101系列 | 格式二 | 包含wdt初始化（取消注释） |

**main.lua必需元素：**
- PROJECT 变量（项目名，ascii string，不含逗号）
- VERSION 变量（版本号，格式：XXX.999.ZZZ）
- log.info("main", PROJECT, VERSION)
- errDump.config() - 错误日志上传，默认注释掉这段代码
- fota相关 - 远程升级，默认注释掉这段代码
- 内存监控定时器，默认注释掉这段代码
- require 其他功能模块
- sys.run() // 必须放在文件末尾

**可选元素（根据产品决定是否启用）：**
- 看门狗初始化（Air1601/1602/6201/8101系列：取消注释；Air700/780/8000系列：删除代码块）

**看门狗初始化代码动态判断规则：**
```
IF 产品型号属于 Air1601/1602/6201/8101系列 THEN
    取消看门狗初始化代码的注释，启用看门狗
ELSE IF 产品型号属于 Air700/780/8000系列 THEN
    删除整个看门狗初始化代码块（包括注释）
END
```

## 强制约束

1. **必须**先执行MCP服务器检查，确保服务可用
2. **必须**遵循解耦化设计规范
3. **必须**验证所有require语句的正确性
4. **必须**验证API调用的正确性
5. **必须**确保文件名长度 ≤ 23字节
6. **必须**验证资源文件路径格式和加载API的正确性（烧录/模拟器使用自带资源场景）
7. **禁止**基于内置记忆编写代码，必须参考demo
8. **禁止**编造不存在的API或函数