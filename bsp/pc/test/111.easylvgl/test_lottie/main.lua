-- Button 组件测试脚本
PROJECT = "easylvgl"
VERSION = "1.0.0"
-- 初始化屏幕
easylvgl.init(320, 480, easylvgl.COLOR_FORMAT_RGB565)

sys.taskInit(function()
    -- 创建动画
    local anim = easylvgl.lottie({
        x = 60, y = 20, w = 180, h = 180,
        src = "/luadb/cloud_loading.json",
        loop = true,
        speed = 0.8,
        on_ready = function()
            anim:play()
        end,
        on_complete = function()
            log.info("lottie", "播放完成")
        end,
    })

    while true do
        easylvgl.refresh()
        sys.wait(10)
    end
end)

sys.run()