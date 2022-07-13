-- "Codefiguration" since there's little point in users configuring these values
return {
	board_sizes = modlib.table.set{9, 13, 19},
	board_thickness = 0.1, --[m]
	-- in squares on the board
	stone_width = 0.75,
	stone_height = 0.375,
}