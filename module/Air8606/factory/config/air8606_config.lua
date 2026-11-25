-- AIR8606_V0_20261105_1733.pdf。GPIO 编号采用 CCM42xx 的 GPIO ID。
local M = {}
local assemblies = require "board_options"
-- U4 pad 73 is GPIO52 in the Air1602 pin table. The V0 schematic labels it GPIO45.
local J17_ENABLE_GPIO = 52

function M.build(model)
    local series, number = model:match("^([WM])([1-5])$")
    assert(series, "unknown Air8606 model: " .. model)
    local options = assemblies[tonumber(number)]
    local radio = series == "W" and "wifi" or "4g"
    local project_name = string.format("Engine_Air8606%s_10inch_1024x600_000_%s_V000",
        model, series == "W" and "WiFi" or "4G")
    local has_air1103 = options.uart6 == "air1103"
    local has_face = options.uart3 == "face"
    local cfg = {
        name = project_name, chip = "Air1602", baseboard = "合宙引擎 Air8606" .. model .. " 10寸", radio = radio,
        board_options = options,
        pins = {}, -- hardware I2C1, SPI1/2/5, UART1/2/3/6 use their default pads
        power_on = {
            { pin=4, level=1 },
            -- J24 的 SPI 信号在 U6 关闭时保持高阻，避免经 IO 给 U2 反向供电。
            { pin=56 }, { pin=57 }, { pin=58 }, { pin=64 }, { pin=47 }, { pin=40, level=0, delay=20 },
            { pin=0, level=0 }, { pin=14, level=0 }, -- J21 初始接收，485 电源默认关闭
            { pin=options.uart2 == "can" and 48 or 41, level=0 }, -- UART2 收发器电源
            { pin=13, level=0 }, -- USB Host 供电随后交给摄像头或键鼠
            { pin=44, level=0 }, { pin=J17_ENABLE_GPIO, level=0 }, -- external outputs default off
            { pin=12, level=1, delay=100 }, -- LCD, TP and PA shared 5V rail
            -- GPIO73 为 Air1103 与功放的共用使能。TTL + C104 由 DAC 播放按需开启功放。
            { pin=73, level=has_air1103 and 1 or 0, delay=has_air1103 and 100 or nil },
        },
        hw = {
            lcd = {
                model="lcd_display_rgb", need_buffer=true, screen_size=10.0,
                params={ interface="rgb", pin_rst=15, w=1024, h=600,
                    hbp=140, hspw=20, hfp=160, vbp=20, vspw=3, vfp=12,
                    bus_speed=50000000 },
                font={size=20}, backlight={pwm_ch=3,pwm_freq=10000,level=100},
            },
            tp = { model="tp_gt911", params={ port=1, pin_rst=72, pin_int=51, reset_hold_ms=20, rst_external_pullup=true, -- R16 to LCD_3V3
                int_type=tp and tp.FALLING or 2, i2c_speed=i2c and i2c.SLOW or 0,
                w=1024,h=600 } },
            -- GPIO12 belongs to LCD/TP/PA. USB Host has a separate GPIO13 supply.
            usb={vbus_gpio=13},
            wdt={pin=1,auto_feed_period_s=180,strap1=0,strap6=0},
        },
        features={sd_card=options.sd_card,speaker=true,mic=has_air1103,sip=has_air1103,ethernet=true,rs485=true,
            other_func=true,usb_camera=has_face,usb_hid=true,wdt=true,
            ai_chat=true,app_factory=true,cloud_disk=true,file_transfer=true,aircloud=true,
            iot=true,fota=true},
        network = {
            { type="eth_spi",port="J24",chip="CH390",spi_id=5,cs_pin=56,irq_pin=47,pwr_pin=40,
                sck_pin=57,mosi_pin=58,miso_pin=64,speed=4000000 },
        },
        storage={},
        aircloud={report_cycle=180,min_cycle=5},
        ui={show_app_factory=true,show_ai_chat=true,show_cloud_disk=true,
            show_other_func=true,show_file_transfer=true,show_storage_settings=true,
            show_video_area=true,show_brightness_slider=true,show_ethernet_settings=true,
            show_camera_preview=has_face,show_iot=true,show_fota=true,show_autostart=true,
            show_wifi_icon=radio=="wifi",show_4g_icon=radio=="4g",show_aircloud=true},
        peripherals={
            {type="rs485",id="485_1",name="隔离485-1 (J21)",
                uart_id=1,tx_gpio=2,rx_gpio=3,de_pin=0,native_de=true,power_pin=14,baud=9600,test_data="123",manual_init=true},
            {type="power",id="power_5v",name="对外5V输出 (J17)",pin=J17_ENABLE_GPIO},
            {type="power",id="power_vin",name="对外VIN输出 (12V端子)",pin=44},
            {type="wdt",id="wdt1",name="Air153D看门狗"},
        },
    }
    if options.sd_card then
        cfg.storage.sd_card = {spi_id=1,pin_cs=8,speed=10000000}
        table.insert(cfg.power_on, 1, {pin=8, level=1}) -- 拉高 J16 片选后再开启 3.3V
        cfg.power_on[#cfg.power_on+1] = {pin=74, level=1, delay=20}
    end
    cfg.power_on[#cfg.power_on+1] = {pin=43, level=1, delay=20} -- SPI2 从机复位
    cfg.power_on[#cfg.power_on+1] = {pin=43, level=0, delay=200}
    if has_air1103 then
        cfg.hw.audio = {
            model="air1103", play_model="air1103", uart_id=6, baud=2000000, audio_mode="new",
            power_gpio=73, recovery_power_pin=73, recovery_power_active=1,
            pa_ctrl=73, pa_on_level=1, pa_power_hold=true, pa_delay=200, record_format="PCM_16000",
            play_vol=70, mic_vol=70, max_record_time=30,
        }
        table.insert(cfg.peripherals, 2, {type="audio", id="audio1", record_seconds=5,
            name="Air1103录音回放"})
    else
        table.insert(cfg.peripherals, 2, {type="uart", id="ttl6", name="TTL 串口（J22）",
            uart_id=6, baud=115200, databits=8, parity="N", stopbits=1,
            manual_init=true, test_data="TTL test"})
        cfg.hw.audio = {model="dac", pa_ctrl=73, pa_on_level=1, dac_delay=6, pa_delay=10, play_vol=70}
    end
    if has_face then
        table.insert(cfg.peripherals, 1, {type="uvc",id="uvc1",name="USB摄像头/人脸",title="摄像头",
            en_pin=13,ready_delay=200,w=800,h=480,max_pixels=800*480,rotation=90,
            manual_init=true,face={uart_id=3,register_timeout=15,verify_timeout=15}})
    else
        cfg.power_on[#cfg.power_on+1] = {pin=46, level=0} -- J23 初始接收
        table.insert(cfg.peripherals, 2, {type="rs485",id="485_2",name="隔离485-2 (J23)",
            uart_id=3,tx_gpio=22,rx_gpio=23,de_pin=46,native_de=true,power_pin=14,baud=9600,test_data="456",manual_init=true})
    end
    if options.uart2 == "can" then
        cfg.features.can=true
        cfg.peripherals[#cfg.peripherals+1]={type="can",id="can2",name="CAN2",can_id=2,
            uart_id=2,power_pin=48,bitrate=500000,tx_id=0x123,test_data="CAN test",manual_init=true}
    else
        cfg.peripherals[#cfg.peripherals+1]={type="uart",id="rs232",name="RS232",uart_id=2,
            power_pin=41,baud=57600,databits=8,parity="N",stopbits=1,manual_init=true,
            share_group="uart2",share_kind="rs232"}
    end
    local net={spi_id=2,cs_pin=4,rdy_pin=42,airlink_mode="spi_master",speed=4000000}
    if radio == "4g" then
        cfg.features.net_4g=true
        cfg.features.gnss=true
        net.type="4g_airlink_spi"
        cfg.peripherals[#cfg.peripherals+1]={type="gnss",id="gnss1",name="Air510W定位 (EX2)"}
        cfg.peripherals[#cfg.peripherals+1]={type="peer",id="eth_ex2",name="下游网口 (J15 LAN)"}
    else
        cfg.features.wifi=true
        net.type="wifi_airlink_spi"
    end
    cfg.network[#cfg.network+1]=net
    return cfg
end
return M
