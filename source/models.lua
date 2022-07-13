local boards = {
	no_stones = "go_board_no_stones.b3d"
}
for size in pairs(go.conf.board_sizes) do
	boards[size] = ("go_board_%dx%d.b3d"):format(size, size)
end
return {
	boards = boards,
	stone = "go_stone.b3d"
}