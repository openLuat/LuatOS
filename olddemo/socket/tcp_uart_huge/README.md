# TCP/UART大数据量下发的演示

本demo演示从TCP端读取8M字节的数据,以阻塞的方式写入UART

## 文件说明

1. main.lua 下载到模块端的代码, 配合最新固件一起使用
2. main.go   服务器端的代码,golang语言的, 客户端连接后会立即开始下发8M字节的数据
3. README.md 本说明文件

