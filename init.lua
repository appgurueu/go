go = {}

go.T = minetest.get_translator"go"

local modpath = minetest.get_modpath"go"
local function load(name)
	go[name] = dofile(modpath .. "/source/" .. name .. ".lua")
end

load"conf"
load"models"
load"textures"
load"items"
load"crafts"
load"game"
load"board_entity"

-- Build scripts
--[[
dofile(modpath .. "/build/generate_models.lua") -- depends on models
dofile(modpath .. "/build/collect_translation_strings.lua")
--]]