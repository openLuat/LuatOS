# 1 模组信息(hmeta)

## 一、功能模块介绍

### 1.1 核心主程序模块

`main.lua` 是整个 demo 的入口文件，负责定义项目名和版本号、加载业务模块，最后调用 `sys.run()` 启动 LuatOS 运行框架。

### 1.2 业务功能模块

`hmeta_app.lua` 是 hmeta 应用功能模块，核心业务逻辑为：创建一个 task 协程，依次获取模组名称、硬件版本号、芯片型号、模组 muid 和识别 id，并循环打印日志。

### 1.3 核心库说明

hmeta 库：[https://docs.openluat.com/osapi/core/hmeta/](https://docs.openluat.com/osapi/core/hmeta/)

## 二、演示流程介绍

1. 系统启动后，`main.lua` 加载 `hmeta_app` 模块

2. `hmeta_app.lua` 创建一个 task 协程

3. task 协程依次执行 [1/5]~[5/5] 分步演示：获取模组名称 → 硬件版本号 → 芯片型号 → muid → 识别 id

4. 分步演示完毕后进入循环，每隔 3 秒获取一次模组信息并打印日志

## 三、演示硬件环境

### 3.1 硬件清单

|序号|硬件名称|数量|说明|
|---|---|---|---|
|1|Air724UG 核心板|1 块|合宙 Air724UG 核心板|
|2|TYPE-C USB 数据线|1 根|用于供电和烧录调试|

### 3.2 接线配置

Air724UG 核心板通过 TYPE-C USB 口连接 TYPE-C USB 数据线，数据线的另外一端连接电脑的 USB 口；核心板通过 USB 口供电，同时用于烧录固件和查看日志。

## 四、演示软件环境

1、烧录工具：[Luatools 下载调试工具](https://docs.openluat.com/common/Luatools/)

2、内核固件：[Air724UG LuatOS固件](https://docs.openluat.com/air724_soc/luatos/firmware/version/)

3、扩展库脚本文件：使用 Luatools 烧录时，勾选 添加默认扩展库 选项，使用默认扩展库脚本文件

## 五、核心步骤

1、搭建好硬件环境，将 Air724UG 核心板通过 TYPE-C USB 数据线连接到电脑

2、打开 Luatools，烧录内核固件和 demo 脚本代码到 Air724UG 核心板

3、烧录成功后，模组自动开机运行 demo 脚本

4、查看 Luatools 串口日志输出

## 六、运行结果展示

出现类似于下面的日志，就表示运行成功：

```
I/user.hmeta_app	===== [1/5] 获取模组名称 =====
I/user.hmeta	Air724UG
I/user.hmeta_app	===== [2/5] 获取模组硬件版本号 =====
I/user.hmeta	A11
I/user.hmeta_app	===== [3/5] 获取原始芯片型号 =====
I/user.hmeta	8910
I/user.hmeta_app	===== [4/5] 获取模组muid =====
I/user.hmeta	20250724040624A234339A8164909044
I/user.hmeta_app	===== [5/5] 获取模组识别id =====
I/user.hmeta	866965083774767
I/user.hmeta_app	===== [演示完毕] =====
I/user.hmeta	Air724UG	A11	8910
I/user.hmeta	muid:	20250724040624A234339A8164909044
I/user.hmeta	devid:	866965083774767
```
