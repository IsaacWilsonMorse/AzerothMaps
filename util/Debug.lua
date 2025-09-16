-- Debug helpers and clamp utilities.
local AZEROTH_MAPS, AM = ...
local DBG = AM.DBG

local function clamp01(v)
  if type(v) ~= "number" then return nil end
  if v < 0 then return 0 elseif v > 1 then return 1 else return v end
end

AM.clamp01 = clamp01
AM.DBG = DBG

return DBG, clamp01
