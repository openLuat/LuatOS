# Air302刷机

支持两种刷机模式, LuaTools图形化刷机, air302py脚本刷机

刷机前请确保串口驱动已经安装好,模块电源灯已亮起.

## LuaTools刷机

视频演示请查看gif目录里面的"使用LuaTools刷底层"

1. 确保设备已经开机,电源灯亮起. Air302为上电自动开机,没有pwrkey按钮.
2. 确保已安装串口驱动, 使用UART1
3. 按住BOOT按钮, 然后按复位/Reset按钮, 松开BOOT按钮
4. 打开LuaTools, 选择固件下载, 选好ec结尾的固件文件
5. 点击下载, 等待下载完成.

## air302py脚本刷机

视频演示请查看gif目录里面的"使用air302py脚本刷底层"

刷机脚本需要python 3.7+

1. 确保设备已经开机,电源灯亮起. Air302为上电自动开机,没有pwrkey按钮.
2. 确保已安装串口驱动, 使用UART1
3. 按住BOOT按钮, 然后按复位/Reset按钮, 松开BOOT按钮
4. 修改local.ini,配置串口号和ec固件路径,其中的路径支持相对路径.
5. 进入命令行, cd到air302.py的目录, 执行 python air302.py dlrom

## FlashToolCLI下载地址

https://gitee.com/openLuat/LuatOS/attach_files 需要解压到air302.py所在目录,带文件夹.

