# 1 随机数(random)

## 一、功能模块介绍

### 1.1 核心主程序模块

`main.lua` 是整个 demo 的入口文件，负责定义项目名和版本号、加载业务模块，最后调用 `sys.run()` 启动 LuatOS 运行框架。

### 1.2 业务功能模块

`random_app.lua` 是随机数应用功能模块，核心业务逻辑为：使用 `math.randomseed` 设置随机数种子后，循环输出 `crypto.trng` 生成的真随机数和 `math.random` 生成的伪随机数。

### 1.3 核心库说明

crypto库：[https://docs.openluat.com/osapi/core/crypto/](https://docs.openluat.com/osapi/core/crypto/)

math库（Lua标准库）：`math.random` 和 `math.randomseed` 是 Lua 标准库自带函数，无需额外引入，直接使用即可。

## 二、演示流程介绍

1. 系统启动后，`main.lua` 加载 `random_app` 模块

2. `random_app.lua` 创建一个 task 协程

3. task 协程等待系统稳定后，使用系统时间设置随机数种子

4. 循环 10 次输出真随机数和伪随机数，每次间隔 100ms

5. 循环结束后打印 `ALL Done`，演示完毕

## 三、演示硬件环境

### 3.1 硬件清单

|序号|硬件名称|数量|说明|
|---|---|---|---|
|1|Air724UG 核心板|1 块|合宙 Air724UG 核心板|
|2|TYPE-C USB 数据线|1 根|用于供电和通信|

### 3.2 接线配置

![Air724UG核心板](https://docs.openluat.com/air724_soc/luatos/common/hwenv/image/724-C.png)

Air724UG 核心板通过 TYPE-C USB 口连接 TYPE-C USB 数据线，数据线的另外一端连接电脑的 USB 口；

Air724UG 核心板通过 TYPE-C USB 口供电；

Air724UG 核心板购买链接：[合宙官方淘宝店铺](https://luat.taobao.com/)

## 四、演示软件环境

### 4.1 开发工具

烧录工具：[Luatools 下载调试工具](https://docs.openluat.com/air724/common/Luatools/)

### 4.2 内核固件

本 demo 开发测试时使用的固件为 [Air724 LuatOS 固件](https://docs.openluat.com/air724_soc/luatos/firmware/version/)，本 demo 对固件版本没有什么特殊要求，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用开发本 demo 时使用的内核固件版本来对比测试。

### 4.3 脚本文件

脚本文件目录：[https://gitee.com/openLuat/LuatOS/tree/master/module/Air724/demo/random](https://gitee.com/openLuat/LuatOS/tree/master/module/Air724/demo/random)

lib 脚本文件：使用 Luatools 烧录时，勾选「添加默认 lib」选项，使用默认 lib 脚本文件。

## 五、演示核心步骤

### 5.1 硬件准备

1. 准备一块 Air724UG 核心板

2. 准备一根 TYPE-C USB 数据线

3. 将核心板通过 USB 数据线连接到电脑

### 5.2 软件配置

1. 下载并安装 Luatools 烧录工具

2. 下载 Air724 最新版本的 LuatOS 内核固件

3. 准备本 demo 的脚本文件（main.lua、random_app.lua）

### 5.3 软件烧录

参考 [如何烧录项目文件到 Air724UG 核心板](https://docs.openluat.com/air724_soc/luatos/common/download/)，将本 demo 的项目文件烧录到 Air724UG 核心板中。

### 5.4 功能测试

1. 烧录完成后，按下核心板的复位按键（或重新插拔 USB）

2. 打开 Luatools，查看串口日志输出

### 5.5 预期效果（含实测日志）

出现类似于下面的日志，就表示运行成功：

```
[2026-08-19 10:15:32.156][000000000.246] I/user.main        random_demo        001.999.000
[2026-08-19 10:15:33.248][000000001.276] I/user.random_app        ===== [1/1] 随机数测试 =====
[2026-08-19 10:15:33.358][000000001.386] I/user.crypto        真随机数        -2126957010        5
[2026-08-19 10:15:33.369][000000001.388] I/user.crypto        伪随机数        0.4636298
[2026-08-19 10:15:33.373][000000001.389] I/user.crypto        伪随机数        50
[2026-08-19 10:15:33.375][000000001.390] I/user.crypto        伪随机数        46998
[2026-08-19 10:15:34.358][000000001.486] I/user.crypto        真随机数        -309051301        5
[2026-08-19 10:15:34.369][000000001.488] I/user.crypto        伪随机数        0.6394390
[2026-08-19 10:15:34.373][000000001.489] I/user.crypto        伪随机数        10
[2026-08-19 10:15:34.375][000000001.490] I/user.crypto        伪随机数        38883
...
[2026-08-19 10:15:42.107][000000002.385] I/user.crypto        ALL Done
[2026-08-19 10:15:42.108][000000002.386] I/user.random_app        ===== [演示完毕] =====
```

日志中的真随机数和伪随机数每次运行都会不同，这是随机数的正常特性；其中真随机数后面的数字 5 是 `string.unpack` 函数返回的下一个读取位置，无需关注。

### 5.6 故障排除

|故障现象|可能原因|解决方法|
|---|---|---|
|无日志输出|串口驱动未安装或串口选择错误|安装 Air724UG USB 驱动，在 Luatools 中选择正确的串口|
|日志中出现报错信息|固件版本过低或脚本加载失败|烧录最新版本内核固件，检查脚本文件是否完整|
|中文乱码|串口波特率或编码设置错误|Luatools 中检查串口波特率设置，建议使用默认配置|
|伪随机数每次运行都一样|未设置随机数种子或种子变化太小|使用 `math.randomseed(os.time())` 设置随机数种子|

### 5.7 扩展功能建议

1. 可以使用 `crypto.trng` 生成随机字节串，用于设备配网、数据加密等安全场景

2. 可以使用 `math.random` 生成随机延时，避免多设备同时上报造成服务器拥塞

3. 可以使用随机数实现简单的验证码、抽奖等应用逻辑

## 六、总结

通过本 demo 学习，你可以掌握真随机数（`crypto.trng`）、伪随机数（`math.random`）和随机数种子（`math.randomseed`）的使用方法，为后续学习更加复杂的业务逻辑打下基础。
