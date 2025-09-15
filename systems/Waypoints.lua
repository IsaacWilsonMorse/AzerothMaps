-- Handle waypoint placement via Blizzard API or TomTom.
local AZEROTH_MAPS, AM = ...
local DBG = AM.DBG
local clamp01 = AM.clamp01

AM.LastTomTomUID = AM.LastTomTomUID or nil

local function centerWorldMap(mapID, x, y)
  C_Timer.After(0.05, function()
    pcall(function()
      if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
      if WorldMapFrame.SetMapID and mapID then WorldMapFrame:SetMapID(mapID) end
      local sc = WorldMapFrame.ScrollContainer
      if sc then
        local targetScale = sc.GetScaleForMaxZoom and sc:GetScaleForMaxZoom() or 1
        if sc.SetPanTarget then sc:SetPanTarget(x, y) end
        if sc.SetZoomTarget then sc:SetZoomTarget(targetScale, x, y) end
        if sc.SetNormalizedHorizontalScroll then sc:SetNormalizedHorizontalScroll(x) end
        if sc.SetNormalizedVerticalScroll then sc.SetNormalizedVerticalScroll(y) end
      end
    end)
  end)
end

local function setBlizzardNavigator(mapID, x, y, title)
  if not (C_Map and C_SuperTrack and C_Map.SetUserWaypoint and C_SuperTrack.SetSuperTrackedUserWaypoint) then
    return
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
    return
  end
  x, y = clamp01(x), clamp01(y)
  if not x or not y then return end
  local point
  pcall(function()
    if UiMapPoint and UiMapPoint.CreateFromCoordinates then
      point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    end
  end)
  if not point then
    point = { uiMapID = mapID, position = { x = x, y = y } }
  end
  pcall(function() C_Map.SetUserWaypoint(point) end)
  C_Timer.After(0.05, function()
    pcall(function() C_SuperTrack.SetSuperTrackedUserWaypoint(true) end)
  end)
  if AM.flashWorldMapPin and not (x == 0.5 and y == 0.5) then
    centerWorldMap(mapID, x, y)
  end
end

local function openMap(mapID)
  if WorldMapFrame and WorldMapFrame.SetMapID and mapID then
    if C_Map and not C_Map.GetMapInfo(mapID) then
      DBG("openMap: INVALID mapID=%s", tostring(mapID))
      return false
    end
    ShowUIPanel(WorldMapFrame)
    WorldMapFrame:SetMapID(mapID)
    DBG("WorldMap set to mapID=%d", mapID)
    return true
  end
  DBG("openMap: FAILED (mapID=%s)", tostring(mapID))
  return false
end

local function addTomTomWaypoint(mapID, x, y, title, startArrow)
  if not mapID or not x or not y then return nil end
  x, y = clamp01(x) or 0, clamp01(y) or 0
  title = title or "Waypoint"
  local uid
  if AM.useTomTom and TomTom then
    local opts = { title = title, persistent = false, from = "AzerothMaps" }
    local ok
    ok, uid = pcall(function() return TomTom:AddWaypoint(mapID, x, y, opts) end)
    if not ok or not uid then
      ok, uid = pcall(function() return TomTom:AddWaypoint(mapID, { x = x, y = y }, opts) end)
    end
    if ok and uid and startArrow then
      AM.LastTomTomUID = uid
      pcall(function() if TomTom.CancelCrazyArrow then TomTom:CancelCrazyArrow() end end)
      pcall(function() if TomTom.HideCrazyArrow    then TomTom:HideCrazyArrow()    end end)
      pcall(function() if TomTom.ClearCrazyArrow   then TomTom:ClearCrazyArrow()   end end)
      C_Timer.After(0.05, function()
        local armed = pcall(function() TomTom:SetCrazyArrow(uid, 10, title) end)
        if not armed then pcall(function() TomTom:SetCrazyArrow(uid, 10) end) end
        if TomTomCrazyArrow and not TomTomCrazyArrow:IsShown() then TomTomCrazyArrow:Show() end
      end)
    elseif not ok or not uid then
      DBG("|cff33ff99AzerothMaps|r: Could not add TomTom waypoint on map "..tostring(mapID))
    end
  elseif AM.useTomTom then
    DBG("|cff33ff99AzerothMaps|r: TomTom not loaded; cannot set waypoint/arrow.")
  end
  if AM.autoSupertrack then
    setBlizzardNavigator(mapID, x, y, title)
  end
  if AM.autoNavigate and AM.Navigate and AM.Navigate.PathTo then
    AM.Navigate.PathTo(mapID, x, y)
  end
  if AM.flashWorldMapPin and not (x == 0.5 and y == 0.5) then
    centerWorldMap(mapID, x, y)
  end
  return uid
end

local function openMapForFriend(rec)
  local unit = AM.friendUnitTokenByName(rec.name)
  DBG("|cff33ff99AzerothMaps|r: Opening map for friend "..rec.name.." ("..tostring(unit)..")")
  if unit then
    local mapID = C_Map.GetBestMapForUnit(unit)
    DBG("|cff33ff99AzerothMaps|r: Friend "..rec.name.." is at mapID "..tostring(mapID))
    if mapID then
      openMap(mapID)
      return
    end
  end
  -- Fallback: use rec.mapID and rec.area if available
  if rec.mapID then
    DBG("|cff33ff99AzerothMaps|r: Fallback to rec.mapID for "..rec.name.." (mapID="..tostring(rec.mapID)..")")
    openMap(rec.mapID)
    return
  elseif rec.area then
    DBG("|cff33ff99AzerothMaps|r: Fallback to rec.area for "..rec.name.." (area="..tostring(rec.area)..")")
    -- implement a lookup from area name to mapID
    local mapID = AM.findMapIDForAreaName(rec.area)
    if mapID then
      DBG("|cff33ff99AzerothMaps|r: Resolved mapID "..tostring(mapID).." for area: "..tostring(rec.area))
      openMap(mapID)
      return
    end
    DBG("|cff33ff99AzerothMaps|r: Could not resolve mapID for area: "..tostring(rec.area))
    return
  end
  DBG("|cff33ff99AzerothMaps|r: Could not resolve a map for "..rec.name)
end

local function openMapForRecordOnce(rec)
  DBG("|cff33ff99AzerothMaps|r: Opening map for record: "..(rec.name or "nil").." (type "..tostring(rec.type)..")")
  if rec.type == "bnet" then
    openMapForFriend(rec)
    return true
  end
  if rec.type == "poi" then
    -- Resolve mapID lazily (prefer the area name if available)
    local mapID = rec.mapID
    if not mapID then
      local areaName = rec.areaName
      if not areaName and _G.Areas and _G.Areas.recs and rec.areaID then
        local a = _G.Areas.recs[rec.areaID]
        areaName = a and a.name or nil
      end
      if areaName and AM.findMapIDForAreaName then
        mapID = AM.findMapIDForAreaName(areaName)
      end
      if not mapID and rec.continent and rec.wx and rec.wy and AM.findMapIDForCoords then
        mapID, areaName, rec.areaID = AM.findMapIDForCoords(rec.continent, rec.wx, rec.wy)
        if areaName and not rec.areaName then rec.areaName = areaName end
      end
      rec.mapID = mapID
    end
    if not mapID then
      DBG("|cff33ff99AzerothMaps|r: Could not resolve a map for POI "..tostring(rec.name))
      return false
    end
    local x, y
    if AM.WorldToMapXY and rec.continent and rec.wx and rec.wy then
      x, y = AM.WorldToMapXY(rec.continent, rec.wx, rec.wy, mapID)
      rec.x, rec.y = x, y
    else
      x, y = rec.x, rec.y
    end
    if not x or not y then
      x, y = 0.5, 0.5
    end
    openMap(mapID)
    addTomTomWaypoint(mapID, x, y, rec.name, true)
    return true
  end
  local mapID = rec.mapID
  local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) or nil
  DBG("openMapForRecord: map %s(%d), instanceLike=%s, hasInfo=%s", rec.name, mapID, tostring(AM.isInstanceLike(mapID)), tostring(info ~= nil))
  if not info or (AM.isInstanceLike(mapID) and not AM.preferInstanceMap) then
    local parentMapID, x, y = AM.findEntranceForInstance(mapID, rec.name)
    if parentMapID and x and y then
      openMap(parentMapID)
      addTomTomWaypoint(parentMapID, x, y, rec.name, true)
      return true
    end
    if info then
      openMap(mapID)
      addTomTomWaypoint(mapID, 0.5, 0.5, rec.name, true)
      return true
    else
      DBG("openMapForRecord: no map info for mapID=%s", tostring(mapID))
      return false
    end
  end
  openMap(mapID)
  -- If area coordinates are available on the record, drop a waypoint
  local x, y
  if AM.WorldToMapXY and rec.continent and rec.wx and rec.wy then
    x, y = AM.WorldToMapXY(rec.continent, rec.wx, rec.wy, mapID)
    rec.x, rec.y = x, y
  else
    x, y = rec.x, rec.y
  end
  if x and y then
    addTomTomWaypoint(mapID, x, y, rec.name, true)
    return true
  end
  if AM.isInstanceLike(mapID) and AM.preferInstanceMap then
    addTomTomWaypoint(mapID, 0.5, 0.5, rec.name, true)
    return true
  end
  -- Runtime fallback: scan POIs on this map to find a close match to the area name
  if rec.name then
    local function splitTokens(s)
      local t = {}
      for w in tostring(s or ""):gmatch("%w+") do t[#t+1] = w:lower() end
      return t
    end
    local function tokensMatch(s, toks)
      if #toks == 0 then return false end
      local hits = 0
      for _, tok in ipairs(toks) do if s:find(tok, 1, true) then hits = hits + 1 end end
      return hits >= math.max(1, math.ceil(#toks * 0.6))
    end
    local pois = AM.collectPOIsForMap and AM.collectPOIsForMap(mapID) or {}
    local toks = splitTokens(rec.name)
    for _, p in ipairs(pois) do
      local n = (p.name or ""):lower()
      if tokensMatch(n, toks) and p.x and p.y then
        addTomTomWaypoint(mapID, p.x, p.y, rec.name, true)
        return true
      end
    end
  end
  return true
end

local function openMapForRecord(rec)
  local list = { rec }
  if rec.candidates then
    for _, c in ipairs(rec.candidates) do list[#list+1] = c end
  end
  for _, r in ipairs(list) do
    if openMapForRecordOnce(r) then return end
  end
  DBG("openMapForRecord: could not resolve map for %s", tostring(rec.name))
end

AM.openMap = openMap
AM.addTomTomWaypoint = addTomTomWaypoint
AM.setBlizzardNavigator = setBlizzardNavigator
AM.centerWorldMap = centerWorldMap
AM.openMapForRecord = openMapForRecord
AM.openMapForFriend = openMapForFriend
