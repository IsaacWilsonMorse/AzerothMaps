-- Slash command handlers for debug and POI lookups.
local AZEROTH_MAPS, AM = ...
local mapName = AM.mapName

SLASH_AMDEBUG1 = "/amdebug"
SlashCmdList["AMDEBUG"] = function(msg)
  msg = (msg or ""):lower()
  if msg == "on" then
    AM.debug = true
  elseif msg == "off" then
    AM.debug = false
  else
    AM.debug = not AM.debug
  end
  print(("|cff33ff99AzerothMaps|r: Debug %s"):format(AM.debug and "ON" or "OFF"))
end

SLASH_AMENTRANCE1 = "/amentrance"
SlashCmdList["AMENTRANCE"] = function(msg)
  local q = (msg or ""):match("^%s*(.-)%s*$")
  if q == "" then
    print("|cff33ff99AzerothMaps|r: Usage: /amentrance <map name|id>")
    return
  end
  local targetID
  if tonumber(q) then
    targetID = tonumber(q)
  else
    local res = AM.searchMaps(q)
    if #res > 0 then targetID = res[1].mapID end
  end
  if not targetID then
    print("|cff33ff99AzerothMaps|r: Could not resolve a map for "..q)
    return
  end
  local info = C_Map.GetMapInfo(targetID)
  local name = info and info.name or q
  print(("|cff33ff99AzerothMaps|r: Testing entrance for %s(%d)"):format(name, targetID))
  local parent, x, y = AM.findEntranceForInstance(targetID, name)
  if parent and x and y then
    print(("  Entrance: %s(%d) @ %.3f, %.3f"):format(mapName(parent), parent, x, y))
    AM.openMap(parent)
    AM.addTomTomWaypoint(parent, x, y, name .. " (Entrance)", true)
  else
    print("  No entrance POI found.")
  end
end

SLASH_AMSCAN1 = "/amscan"
SlashCmdList["AMSCAN"] = function(msg)
  local q = (msg or ""):match("^%s*(.-)%s*$")
  if q == "" then
    print("|cff33ff99AzerothMaps|r: Usage: /amscan <map name|id>")
    return
  end
  local targetID
  if tonumber(q) then
    targetID = tonumber(q)
  else
    local res = AM.searchMaps(q)
    if #res > 0 then targetID = res[1].mapID end
  end
  if not targetID then
    print("|cff33ff99AzerothMaps|r: Could not resolve a map for "..q)
    return
  end
  print(("|cff33ff99AzerothMaps|r: Scanning %s(%d)..."):format(mapName(targetID), targetID))
  local pois = AM.collectPOIsForMap(targetID)
  for i, p in ipairs(pois) do
    print(string.format("  %02d) [%s] %s  (%.3f, %.3f)%s", i, p.kind, p.name, p.x or -1, p.y or -1, p.atlas and ("  atlas="..p.atlas) or ""))
  end
  print(("Total: %d POIs"):format(#pois))
end

SLASH_AMMARK1 = "/ammarkentrance"
SlashCmdList["AMMARKENTRANCE"] = function(msg)
  local a,b,x,y = msg:match("^%s*(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s*$")
  if not a then
    print("|cff33ff99AzerothMaps|r: Usage: /ammarkentrance <instanceMapID> <parentMapID> <x> <y>")
    return
  end
  a, b, x, y = tonumber(a), tonumber(b), tonumber(x), tonumber(y)
  AM.entranceOverrides[a] = { b, x, y }
  print(string.format("|cff33ff99AzerothMaps|r: Override saved for %s(%d) -> %s(%d) @ %.3f, %.3f", mapName(a), a, mapName(b), b, x, y))
end

SLASH_AMPINS1 = "/ampins"
SlashCmdList["AMPINS"] = function(msg)
  local q = (msg or ""):match("^%s*(.-)%s*$")
  if q == "" then print("|cff33ff99AzerothMaps|r: Usage: /ampins <map name|id>"); return end
  local targetID = tonumber(q)
  if not targetID then
    local res = AM.searchMaps(q); if #res > 0 then targetID = res[1].mapID end
  end
  if not targetID then print("|cff33ff99AzerothMaps|r: Could not resolve map for "..q); return end
  C_Map.RequestPreloadMap(targetID)
  WorldMapFrame:SetMapID(targetID)
  C_Timer.After(0.1, function()
    print(("|cff33ff99AzerothMaps|r: Pins on %s(%d):"):format(mapName(targetID), targetID))
    local count = 0
    WorldMapFrame:ExecuteOnAllPins(function(pin)
      count = count + 1
      local template = rawget(pin, "pinTemplate") or (pin.GetDebugName and pin:GetDebugName()) or pin:GetObjectType()
      local name = rawget(pin, "name") or (pin.Title and pin.Title.GetText and pin.Title:GetText()) or ""
      local areaPoiID = rawget(pin, "areaPoiID")
      local poiID = rawget(pin, "poiID")
      print(("  %02d) %s  name=%s  areaPoiID=%s  poiID=%s"):format(count, tostring(template), tostring(name), tostring(areaPoiID or ""), tostring(poiID or "")))
    end)
    print(("Total pins: %d"):format(count))
  end)
end

SLASH_AMGO1 = "/amgo"
SlashCmdList["AMGO"] = function(msg)
  local q = (msg or ""):match("^%s*(.-)%s*$")
  if q == "" then
    print("|cff33ff99AzerothMaps|r: Usage: /amgo <map name|id>")
    return
  end
  local rec
  local asID = tonumber(q)
  if asID then
    local info = C_Map.GetMapInfo(asID)
    if info and info.name then rec = { type="map", mapID = asID, name = info.name } end
  else
    local res = AM.searchMaps(q)
    if #res > 0 then rec = res[1] end
  end
  if not rec then
    print("|cff33ff99AzerothMaps|r: Could not resolve a map for "..q)
    return
  end
  AM.openMapForRecord(rec)
end

SLASH_AMARROW1 = "/amarrow"
SlashCmdList["AMARROW"] = function()
  if not AM.useTomTom or not TomTom or not AM.LastTomTomUID then
    print("|cff33ff99AzerothMaps|r: No recent waypoint to re-arm.")
    return
  end
  pcall(function() if TomTom.CancelCrazyArrow then TomTom:CancelCrazyArrow() end end)
  C_Timer.After(0.05, function()
    pcall(function() TomTom:SetCrazyArrow(AM.LastTomTomUID, 10) end)
    if TomTomCrazyArrow and not TomTomCrazyArrow:IsShown() then TomTomCrazyArrow:Show() end
    print("|cff33ff99AzerothMaps|r: Arrow refreshed.")
  end)
end

SLASH_AMNAV1 = "/amnavigator"
SlashCmdList["AMNAV"] = function(msg)
  local arg = (msg or ""):lower():match("^%s*(%S*)")
  if arg == "on" or arg == "1" or arg == "true" then
    AM.autoSupertrack = true
  elseif arg == "off" or arg == "0" or arg == "false" then
    AM.autoSupertrack = false
  end
  print(("|cff33ff99AzerothMaps|r: Blizzard navigator is %s."):format(AM.autoSupertrack and "ON" or "OFF"))
end

-- /amconfig: open the options panel
SLASH_AMCONFIG1 = "/amconfig"
SlashCmdList["AMCONFIG"] = function()
  if AM.OpenConfig then AM.OpenConfig() end
end

-- /amsolve [UiMapID] [WX WY]
-- Examples:
--   /amsolve                 -- use current map and your current world pos
--   /amsolve 2273            -- use map 2273 and your current world pos
--   /amsolve 2273 1600 1900  -- use map 2273 and world point (1600,1900)

SLASH_AMSOLVE1 = "/amsolve"
SlashCmdList["AMSOLVE"] = function(msg)
  local function p(...) print("|cff33ff99AzerothMaps|r:", ...) end
  local id, wx, wy = msg:match("^%s*(%d+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
  local onlyID = msg:match("^%s*(%d+)%s*$")

  local uiMapID
  if id then
    uiMapID = tonumber(id); wx, wy = tonumber(wx), tonumber(wy)
  elseif onlyID then
    uiMapID = tonumber(onlyID)
  else
    uiMapID = C_Map.GetBestMapForUnit("player")
  end

  if not wx or not wy then
    wx, wy = UnitPosition("player")
  end

  if not uiMapID or not wx or not wy then
    p("Usage: /amsolve [UiMapID] [WX WY]")
    return
  end

  -- Basis points for the map
  local _, origin = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(0,0))
  local _, east   = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(1,0))
  local _, north  = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(0,1))
  if not (origin and east and north) then
    p("Could not get basis points for map", uiMapID)
    return
  end

  -- Build basis
  local basisXx, basisXy = east.x - origin.x, east.y - origin.y
  local basisYx, basisYy = north.x - origin.x, north.y - origin.y
  local relX, relY       = wx - origin.x, wy - origin.y
  local det = basisXx*basisYy - basisXy*basisYx
  if det == 0 then
    p("Degenerate basis (det=0)")
    return
  end
  local uiX = ( relX*basisYy - relY*basisYx) / det
  local uiY = ( basisXx*relY - basisXy*relX) / det

  -- Reproject back for error check
  local checkX = origin.x + uiX*basisXx + uiY*basisYx
  local checkY = origin.y + uiX*basisXy + uiY*basisYy
  local err = math.sqrt((checkX-wx)^2 + (checkY-wy)^2)

  local info = C_Map.GetMapInfo(uiMapID)
  local mapName = info and info.name or "?"

  -- Print each variable on a new line for easy copying
  p(("MapName=%s"):format(mapName))
  p(("MapID=%d"):format(uiMapID))
  p(("OriginX=%.3f"):format(origin.x))
  p(("OriginY=%.3f"):format(origin.y))
  p(("EastX=%.3f"):format(east.x))
  p(("EastY=%.3f"):format(east.y))
  p(("NorthX=%.3f"):format(north.x))
  p(("NorthY=%.3f"):format(north.y))
  p(("WorldX=%.3f"):format(wx))
  p(("WorldY=%.3f"):format(wy))
  p(("UIX=%.4f"):format(uiX))
  p(("UIX=%.2f%%"):format(uiX*100))
  p(("UIY=%.4f"):format(uiY))
  p(("UIY=%.2f%%"):format(uiY*100))
  p(("CheckWorldX=%.3f"):format(checkX))
  p(("CheckWorldY=%.3f"):format(checkY))
  p(("Error=%.3f yds"):format(err))

end

SLASH_AZEROTHMAPS1 = "/azerothmaps"
SlashCmdList["AZEROTHMAPS"] = function(msg)
  local destMap, dx, dy = AM.ResolveTarget(msg or "")
  AM.DBG("/azerothmaps resolved -> map=%s x=%s y=%s", tostring(destMap), tostring(dx), tostring(dy))
  if not destMap then
    print("|cff33ff99AzerothMaps|r: Could not resolve destination.")
    return
  end
  local path
  if AM.Navigate and AM.Navigate.PathTo then
    path = AM.Navigate.PathTo(destMap, dx, dy)
  end
  if path and #path > 0 then
    print(("|cff33ff99AzerothMaps|r: Path with %d step(s) set."):format(#path))
  else
    print("|cff33ff99AzerothMaps|r: No path found.")
  end
end
