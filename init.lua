go = {}

go.T = minetest.get_translator"go"

local function load(name)
	go[name] = modlib.mod.include(name .. ".lua")
end

load"conf"
load"models"

-- Build scripts
--[[
load"build/generate_models" -- depends on models
load"build/collect_translation_strings"
--]]

load"textures"
load"items"
load"crafts"
load"board_entity"