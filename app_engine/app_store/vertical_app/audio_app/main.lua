PROJECT = "AUDIO_APP"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "audio_main_win"
require "audio_play_win"
sys.publish("OPEN_AUDIO_WIN")
if audio_open then
    audio_open()
end

sys.run()
