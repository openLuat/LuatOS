
print(_VERSION)
print("from main.lua file")

rtos.timer_start(1, 3000)
local t = 1
while 1 do
    rtos.receive(0)
    print("timer trigger, 3000ms" .. tostring(t))
    t = t + 1
    rtos.timer_stop(1)
    rtos.timer_start(1, 3000)
end
