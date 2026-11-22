-- Even out every dwindle split on a workspace: each split back to halves.
--
-- splitratio only reaches the split above the focused window, so it would
-- need focus to visit every window and still miss a split with no window
-- directly under it (the middle of a 2x2). This works on geometry instead:
-- it finds each split from the window edges, top down, and moves it to the
-- middle with a pixel resize of a window beside it. Dwindle applies that to
-- the window's nearest split on that axis, which may be a different one, so
-- each move is kept only if the split lands in the middle, else undone.
-- Focus never moves.

local TOL = 2 -- px; window edges are rounded

local function box(w)
	return { w = w, x = w.at.x, y = w.at.y, r = w.at.x + w.size.x, b = w.at.y + w.size.y }
end

-- Splits of a group of boxes along one axis: lines that every box is wholly
-- on one side of. lo/hi are the box edges facing the line.
local AXES = {
	{ name = "x", lo = "x", hi = "r" },
	{ name = "y", lo = "y", hi = "b" },
}

local function splits(group, axis)
	local out, seen = {}, {}
	local min, max = math.huge, -math.huge
	for _, b in ipairs(group) do
		min, max = math.min(min, b[axis.lo]), math.max(max, b[axis.hi])
	end
	for _, cand in ipairs(group) do
		local edge = cand[axis.hi]
		if not seen[edge] and edge < max - TOL then
			seen[edge] = true
			local before, after, far = {}, {}, math.huge
			local whole = true
			for _, b in ipairs(group) do
				if b[axis.hi] <= edge + TOL then
					table.insert(before, b)
				elseif b[axis.lo] >= edge - TOL then
					table.insert(after, b)
					far = math.min(far, b[axis.lo])
				else
					whole = false
					break
				end
			end
			if whole and #before > 0 and #after > 0 then
				table.insert(out, {
					axis = axis,
					before = before,
					after = after,
					edge = edge,
					far = far,
					off = (min + max) / 2 - (edge + far) / 2,
				})
			end
		end
	end
	return out
end

-- The first split, top down, that is off the middle and not given up on.
local function find(group, skip)
	if #group < 2 then
		return nil
	end
	local first
	for _, axis in ipairs(AXES) do
		for _, s in ipairs(splits(group, axis)) do
			first = first or s
			if math.abs(s.off) > TOL and not skip[s.axis.name .. s.edge] then
				return s
			end
		end
	end
	if not first then
		return nil
	end
	return find(first.before, skip) or find(first.after, skip)
end

local function centred(group, axis)
	for _, s in ipairs(splits(group, axis)) do
		if math.abs(s.off) <= TOL then
			return true
		end
	end
	return false
end

local function resize(w, d, axis)
	local x, y = 0, 0
	if axis.name == "x" then x = d else y = d end
	hl.dispatch(hl.dsp.window.resize({ x = x, y = y, relative = true, window = w }))
end

local function fix(s)
	local d = math.floor(s.off + 0.5)
	local touching = {}
	for _, b in ipairs(s.before) do
		if b[s.axis.hi] >= s.edge - TOL then table.insert(touching, b.w) end
	end
	for _, b in ipairs(s.after) do
		if b[s.axis.lo] <= s.far + TOL then table.insert(touching, b.w) end
	end
	local members = {}
	for _, b in ipairs(s.before) do table.insert(members, b.w) end
	for _, b in ipairs(s.after) do table.insert(members, b.w) end
	for _, w in ipairs(touching) do
		resize(w, d, s.axis)
		local now = {}
		for _, m in ipairs(members) do table.insert(now, box(m)) end
		if centred(now, s.axis) then
			return true
		end
		resize(w, -d, s.axis)
	end
	return false
end

return function(workspace)
	local ws = workspace or hl.get_active_workspace()
	if not ws or ws.has_fullscreen or ws.tiled_layout ~= "dwindle" then
		return
	end
	local skip = {}
	for _ = 1, 32 do
		local group = {}
		for _, w in ipairs(hl.get_workspace_windows(ws)) do
			if not w.floating and not w.hidden then
				table.insert(group, box(w))
			end
		end
		local s = find(group, skip)
		if not s then
			return
		end
		if not fix(s) then
			skip[s.axis.name .. s.edge] = true
		end
	end
end
