globals = {
	"go";
	"visible_wielditem";
	-- HACK item entity override
	minetest = {fields = {"registered_entities"}};
}
read_globals = {
	"minetest", "vector", "ItemStack";
	table = {fields = {"copy"}};
	"modlib", "fslib";
}