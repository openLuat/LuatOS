PROJECT = "PIANO"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "piano_win"
sys.publish("OPEN_PIANO_WIN")
if piano_open then
    piano_open()
end

sys.run()
