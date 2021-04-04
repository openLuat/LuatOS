
# LuatOS V0005 发布了, Cat.1/NbIot/Wifi全覆盖

* Cat.1 -> Air724,Air722/展锐RDA8910
* NBIOT -> Air302/移芯EC616
* Wifi  -> Air640W/联盛德W600

# LuatOS固件特点

### 完全抛弃AT的底层设计

没有虚拟AT接口, 没有ril库, 没有AT命令的解析与回调, 不用在系统队列与用户队列中反复绕圈

设计之初就秉着替代并超越AT的信仰, 绕过sdk的AT框架, 实现一整套与AT engine平行的LuatOS engine.

API调用更快捷高效, 内存更省, 逻辑更清晰, 扩展性更好

### 基于Lua 5.3, 支持原生位运算符

```lua
local newval = val ^ 0xFF
local newval2 = val2 << 3
```

### 数值类型扩展到64位, 支持更大的数据范围

```lua
local val = 1 << 63
local val2 = 0xFFFFFFFF
```

### 利用率更高的Lua专属内存

最低内存需求仅16k, 提供64k内存足以满足低复杂度的应用.

在资源紧缺的wifi/nbiot模块,默认提供64kb内存, 也能满足紧凑型应用的内存需求, 后续还有提高内存使用率的方案.

### 内置墨水屏驱动

无需复杂的调试,内置驱动从1寸到2.9寸均为默认支持, 更大尺寸可通过自行编译固件开启. 内置中文字体, 显示无忧.

## Cat.1固件的额外特性

本次发布的V0005是针对Cat.1模组的第一个版本,涵盖一般的外设功能和联网功能外,还有一些知道关注的特性

### 可调整的串口缓冲区大小

默认16k, 最高128k, 避免极端场景下uart出现overflow的可能性

### 可回滚的脚本升级机制

脚本区与脚本OTA区,均为256kb, 前者为线刷, 后者为OTA写入, 没有繁琐的AT解析, LuatOS提供的lua库文件很小,用户脚本占大头

后续还支持SD卡升级,敬请期待

### 连续性内存

Air724(RDA8910系列)固件默认提供1.5mb的Lua VM独占内存, 最高可容纳512kb的单一长字符串,字符串拼接不再惧怕内存溢出.

## NBIOT固件的额外更新

### 释放uart0供用户使用

虽然它不是很纯(有点脏数据),但胜在波特率可以很高很高(最高6M)

### ctiot库优化

紧跟sdk的升级, 对ctiot库进行改进


## 那下个版本V0006, 会带来什么?

预期会增加或实现的功能有:

### Lua脚本调试

当前仅Air640w固件得以实现, V0006将覆盖全部模块!!

https://gitee.com/openLuat/vscode-luatos-debug

### zbuff库

高性能的C风格缓冲区库, 提供丝滑的`char[]`操作体验

```lua
-- 创建zbuff
local buff = zbuff.create(1024) -- 空白的
-- local buff = zbuff.create(1024, "123321456654") -- 创建,并填充一个已有字符串的内容

-- 类file的读写操作
buff:write("123") -- 写入数据, 指针相应地往后移动
buff:seek(0, zbuff.SEEK_SET) -- 把指针设置到指定位置
local str = buff:read(3) -- 把刚才那3个字节读出来,内容是字符串,指针也往后移动了

-- 按数据类型读写
local n = buff:readInt8() -- 支持int8~int64,uint8~uint64,float32,double64
-- buff:writeInt8(0x32)   -- 同时也支持写入上述整型/浮点数

-- 支持pack/unpack操作
local _, a, b, c = buff:unpack("IIH") -- 支持unpack解码
-- buff:pack("IIH", 0x1234, 0x4567, 0x12) -- 也支持pack打包
log.info("buff", str, n)

-- 类数组操作
buff:seek(0, zbuff.SEEK_SET) -- 又回到开头
local b = buff[2] -- 直接按数组来读取, 得到ASCII码, 0x32, 注意,这里按C的标准来
buff[3] = 0x33 -- 直接赋值可还行
```

### 还有很多想法,等待一步步实现

* Air724固件的文件浏览器 - 像资源管理器那样操作模块的里面文件, 如何怎样的体验?
* 云刷机 - 在页面编辑,按一下远程下载,模块自行下载脚本,自动开始运行, 很流畅呀
* 压榨内存 - 既然code是固定的,那岂不是能放在flash上吗?那调试信息也可以嘛
* spi flash也挂文件系统 - w25q挺便宜的呀, 扩容杠杠的



## 版本列表

* air302 72kb noui noctiot
* air302 64kb disp/u8g2 ctiot
* air302 64kb eink noctiot
* air640w wifi
* air640w wifi noui
* air640w mcu
* air724ug ALL
