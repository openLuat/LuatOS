PROJECT = "PINBALL"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "pinball_win"
sys.publish("OPEN_PINBALL_WIN")
if pinball_open then
    pinball_open()
end

sys.run()
