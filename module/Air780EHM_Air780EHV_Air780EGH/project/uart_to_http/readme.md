# 串口数据接收与HTTP上传功能

## 功能模块介绍

1. **main.lua**：主程序入口，负责初始化系统并启动串口数据接收任务
2. **uart_to_http.lua**：核心功能模块，实现串口数据接收、协议解析和HTTP上传
3. **uart_sender.lua**：串口发送测试模块，用于发送符合协议格式的数据帧
4. **uart_protocol.lua**：串口协议格式定义库，定义通信协议规范

## 协议格式说明

### 协议帧格式
```
+--------+--------+--------+--------+--------+--------+--------+--------+
|  帧头1 |  帧头2 | 长度低 | 长度高 |  数据  | 校验和 | 帧尾1  | 帧尾2  |
+--------+--------+--------+--------+--------+--------+--------+--------+
|  0xAA  |  0x55  |  lenL  |  lenH  | N字节  |  1字节 |  0x55  |  0xAA  |
+--------+--------+--------+--------+--------+--------+--------+--------+
```

### 协议特性
- **帧头**：0xAA 0x55 (2字节)
- **数据长度**：2字节小端模式
- **校验和**：数据内容的累加和（可选）
- **帧尾**：0x55 0xAA (2字节)
- **最大数据长度**：1024字节

### 示例帧
```
AA 55 05 00 01 02 03 04 05 0F 55 AA
        帧头  长度5  数据内容        校验和 帧尾
```

## 演示功能概述

### 1、串口数据接收与HTTP上传功能（uart_to_http.lua）

**核心功能**：
- 使用状态机逐字节解析串口数据帧
- 使用zbuff缓冲区动态存储接收到的数据
- 支持大文件分帧接收和缓冲区自动扩展
- 通过httpplus库将接收到的数据上传到服务器
- 支持网络重连和上传重试机制

**工作流程**：
1. 初始化串口和接收缓冲区
2. 等待串口数据接收
3. 使用状态机解析协议帧
4. 将数据存储到zbuff缓冲区
5. 检测到最后一帧（小于512字节）时触发上传
6. 将缓冲区数据保存为临时文件并上传
7. 上传完成后清理缓冲区

### 2、串口发送测试功能（uart_sender.lua）

**核心功能**：
- 发送符合协议格式的数据帧
- 支持文本数据和文件数据发送
- 自动计算校验和并封装协议帧
- 支持大文件分帧传输（512字节/帧）

### 3、协议定义库（uart_protocol.lua）

**核心功能**：
- 定义串口通信协议格式规范
- 提供协议解析工具函数
- 支持校验和计算与验证
- 配置协议参数和限制

## 演示硬件环境

![](https://docs.openluat.com/air780ehv/luatos/common/hwenv/image/Air780EHV.png)

1、两块Air780EHM/Air780EHV/Air780EGH核心板

2、Air780EHM/Air780EHV/Air780EGH核心板和数据线的硬件接线方式为

- Air780EHM/Air780EHV/Air780EGH核心板通过TYPE-C USB口供电；

- 如果测试发现软件频繁重启，重启原因值为：poweron reason 0，可能是供电不足，此时再通过直流稳压电源对核心板的vbat管脚进行4V供电，或者5V管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、Luatools下载调试工具

2、固件获取地址：

[Air780EHM 固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

[Air780EHV 固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

[Air780EGH 固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)

## 演示核心步骤

### 1、串口数据接收与上传功能测试

1. **搭建硬件环境**

   a. 准备一块Air780EHM/Air780EHV/Air780EGH核心板/开发板作为接收端
   b. 准备另一块核心板/开发板或串口调试工具作为发送端
   c. 确保接收端核心板能够连接到互联网

2. **配置接收端（uart_to_http模块）**

   a. 确保`main.lua`中已启用接收模块，禁用发送模块：

   ```lua
   -- 加载串口数据接收与HTTP上传模块
   require "uart_to_http"

   -- 加载串口发送测试模块
   -- require "uart_sender"
   ```

   b. 将代码烧录到接收端核心板或开发板

3. **配置发送端**

   a. 如果使用另一块核心板/开发板作为发送端：

      - 确保`main.lua`中启用发送模块，禁用接收模块：

      ```lua
      -- 加载串口数据接收与HTTP上传模块
      -- require "uart_to_http"

      -- 加载串口发送测试模块
      require "uart_sender"
      ```

   b. 将代码烧录到发送端核心板或开发板

4. **启动测试**

   a. 启动接收端核心板/开发板，等待串口初始化完成
   b. 启动发送端或串口调试工具，发送测试数据

## 查看测试结果

测试启动后，可以通过Luatools工具查看测试日志。接收端将显示数据接收和上传的详细过程，发送端将显示发送进度和状态。

**接收端运行结果示例**：

```lua
# 模块初始化
I/user.uart_to_http 模块初始化开始
I/user.uart_to_http 缓冲区大小: 2048
I/user.uart_to_http 初始化串口
Uart_ChangeBR 1461:uart1, 115200 115203 26000000 3611
I/user.uart_to_http 串口初始化完成
I/user.uart_to_http 模块初始化完成
I/user.uart_to_http 等待串口数据...
I/mobile sim0 sms ready
D/mobile cid1, state0
D/mobile bearer act 0, result 0
D/mobile NETIF_LINK_ON -> IP_READY

# 接收到数据帧
I/user.uart_to_http 收到帧, 数据长度: 512
I/zbuff create large size: 64 kbyte, trigger force GC
I/user.uart_to_http 开始接收文件数据
I/user.uart_to_http 文件接收中: 512 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 1024 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 1536 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 2048 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 2560 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 3072 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 3584 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 4096 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 4608 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 5120 字节
I/user.uart_to_http 收到帧, 数据长度: 512
...

# 接收完成并上传
...
I/user.uart_to_http 文件接收中: 10240 字节
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 收到帧, 数据长度: 512
I/user.uart_to_http 文件接收中: 10752 字节
I/user.uart_to_http 收到帧, 数据长度: 327
I/user.uart_to_http 文件接收中: 11079 字节
I/user.uart_to_http 文件接收完成，总大小: 11079
I/user.uart_to_http 准备上传文件，大小: 11079
I/user.uart_to_http 开始上传，大小: 11079 重试: 0
I/user.[excloud]开始文件上传 类型: 1 文件: /temp_upload.jpg 大小: 11079
I/user.[excloud]开始文件上传 类型: 1 文件: uart_image_1775015373.jpg 大小: 11079
I/user.[excloud]构建发送数据 23 0 0 
I/user.[excloud]构建发送数据 784 0 1 
I/user.[excloud]构建发送数据 785 3 uart_image_1775015373.jpg 
I/user.[excloud]构建发送数据 786 0 11079 
I/user.[excloud]tlv发送数据长度4 53
I/user.[excloud]构建消息头 " 
I/user.uart_to_http excloud收到数据: send_result
I/user.[excloud]数据发送成功 69 字节
I/user.[excloud]开始发送HTTP请求 URL: https://gps.openluat.com/aircloud/air_up/image
I/user.[excloud]socket cb userdata: 0C7DA780 33554450 0
I/user.[excloud]socket 发送完成
I/http http close c12507c
I/user.[excloud]excloud.getip文件上传响应 HTTP Code: 200 Body: {"info":"aircloud./aircloud/air_up/image","code":0,"trace":"code:aircloud./aircloud/air_up/image,  trcace:","log":"^^^","value":{"uri":"/vsa/aircloud_image/7yAT2Rt9miFaTaZxPi8VvY/2026-04/862288081583054/20260401114936_temp_upload.jpg","size":"10.00KB","thumb":"/vsa/aircloud_image/7yAT2Rt9miFaTaZxPi8VvY/2026-04/862288081583054/20260401114936_temp_uploadt.jpg"}}
I/user.[excloud]文件上传成功 URL: /vsa/aircloud_image/7yAT2Rt9miFaTaZxPi8VvY/2026-04/862288081583054/20260401114936_temp_upload.jpg
I/user.[excloud]构建发送数据 24 0 0 
I/user.[excloud]构建发送数据 784 0 1 
I/user.[excloud]构建发送数据 785 3 uart_image_1775015373.jpg 
I/user.[excloud]构建发送数据 787 0 0 
I/user.[excloud]tlv发送数据长度4 53
I/user.uart_to_http excloud收到数据: send_result
I/user.[excloud]数据发送成功 69 字节
I/user.uart_to_http 文件上传成功!
I/user.uart_to_http 累计上传: 1 个文件
I/user.uart_to_http 上传文件名: uart_image_1775015373.jpg
network_default_socket_callback 1123:before process socket 1,event:0xf2000004(发送成功),state:5(在线),wait:3(等待发送完成)
network_default_socket_callback 1127:after process socket 1,state:5(在线),wait:0(无等待)
I/user.[excloud]socket cb userdata: 0C7DA780 33554450 0
I/user.[excloud]socket 发送完成
```
