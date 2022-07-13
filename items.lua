local visible_wielditem = rawget(_G, "visible_wielditem")

local function tweak_wielditem(itemname, tweaks)
	if visible_wielditem then
		visible_wielditem.item_tweaks.names[itemname] = tweaks
	end
end

local T, models, textures, conf = go.T, go.models, go.textures, go.conf

go.board_itemnames = {}

for board_size in pairs(conf.board_sizes) do
	local size_str = ("%dx%d"):format(board_size, board_size)
	local itemname = "go:board_" .. size_str
	go.board_itemnames[itemname] = true
	tweak_wielditem(itemname, {position = vector.new(0, conf.board_thickness/2 - 0.25, 0)})
	-- TODO (?) use the same hack as for items on visible wielditem entities to display board constellation
	minetest.register_node(itemname, {
		description = T"Go Board" ..  " (" .. size_str .. ")",
		stack_max = 1, -- unstackable
		drawtype = "mesh",
		mesh = models.boards.no_stones,
		tiles = {textures.boards[board_size], "go_board_background.png"},
		node_placement_prediction = "", -- disables prediction
		on_place = function(itemstack, _, pointed_thing)
			if pointed_thing.above.y <= pointed_thing.under.y then return end
			local top_edge = -math.huge
			for _, box in pairs(modlib.minetest.get_node_collisionboxes(pointed_thing.under)) do
				if box[5] > top_edge then
					top_edge = box[5]
				end
			end
			if top_edge == -math.huge then
				top_edge = 0.5 -- nonphysical node
			end
			local pos = vector.offset(pointed_thing.under, 0, top_edge + conf.board_thickness / 2, 0)
			minetest.sound_play("go_board_place", {pos = pos, max_hear_distance = 10}, true)
			minetest.add_entity(pos, "go:board", itemstack:get_meta():get"go_staticdata" or tostring(board_size))
			return ItemStack""
		end,
	})
end

for letter, description in pairs{B = T"Infinite Black Go Stones", W = T"Infinite White Go Stones"} do
	local itemname = "go:stones_" .. letter
	tweak_wielditem(itemname, {position = vector.new(0, -0.2, 0)})
	minetest.register_node(itemname, {
		description = description,
		stack_max = 1, -- unstackable
		drawtype = "mesh",
		mesh = models.stone, -- HACK nodeboxes would work poorly here due to their fixed UV mapping
		visual_scale = 0.5,
		wield_scale = vector.new(0.5, 0.5, 0.5),
		tiles = {("go_stone_%s.png"):format(letter)},
		node_placement_prediction = "", -- disables prediction
		on_place = function() end,
		-- HACK store this in the tool capabilities as the item that was used to punch is otherwise not known
		-- and player:get_wielded_item() may be inaccurate
		tool_capabilities = {groupcaps = {[itemname] = {}}}
	})
end