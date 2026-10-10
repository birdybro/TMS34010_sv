-- Game survey: attract mode, then coin/start and random player inputs. Measurement only.
local f = 0
local ATTRACT = 90*60          -- frames of attract before the first coin
local ENDF = 295*60
local seed = 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed end
local fields = nil
local coin, start1, start2 = {}, {}, {}
local players = {}
local analogs = {}
local function scan()
  fields = {}
  for _,p in pairs(manager.machine.ioport.ports) do
    for n,fl in pairs(p.fields) do
      local ln = n:lower()
      if ln:match("^coin 1") or ln == "coin 1" then table.insert(coin, fl)
      elseif ln:match("1 player start") or ln:match("^p1 start") or ln:match("^start 1") or ln:match("^1p start") then table.insert(start1, fl)
      elseif ln:match("2 players start") or ln:match("^p2 start") or ln:match("^start 2") then table.insert(start2, fl)
      elseif (ln:match("^p1 ") or ln:match("^p2 ")) then
        if fl.is_analog then table.insert(analogs, fl) else table.insert(players, fl) end
      end
    end
  end
end
local function setall(t, v) for _,fl in ipairs(t) do fl:set_value(v) end end
function tick()
  f = f + 1
  if f == 2 then scan() end
  if f > ATTRACT then
    local k = (f - ATTRACT) % 3000
    setall(coin, (k >= 0 and k < 8) and 1 or 0)
    setall(start1, (k >= 120 and k < 128) and 1 or 0)
    setall(start2, (k >= 200 and k < 208 and (f - ATTRACT) % 6000 >= 3000) and 1 or 0)
    if k > 300 and f % 8 == 0 then
      for _,fl in ipairs(players) do fl:set_value((rnd() % 4 == 0) and 1 or 0) end
      for _,fl in ipairs(analogs) do fl:set_value(fl.minvalue + rnd() % (fl.maxvalue - fl.minvalue + 1)) end
    end
  end
  if f % 3600 == 0 then manager.machine.video:snapshot() end
  if f == ENDF then manager.machine:exit() end
end
g_sub = emu.add_machine_frame_notifier(tick)
