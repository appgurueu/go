-- Utilities

local next = next

local table_empty = modlib.table.is_empty

local function table_only_entry(tab)
	local only = next(tab)
	if next(tab, only) ~= nil then return nil end
	return only
end

-- TODO (?) use modlib.table.count_equals(tab, 1) for this once released
local function table_cnt_eq_one(tab)
	local first_key = next(tab)
	return first_key ~= nil and next(tab, first_key) == nil
end

-- Go game "class"
-- Strict separation between named constructors Game.* and instance methods game:*
local Game = {}
local M = {} -- methods
local metatable = {__index = M}

-- "Public" interface

function Game.deserialize(str)
	local self = minetest.deserialize(str)
	setmetatable(self, metatable)
	local state = self:state()
	if state == "in_game" then
		-- Also sets self.groups
		self.possible_moves = self:_determine_possible_moves()
	elseif state == "scoring" then
		-- Also sets self.groups, determines two eye groups
		self:_count_territory() -- deliberately ignore the result (territory counts) here
	end
	return self
end

function Game.new(board_size)
	local self = {
		turn = "B",
		players = {},
		stones = {},
		board_size = board_size,
		-- Data derived from the board state:
		groups = {},
		possible_moves = setmetatable({}, {__index = function(_, i)
			assert(i >= 0 and i < board_size^2)
			return true -- all moves are valid initially
		end})
	}
	setmetatable(self, metatable)
	return self
end

function M:serialize()
	local groups, possible_moves = self.groups, self.possible_moves
	self.groups, self.possible_moves = nil, nil
	local serialized = minetest.serialize(self)
	self.groups, self.possible_moves = groups, possible_moves
	return serialized
end

function M:state()
	if self.scoring then
		return "scoring"
	elseif self.winner or self.scores then
		return "scored"
	else
		return "in_game"
	end
end

function M:get_index(x, y)
	return (y - 1) * self.board_size + (x - 1)
end

function M:get_xy(i)
	local x = i % self.board_size
	local y = (i - x) / self.board_size
	return x + 1, y + 1
end

function M:xy_stones()
	local i
	return function()
		local stone
		i, stone = next(self.stones, i)
		if not i then return end
		local x, y = self:get_xy(i)
		return x, y, stone
	end
end

function M:place(playername, x, y)
	if not self:_check_turn(playername) then
		return
	end
	local i = self:get_index(x, y)
	if not self.possible_moves[i] then
		return false
	end
	self.stones[i] = self.turn
	local captures = {}
	self:_adjacent_intersections(x, y, function(nx, ny)
		local ni = self:get_index(nx, ny)
		local group = self.groups[ni]
		if group and group.critical and self.stones[ni] ~= self.turn then
			-- Kill critical group
			for ci in pairs(group.stones) do
				captures[ci] = self.stones[ci]
				self.stones[ci] = nil
			end
		end
	end)
	self.last_action = {type = "place", ko = table_cnt_eq_one(captures), x = x, y = y, i = i}
	self:_next_turn()
	self.possible_moves = self:_determine_possible_moves()
	if table_empty(self.possible_moves) then
		self:pass(self.players[self.turn])
	end
	return captures
end

function M:pass(playername)
	if not self:_check_turn(playername) then
		return
	end
	local consecutive_passes = self.last_action.type == "pass"
	self.last_action = {type = "pass"}
	self:_next_turn()
	self.possible_moves = nil
	if consecutive_passes then -- 2 consecutive passes end the game
		self:_count_territory() -- Also determines two eye groups; deliberately ignore the result (territory counts) here
		local all_invincible = true
		for _, group in pairs(self.groups) do
			if not group.invincible then all_invincible = false break end
		end
		if all_invincible then
			self:score() -- score immediately: no groups may be marked as dead
		else
			self.scoring = {captures = {}, approvals = {}} -- start scoring phase
		end
	else
		local possible_moves = self:_determine_possible_moves()
		if table_empty(possible_moves) then
			self:pass(self.players[self.turn])
		else
			self.possible_moves = possible_moves
		end
	end
end

function M:resign(playername)
	if not self:_check_turn(playername) then
		return
	end
	self.last_action = {type = "resign"}
	self:_next_turn()
	self.winner = self.turn
	self.turn = nil
end

function M:mark_capture(x, y)
	local i = self:get_index(x, y)
	local group = self.groups[i]
	if not group then
		return -- can't mark free intersections as captured
	end
	if group.invincible then
		return -- can't mark invincible groups as captured
	end
	local captures = self.scoring.captures
	for j in pairs(group.stones) do
		if captures[j] then
			captures[j] = nil
		else
			captures[j] = assert(self.stones[i])
		end
	end
	self.scoring.approvals = {} -- clear approvals
	return true
end

function M:approve(playername)
	local approvals = self.scoring.approvals
	if approvals[playername] then
		return
	end
	approvals[playername] = true
	if approvals[self.players.B] and approvals[self.players.W] then
		local captures = self.scoring.captures
		self:score()
		return true, captures
	end
	return true
end

function M:resume()
	self.scoring = nil -- end scoring phase
	self.last_action = {type = "resume"}
	self.possible_moves = self:_determine_possible_moves()
end

function M:score()
	if self.scoring then
		-- Remove marked captures from the board
		-- TODO (?) just ignore rather than remove these stones
		for i in pairs(self.scoring.captures) do
			self.stones[i] = nil
		end
		self.scoring = nil
	end
	-- Delete irrelevant information
	self.turn, self.groups, self.possible_moves = nil, nil, nil

	local scores = self:_count_territory()
	-- Area scoring: One point for each alive stone at the end of the game
	for _, stone_color in pairs(self.stones) do
		scores[stone_color] = scores[stone_color] + 1
	end
	self.scores = scores
	if scores.W > scores.B then
		self.winner = "W"
	elseif scores.B > scores.W then
		self.winner = "B"
	end
end

-- "Private" methods

function M:_adjacent_intersections(x, y, func)
	if x > 1 then
		func(x - 1, y)
	end
	if y > 1 then
		func(x, y - 1)
	end
	if x < self.board_size then
		func(x + 1, y)
	end
	if y < self.board_size then
		func(x, y + 1)
	end
end

function M:_determine_groups()
	-- Build a table of groups
	local groups = {} -- [i] = {stones = {[i] = true, ...}, critical = bool}
	for x, y, stone in self:xy_stones() do
		local group, group_freedoms = {stones = {}, critical = false}, {}
		local function visit(x, y) -- luacheck: ignore
			local index = self:get_index(x, y)
			if self.stones[index] == stone then
				if groups[index] then
					return
				end
				group.stones[index] = true
				groups[index] = group
				self:_adjacent_intersections(x, y, visit)
			elseif not self.stones[index] then
				group_freedoms[index] = true
			end
		end
		visit(x, y)
		-- Mark groups with a single liberty as "critical"
		if table_cnt_eq_one(group_freedoms) then
			group.critical = true
		end
	end
	return groups
end


function M:_determine_possible_moves()
	self.groups = self:_determine_groups()

	local possible_moves = {}
	for x = 1, self.board_size do
		for y = 1, self.board_size do
			local i = self:get_index(x, y)
			if not self.stones[i] then
				local seki, ko = true, false -- seki ("suicide") & ko ("no immediate repetition") rule
				self:_adjacent_intersections(x, y, function(nx, ny)
					local ni = self:get_index(nx, ny)
					local neighbor_stone = self.stones[ni]
					if neighbor_stone then
						local group = self.groups[ni]
						if neighbor_stone == self.turn then -- connects to a friendly group
							seki = seki and group.critical -- seki if all neighboring groups are critical
						elseif group.critical then -- kills a critical enemy group
							seki = false -- no seki since it creates liberties
							local one_capture = table_cnt_eq_one(group.stones)
							if self.last_action.type == "place" then
								ko = ko or (one_capture and self.last_action.i == ni and self.last_action.ko)
							end
						end
					else -- liberty
						seki = false
					end
				end)
				if not (seki or ko) then
					possible_moves[i] = true
				end
			end
		end
	end
	return possible_moves
end

function M:_count_territory()
	self.groups = self:_determine_groups()

	local eyes = {}

	local function count_territory(color)
		local visited = {}
		local area, border_groups, neutral
		local function visit(x, y)
			local index = self:get_index(x, y)
			local stone = self.stones[index]
			if stone == color then
				border_groups[self.groups[index]] = true
			elseif not stone then
				if area[index] or visited[index] then
					return
				end
				area[index] = true
				visited[index] = true
				self:_adjacent_intersections(x, y, visit)
			else -- opponent stone
				neutral = true
			end
		end
		local territory = 0
		for x = 1, self.board_size do
			for y = 1, self.board_size do
				local i = self:get_index(x, y)
				if not self.stones[i] then
					area, border_groups, neutral = {}, {}, false
					visit(x, y)
					if not neutral then
						for _ in pairs(area) do
							territory = territory + 1
						end
						local border_group = table_only_entry(border_groups)
						if border_group ~= nil then
							local eye_count = (eyes[border_group] or 0) + 1
							eyes[border_group] = eye_count
							if eye_count >= 2 then
								border_group.invincible = true
							end
						end
					end
				end
			end
		end
		return territory
	end

	return {B = count_territory"B", W = count_territory"W"}
end

-- Turn utils

function M:_check_turn(playername)
	assert(self:state() == "in_game")
	if self.players[self.turn] then
		if self.players[self.turn] ~= playername then
			return false
		end
	else
		self.players[self.turn] = playername
	end
	return true
end

function M:_next_turn()
	self.turn = self.turn == "W" and "B" or "W"
end

return Game