## 演示模块概述

1、main.lua：主程序入口；

2、protobuf_app.lua：protobuf 编解码功能模块；

## 演示功能概述

使用 Air8000 核心板搭配 protobuf 库演示 protobuf 编码与解码功能；

1、加载 protobuf 定义文件；

2、将符合 protobuf 定义的 Lua table 数据编码为二进制数据；

3、使用 json 编码同样的 Lua table 数据后，对比 protobuf 和 json 编码后数据的大小；

4、将二进制数据解码为 Lua table 数据；

5、清除所有已加载的定义数据；

注意事项：

1、protobuf 库支持 Proto2 和 Proto3 协议版本；

2、person.proto 文件是消息结构定义文件（Schema），它是人类可读的文本文件，使用 Protobuf IDL 语法，该文件定义了消息类型 Person 的结构（字段名、类型、编号等），文件中示例内容如下：

```protobuf
syntax = "proto2";

message Person {
  optional string name = 1;
  optional int32 id = 2;
  optional string email = 3;
}
```

该文件需要由开发者手动创建编写，语言规范参考：

Protocol Buffers 官方语言指南（proto3）：[Language Guide (proto 3) | Protocol Buffers Documentation](https://protobuf.dev/programming-guides/proto3/) ；

Protocol Buffers 官方语言指南（proto2）：[Language Guide (proto 2) | Protocol Buffers Documentation](https://protobuf.dev/programming-guides/proto2/) ；

3、person.pb 文件是 Schema 描述的二进制文件（FileDescriptorSet），是 person.proto 经过 protoc -o 编译后生成的二进制元数据，该文件包含 Person 消息的完整结构描述（字段名、编号、类型），用于被 protobuf.load() 加载，供后续 protobuf.encode() 和 protobuf.decode() 能知道 Person 的结构，从而正确编解码；

4、关于如何得到 person.pb 文件说明如下：

- 需要先下载 protoc.exe，下载链接：https://github.com/protocolbuffers/protobuf/releases ；
- 在 protoc.exe 文件目录下打开 CMD，输入 protoc -o person.pb person.proto 即可生成 person.pb 文件，前提需要同目录下包含 person.proto 文件；

5、person.pbtxt 文件是用户数据的文本表示（TextFormat），它是人类可读的文本文件，表示一个具体的 Person 消息实例，内容是字段赋值，文件中示例内容如下：

```textproto
name: "wendal"
id: 123
email: "abc@qq.com"
```

该文件需要用户手动编写（用于配置、测试），或者通过程序把用户数据以人类可读的文本格式保存在 .pbtxt 文件下；

该文件内容需要遵循 Protobuf 文本格式语法规范（Text Format Syntax），语言规范参考：

Protobuf Text Format 官方语言规范（草案）：[Text Format Language Specification | Protocol Buffers Documentation](https://protobuf.dev/reference/protobuf/textformat-spec/) ；

6、person.pbtxt 文件用于调试、写测试用例、作为配置文件，可被支持 TextFormat 的 Protobuf 库解析为内存对象，在 LuatOS 中不使用 .pbtxt 文件（protobuf 库只支持 binary encode/decode，也就是 .pb 文件）；

## 演示硬件环境

1、Air8000 核心板一块

2、TYPE-C USB数据线一根

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 V2016 版本](https://docs.openluat.com/air8000/luatos/common/download/)（理论上最新版本固件也可以，如果使用最新版本的固件不可以，可以烧录 V2016-1 固件对比验证）

## 演示核心步骤

1、搭建好硬件环境

2、Luatools 工具烧录内核固件和 demo 脚本代码

3、烧录成功后，自动开机运行

4、正常运行情况时的日志如下：

```
[000000000.744] I/user.main protobuf 001.000.000
[000000000.753] I/user.protobuf 加载 protobuf 定义成功，共解析 85 字节
[000000000.753] I/user.protobuf 编码成功，数据长度：22
[000000000.754] I/user.protobuf 十六进制内容：0A0677656E64616C107B1A0A6162634071712E636F6D
[000000000.754] I/user.json 编码成功，数据长度：47
[000000000.754] I/user.json 数据内容：{"name":"wendal","id":123,"email":"abc@qq.com"}
[000000000.755] I/user.protobuf 解码成功，数据内容： {"name":"wendal","id":123,"email":"abc@qq.com"}
[000000000.755] I/user.protobuf 所有 protobuf 定义已清除
```

