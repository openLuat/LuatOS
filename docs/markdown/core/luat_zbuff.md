# C风格的缓冲区

## 基本信息

* 起草日期: 2021-03-24
* 设计人员: [wendal](https://github.com/wendal)

## 有什么用途

直接指向一块内存区域,提供一系列API操作这块内存

* 拼接待发送的数据, 部分替代pack库
* 作为FrameBuffer,在显示框架中充当显示缓冲区

## 设计思路和边界


## Lua API

使用示例

```lua
-- 创建zbuff
local buff = zbuff.create(1024) -- 空白的
-- local buff = zbuff.create(1024, "123321456654") -- 创建,并填充一个已有字符串的内容

-- 类file的读写操作
buff:write("123") -- 写入数据, 指针相应地往后移动
buff:seek(0, zbuff.SEEK_SET) -- 把指针设置到指定位置
local str = buff:read(3) -- 把刚才那3个字节读出来,内容是字符串,指针也往后移动了

-- 按数据类型读写
local n = buff:readInt8() -- 支持int8~int64,uint8~uint32,float32,double64
-- buff:writeInt8(0x32)   -- 同时也支持写入上述整型/浮点数

-- 支持pack/unpack操作
local _, a, b, c = buff:unpack("IIH") -- 支持unpack解码
-- buff:pack("IIH", 0x1234, 0x4567, 0x12) -- 也支持pack打包
log.info("buff", str, n)

-- 类数组操作
buff:seek(0, zbuff.SEEK_SET) -- 又回到开头
local b = buff[2] -- 直接按数组来读取, 得到ASCII码, 0x32, 注意,这里按C的标准来
buff[3] = 0x33 -- 直接赋值可还行

-- FrameBuffer操作
buff:asFB(128, 240, 16) -- 宽,高,色深
buff:drawLine(1, 2, 1, 20, 0x21) -- 画线操作
buff:drawRect(20, 40, 40, 40) -- 画矩形
buff:setPix(1, 2, 0x01) -- 设置具体像素值
buff:drawStr(20, 40, "中文也ok") -- 写字
buff:clear() -- 清空,全部填0

-- 取出缓冲区的内容, 返回值是string
buff:str() -- 默认是0 ~ limit/len 从头到limit值或者到尾部
buff:str(2, 12) -- 取出特定偏移量和长度
```


## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)

