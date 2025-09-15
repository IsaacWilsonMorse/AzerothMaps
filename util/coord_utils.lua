-- World to map coordinate conversion helpers.
local AZEROTH_MAPS, AM = ...
local clamp01 = AM and AM.clamp01 or function(v)
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end

local function WorldToMapXY(continentMapID, wx, wy, uiMapID)
  if continentMapID and C_Map and C_Map.GetMapPosFromWorldPos then
    local ok, mapID, res = pcall(function()
      return C_Map.GetMapPosFromWorldPos(continentMapID, { x = wx, y = wy }, uiMapID)
    end)
    if ok and type(res) == "table" and res.x and res.y then
      return clamp01(res.x), clamp01(res.y)
    end
  end
  return nil, nil
end

AM.WorldToMapXY = WorldToMapXY
return WorldToMapXY

