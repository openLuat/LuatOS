local airaudio = {}

exaudio = require("exaudio")

-- 音频初始化设置参数,exaudio.setup 传入参数
local audio_setup_param ={
    model= "es8311",          -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,          -- i2c_id,可填入0，1 并使用pins 工具配置对应的管脚
    pa_ctrl = 162,         -- 音频放大器电源控制管脚
    dac_ctrl = 164,        --  音频编解码芯片电源控制管脚    
}


function airaudio.init()
    gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域
    sys.wait(100)
    exaudio.setup(audio_setup_param)
end


return airaudio