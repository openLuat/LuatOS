## 功能模块介绍

1、main.lua：主程序入口；

2、codec_mp3_to_pcm： MP3解码为PCM并流式播放

3、codec_g711_pcm： G711编解码演示  

4、codec_pcm_to_amr： PCM编码为AMR并播放

5、sample-6s.mp3 ：用于MP3解码为PCM并流式播放演示的音频文件

6、test.pcm: 用于G711编解码和PCM编码为AMR并播放演示的音频文件

## 常量的介绍

1、codec.MP3 : MP3音频格式，仅支持解码功能，用于将MP3文件解码为PCM数据

2、codec.AMR : AMR_NB格式（窄带AMR），支持编码和解码

3、codec.AMR_WB : AMR_WB格式（宽带AMR），仅在支持VoLTE的固件上支持编解码

4、codec.ULAW : G711 μ-law格式，支持编码和解码

5、codec.ALAW : G711 A-law格式，支持编码和解码

## 演示功能概述

1、codec_mp3_to_pcm：将MP3文件解码为PCM数据，并使用exaudio进行流式播放。

2、codec_g711_pcm：演示G711编解码功能，将PCM文件进行G711编码，然后解码并播放。

3、codec_pcm_to_amr：将PCM文件编码为AMR格式，然后使用exaudio播放AMR文件，使用单声道，保持原始PCM文件的采样率和采样位深。


## 演示硬件环境

1、Air780EHV核心板+AirAUDIO_1000配件板+喇叭

![alt text](https://docs.openLuat.com/cdn/image/Air780EHV+Airaudio1000.jpg)

2、TYPE-C USB数据线一根
- Air780EHV核心板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

3、可选AirAudio_1000 配件板一块，Air780EHV核心板和AirAudio_1000 配件板的硬件接线方式为:
| Air780EHV核心板 | AirAUDIO_1000配件板 |
| ---------------| -----------------   |
| 3/MIC+         |     MIC+            |
| 4/MIC-         |     MIC-            |
| 5/SPK+         |     SPK+            |
| 6/SPK-         |     SPK-            |
| 19/GPIO22      |     PA_EN           |
| 3V3            |     VCC             |
| GND            |     GND             |

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/) 

2、Air780EHV V2018及以上版本固件，选择支持codec功能的固件。不同版本区别请见https://docs.openluat.com/air780ehv/luatos/firmware/version/
3、 luatos需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air780EHM_Air780EHV_Air780EGH/demo/codec/Air780EHV)

- 准备好软件环境之后，接下来查看[如何烧录项目文件到Air780EHV核心板](https://docs.openluat.com/air780ehv/luatos/common/download/)， 将本篇文章中演示使用的项目文件烧录到Air780EHV核心板中。

4、lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件；

## 演示核心步骤

1、搭建好硬件环境

2、搭配AirAUDIO_1000 音频板测试，需将AirAUDIO_1000 音频板中PA开关拨到OFF，让软件控制PA，避免pop音

3、demo脚本代码main.lua中，按照自己的需求选择对应的功能

    如果需要测试MP3转PCM流式播放，则取消注释 require "codec_mp3_to_pcm"

    如果需要测试G711编解码，则取消注释 require "codec_g711_pcm"

    如果需要测试PCM转AMR并播放，则取消注释 require "codec_pcm_to_amr"

4、Luatools烧录内核固件和demo脚本代码

5、运行程序，观察Luatools日志输出和音频播放效果

6、各个功能模块的详细说明：

- MP3转PCM流式播放 (codec_mp3_to_pcm)

    自动加载sample-6s.mp3文件

    将MP3文件解码为PCM数据

    使用exaudio进行流式播放

    自动识别MP3文件的采样率和位深度

    使用单声道播放


- G711编解码演示 (codec_g711_pcm)

    自动加载test.pcm文件

    对PCM文件进行G711编码

    对编码后的文件进行G711解码

    使用exaudio流式播放解码后的PCM数据

    使用单声道、16kHz采样率、16位深度


- PCM转AMR并播放 (codec_pcm_to_amr)

    自动加载test.pcm文件

    将PCM文件编码为AMR格式

    保存编码后的AMR文件

    使用exaudio播放AMR文件

    使用单声道，保持原始PCM文件的采样率和采样位深


6、运行结果展示

- MP3转PCM流式播放 (codec_mp3_to_pcm)

``` lua
I/user.开始MP3解码为PCM并使用exaudio流式播放
I/user.使用exaudio.setup初始化音频设备
I/user.exaudio.setup初始化成功
I/user.初始音量设置为50
I/user.启动数据获取和播放任务
I/user.开始流式获取音频数据
I/user.MP3文件原始信息:
I/user.声道数: 1
I/user.采样率: 44100
I/user.位深度: 16
I/user.播放声道数: 1 (强制单声道)
I/user.预先解码数据准备...
I/user.预先解码块 1 大小: 13824 字节
I/user.预先解码块 2 大小: 13824 字节
I/user.预先解码块 3 大小: 13824 字节
I/user.预先解码块 4 大小: 11520 字节
I/user.预先解码块 5 大小: 13824 字节
I/user.预先解码完成，总数据大小: 67584 字节
I/user.exaudio流式播放启动成功
I/user.预先解码数据已写入，大小: 67584 字节
I/user.开始持续解码剩余数据...
I/user.解码并写入数据块 10 大小: 12288 字节 累计: 129792 字节
I/user.解码并写入数据块 20 大小: 12288 字节 累计: 256512 字节
……
I/user.解码并写入数据块 40 大小: 12288 字节 累计: 509952 字节
I/user.MP3解码完成
I/user.MP3解码完成，总解码数据: 569856 字节

I/user.MP3播放完成 回调触发
I/user.MP3播放正常完成
I/user.MP3转PCM流式播放演示完成
D/user.资源清理 MP3解码器已释放
D/user.资源清理 解码缓冲区已释放
D/user.资源清理 播放器已停止
 ```

- G711编解码演示 (codec_g711_pcm)

``` lua
I/user.开始G711编解码测试
I/user.exaudio 开始配置音频设备
I/user.exaudio 音频设备配置成功
I/user.第一步：流式播放原始PCM文件
I/user.开始流式播放: 原始PCM文件
I/user.文件路径: /luadb/test.pcm
I/user.流式播放 开始流式播放
I/user.文件大小 54594 字节
D/user.流式播放 写入音频数据块 10 大小: 4096 字节
I/user.流式播放 文件数据写入完成，总共 14 块， 54594 字节
...
I/user.播放完成 回调触发
I/user.播放正常完成
D/user.资源清理 文件句柄已关闭
audio_play_stop 651:no audio require, no need stop
D/user.资源清理 播放器已停止
I/user.流式播放 文件播放完成: 原始PCM文件
I/user.第二步：对/luadb/test.pcm进行G711编码
I/user.G711编码器创建成功
I/user.PCM文件大小: 54594 字节
I/user.开始G711编码，PCM数据大小: 54594 字节
I/user.G711编码结果: true
I/user.编码成功，编码后数据大小: 27360 字节
I/user.编码数据已保存到 /aaa.g711
I/user.第三步：先完全解码G711文件，再播放
I/user.开始完全解码G711文件: /aaa.g711
I/user.G711文件信息 采样率: 8000 声道数: 1 位深度: 8
I/user.开始解码过程...
D/user.解码 解码数据块 20 大小: 320 字节
D/user.解码 解码数据块 40 大小: 320 字节
...
I/user.解码 G711解码完成
I/user.解码完成 总解码数据大小: 54720 字节
I/user.解码完成 总共解码块数: 171
D/user.资源清理 解码器已释放
D/user.资源清理 解码缓冲区已释放
I/user.解码完成 准备播放解码后的数据，大小: 54720 字节
I/user.开始流式播放内存数据: G711解码数据
I/user.数据大小: 54720 字节
I/user.流式播放 开始流式播放内存数据
D/user.内存播放 写入音频数据块 10 大小: 4096 字节
I/user.内存播放 数据写入完成，总共 14 块， 54720 字节
I/user.播放完成 回调触发
I/user.播放正常完成
audio_play_stop 651:no audio require, no need stop
D/user.资源清理 播放器已停止
I/user.内存播放 数据播放完成: G711解码数据
I/user.播放 G711解码数据播放成功
I/user.G711编解码测试完成
D/user.资源清理 编码器已释放
D/user.资源清理 输入缓冲区已释放
D/user.资源清理 输出缓冲区已释放
audio_play_stop 651:no audio require, no need stop
D/user.资源清理 播放器已停止
 ```

- PCM转AMR并播放 (codec_pcm_to_amr)
``` lua
 I/user.开始PCM转AMR_WB编码并播放演示
I/user.初始化音频设备
I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40
D/audio codec init es8311 
I/user.音量设置为60
I/user.原始PCM文件大小: 54594 字节
I/user.AMR_WB编码器创建成功
I/user.实际读取的PCM数据大小: 54594 字节
I/user.开始AMR_WB编码
I/user.AMR_WB编码成功，编码后数据大小: 3485 字节
I/user.AMR_WB文件保存成功: /encoded.amr.wb 大小: 3494 字节
I/user.开始播放AMR_WB文件
I/user.AMR_WB文件开始播放
I/user.AMR_WB播放完成 回调触发
I/user.AMR_WB播放正常完成
I/user.PCM转AMR_WB编码并播放演示完成
D/user.资源清理 AMR_WB编码器已释放
D/user.资源清理 输入缓冲区已释放
D/user.资源清理 输出缓冲区已释放
audio_play_stop 651:no audio require, no need stop
D/user.资源清理 播放器已停止
``` 
