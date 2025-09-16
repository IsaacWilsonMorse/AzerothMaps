-- Fallback helpers for locating instance entrances without live data.
local AZEROTH_MAPS, AM = ...

local AM_OFF = _G.AzerothMapsOffline or {}

local WorldToMapXY = AM.WorldToMapXY or function() return nil, nil end

local function _am_findOfflineEntrance(instanceMapID, instanceName, candidateParents)
  if not (AM_OFF and AM_OFF.recs) then return nil, nil, nil end
  local tokens = {}
  for w in tostring(instanceName or ""):gmatch("%w+") do tokens[#tokens+1] = w:lower() end

  local function tokensMatch(s, toks)
    if #toks == 0 then return false end
    local hits = 0
    for _, tok in ipairs(toks) do if s:find(tok, 1, true) then hits = hits + 1 end end
    return hits >= math.max(1, math.ceil(#toks * 0.6))
  end

  for id, rec in pairs(AM_OFF.recs) do
    if rec.name_l and tokensMatch(rec.name_l, tokens) then
      for _, parent in ipairs(candidateParents) do
        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo then
          local poi = C_AreaPoiInfo.GetAreaPOIInfo(parent, id)
          if poi and poi.position and poi.position.x and poi.position.y then
            return parent, poi.position.x, poi.position.y
          end
        end
        local x, y = WorldToMapXY(rec.continent, rec.wx, rec.wy, parent)
        if x and y then
          return parent, x, y
        end
      end
    end
  end
  return nil, nil, nil
end

AM.AM_OFF = AM_OFF
AM._am_findOfflineEntrance = _am_findOfflineEntrance
-- Backwards compatibility: expose under old name
AM._am_worldToMapXY = WorldToMapXY

return AM_OFF
