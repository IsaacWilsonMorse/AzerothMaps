-- Pathfinding utilities that build a graph from portal data.
local AZEROTH_MAPS, AM = ...

local Pathfinder = {}
local DBG = AM and AM.DBG or function() end

local W_PORTAL = 0.1
local W_MOVE = 100
local K_NEAREST = 32

local allowedKinds = {
  area_trigger = true,
  lfg_entrance = true,
  ui_parent = true,
  ui_link = true,
  seamless_edge = true,
  instance_portal = true,
}

local function nodeKey(map, x, y)
  return string.format("%d:%.4f:%.4f", map, x, y)
end

local function euclid(a, b)
  local dx = (a.x - b.x)
  local dy = (a.y - b.y)
  return math.sqrt(dx * dx + dy * dy)
end

local function resolveMapID(rec)
  -- Prefer the uiMapID when available; fall back to any explicit mapID/map_id.
  if not rec then return nil end
  if rec.uimap then return rec.uimap end
  if rec.mapID then return rec.mapID end
  if rec.map_id then return rec.map_id end
  return nil
end

-- expose resolver so callers (e.g. Navigate.PathTo) can normalise ids
function Pathfinder.ResolveMapID(id)
  local res
  if type(id) == "table" then
    res = resolveMapID(id)
  else
    res = resolveMapID({ uimap = id })
  end
  DBG("ResolveMapID(%s) -> %s", tostring(id), tostring(res))
  return res
end

function Pathfinder.BuildGraph(Portals)
  local graph = { nodes = {}, byMap = {} }
  if not Portals or not Portals.recs then return graph end
  for rid, rec in pairs(Portals.recs) do
    local src = rec.src
    local dst = rec.dst
    local fm = resolveMapID(src)
    local tm = resolveMapID(dst)
    if allowedKinds[rec.kind]
       and src and fm
       and dst and tm then
      local fx, fy = 0.5, 0.5
      if AM.WorldToMapXY and (src.map_id or src.mapID) and src.wx and src.wy then
        local x, y = AM.WorldToMapXY(src.map_id or src.mapID, src.wx, src.wy, src.uimap or fm)
        if x and y then fx, fy = x, y end
      end
      local tx, ty = 0.5, 0.5
      if AM.WorldToMapXY and (dst.map_id or dst.mapID) and dst.wx and dst.wy then
        local x, y = AM.WorldToMapXY(dst.map_id or dst.mapID, dst.wx, dst.wy, dst.uimap or tm)
        if x and y then tx, ty = x, y end
      end
      local fk = nodeKey(fm, fx, fy)
      local tk = nodeKey(tm, tx, ty)
      local fromNode = graph.nodes[fk]
      if not fromNode then
        fromNode = { mapID = fm, x = fx, y = fy, edges = {} }
        graph.nodes[fk] = fromNode
        graph.byMap[fm] = graph.byMap[fm] or {}
        table.insert(graph.byMap[fm], fromNode)
      end
      local toNode = graph.nodes[tk]
      if not toNode then
        toNode = { mapID = tm, x = tx, y = ty, edges = {} }
        graph.nodes[tk] = toNode
        graph.byMap[tm] = graph.byMap[tm] or {}
        table.insert(graph.byMap[tm], toNode)
      end
      table.insert(fromNode.edges, { node = toNode, weight = W_PORTAL, kind = rec.kind, recID = rid })
      -- automatically add reverse edges for seamless transitions
      if rec.kind == "seamless_edge" or rec.kind == "ui_parent" or rec.kind == "ui_link" then
        table.insert(toNode.edges, { node = fromNode, weight = W_PORTAL, kind = rec.kind, recID = rid })
      end
    end
  end
  -- connect portals on the same map for walking between them
  for _, nodes in pairs(graph.byMap) do
    for i, a in ipairs(nodes) do
      local cand = {}
      for j, b in ipairs(nodes) do
        if i ~= j then
          local d = euclid(a, b)
          table.insert(cand, { node = b, d = d })
        end
      end
      table.sort(cand, function(u, v) return u.d < v.d end)
      for k = 1, math.min(K_NEAREST, #cand) do
        local c = cand[k]
        table.insert(a.edges, { node = c.node, weight = c.d * W_MOVE, kind = "move" })
      end
    end
  end
  return graph
end

local function pqPush(pq, node, cost)
  local item = { node = node, cost = cost }
  local i = #pq + 1
  pq[i] = item
  while i > 1 do
    local parent = math.floor(i / 2)
    if pq[parent].cost <= item.cost then break end
    pq[i] = pq[parent]
    pq[parent] = item
    i = parent
  end
end

local function pqPop(pq)
  local root = pq[1]
  local last = table.remove(pq)
  if #pq > 0 then
    pq[1] = last
    local i = 1
    while true do
      local left = i * 2
      local right = left + 1
      local smallest = i
      if left <= #pq and pq[left].cost < pq[smallest].cost then smallest = left end
      if right <= #pq and pq[right].cost < pq[smallest].cost then smallest = right end
      if smallest == i then break end
      pq[i], pq[smallest] = pq[smallest], pq[i]
      i = smallest
    end
  end
  return root.node, root.cost
end

function Pathfinder.ShortestPath(graph, start, goal)
  if not graph or not start or not goal then return {} end
  local K = K_NEAREST
  local startNode = { mapID = start.mapID, x = start.x, y = start.y, edges = {} }
  local goalNode  = { mapID = goal.mapID,  x = goal.x,  y = goal.y,  edges = {} }

  local candidates = {}
  for _, node in ipairs(graph.byMap[start.mapID] or {}) do
    local d = euclid(startNode, node)
    table.insert(candidates, { node = node, d = d })
  end
  table.sort(candidates, function(a,b) return a.d < b.d end)
  for i=1, math.min(K, #candidates) do
    local c = candidates[i]
    table.insert(startNode.edges, { node = c.node, weight = c.d * W_MOVE, kind = "move" })
  end
  if start.mapID == goal.mapID then
    local d = euclid(startNode, goalNode)
    table.insert(startNode.edges, { node = goalNode, weight = d * W_MOVE, kind = "move" })
  end

  local added = {}
  for _, node in ipairs(graph.byMap[goal.mapID] or {}) do
    local d = euclid(node, goalNode)
    local e = { node = goalNode, weight = d * W_MOVE, kind = "move" }
    table.insert(node.edges, e)
    table.insert(added, { node = node, edge = e })
  end

  local dist, prev = {}, {}
  dist[startNode] = 0
  local pq = {}
  pqPush(pq, startNode, 0)

  while #pq > 0 do
    local u, cost = pqPop(pq)
    if cost > (dist[u] or math.huge) then
      -- skip stale entry
    else
      if u == goalNode then break end
      for _, e in ipairs(u.edges) do
        local alt = cost + e.weight
        if alt < (dist[e.node] or math.huge) then
          dist[e.node] = alt
          prev[e.node] = u
          pqPush(pq, e.node, alt)
        end
      end
    end
  end

  for _, r in ipairs(added) do
    local edges = r.node.edges
    for i=#edges,1,-1 do
      if edges[i] == r.edge then table.remove(edges, i) break end
    end
  end

  if not prev[goalNode] and startNode ~= goalNode then return {} end
  local path = {}
  local cur = goalNode
  while cur do
    table.insert(path, 1, cur)
    cur = prev[cur]
  end
  return path
end

function Pathfinder.CollapsePath(graph, path)
  if not path or #path == 0 then return {} end
  local out = { path[1] }
  for i = 2, #path do
    local prev = path[i-1]
    local node = path[i]
    local kind
    for _, e in ipairs(prev.edges or {}) do
      if e.node == node then kind = e.kind break end
    end
    if kind ~= "move" and i < #path then
      -- skip arrival via portal or map transition
    else
      table.insert(out, node)
    end
  end
  return out
end

function Pathfinder.DebugPath(graph, startMap, destMap)
  if not graph then DBG("DebugPath: missing graph") return end
  local raw = Pathfinder.ShortestPath(graph,
    { mapID = startMap, x = 0.5, y = 0.5 },
    { mapID = destMap,  x = 0.5, y = 0.5 })
  if not raw or #raw == 0 then
    DBG("DebugPath: no path %s -> %s", tostring(startMap), tostring(destMap))
    DBG("DebugPath: edges from %s", tostring(startMap))
    for _, node in ipairs(graph.byMap[startMap] or {}) do
      for _, e in ipairs(node.edges or {}) do
        DBG("  %d -> %d via %s (rec %s)", node.mapID, e.node.mapID,
          e.kind or "?", tostring(e.recID))
      end
    end
    return
  end
  DBG("DebugPath: %s -> %s", tostring(startMap), tostring(destMap))
  for i = 1, (#raw - 1) do
    local a, b = raw[i], raw[i + 1]
    local edge
    for _, e in ipairs(a.edges or {}) do
      if e.node == b then edge = e break end
    end
    DBG("  %d -> %d via %s (rec %s)", a.mapID, b.mapID,
      edge and edge.kind or "?", edge and edge.recID or "-")
  end
end

Pathfinder.W_PORTAL = W_PORTAL
Pathfinder.W_MOVE = W_MOVE

AM.Pathfinder = Pathfinder

return Pathfinder
