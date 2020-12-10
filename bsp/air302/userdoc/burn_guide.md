# Air302刷机

支持两种刷机模式, LuaTools图形化刷机, air302py脚本刷机

刷机前请确保串口驱动已经安装好,模块电源灯已亮起.

## LuaTools刷机

LuaTools是合宙主推的Luat系列刷机工具, 功能强大, 可以从www.openluat.com的产品中心下载.

视频演示请查看gif目录里面的"使用LuaTools刷底层"

1. 确保设备已经开机,电源灯亮起. Air302为上电自动开机,没有pwrkey按钮.
2. 确保已安装串口驱动, 使用UART1
3. 按住BOOT按钮, 然后按复位/Reset按钮, 松开BOOT按钮
4. 打开LuaTools, 选择固件下载, 选好ec结尾的固件文件
5. 点击下载, 等待下载完成.

## air302py脚本刷机

视频演示请查看gif目录里面的"使用air302py脚本刷底层"

刷机脚本需要python 3.7+, 可以到python.org下载安装

1. 确保设备已经开机,电源灯亮起. Air302为上电自动开机,没有pwrkey按钮
2. 确保已安装串口驱动, 使用UART1
3. 按住BOOT按钮, 然后按复位/Reset按钮, 松开BOOT按钮
4. 修改local.ini,配置串口号和ec固件路径,其中的路径支持相对路径.
5. 进入命令行, cd到air302.py的目录, 执行 python air302.py lfs dlfull

```
python air302.py [action1] [action2] [...]
```

lfs 生成文件系统
dlfs 下载文件系统
dlrom 下载固件,仅系统分区,不含文件系统
dlfull 下载系统分区和文件系统

## FlashToolCLI

这是厂商的刷机工具, 与air302.py配合使用, 不是直接双击启动的.

已经在固件压缩包里面, 不需要额外下载, 除非你看的是LuatOS源码

## 常见问题

1. 无法刷机, 提示设备返回的0x2acbd 之类的字样 -- 检查选择的串口是不是U1, UART1
2. 提示串口无权限 -- 被其他工具打开了, 关掉其他串口工具即可
3. lfs 提示错误 -- 通常是语法错误,按行号检查并修正
