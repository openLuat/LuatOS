-- 同编号的 W / M 款使用同一组串口和卡座装配。SPI2 分别接 Air6205 / Air780EX2。
-- J30 只记录 UART5 是否引出。RX5/TX5 与触摸 I²C1 复用，出厂程序保留触摸。
return {
    [1] = { uart2="can",   uart3="face",  uart6="air1103", uart5_breakout=true,  sd_card=true  },
    [2] = { uart2="rs232", uart3="face",  uart6="air1103", uart5_breakout=true,  sd_card=true  },
    [3] = { uart2="can",   uart3="rs485", uart6="air1103", uart5_breakout=true,  sd_card=false },
    [4] = { uart2="can",   uart3="rs485", uart6="ttl",     uart5_breakout=false, sd_card=false },
    [5] = { uart2="rs232", uart3="rs485", uart6="ttl",     uart5_breakout=false, sd_card=false },
}
