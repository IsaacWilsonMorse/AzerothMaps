-- Resolve player and target positions and emit navigation waypoints.
local AZEROTH_MAPS, AM = ...

local DBG = AM and AM.DBG or function() end
local Navigate = {}

local function clamp01(v)
  if AM and AM.clamp01 then return AM.clamp01(v) end
  if v == nil then return v end
  if v < 0 then return 0 elseif v > 1 then return 1 else return v end
end

function Navigate.ResolvePlayer()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    DBG("ResolvePlayer: missing C_Map API")
    return nil
  end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then DBG("ResolvePlayer: no mapID") return nil end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  local x = pos and pos.x or 0.5
  local y = pos and pos.y or 0.5
  DBG("ResolvePlayer: map=%s x=%.3f y=%.3f", tostring(mapID), x, y)
  return mapID, x, y
end

local function resolveMapByName(name)
  if not name or name == "" then return nil end
  name = name:lower()
  if AM and AM.searchMaps then
    local res = AM.searchMaps(name)
    if res and res[1] then
      DBG("resolveMapByName(%q) -> %d via searchMaps", name, res[1].mapID)
      return res[1].mapID
    end
  end
  if C_Map and C_Map.GetMapInfo then
    for id = 1, 10000 do
      local info = C_Map.GetMapInfo(id)
      if info and info.name and info.name:lower():find(name, 1, true) then
        DBG("resolveMapByName(%q) -> %d via C_Map", name, id)
        return id
      end
    end
  end
  DBG("resolveMapByName(%q) failed", name)
  return nil
end

function Navigate.ResolveTarget(query)
  DBG("ResolveTarget(%q)", tostring(query))
  if not query or query == "" then return nil end
  query = query:match("^%s*(.-)%s*$")
  local name, xs, ys = query:match("^(.-)%s+(%d+%.?%d*)%s*,%s*(%d+%.?%d*)$")
  if name then
    local mapID = resolveMapByName(name) or tonumber(name)
    if not mapID then DBG("ResolveTarget: could not map '%s'", name) return nil end
    local x = tonumber(xs) / 100
    local y = tonumber(ys) / 100
    DBG("ResolveTarget: %d @ %.3f, %.3f", mapID, x, y)
    return mapID, x, y
  else
    local mapID = tonumber(query) or resolveMapByName(query)
    if not mapID then DBG("ResolveTarget: could not map '%s'", query) return nil end
    DBG("ResolveTarget: %d @ center", mapID)
    return mapID, 0.5, 0.5
  end
end

function Navigate.SetPathWaypoints(nodes)
  if not nodes or #nodes == 0 then
    DBG("SetPathWaypoints: missing nodes")
    return
  end
  DBG("SetPathWaypoints: %d node(s)", #nodes)
  if AM and AM.addTomTomWaypoint and AM.useTomTom then
    if TomTom and TomTom.ClearWaypoints then
      pcall(function() TomTom:ClearWaypoints() end)
    end
    local old = AM.autoNavigate
    AM.autoNavigate = false
    for i = 2, #nodes do
      local n = nodes[i]
      local x, y = clamp01(n.x), clamp01(n.y)
      DBG("  waypoint %d: map=%s x=%.3f y=%.3f", i - 1, tostring(n.mapID), x or -1, y or -1)
      DBG("    (from %s)", tostring(nodes[i - 1] and nodes[i - 1].mapID or "nil"))
      DBG("    (to   %s)", tostring(nodes[i] and nodes[i].mapID or "nil"))
      pcall(function()
        AM.addTomTomWaypoint(n.mapID, x, y, "AzerothMaps step " .. (i - 1), i == 2)
      end)
    end
    AM.autoNavigate = old
    return
  end
  if C_Map and C_Map.SetUserWaypoint and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
    local n = nodes[#nodes]
    local x, y = clamp01(n.x), clamp01(n.y)
    DBG("  blizzard waypoint: map=%s x=%.3f y=%.3f", tostring(n.mapID), x or -1, y or -1)
    local point
    local ok = pcall(function()
      if UiMapPoint and UiMapPoint.CreateFromCoordinates then
        point = UiMapPoint.CreateFromCoordinates(n.mapID, x, y)
      end
    end)
    if not ok or not point then
      point = { uiMapID = n.mapID, position = { x = x, y = y } }
    end
    pcall(function() C_Map.SetUserWaypoint(point) end)
    pcall(function() C_SuperTrack.SetSuperTrackedUserWaypoint(true) end)
  else
    DBG("SetPathWaypoints: no TomTom or C_Map API")

  end
end

local function resolveMapID(id)
  if AM and AM.Pathfinder and AM.Pathfinder.ResolveMapID then
    return AM.Pathfinder.ResolveMapID(id)
  end
  return id
end

function Navigate.PathTo(destMapID, dx, dy)
  DBG("PathTo: dest=%s x=%.3f y=%.3f", tostring(destMapID), dx or -1, dy or -1)
  if not destMapID or dx == nil or dy == nil then return nil end
  local startMapID, sx, sy = Navigate.ResolvePlayer()
  destMapID = resolveMapID(destMapID)
  startMapID = resolveMapID(startMapID)
  DBG("PathTo: resolved start=%s dest=%s", tostring(startMapID), tostring(destMapID))
  if not startMapID then DBG("PathTo: could not resolve player") return nil end
  if not AM.pathGraph and AM.Pathfinder and Portals then
    DBG("PathTo: building graph")
    AM.pathGraph = AM.Pathfinder.BuildGraph(Portals)
  end
  if not (AM.Pathfinder and AM.pathGraph) then DBG("PathTo: missing Pathfinder or graph") return nil end
  DBG("PathTo: start nodes=%d dest nodes=%d",
    #(AM.pathGraph.byMap[startMapID] or {}), #(AM.pathGraph.byMap[destMapID] or {}))
  local path = AM.Pathfinder.ShortestPath(AM.pathGraph,
    { mapID = startMapID, x = sx, y = sy },
    { mapID = destMapID, x = dx, y = dy })
  DBG("PathTo: path length %d", path and #path or 0)
  if path and #path > 0 then
    if AM.Pathfinder and AM.Pathfinder.CollapsePath then
      path = AM.Pathfinder.CollapsePath(AM.pathGraph, path)
      DBG("PathTo: collapsed path length %d", #path)
    end
    Navigate.SetPathWaypoints(path)
    return path
  end
  if AM.Pathfinder and AM.Pathfinder.DebugPath then
    AM.Pathfinder.DebugPath(AM.pathGraph, startMapID, destMapID)
  end
  return nil
end

AM.ResolvePlayer = Navigate.ResolvePlayer
AM.ResolveTarget = Navigate.ResolveTarget
AM.SetPathWaypoints = Navigate.SetPathWaypoints
AM.NavigateTo = Navigate.PathTo
AM.Navigate = Navigate

return Navigate
