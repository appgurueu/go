local wood, blck = "group:wood", "group:dye,color_black"

local brd9 = "go:board_9x9"

minetest.register_craft({
	output = brd9,
	recipe = {
		{wood, blck, wood},
		{blck, wood, blck},
		{wood, blck, wood},
	},
})

minetest.register_craft({
	output = "go:board_13x13",
	recipe = {
		{wood, blck, wood},
		{blck, brd9, blck},
		{wood, blck, wood},
	},
})
minetest.register_craft({
	output = "go:board_19x19",
	recipe = {
		{brd9, blck, brd9},
		{blck, wood, blck},
		{brd9, blck, brd9},
	},
})

for color, long_name in pairs{B = "black", W = "white"} do
	minetest.register_craft({
		output = "go:stones_" .. color,
		type = "shapeless",
		recipe = {
			"group:stone", -- don't use default:stone here to be compatible with more games
			"group:dye,color_" .. long_name,
		},
	})
end
