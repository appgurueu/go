local conf = go.conf

local board_thickness = conf.board_thickness -- in nodes
local stone_width, stone_height = conf.stone_width, conf.stone_height

local function texture(file)
	return {
		file = file,
		flags = 1,
		blend = 2,
		pos = {0, 0},
		scale = {1, 1},
		rotation = 0,
	}
end

local function brush(name, texture_id)
	return {
		name = name,
		texture_id = {texture_id},
		color = {r = 1, g = 1, b = 1, a = 1},
		fx = 0,
		blend = 1,
		shininess = 0
	}
end

local function add_box(vertices, tris, center, size)
	for axis = 0, 2 do
		local other_axis_1, other_axis_2 = 1 + ((axis + 1) % 3), 1 + ((axis - 1) % 3)
		axis = axis + 1
		for dir = -1, 1, 2 do
			local normal = {0, 0, 0}
			normal[axis] = dir
			for val_1 = -1, 1, 2 do
				for val_2 = -1, 1, 2 do
					local pos = {0, 0, 0}
					pos[axis] = center[axis] + dir * size[axis]/2
					pos[other_axis_1] = center[other_axis_1] + val_1 * size[other_axis_1]/2
					pos[other_axis_2] = center[other_axis_2] + val_2 * size[other_axis_2]/2
					table.insert(vertices, {
						pos = modlib.vector.apply(pos, modlib.math.fround),
						tex_coords = {{(val_1+1)/2, (val_2+1)/2}}
					})
				end
			end
			local last = #vertices
			local function fix_winding_order(indices)
				local poses = {}
				for i = 1, 3 do
					poses[i] = modlib.vector.new(vertices[indices[i]].pos)
				end
				local tri_normal = modlib.vector.triangle_normal(poses)
				local cos_angle = tri_normal:dot(normal)
				assert(cos_angle ~= 0, "normal is orthogonal to face normal")
				if cos_angle < 0 then
					modlib.table.reverse(indices)
					modlib.table.reverse(poses)
					tri_normal = modlib.vector.triangle_normal(poses)
					assert(tri_normal:dot(normal) > 0)
				end
				return indices
			end
			table.insert(tris, fix_winding_order({last - 1, last - 2, last - 3}))
			table.insert(tris, fix_winding_order({last - 1, last - 2, last}))
		end
	end
end

local function write_board(size, filename)
	local vertices = {
		flags = 0,
		tex_coord_sets = 1,
		tex_coord_set_size = 2,
	}
	local tris = {}

	-- Add board

	add_box(vertices, tris, {0, 0, 0}, {1, board_thickness, 1})

	local board = {
		-- Always two tris per face
		top = {tris[7], tris[8]},
		bottom = {tris[5], tris[6]},
		sides = {tris[1], tris[2], tris[3], tris[4], unpack(tris, 9)} -- everything else
	}

	-- Add stones

	local stone_bones = {}

	local function add_stones(color)
		local stone_tris = {}

		for i = 1, size do
			for j = 1, size do
				local first_vertex_index = #vertices + 1
				add_box(vertices, stone_tris,
					{(i-.5) / size - 0.5, 0, (j -.5) / size - 0.5}, {stone_width / size, stone_height / size, stone_width / size})
				local bonename = ("%s%02d%02d"):format(color, i, j)
				local weights = {}
				for v_id = first_vertex_index, #vertices do
					weights[v_id] = 1
				end
				table.insert(stone_bones, {
					name = bonename,
					scale = {1, 1, 1},
					position = {0, 0, 0},
					rotation = {0, 0, 0, 1},
					children = {},
					bone = weights
				})
			end
		end

		return stone_tris
	end

	local white_stones, black_stones
	if size ~= "no_stones" then
		white_stones = add_stones"W"
		black_stones = add_stones"B"
	end

	local board_model = {
		version = {
			major = 0,
			minor = 1
		},
		textures = {
			texture"go_board_top.png",
			texture"go_board_bottom.png",
			texture"go_board_background.png",
		},
		brushes = {
			brush("Board top", 1),
			brush("Board bottom", 2),
			brush("Board sides", 3),
		},
		node = {
			name = "Board",
			scale = {1, 1, 1},
			position = {0, 0, 0},
			rotation = {0, 0, 0, 1},
			children = stone_bones,
			mesh = {
				vertices = vertices,
				triangle_sets = {
					{
						brush_id = 1,
						vertex_ids = board.top
					},
					{
						brush_id = 2,
						vertex_ids = board.bottom
					},
					{
						brush_id = 3,
						vertex_ids = board.sides
					},
				}
			}
		},
	}

	if size ~= "no_stones" then
		table.insert(board_model.textures, texture"go_stone_W.png")
		table.insert(board_model.textures, texture"go_stone_B.png")
		table.insert(board_model.brushes, brush("White stones", 4))
		table.insert(board_model.brushes, brush("Black stones", 5))
		table.insert(board_model.node.mesh.triangle_sets, {
			brush_id = 4,
			vertex_ids = white_stones
		})
		table.insert(board_model.node.mesh.triangle_sets, {
			brush_id = 5,
			vertex_ids = black_stones
		})
	end

	local file = assert(io.open(modlib.mod.get_resource("go", "models", filename), "wb"))
	modlib.b3d.write(board_model, file)
	file:close()
end

for board_size, filename in pairs(go.models.boards) do
	write_board(board_size, filename)
end

local stone = {
	version = {
		major = 0,
		minor = 1
	},
	textures = {
		texture"go_stone_*.png"
	},
	brushes = {
		brush("Go stone", 1)
	},
	node = {
		name = "Go stone",
		scale = {1, 1, 1},
		position = {0, 0, 0},
		rotation = {0, 0, 0, 1},
		children = {},
		mesh = {
			vertices = {
				flags = 0,
				tex_coord_sets = 1,
				tex_coord_set_size = 2,
			},
			triangle_sets = {
				{
					brush_id = 1,
					vertex_ids = {}
				}
			}
		}
	},
}

add_box(
	stone.node.mesh.vertices,
	stone.node.mesh.triangle_sets[1].vertex_ids,
	{0, 0, 0}, {stone_width, stone_height, stone_width}
)

modlib.file.write(modlib.mod.get_resource("go", "models", go.models.stone), modlib.b3d.write_string(stone))
