--[[
本demo演示的功能为：
使用Air780EPM开发板通过spi接口驱动RC522传感器读取ic数据卡数据
通过spi0通道
cs片选脚接gpio8
rst接gpio16
]]

local rc522 = require "rc522"  --引入rc522驱动模块
function rc522_test()
    spi_rc522 = spi.setup(0,8,0,0,8,10*1000*1000,spi.MSB,1,0)  --初始化spi接口
    rc522.init(0,8,16)   --初始化rc522相关接口
    wdata = {0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00} --测试写入数据
    while 1 do
        -- rc522.write_datablock(7,wdata) --测试ic卡写入
        for i=0,63 do
            local a,b = rc522.read_datablock(i) --测试ic卡读取
            if a then
                print("read",i,b:toHex())  --打印读取的数据
            end
            sys.wait(50)
        end
        sys.wait(500)
    end
end
sys.taskInit(rc522_test)
