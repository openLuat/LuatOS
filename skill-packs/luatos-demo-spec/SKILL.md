---
name: luatos-demo-spec
description: LuatOS Demo 代码与文档设计规范。编写/审查 demo 代码、readme 时必须遵循：文件结构、命名规范（常量/变量/函数）、注释格式、禁止闭包和匿名函数。
---

# LuatOS Demo 代码与文档设计规范

编写 LuatOS demo 代码、readme 文档时必须严格遵循本规范。

---

## 一、Demo 文件划分

每个 demo 目录包含：

### readme.md（必选）
- Markdown 格式的使用说明文档
- 是 docs 在线文档的核心提炼版本
- 用户阅读后可清楚了解业务逻辑和操作步骤

### main.lua（必选）
- Demo 入口文件
- 除 require 业务模块外，其余规范保持一致

### pins_AirXXX.json（可选）
- 用到 GPIO 复用引脚功能时必须包含
- LuatIO 工具自动生成，无需手动修改

### 业务逻辑 Lua 文件（至少一个）
- 至少一个；可拆分时进一步拆分为多个低耦合模块
- 例如 WiFi 配网和 HTTP GET 拆为两个文件

---

## 二、业务逻辑与文件名设计

1. 先学习已有 demo（`luat/demo/`、`module/`、`docs.openluat.com/osapi/`）
2. 尽可能覆盖所有相关 API（如 i2c 含硬/软、开/关）
3. 模块化，低耦合
4. 文件名自描述——"通过文件名就知道功能"

---

## 三、常量命名

```lua
local UART_ID = 2
```
- 全部大写 + 下划线（与 C 一致）
- local 修饰
- 名称与意义匹配

---

## 四、变量命名

```lua
local loop_index = 1
```
- **小写字母 + 下划线**（与 LuatOS API 一致）
- local 修饰
- 名称与意义匹配

---

## 五、函数命名

### 命名法
**小写字母 + 下划线**

### 外部函数（可被其他文件调用）
```lua
local tcp_client_sender = {}

function tcp_client_sender.proc(task_name, socket_client)
end

return tcp_client_sender
```
- 不用 local 修饰
- 函数名前用模块表修饰

### 内部函数（仅本文件调用）
```lua
local function send_data_req_timer_loop_func()
end
```
- 必须用 local 修饰

### 命名后缀建议（非强制）
- task 主函数: `..._task_func`
- 定时器回调: `..._timer_cbfunc`
- 消息处理: `..._msg_proc_func`

---

## 六、注释规范

### 总体要求
- 注释必须详细，所有点都写清楚
- 目的：有 Lua 基础但首次接触 LuatOS 的用户不查 API 就能看懂

### 文件头注释（每个 Lua 文件必须有）

```lua
--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本demo演示的核心功能为：
1、创建四路socket连接...
2、每一路socket连接出现异常后，自动重连...
...
更多说明参考本目录下的readme.md文件
]]
```

**@author 必须用中文姓名**，不用英文、拼音或缩写。

### 外部函数注释（@api 格式）

```lua
--[[
配置GPIO管脚功能；支持输出、输入和中断三种模式；

@api AirGPIO_1000.setup(gpio_id, gpio_mode)

@number
gpio_id
GPIO ID；取值范围：0x00~0x07, 0x10~0x17；必须传入，不允许为空

@number or function or nil
gpio_mode
number时：输出模式，0=低电平，1=高电平
nil时：输入模式
function时：中断模式（回调函数）

@return bool
成功返回true，失败返回false

@usage
AirGPIO_1000.setup(0x00, 0)  -- 输出模式，默认低电平
AirGPIO_1000.setup(0x11)      -- 输入模式
]]
```

### 内部函数注释
描述清楚功能、输入参数、返回值即可。

### 行内注释
- 写在代码上方（推荐）或右方，风格统一
- 注释多时写上方，可随意分行

```lua
--连接WIFI热点，连接结果通过"IP_READY"或"IP_LOSE"消息通知
--Air8101仅支持2.4G WIFI，不支持5G
--第三个参数1表示异常时内核自动重连
wlan.connect("热点名", "密码", 1)
```

---

## 七、禁止使用的技巧

### 禁止闭包
- 历史原因必须返回闭包的 API 除外
- 其他情况一律禁止

### 禁止匿名函数
- 所有函数必须显式定义，然后按函数名调用

### 禁止单目录多功能
- 一个 demo 目录尽量演示单一功能
- 如以太网 LAN 和 WAN 分为 `ethernet_wan` 和 `ethernet_lan`

### 禁止命名过于简化
- 目录/文件名应让用户看出大致功能
- 如不用 `lan`，用 `ethernet_lan`

---

## 八、输出行为准则

1. 严格遵循命名规范（常量 UPPER_SNAKE、变量/函数 lower_snake）
2. 文件头注释必须有：@module, @summary, @version, @date, @author(中文), @usage
3. 外部函数用 @api 格式注释
4. 不使用闭包和匿名函数
5. 代码注释详细，新手友好
6. Demo 结构完整：readme.md + main.lua + 业务模块 + 可选 pins JSON
7. 业务逻辑模块化，多拆分，低耦合
8. 所有变量/常量用 local 修饰
