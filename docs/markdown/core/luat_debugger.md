# Luat调试器

## 基本信息

* 起草日期: 2021-01-02
* 设计人员: [wendal](https://github.com/wendal)

本文档描述 LuatOS 调试器相关的信息, 主要用于lua脚本的单步调试

## 术语表

* DAP - debug-adapter-protocol 微软主导的一个调试适配协议, 主要用于vscode
* Debugger - 调试器,本文内基本等同于Lua脚本调试器, 执行单步调试,上下变量查看与设置,堆栈查询等等

## 通信流程

### 设计的软硬件实体

* 模块, 具体执行LuatOS和脚本
* 串口/USB/UART, 模块与调试器的通信方式
* LuaTools, 代理调试器与模块之间的通信形式
* 调试器, 跑在vscode内的独立程序
* VSCODE, 执行调试器,与其进行通信, 展示调试界面

### 相互间的通信联系

1. 模块 <--> 串口/USB. 模块的对外通信渠道, 与windows/linux/macos下的进程调试不一样. 但依然可以抽象为 Input/Output
2. 串口/USB <--> LuaTools. LuaTools负责解析模块的输出数据,分离出里面的调试数据, 发送到调试器, 并接收调试器的命令, 转换为模块能识别的格式,写入串口/USB.
3. LuaTools <--> 调试器. 两者通信的渠道是Socket或IPC,通常是socket, 使用的协议为LuatOS 调试器协议
4. 调试器 <--> vscode. 两者通信的渠道到标准输入输出,格式是DAP.

整体展示

```
模块 <--USB--> LuaTools <--Socket--> 调试器 <--标准输入输出--> vscode
```

补充说明

* 从简化通信的方式看, 调试器也能通过串口/USB与模块进行通信, 无需LuaTools.
* 鉴于适配器读取串口的实现难度,及rda8910会走的AP日志通道, 选择LuaTools是比较合理的方式
* 远期来看, 调试器与设备直接通信是最佳体验.
* LuaTools的具体行为等价于协议代理, 屏蔽不同硬件设备接口通信方式的差异, 模块与调试器之间, 走的是LuatOS 调试协议.

## LuatOS 调试协议

当前协议版本 v1

### 基本通信方式(输出)

协议的输出, 以 `[head] exts` 形式,按行进行输出

其中:
* `[head]` 的 head, 为英文逗号分隔的字符串,仅为英文字母或数字
*  `exts` 为字符串, 按`head` 的不同, 含义会有差异

### 基本通信方式(输入)

协议的输入, 以 `cmd arg1 arg2 ...` 形式,按行进行输入, 一般为命令

其中:
* `cmd` 是命令
*  `arg1 arg2` 为不同的字符串参数

#### 状态变更输出(state,changed)

`[state,changed,1,2]`

调试状态变化, 前者为原状态, 后者为更新后的状态

* 0  调试模式关闭,程序在运行
* 1  等待调试器连接,程序在等待
* 2  程序在运行,直至遇到断点
* 3  程序已暂停,通常附带一个event事件,例如`[event,stopped,break]`
* 4  程序在运行,正在执行`next`或者`step`操作, 下一状态通常为 3
* 5  程序在运行,正在执行`stepIn`操作, 下一状态通常为 3
* 6  程序在运行,正在执行`stepOut`操作, 下一状态通常为 3

#### 等待调试器(event,waitc)

`[event,waitc]`

通常,在lua脚本内加入 `dbg.wait(300)` 语句后, luatos就会停在该语句,等待调试器的命令

#### 等待调试器(event,waitt)

`[event,waitt]`

等待指定秒数后,依然没有收到`start`命令, 自动退出等待, 状态恢复到0, 调试模式关闭

#### 程序已暂停(event,stopped)

`[event,stopped,break]`
`[event,stopped,step]`
`[event,stopped,stepIn]`
`[event,stopped,stepOut]`

遇到断点,或者执行调试指令后(`step/stepIn/stepOut`)后,遇到符合条件的情况,触发暂停

与此同时, `[state,changed,X,3]` 应该会一起到来

#### 响应类

TODO resp类及可执行的命令参数


