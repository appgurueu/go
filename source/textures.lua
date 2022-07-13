local conf = go.conf

local round = modlib.math.round

local boards = {}
for board_size in pairs(conf.board_sizes) do
	local resolution = 12 * board_size
	local margin = round(resolution * 0.5 / board_size)
	local len = round(resolution * (board_size - 1) / board_size) + 1
	local combine = {
		([[([combine:%dx%d:0,0=go_board_background.png\^\[resize\:%dx%d]])
			:format(resolution, resolution, resolution, resolution)
	}
	for i = 1, board_size do
		local pixel_coord = round(resolution * (i - 0.5) / board_size)
		assert(pixel_coord % 1 == 0)
		local line = [[%d,%d=go_line_color.png\^\[resize\:%dx%d]]
		table.insert(combine, line:format(pixel_coord, margin, 1, len))
		table.insert(combine, line:format(margin, pixel_coord, len, 1))
	end
	boards[board_size] = table.concat(combine, ":") .. ")"
end

local stones = {}

for _, color in pairs{"B", "W"} do
	-- HACK the parentheses are a workaround for https://github.com/minetest/minetest/issues/12209
	local base = ("([combine:20x20:2,2=go_stone_%s.png)"):format(color)
	local bg_color_fmt = "blank.png^[noalpha^[colorize:%s:255^[resize:20x20^" .. base
	stones[color] = {
		plain = base,
		hover = base .. "^[opacity:128",
		highlight = bg_color_fmt:format"cyan",
		winner_highlight = bg_color_fmt:format"yellow"
	}
end

return {
	boards = boards,
	stones = stones
}