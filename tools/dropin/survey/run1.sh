#!/bin/bash
# Paths below are for this PC (~/wt/mame_survey runs, ~/wt/mame_cov/tmscov build); edit them to repeat elsewhere.
# The counter patch for MAME 0.282 is kept outside this repo (it carries MAME source lines).
# One survey run: counting MAME (measurement build), headless, isolated cfg/nvram.
SET=$1; OUT=/home/midihex/wt/mame_survey/runs/$SET
mkdir /home/midihex/wt/mame_survey/runs/$SET.lock 2>/dev/null || exit 0   # another runner has it
mkdir -p $OUT/.mame/cfg $OUT/.mame/nvram $OUT/.mame/state $OUT/snap
printf 'skip_warnings 1\n' > $OUT/ui.ini
cp /home/midihex/wt/mame_survey/play.lua $OUT/
cd $OUT
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 40m /home/midihex/wt/mame_cov/tmscov $SET -rompath /mnt/c/roms/Mame \
  -autoboot_script play.lua -str 299 -skip_gameinfo -nothrottle -sound none -video none \
  -cfg_directory .mame/cfg -nvram_directory .mame/nvram -state_directory .mame/state \
  -snapshot_directory snap -nowriteconfig > mame.log 2>&1 &
PID=$!
# Some sets spin in shutdown after the counters are dumped: stop them 60 s after MAME's end-of-run line.
while kill -0 $PID 2>/dev/null; do
  if grep -q "Average speed" mame.log && ls tmscov*.txt >/dev/null 2>&1; then
    sleep 60; kill -0 $PID 2>/dev/null && { echo "stopped after end-of-run" >> mame.log; pkill -P $PID; kill $PID; }
    break
  fi
  sleep 10
done
wait $PID
echo "$SET exit $? $(ls tmscov*.txt 2>/dev/null | tr '\n' ' ')" >> /home/midihex/wt/mame_survey/done.txt
