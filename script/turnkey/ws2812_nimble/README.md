# 蓝牙ws2812控制器

适用于air101/air103, 但需要提醒的是, 绝非低功耗!!!

## 关于Air101/Air103的蓝牙

虽然开发板没有引出天线, 实际上这两款芯片是带蓝牙的, 但功耗很高,只能做简单的收发.

Air103的pinout图链接 https://wiki.luatos.com/chips/air103/mcu.html#pinout

其中的 14 脚, 标注为NC ,实际为ANT, 天线脚, 可飞线.

Air101的pinout图链接 https://wiki.luatos.com/chips/air101/mcu.html

其中的 8 脚, 标注为NC ,实际为ANT

## 关于固件

在发布版的固件压缩包里, 带BLE字样的固件才支持蓝牙, 也可以使用云编译自行定制

https://gitee.com/openLuat/LuatOS/releases

https://wiki.luatos.com/develop/compile/Cloud_compilation.html

## 微信小程序

搜 "LuatOS蓝牙" 就可以了.

设备蓝牙名称默认 `LOS-` 开头, 若没有把天线飞线出来, 把手机贴到芯片上就能搜到.

