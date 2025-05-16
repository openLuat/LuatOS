local libnet = require "libnet"
local GC032A_InitReg =
{
	zbar_scan = 0,--是否为扫码
    draw_lcd = 0,--是否向lcd输出
    i2c_id = 0,
	i2c_addr = 0x21,
    pwm_id = 5;
    pwm_period  = 24*1000*1000,
    pwm_pulse = 0,
	sensor_width = 640,
	sensor_height = 480,
    color_bit = 16,
	init_cmd = "/luadb/GC032A_InitReg.txt"--此方法将初始化指令写在外部文件,支持使用 # 进行注释

}
local MSG_NEW = "DataNew"  -- 新的一帧到来
local camera_pwdn = gpio.setup(pin.PD06, 1, gpio.PULLUP) -- PD06 camera_pwdn引脚
local camera_rst = gpio.setup(pin.PD07, 1, gpio.PULLUP) -- PD07 camera_rst引脚
local taskName = "CAM_TASK"

camera.on(0, "scanned", function(id, str)
    if type(str) == 'number' then   --说明已经采集完成1fps，可以通知处理任务进行处理了
        sys_send(taskName, MSG_NEW, str)
        --camera.getRaw(0)  --如果不想处理，纯粹看速度的，打开这行，上报速度为15fps
    elseif str == true then
    	log.info("拍照完成")
    elseif str == false then
        log.error("摄像头没有数据")
    end
end)


local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end
--标注必要的是摄像头采集原始数据必须的操作
local function camTask(ip, port)
	camera_rst(0)  --必要的
	local camera_id = camera.init(GC032A_InitReg) --必要的
    local w,h = 320,240
    local cbuff = zbuff.create(w * h *2)--必要的
    local blen = w * 16 * 2
    local tx_buff = zbuff.create(blen + 16)
	local netc 
	local result, param, is_err, rIP, rPort, vlen, start
    netc = socket.create(socket.ETH0, taskName)
    --socket.debug(netc, true)
    socket.config(netc, nil, true)
    result = libnet.waitLink(taskName, 0, netc)
    camera.startRaw(camera_id, w, h, cbuff)--必要的
    log.info("摄像头启动完成")
    while true do
        result = libnet.waitLink(taskName, 0, netc)
		result = libnet.connect(taskName, 5000, netc, ip, port)
        log.info(result, ip, port)
        while result do
            result = sys_wait(taskName, MSG_NEW, 200)--这个等采集完成的消息，当然不限于这个形式
            if type(result) == 'table' then --收到采集完成的消息后，就可以开始上传了，无论何种方法，只要把所有图像数据按照顺序上传即可
                vlen = 0
                start = 0
                while result and vlen < h do
                    tx_buff:del()
                    tx_buff:pack("<AHHIHH", "VCAM", w, h, vlen, blen, blen) --加入一个包头方便重新合成图片，当然也可以自己定义协议，无限制
                    tx_buff:copy(nil, cbuff, start, blen)
                    start = start + blen
                    if (vlen + 16) >= h then
                        camera.getRaw(0)
                    end
                    result = libnet.tx(taskName, 100, netc, tx_buff)
                    vlen = vlen + 16
                end
                log.info("发送完成")
            else
                camera.getRaw(0)
                result = true
            end
        end
        libnet.close(taskName, 5000, netc)
		log.info(rtos.meminfo("sys"))
		sys.wait(1000)
    end
end

function camDemo(ip, port)
	sysplus.taskInitEx(camTask, taskName, netCB, ip, port)
end