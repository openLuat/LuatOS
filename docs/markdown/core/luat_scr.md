# 屏幕显示接口

## 基本信息

* 起草日期: 2021-05-26
* 设计人员: [chenxuuu](https://github.com/chenxuuu)

## 有什么用途

提供统一的API对屏幕进行初始化、唤醒、刷新、休眠操作

* 利用zbuff作为缓存
* 只提供屏幕操作功能，屏幕数据处理交给zbuff处理

## 设计思路和边界

## Lua API

使用示例

```lua
-- 创建FrameBuffer的zbuff对象，初始化白色
local buff = zbuff.create({200,200,16},0xffff)

--新建一个屏幕对象，xy偏移默认0
local screen = scr.create("st7735",scr.port_spi连接类型,连接id,复位引脚,使能引脚,背光引脚,x偏移,y偏移)
screen:wake()--唤醒屏幕
screen:sleep()--休眠屏幕
screen:show(buff)--显示buff内容

buff:pixel(0,3,0)-- 设置具体像素值
buff:drawLine(1, 2, 1, 20, 0) -- 画线操作
buff:drawRect(20, 40, 40, 40, 0) -- 画矩形

screen:show(buff)--显示buff内容
```

## Luat C API

所有屏幕刷新控制逻辑，都由luat层处理。
仅需适配spi/12c/特殊接口即可

```c
//连接类型
enum luat_scr_port{
    luat_scr_spi,
    luat_scr_i2c,
    luat_scr_lcd,
    luat_scr_other
}

typeof struct luat_scr_cfg{
    char* name;   //注意不用的时候要手动free掉
    luat_scr_port port; //连接类型
    int id;       //连接id
    int rst_pin;  //复位引脚
    int cs_pin;   //使能引脚
    int blk_pin;  //背光引脚
    int x_offset; //x偏移
    int y_offset; //y偏移
}luat_scr_cfg;

int luat_scr_initial(luat_scr_cfg* cfg);
int luat_scr_close(luat_scr_cfg* cfg);

//下面这几个函数，只有是用到了spi/i2c外的类型时才用到
int luat_scr_reset(luat_scr_cfg* cfg,uint32_t ms);
int luat_scr_blk(luat_scr_cfg* cfg,char enable);

//下面这几个函数，只有是用到了luat_scr_lcd类型时才用到
int luat_scr_cmd(luat_scr_cfg* cfg,uint8_t* data,uint32_t length);
int luat_scr_data(luat_scr_cfg* cfg,uint8_t* data,uint32_t length);

//下面这几个函数，只有是用到了luat_scr_other类型时才用到
int luat_scr_display(luat_scr_cfg* cfg,zbuff* data);//要完全自己实现刷屏功能
int luat_scr_wake(luat_scr_cfg* cfg);
int luat_scr_sleep(luat_scr_cfg* cfg);
```

## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)
