--[[
@module  uart_manger
@summary 串口功能管理模块
@version 1.0
@date    2025.09.23
@author  魏健强
@usage
本模块为串口功能管理模块，核心业务逻辑为：根据项目需求，选择并且配置合适的串口功能
1、simple_uart：简易串口，小数据字符串收发；
2、high_volume_uart：大数据收发串口；
3、485_uart：485串口；
4、multiple_uart：多串口；
5、usb_uart：USB虚拟串口；
]]
-- 根据自己的项目需求，只需要require以下五种中的一种即可；
-- 简易串口，小数据字符串收发
require "simple_uart"

-- 大数据收发串口
-- require "high_volume_uart"

-- 485串口
-- require "485_uart"

-- 多串口
-- require "multiple_uart"

-- USB虚拟串口
-- require "usb_uart"

-- 动态切换串口引脚复用
-- require "uart_mux"