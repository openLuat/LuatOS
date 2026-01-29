local PWM_ID = 4

mcu.altfun(mcu.PWM, 4, 46, 5, nil)--1.2版本PWM4对应的GPIO22，复用接口

sys.taskInit(function()
    log.info("pwm", "ch", PWM_ID)
    while 1 do
        sys.wait(5000)
        --PWM接的蜂鸣器响的频率是4000和8000
        log.info("pwm", ">>>>>3K")
        pwm.open(PWM_ID, 1000, 50) -- 频率4000hz, 占空比0-100
        sys.wait(5000)
        log.info("pwm", ">>>>>8K")
        pwm.open(PWM_ID, 8000, 50)
        sys.wait(5000)
        log.info("pwm", ">>>>>CLOSE")
        -- pwm.open(PWM_ID, 0, 50)
        pwm.close(PWM_ID)
    end
end)
