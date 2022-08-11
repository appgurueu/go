local Game = go.game

local T, models, textures, conf = go.T, go.models, go.textures, go.conf

local board_thickness, stone_width, stone_height = conf.board_thickness, conf.stone_width, conf.stone_height

local function _set_stone_bone(object, board_size, player, x, y, show)
	object:set_bone_position(player .. ("%02d%02d"):format(x, y),
		vector.new(0, show and ((board_thickness + stone_height/board_size) / 2) or 0, 0))
end

-- HACK hook into item entity to set Go board appearance, including placed stones
do
	local item_ent_def = minetest.registered_entities["__builtin:item"]
	local item_ent_def_set_item = item_ent_def.set_item
	function item_ent_def:set_item(item, ...)
		item_ent_def_set_item(self, item, ...)
		local itemstack = ItemStack(item or self.itemstring)
		local staticdata = itemstack:get_meta():get"go_staticdata"
		if go.board_itemnames[itemstack:get_name()] and staticdata then
			local game = Game.deserialize(staticdata)
			self.object:set_properties{
				visual = "mesh",
				mesh = models.boards[game.board_size],
				textures = {
					textures.boards[game.board_size],
					"go_board_background.png",
					"go_board_background.png",
					"go_stone_W.png",
					"go_stone_B.png"
				},
				visual_size = 10 * self.object:get_properties().visual_size
			}
			for x, y, stone in game:xy_stones() do
				_set_stone_bone(self.object, game.board_size, stone, x, y, true)
			end
		end
	end
end

local board = {}

board.initial_properties = {
	visual = "mesh",
	mesh = models.boards[19],
	textures = {
		textures.boards[19],
		"go_board_background.png",
		"go_board_background.png",
		"go_stone_W.png",
		"go_stone_B.png"
	},
	shaded = true,
	backface_culling = true,
	physical = true,
	collisionbox = {-0.5, -0.05, -0.5, 0.5, 0.05, 0.5},
	visual_size = vector.new(10, 10, 10) -- blocksize
}

function board:_set_stone_bone(...)
	_set_stone_bone(self.object, self._game.board_size, ...)
end

local gravity = vector.new(0, -9.81, 0)
function board:on_activate(staticdata)
	local object = self.object

	if staticdata == "" then
		minetest.log("warning",
			("[go] Board entity at %s has invalid staticdata, removing")
			:format(minetest.pos_to_string(self.object:get_pos())))
		object:remove()
		return
	end

	local board_size = tonumber(staticdata)
	local game
	if board_size then
		game = Game.new(board_size)
	else
		game = Game.deserialize(staticdata)
	end
	self._game = game
	self._fs_viewers = {}

	object:set_acceleration(gravity)
	object:set_armor_groups{punch_operable = 1}
	object:set_properties{
		textures = {textures.boards[game.board_size], unpack(board.initial_properties.textures, 2)},
		mesh = models.boards[game.board_size]
	}
	for x, y, stone in game:xy_stones() do
		self:_set_stone_bone(stone, x, y, true)
	end
end

function board:get_staticdata()
	return self._game:serialize()
end

function board:on_punch(puncher, _, tool_capabilities)
	local game = self._game
	local board_size = game.board_size

	-- Board pickup
	if
		puncher:get_wielded_item():is_empty()
		and not minetest.is_protected(self.object:get_pos(), puncher:get_player_name())
	then
		local item = ItemStack(("go:board_%dx%d"):format(board_size, board_size))
		local meta = item:get_meta()
		meta:set_string("go_staticdata", self:get_staticdata())
		local B, W = game.players.B or "?", game.players.W or "?"
		meta:set_string("description", ("%s - %s vs %s"):format(item:get_description(), B, W))
		meta:set_string("count_meta", B:sub(1, 1):upper() .. "-" .. W:sub(1, 1):upper())
		meta:set_int("count_alignment", 2 + 2 * 4) -- centered
		self:_close_formspecs()
		self.object:remove()
		puncher:set_wielded_item(item)
		return
	end

	if game:state() ~= "in_game" then
		return -- can't place pieces
	end

	if not (tool_capabilities.groupcaps["go:stones_" .. game.turn]) then
		return -- not the right Go stone
	end

	-- Determine eye position
	local eye_pos = puncher:get_pos()
	eye_pos.y = eye_pos.y + puncher:get_properties().eye_height
	local first, third = puncher:get_eye_offset()
	if not vector.equals(first, third) then
		minetest.log("warning", "[go] First & third person eye offsets don't match, assuming first person")
	end
	eye_pos = vector.add(eye_pos, vector.divide(first, 10))
	-- Look dir
	local dir = puncher:get_look_dir()
	if dir.y >= 0 then
		return -- looking up
	end
	-- Tool range
	local range = puncher:get_wielded_item():get_definition().range
	if (range or -1) < 0 then
		local inv = puncher:get_inventory()
		local hand = (inv and inv:get_size"hand" > 0) and inv:get_stack("hand", 1) or ItemStack()
		range = hand:get_definition().range
		if (range or -1) < 0 then
			range = 4
		end
	end

	-- Calculate world pos of intersection
	local board_pos = self.object:get_pos()
	local board_top_y = board_pos.y + board_thickness / 2
	local y_diff = board_top_y - eye_pos.y
	local pos_on_ray = y_diff / dir.y
	if pos_on_ray > range then
		return -- out of range
	end
	local world_pos = eye_pos + vector.multiply(dir, pos_on_ray)
	-- Relative position on the board, translated by 0.5 for convenience
	local board_x, board_z = world_pos.x - board_pos.x + 0.5, world_pos.z - board_pos.z + 0.5
	if board_x < 0 or board_x > 1 or board_z < 0 or board_z > 1 then
		return -- out of board bounds
	end
	self:_place(puncher, math.ceil(board_x * game.board_size), math.ceil(board_z * game.board_size))
end

function board:on_rightclick(clicker)
	self:_show_formspec(clicker)
end

function board:_place(placer, x, y)
	local game = self._game
	local color = game.turn
	local captures = game:place(placer:get_player_name(), x, y)
	if not captures then
		return -- invalid move
	end
	self:_set_stone_bone(color, x, y, true)
	for ci, stone in pairs(captures) do
		self:_set_stone_bone(stone, game:get_xy(ci))
	end
	do
		local stone_center = vector.offset(self.object:get_pos(),
			(x - 0.5) / game.board_size - 0.5,
			(stone_height/game.board_size + board_thickness) / 2,
			(y - 0.5) / game.board_size - 0.5)
		-- Particle effect
		local stone_extent = vector.divide(vector.new(stone_width, stone_height, stone_width), 2 * game.board_size)
		minetest.add_particlespawner{
			time = 0.5,
			amount = 10,
			minpos = vector.subtract(stone_center, stone_extent),
			maxpos = vector.add(stone_center, stone_extent),
			minvel = vector.new(-0.5, 0, -0.5),
			maxvel = vector.new(0.5, 0.5, 0.5),
			minacc = vector.new(0, -0.981, 0),
			maxacc = vector.new(0, -0.981, 0),
			minsize = 0.2,
			maxsize = 0.4,
			minexptime = 0.2,
			maxexptime = 0.4,
			node = {name = "go:stones_" .. color},
			glow = 7,
		}
		-- Sound effect
		minetest.sound_play("go_stone_place", {
			pos = stone_center,
			gain = 0.75 + 0.5 * math.random(),
			pitch = 0.75 + 0.5 * math.random(),
			max_hear_distance = 5,
		}, true)
	end
	self:_update_formspecs()
end

function board:_approve_scoring(viewer)
	local game = self._game
	local success, captures = game:approve(viewer:get_player_name())
	if not success then
		return -- no formspec update necessary
	end
	if captures then
		for i, stone in pairs(captures) do
			self:_set_stone_bone(stone, game:get_xy(i))
		end
	end
	self:_update_formspecs()
end

-- Formspec stuff

function board:_reset()
	local game = self._game

	-- Clear all stones
	for x, y, stone in game:xy_stones() do
		self:_set_stone_bone(stone, x, y)
	end
	-- Reset game
	self._game = Game.new(game.board_size)

	self:_update_formspecs()
end

local fs_size = 16 -- force 16x16 formspec dimensions
function board:_build_formspec(viewer)
	local game = self._game
	local state = game:state()
	local board_size = game.board_size
	local board_unit = fs_size / board_size
	local viewers_turn, enter_game = game.players[game.turn] == viewer:get_player_name(), not game.players[game.turn]

	local function get_highlight(player)
		if state == "scored" and player == game.winner then
			return "winner_highlight"
		end
		if state == "in_game" and player == game.turn then
			return "highlight"
		end
		return "plain"
	end

	local text
	if state == "in_game" then
		if not game.players[game.turn] then
			text = T"Make a move to enter the game"
		elseif game.turn == "B" then
			text = T"Black to play"
		else assert(game.turn == "W")
			text = T"White to play"
		end
	elseif state == "scoring" then
		text = T"Mark captured groups"
	else assert(state == "scored")
		local scores, winner = game.scores, game.winner
		if scores then
			if winner == "B" then
				text = T("Black wins @1 to @2", scores.B, scores.W)
			elseif winner == "W" then
				text = T("White wins @1 to @2", scores.W, scores.B)
			else assert(scores.W == scores.B)
				text = T("Draw (@1 each)", scores.B)
			end
		else
			if winner == "B" then
				text = T"Black wins (White resigned)"
			else assert(winner == "W")
				text = T"White wins (Black resigned)"
			end
		end
	end

	-- Two bars with height 1 with 0.5 spacing
	local form = {
		-- Header
		{"formspec_version", 2};
		{"size", {fs_size, fs_size + 3, false}};
		{"no_prepend"},

		-- Transparent background
		{"bgcolor", "#0000"},

		-- Top bar
		{"background", {0, 0}; {fs_size, 1}, "go_board_background.png"};
		-- Black player
		{"image", {0, 0}; {1, 1}; textures.stones.B[get_highlight"B"]};
		{"label", {1 + fs_size / 100 --[[HACK: small offset to match the hypertext margin]], 0.5}; game.players.B or ""};
		-- White player
		-- HACK use hypertext for right-aligned text
		{"hypertext", {fs_size/2, 0}; {fs_size/2 - 1.25, 1}; ""; fslib.hypertext_root{
			fslib.hypertext_tags.global{color = "white", valign = "middle", halign = "right", margin = 0},
			game.players.W or ""
		}},
		{"image", {fs_size - 1, 0}; {1, 1}; textures.stones.W[get_highlight"W"]};

		-- Background
		{"background", {0, 1.5}; {fs_size, fs_size}, textures.boards[board_size]};

		-- Bottom bar
		{"background", {0, fs_size + 2}; {fs_size, 1}, "go_board_background.png"};
		{"label", {0.25, fs_size + 2.5}; text};

		-- Button styles
		{"style_type", "button"; {bgcolor = "#EDD68E"}};
		{"style_type", "button:hovered"; {bgcolor = "#FDE69E"}};
		{"style_type", "button:pressed"; {bgcolor = "#DDC67E"}};
	}

	-- Add buttons to the bottom bar, right-to-left
	local btn_wh, btn_count = {4, 1}, 0
	local function add_button(name, label)
		btn_count = btn_count + 1
		table.insert(form, {"button", {fs_size - btn_wh[1] * btn_count, fs_size + 2}, btn_wh; name; label})
	end

	local stone_hover
	if state == "in_game" then
		stone_hover = textures.stones[game.turn].hover
		table.insert(form, {"style_type", "image_button:hovered"; {fgimg = textures.stones[game.turn].hover}})
		-- Deliberately omitted to avoid flickering:
		-- {"style_type", "image_button:pressed"; {fgimg = textures.stones[game.turn].plain}}
		-- to be re-added when stylable image "checkbuttons" exist
		if viewers_turn then
			add_button("resign", T"Resign")
			add_button("pass", T"Pass")
		end
	elseif state == "scoring" then
		add_button("resume", T"Resume")
		if not game.scoring.approvals[viewer:get_player_name()] then
			add_button("score", T"Score")
		end
	elseif state == "scored" then
		add_button("reset", T"Reset")
	end

	-- Transform formspec coordinates to absolute board coordinates relative to viewer look dir
	local look_dir = viewer:get_look_dir()
	local function fs_to_board_coords(x, y)
		local x_flipped, y_flipped = board_size - x + 1, board_size - y + 1
		if math.abs(look_dir.z) > math.abs(look_dir.x) then -- Z is the closest cardinal direction
			if look_dir.z < 0 then -- -Z
				return x_flipped, y
			else -- +Z
				return x, y_flipped
			end
		else -- X is the closest cardinal direction
			if look_dir.x < 0 then -- -X
				return y, x
			else -- +X
				return y_flipped, x_flipped
			end
		end
	end

	for fs_x = 1, board_size do
		for fs_y = 1, board_size do
			local x, y = fs_to_board_coords(fs_x, fs_y)
			local i = game:get_index(x, y)
			local stone = game.stones[i]

			local xy, wh = {(fs_x - 1) * board_unit, 1.5 + (fs_y - 1) * board_unit}, {board_unit, board_unit}
			local element
			if stone then
				if state == "scoring" and not game.groups[i].invincible then
					local captured = game.scoring.captures[i]
					local name = ("P%02d%02d"):format(x, y)
					-- Marked as capture: Hover -> plain
					local image = textures.stones[stone][captured and "hover" or "plain"]
					-- Not marked as capture (yet): Plain -> hover
					local hover = textures.stones[stone][captured and "plain" or "hover"]
					table.insert(form, {"style", name .. ":hovered"; {fgimg = hover}})
					element = {"image_button", xy; wh; image; name; ""; true; hover}
				else
					local highlight
					if state == "scored" or i ~= (game.last_action or {}).i then
						highlight = "plain"
					else
						highlight = "highlight"
					end
					element = {"image", xy; wh; textures.stones[stone][highlight]}
				end
			elseif state == "in_game" and (viewers_turn or enter_game) and game.possible_moves[i] then
				element = {"image_button", xy; wh; "blank.png"; ("P%02d%02d"):format(x, y); ""; true; stone_hover}
			end
			table.insert(form, element) -- inserting nil is a no-op
		end
	end

	table.insert(form, {"no_prepend"})

	return form
end

function board:_show_formspec(viewer)
	local viewer_name = viewer:get_player_name()
	self._fs_viewers[viewer_name] = fslib.show_formspec(viewer, self:_build_formspec(viewer), function(fields)
		if fields.quit then
			self._fs_viewers[viewer_name] = nil
			return
		end

		if not self.object:get_pos() then
			return -- entity was removed
		end

		local game = self._game

		local function get_xy()
			for field in pairs(fields) do
				local x, y = field:match"P(%d%d)(%d%d)"
				x, y = tonumber(x), tonumber(y)
				if x and y and x >= 1 and x <= game.board_size and y >= 1 and y <= game.board_size then
					return x, y
				end
			end
		end

		local state = game:state()
		if state == "in_game" then
			if fields.pass then
				game:pass(viewer_name)
				self:_update_formspecs()
			elseif fields.resign then
				game:resign(viewer_name)
				self:_update_formspecs()
			else
				local x, y = get_xy()
				if x and y then
					self:_place(viewer, x, y)
				end
			end
		elseif state == "scoring" then
			if fields.score then
				self:_approve_scoring(viewer)
			elseif fields.resume then
				game:resume()
				self:_update_formspecs()
			else
				local x, y = get_xy()
				if x and y then
					if game:mark_capture(x, y) then
						self:_update_formspecs()
					end
				end
			end
		else assert(state == "scored")
			if fields.reset then
				self:_reset()
			end
		end
	end)
end

function board:_update_formspecs()
	for viewer_name, fs_id in pairs(self._fs_viewers) do
		local viewer = minetest.get_player_by_name(viewer_name)
		if viewer then
			fslib.reshow_formspec(viewer, fs_id, self:_build_formspec(viewer))
		else -- viewer left
			self._fs_viewers[viewer_name] = nil
		end
	end
end

function board:_close_formspecs()
	for viewer_name in pairs(self._fs_viewers) do
		local viewer = minetest.get_player_by_name(viewer_name)
		if viewer then
			fslib.close_formspec(viewer) -- HACK (?) should perhaps allow passing the fs_id
		end
		self._fs_viewers[viewer_name] = nil
	end
end

minetest.register_entity("go:board", board)
