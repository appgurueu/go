-- Collects translation strings; alternative to tools like https://github.com/minetest-tools/update_translations
--[[
	Calls must be T or S, followed by an optional parens, followed by a string using double quotes
	Expects translation files to use @n rather than @\n
]]

local modname = minetest.get_current_modname()
local base_path = minetest.get_modpath(modname)
local strs = {}
local filenames = minetest.get_dir_list(base_path, false)
table.sort(filenames)
for _, filename in ipairs(filenames) do
	if filename:match"%.lua$" then
		local lua = modlib.file.read(base_path .. "/" .. filename)
		for str in lua:gmatch[[%W[TS]%s*%(?%s*(".-[^\]")]] do
			str = setfenv(assert(loadstring("return"..str)), {})():gsub(".", {
				["\n"] = "@n",
				["="] = "@=",
			})
			strs[str] = ""
			table.insert(strs, str)
		end
	end
end

local locale_path = base_path .. "/locale"
for _, filename in ipairs(minetest.get_dir_list(locale_path, false)) do
	local filepath = locale_path .. "/" .. filename
	local lines = {}
	local existing_strs = {}
	for line in io.lines(filepath) do
		if line:match"^#" then -- preserve comments
			table.insert(lines, line)
		elseif line:match"%S" then
			local str = line:match"^%s*(.-[^=])%s*="
			if strs[str] then
				table.insert(lines, line)
				existing_strs[str] = true
			end
		end
	end
	local textdomain = "# textdomain: " .. modname
	if lines[1] ~= textdomain then
		table.insert(lines, 1, textdomain)
	end
	for _, str in ipairs(strs) do
		if not existing_strs[str] then
			lines[#lines + 1] = str .. "="
		end
	end
	table.insert(lines, "") -- trailing newline
	modlib.file.write(filepath, table.concat(lines, "\n"))
end