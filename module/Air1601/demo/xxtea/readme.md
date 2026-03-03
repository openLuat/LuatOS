## 演示功能概述

使用Air8000整机开发板，本示例主要是展示xxtea核心库的使用，使用xxtea加密算法，对数据进行加密和解密

## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

## **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/) ；

3.准备好软件环境之后，接下来查看[如何烧录项目文件到 Air1601 开发板中](https://docs.openluat.com/air1601/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到Air1601开发板中。

## 演示核心步骤

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到整机开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印：

xxtea_encrypt为加密后的字符串，xxtea_decrypt为解密后的字符串，通过16进制展示

```lua
[2025-09-25 12:01:10.767][000000001.449] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:10.777][000000001.449] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:11.055][000000002.450] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:11.064][000000002.450] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:12.053][000000003.451] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:12.061][000000003.451] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:13.105][000000004.478] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:13.113][000000004.479] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:14.080][000000005.480] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:14.089][000000005.480] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:15.079][000000006.481] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:15.090][000000006.481] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:16.089][000000007.482] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:16.098][000000007.482] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24
[2025-09-25 12:01:17.091][000000008.483] I/user.testCrypto.xxteaTest xxtea_encrypt: 4088CEEE2EDF81BE3DCDC5FAB6D20925 32
[2025-09-25 12:01:17.100][000000008.483] I/user.testCrypto.xxteaTest decrypt_data: 48656C6C6F20576F726C6421 24


```

