# Air640W 量产固件的格式设计

本文描述的是Air640W固件的一次性刷机所需要的格式

## 最早的刷机是这样的

1. 输入FLS文件, 底层固件
2. 重启后, 通过ymodem协议逐个文件写入lua脚本

## 设计一款新的格式

外层结构为zip 或 7zip, 具体待定

里层文件有

```bash
- rominfo.json               # [必] 固件信息描述文件
- luatos_w600_v0006.bin      # [必] 底层固件文件
- luadb.bin                  # [选] 脚本文件,luadb 2.0格式
- disk.bin                   # [选] 文件系统分区
```

### rominfo.json

内容如下

```json
{
    "type"         : "w600",
    "luadb_offset" : 0x080A0000,
    "luadb_size"   : 64 * 1024, 
    "luaota_offset": 0x080B0000,
    "luaota_size"  : 64 * 1024, 
    "disk_offset"  : 0x080C0000,
    "disk_size"    : 128 * 1024
}
```

* type : 固件类型
* luadb_offset  : lua脚本区起始偏移量
* luadb_size    : lua脚本区大小,字节
* luaota_offset : lua脚本ota区起始偏移量
* luaota_size   : lua脚本ota区大小,字节
* disk_offset   : 文件系统分区起始偏移量
* disk_size     : 文件系统分区大小

## Flash 片上文件分布情况

0x08010000 -- RUN PARAM, 256字节, 不可控
0x08010100 -- RUN AREA, 对应 luatos_w600_v0006.bin
0x080A0000 -- LuaDB, 对应luadb.bin
0X080B0000 -- LuaOTA, 默认空白, 大小64kb
0X080C0000 -- FileSystem, 文件系统, 大小128kb
0x080F0000 -- 默认文件系统边界, 也是默认的UserParam区, 48kb, 考虑用上?
0x080FC000 -- 文件系统最远边界

## 固件合成逻辑

makeimg的时候,按把RUN AREA(当前对应luatos_w600_v0006.bin)写入FLS.

所以, 把luadb/disk等区域, 按偏移量, 逐一附加到luatos_w600_v0006.bin文件末尾, 并在间歇内填充0

就能做出一个很大的RUN AREA, 欺骗secboot进行刷机


效果是:

对外提供的固件包是 压缩包(后缀为.air?), 刷机时, 自动合成FLS文件,进行一体化刷机


## 验证过程及结论

**致命的限制: RUN AREA 的内容不可修改**

什么不变呢?

* 原固件本身
* 填充的空白
* LuaDB

OTA, disk 都不能放在 RUN AREA

解决方式:

* 在代码里声明一个64kb数组,用于量产时填充脚本数据
* 量产时把luadb的内容填入数据, 变成FLS文件的一部分
* 切换到刷机模式前, 考虑把flash清空
