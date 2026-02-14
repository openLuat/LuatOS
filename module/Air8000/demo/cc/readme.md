# CC_DEMO 项目说明

## 项目概述

本项目是基于 Air8000 的语音通信演示demo，实现了两种语音通话应用场景（二选一）：基础通话功能和TTS循环播放与通话处理功能。

## 文件结构

- main.lua: 主程序入口，支持二选一演示模式
- audio_drv.lua: 管理音频设备初始化与控制
- cc_app.lua: 实现基础通话业务逻辑以及通话录音
- cc_tts_app.lua: 实现TTS循环播放与通话业务逻辑

## 功能模块说明

### 场景一：基础通话功能（默认启用）

1. **音频设备初始化与控制**：配置并管理ES8311音频编解码芯片和扬声器功放，包括I2C、I2S接口设置及音量控制。

2. **完整通话业务逻辑处理**：实现4种通话场景，包括呼入和呼出的各种情况处理。

   按照自己的通话需求启用对应的Lua文件，其余注释掉；

   - (1)呼入，主动挂断（响铃3次后自动拒接）；

   - (2)呼入，自动接听，接听消息识别打印，主动挂断，挂断消息识别打印；

   - (3)呼入，自动接听，接听消息识别打印，等待对方挂断，挂断消息识别打印；

   - (4)呼出，对方接通，接听消息识别打印，建立通话后一段时间，等待对方挂断，挂断消息识别打印；

3. **通话状态监控与日志记录**：实时记录通话状态变化及相关信息。

### 场景二：TTS循环播放与通话处理

1. **音频设备初始化与控制**：使用exaudio.setup统一配置ES8311音频编解码芯片和扬声器功放，包括I2C、I2S接口设置及音量控制。

2. **TTS循环播放功能**：
   - 循环播放"支付宝到账，1千万元"语音提示
   - 支持音量调节（默认设置为50）
   - 播放完成后自动重新播放

3. **来电自动接听功能**：
   - 来电响铃2声后自动接听
   - 通话过程中自动暂停TTS播放
   - 通话结束后自动恢复TTS播放
   - 来电时自动关闭音频输出，避免POP音

4. **通话录音功能**：所有通话均支持双向录音（上行+下行），实时记录通话数据。

## 演示硬件环境

1、Air8000开发板一块+喇叭

![alt text](https://docs.openLuat.com/cdn/image/Air8000%E5%BC%80%E5%8F%91%E6%9D%BF.jpg )

或者Air8000核心板+AirAUDIO_1010 音频配件板+喇叭

![alt text]( https://docs.openLuat.com/cdn/image/Air8000%E6%A0%B8%E5%BF%83%E6%9D%BF+1010.jpg)

Air8000核心板和AirAudio_1010 配件板的硬件接线方式为:

|  Air8000核心板   | AirAUDIO_1010配件板 |
| --------------- | -----------------   |
| 22/I2S_MCLK     | I2S_MCLK            |
| 18/I2S_BCK      | I2S_BCK             |
| 19/I2S_LRCK     | I2S_LRCK            |
| 20/I2S_DIN      | I2S_DIN             |
| 21/I2S_DOUT     | I2S_DOUT            |
| 80/I2C_SCL      | I2C_SCL             |
| 81/I2C_SDA      | I2C_SDA             |
| 82/GPIO17       | PA_EN               |
| 83/GPIO16       | 8311_EN             |
| VDD_EXT         | VCC                 |
| GND             | GND                 |

2、TYPE-C USB数据线一根

- Air780EHM核心板通过 TYPE-C USB 口供电；

- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、[Air8000 固件](https://docs.openluat.com/air8000/luatos/firmware/)，选择支持CC和TTS功能的固件。

3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/cc)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air8000核心板](https://docs.openluat.com/air8000/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air8000开发板/核心板中。

4、[合宙 LuatIO 工具(GPIO 复用初始化配置)使用说明](https://docs.openluat.com/air780epm/common/luatio/)

5、 lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 相关软件资料

1、cc库   https://docs.openluat.com/osapi/core/cc/

2、exaudio - 音频扩展库  https://docs.openluat.com/osapi/ext/exaudio/

3、CC_IND -- 通话状态变化
  "READY":通话准备完成，可以拨打电话或者呼入电话了
  "INCOMINGCALL"：有电话呼入
  "CONNECTED"：电话已经接通
  "DISCONNECTED"：电话被对方挂断
  "SPEECH_START"：通话开始
  "MAKE_CALL_OK"：拨打电话请求成功
  "MAKE_CALL_FAILED"：拨打电话请求失败
  "ANSWER_CALL_DONE"：接听电话请求完成
  "HANGUP_CALL_DONE"：挂断电话请求完成
  "PLAY"：开始有音频输出

## 演示核心步骤

1、搭建好硬件环境

2、搭配AirAUDIO_1010 音频板测试，需将AirAUDIO_1010 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

3、根据需求配置演示功能：

   - 编辑main.lua文件，选择需要演示的功能
   - 功能一（基础通话功能）：取消注释 `require "cc_app"`，注释掉 `require "cc_tts_app"`
   - 功能二（TTS循环播放与通话处理）：注释掉 `require "cc_app"`，取消注释 `require "cc_tts_app"`

4、功能一场景四需要修改测试号码：

   - 编辑cc_app.lua文件中的 `local TEST_PHONE_NUMBER = "10086"`，修改为自己测试时要拨打的电话号码

5、Luatools烧录内核固件和修改后的demo脚本代码

6、烧录成功后，自动开机运行

7、运行程序，观察日志输出了解系统状态

### 功能一：基础通话功能

#### 场景1 呼入立即挂断

当设备启动并初始化完成后，打印READY和电话系统初始化完成。

当有来电时，会打印INCOMINGCALL，并开始计数响铃次数。

响铃3次后，自动拒接来电，打印拒接来电和挂断完成。

类似以下日志：

``` lua
I/user.cc_app 通话业务逻辑模块加载完成，当前场景: 1
I/user.exaudio_device 使用exaudio.setup初始化音频设备
I/user.exaudio_device exaudio.setup初始化成功
I/user.CC状态 READY
I/user.exaudio_device 通话录音已启用
I/user.cc_app 电话系统初始化完成
I/user.CC状态 INCOMINGCALL
I/user.场景1 收到来电，号码: 139XXXXXXXX 响铃次数: 1
I/user.CC状态 INCOMINGCALL
I/user.场景1 收到来电，号码: 139XXXXXXXX 响铃次数: 2
I/user.CC状态 INCOMINGCALL
I/user.场景1 收到来电，号码: 139XXXXXXXX 响铃次数: 3
I/user.场景1 拒接来电
I/user.CC状态 HANGUP_CALL_DONE
I/user.场景1 挂断完成
``` 

#### 场景2 呼入自动接听+10秒后主动挂断

来电响铃2次后自动接听，通话建立10秒后设备会自动挂断。通话期间持续进行双向录音。

类似以下日志：

``` lua
I/user.cc_app 通话业务逻辑模块加载完成，当前场景: 2
I/user.exaudio_device 使用exaudio.setup初始化音频设备
I/user.exaudio_device exaudio.setup初始化成功
I/user.CC状态 READY
I/user.exaudio_device 通话录音已启用
I/user.cc_app 电话系统初始化完成
I/user.CC状态 PLAY
I/user.CC状态 INCOMINGCALL   
I/user.场景2 收到来电，号码: 139xxxxxxxx 响铃次数: 1  
I/user.场景2 收到来电，号码: 139xxxxxxxx 响铃次数: 2  
I/user.场景2 自动接听来电   
I/user.场景2 接听完成，等待通话建立             
I/user.场景2 通话已建立，开始计时  
I/user.场景2 10秒挂断定时器创建成功，ID: 2097153
I/user.录音 上行数据，位于缓存 1 缓存1数据量 6400 缓存2数据量 0
I/user.通话质量 2
I/user.CC状态 HANGUP_CALL_DONE
I/user.场景2 通话结束
I/user.场景2 已取消挂断定时器 
```

#### 场景3 呼入自动接听+等待对方挂断

呼入主动接听并等待对方主动挂断。通话期间持续进行双向录音。

类似以下日志：

``` lua
I/user.cc_app 通话业务逻辑模块加载完成，当前场景: 3
I/user.exaudio_device 使用exaudio.setup初始化音频设备
I/user.exaudio_device exaudio.setup初始化成功
I/user.CC状态 READY
I/user.exaudio_device 通话录音已启用
I/user.cc_app 电话系统初始化完成
I/user.CC状态 PLAY
I/user.CC状态 INCOMINGCALL   
I/user.场景2 收到来电，号码: 139xxxxxxxx 响铃次数: 1  
I/user.场景2 收到来电，号码: 139xxxxxxxx 响铃次数: 2  
I/user.场景2 自动接听来电  
I/user.场景3 电话已接通，电话号码: 139xxxxxxxx
I/user.录音 上行数据，位于缓存 1 缓存1数据量 6400 缓存2数据量 0
I/user.通话质量 2
I/user.CC状态 DISCONNECTED
I/user.场景3 通话结束对方挂断
```

#### 场景4 主动呼出预设号码并等待对方挂断

类似以下效果：

``` lua
I/user.cc_app 通话业务逻辑模块加载完成，当前场景: 4
I/user.exaudio_device 使用exaudio.setup初始化音频设备
I/user.exaudio_device exaudio.setup初始化成功
I/user.CC状态 READY
I/user.exaudio_device 通话录音已启用
I/user.cc_app 电话系统初始化完成
I/user.场景4 开始拨打 139xxxxxxxx
I/user.CC状态 MAKE_CALL_OK
I/user.CC状态 PLAY
I/user.录音 上行数据，位于缓存 1 缓存1数据量 6400 缓存2数据量 0
I/user.通话质量 2
I/user.CC状态 DISCONNECTED
I/user.场景4 通话结束（对方挂断）
```

### 功能二：TTS循环播放与通话处理

#### TTS循环播放功能

设备启动后会自动循环播放"支付宝到账，1千万元"语音提示，播放完成后间隔1秒继续播放。

类似以下日志：

``` lua
I/user.cc_app TTS循环播放与通话处理模块加载完成
I/user.exaudio_device 使用exaudio.setup初始化音频设备
I/user.exaudio_device exaudio.setup初始化成功
I/user.CC状态 READY
I/user.exaudio_device 通话录音已启用
I/user.cc_app 电话系统初始化完成
I/user.开始播放TTS
I/user.播放完成 true
I/user.开始播放TTS
I/user.播放完成 true
```

#### 来电自动接听功能

当有来电时，设备会响铃2声后自动接听，通话过程中暂停TTS播放，通话结束后恢复播放。

类似以下日志：

``` lua
I/user.CC状态 INCOMINGCALL
I/user.场景3 收到来电，号码: 139XXXXXXXX 响铃次数: 1
I/user.CC状态 INCOMINGCALL
I/user.场景3 收到来电，号码: 139XXXXXXXX 响铃次数: 2
I/user.场景3 自动接听来电
I/user.场景3 电话已接通，电话号码: 139XXXXXXXX
I/user.录音 上行数据，位于缓存 1 缓存1数据量 6400 缓存2数据量 0
I/user.通话质量 2
I/user.CC状态 DISCONNECTED
I/user.场景3 通话结束对方挂断
I/user.开始播放TTS
I/user.播放完成 true
```

#### 通话录音功能

所有通话均会进行双向录音，实时记录通话数据，可通过日志查看录音状态。

``` lua
I/user.录音 上行数据，位于缓存 1 缓存1数据量 6400 缓存2数据量 0
I/user.通话质量 2
```
