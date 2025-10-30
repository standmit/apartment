local S = minetest.get_translator("apartment")
apartment = {}
apartment.enable_aphome_command = minetest.settings:get_bool("apartment.enable_aphome_command", true)

minetest.register_privilege("apartment_unrent", {
	description = S("Allows player to throw other players out from apartments not owned by them."),
	give_to_singleplayer = false
})

minetest.register_privilege("apartment", {
	description = S("Allows player to place or destroy Apartment Management Panels."),
	give_to_singleplayer = false
})

function apartment.split_string(str)
	local ids = {}
	for token in str:gmatch("%d+") do
		local id = tonumber(token)
		if id then
			table.insert(ids, id)
		end
	end
	return ids
end

local areas_mod_loaded = minetest.get_modpath("areas") ~= nil
if areas_mod_loaded then
	apartment.areas = {}

	areas:registerOnRemove(
		function (rem_area_id)
			local pos = apartment.areas[rem_area_id]
			if pos then
				local meta = minetest.get_meta(pos)
				local area_ids = meta:get_string("area_id")
				area_ids = apartment.split_string(area_ids)
				local new_area_ids = ""
				for _, id in ipairs(area_ids) do
					if id ~= rem_area_id then
						new_area_ids = new_area_ids .. id .. " "
					end
				end
				meta:set_string("area_id", new_area_ids)
				apartment.areas[rem_area_id] = nil
				apartment.data_modified = true
			end
		end
	)
end

-- v2 will contain information about all apartments of the server in the form:
-- { cat = { ap_descr = { pos = {x=0,y=0,z=0}, original_owner='', owner='' } } }
apartment.apartments = {}
apartment.working = true
apartment.data_modified = false
local WP = minetest.get_worldpath()
local MP = minetest.get_modpath("apartment")
apartment.save_path_v1 = WP .. "/apartment.data"
apartment.save_path = WP .. "/apartment_v2.data"
apartment.save_path_bak = WP .. "/apartment_v2.data.bak"
apartment.gui = dofile(MP .. "/gui.lua")

apartment.save_data = function()
	minetest.log("action", "[Apartment] Saving data")
	for k, v in pairs(apartment.apartments) do
		if next(v) == nil then
			minetest.log("action", "[Apartment] Category " .. k .. " is empty, removed.")
			apartment.apartments[k] = nil
		end
	end
	local buffer = { apartments = apartment.apartments }
	if areas_mod_loaded then
		buffer.areas = apartment.areas
	end
	local data = minetest.serialize(buffer)
	if minetest.safe_file_write(apartment.save_path, data) then
		return true
	else
		minetest.log("error", "[Apartment] Failed to write save file: " .. apartment.save_path)
	end
end

local function save_loop()
	if apartment.data_modified then
		apartment.data_modified = false
		apartment.save_data()
	end
	minetest.after(1, save_loop)
end
minetest.after(1, save_loop)
minetest.register_on_shutdown(apartment.save_data)

apartment.migrate_v1 = function()
	minetest.log("action", "[Apartment] Finding old files...")
	local file_v1 = io.open(apartment.save_path_v1, "r")
	if not file_v1 then
		minetest.log("error", "[Apartment] v1 save file not found.")
		return false
	end
	local s_data_v1 = file_v1:read("*all")
	if s_data_v1 == "" then
		minetest.log("error", "[Apartment] v1 save file was empty.")
		file_v1:close()
		return false
	end
	local data_v1 = minetest.deserialize(s_data_v1)
	if data_v1 == nil then  -- Known bug of advtrains: when file grows, it may fail to load.
		apartment.working = false -- Even if pcall()ed, the mod will still refuse to do any operations.
		error("[Apartment] Failed to deserialize v1 data. Please solve this problem manually.")
		return false
	end
	local data_v2 = {}
	for k, v in pairs(data_v1) do
		if v.category then
			if not data_v2[v.category] then data_v2[v.category] = {} end
			data_v2[v.category][k] = { pos = v.pos, owner = v.owner }
		end
	end
	return data_v2
end

apartment.restore_data = function()
	local file = io.open(apartment.save_path, "r")
	if not file then
		minetest.log("action", "[Apartment] v2 save file not found. Finding v1 files...")
		local data = apartment.migrate_v1()
		if data then
			apartment.apartments = data
		end
		apartment.data_modified = true
	else
		local s_data = file:read("*all")
		if s_data == "" then
			minetest.log("error", "[Apartment] Save file was empty: " .. apartment.save_path)
			file:close()
			return false
		end
		local data = minetest.deserialize(s_data)
		if data == nil then  -- Known bug of advtrains: when file grows, it may fail to load.
			apartment.working = false -- Even if pcall()ed, the mod will still refuse to do any operations.
			error("[Apartment] Failed to deserialize data. Please solve this problem manually.")
			return false
		end
		if data.apartments then
			apartment.apartments = data.apartments
			apartment.areas = data.areas
		else
			apartment.apartments = data
		end
		return true
	end
end

dofile(MP .. "/chg_owner.lua")

apartment.rent = function(pos, owner, oldmetadata, actor)
	local node = minetest.get_node(pos)
	local meta, original_owner, now_owner, descr, category, size_up, size_down, size_right, size_left, size_front, size_back
	if not oldmetadata then
		meta           = minetest.get_meta(pos)
		original_owner = meta:get_string('original_owner')
		now_owner      = meta:get_string('owner')
		descr          = meta:get_string('descr')
		category       = meta:get_string('category')

		size_up        = meta:get_int('size_up');
		size_down      = meta:get_int('size_down');
		size_right     = meta:get_int('size_right');
		size_left      = meta:get_int('size_left');
		size_front     = meta:get_int('size_front');
		size_back      = meta:get_int('size_back');
	else
		original_owner = oldmetadata.fields["original_owner"]
		now_owner      = oldmetadata.fields["owner"]
		descr          = oldmetadata.fields["descr"]
		category       = oldmetadata.fields["category"]

		size_up        = tonumber(oldmetadata.fields["size_up"])
		size_down      = tonumber(oldmetadata.fields["size_down"])
		size_right     = tonumber(oldmetadata.fields["size_right"])
		size_left      = tonumber(oldmetadata.fields["size_left"])
		size_front     = tonumber(oldmetadata.fields["size_front"])
		size_back      = tonumber(oldmetadata.fields["size_back"])

		node.param2    = oldmetadata.param2
	end
	if not (original_owner and now_owner and descr and size_up and size_down and size_right and size_left and size_front and size_back) then
		return false, "META_LOOKUP_ERR"
	end

	local x1 = pos.x;
	local y1 = pos.y;
	local z1 = pos.z;
	local x2 = pos.x;
	local y2 = pos.y;
	local z2 = pos.z;

	if node.param2 == 0 then -- z gets larger
		x1 = x1 - size_left; x2 = x2 + size_right;
		z1 = z1 - size_front; z2 = z2 + size_back;
	elseif node.param2 == 1 then -- x gets larger
		z1 = z1 - size_right; z2 = z2 + size_left;
		x1 = x1 - size_front; x2 = x2 + size_back;
	elseif node.param2 == 2 then -- z gets smaller
		x1 = x1 - size_right; x2 = x2 + size_left;
		z1 = z1 - size_back; z2 = z2 + size_front;
	elseif node.param2 == 3 then -- x gets smaller
		z1 = z1 - size_left; z2 = z2 + size_right;
		x1 = x1 - size_back; x2 = x2 + size_front;
	end
	y1 = y1 - size_down; y2 = y2 + size_up;

	local px = x1;
	local py = x1;
	local pz = z1;
	for px = x1, x2 do
		for py = y1, y2 do
			for pz = z1, z2 do
				local npos = vector.new(px, py, pz)
				apartment.chg_owner(pos, npos, category, descr, original_owner, now_owner, owner, actor)
			end
		end
	end

	if not apartment.apartments[category] then apartment.apartments[category] = {} end
	if not oldmetadata then
		meta:set_string("owner", owner)
		apartment.apartments[category][descr] = { pos = pos, original_owner = original_owner, owner = owner }
		apartment.data_modified = true
		if (owner == "" or original_owner == owner) and (node.name == 'apartment:apartment_occupied') then
			minetest.swap_node(pos, { name = 'apartment:apartment_free', param2 = node.param2 })
		elseif (original_owner ~= owner) and (node.name == 'apartment:apartment_free') then
			minetest.swap_node(pos, { name = 'apartment:apartment_occupied', param2 = node.param2 })
		end
	end
	if areas_mod_loaded and owner ~= "" then
		local area_ids
		if not oldmetadata then
			area_ids = meta:get_string('area_id')
		else
			area_ids = oldmetadata.fields['area_id'] or ""	
		end
		if area_ids ~= "" then
			area_ids = apartment.split_string(area_ids)
			local new_area_ids = ""
			for _, id in ipairs(area_ids) do
				local success, msg = minetest.registered_chatcommands["change_owner"].func(
					original_owner,
					tostring(id) .. " " .. owner
				)
				if success then
					new_area_ids = new_area_ids .. id .. " "
				else
					minetest.log("error", "[Apartment] Failed to set owner of area " .. id .. " (" .. msg .. "). Its ID will be removed from Apartment registry.")
				end
			end
			if not oldmetadata then
				meta:set_string("area_id", new_area_ids)
			end
		end
	end
	return true
end

apartment.on_construct = function(pos)
	local meta = minetest.get_meta(pos);
	meta:set_string('infotext', S('Apartment Management Panel (unconfigured)'))
	meta:set_string('original_owner', '')
	meta:set_string('owner', '')
	meta:set_string('descr', '')
	meta:set_string('area_id', '')
	meta:set_int('size_up', 0)
	meta:set_int('size_down', 0)
	meta:set_int('size_right', 0)
	meta:set_int('size_left', 0)
	meta:set_int('size_front', 0)
	meta:set_int('size_back', 0)
end

apartment.after_place_node = function(pos, placer)
	local meta  = minetest.get_meta(pos);
	local pname = (placer:get_player_name() or "");
	meta:set_string("original_owner", pname);
	meta:set_string("owner", pname);
	meta:set_string('infotext', S('Apartment Management Panel (owned by @1)', pname))
end

apartment.can_dig = function(pos, player)
	local meta           = minetest.get_meta(pos)
	local owner          = meta:get_string('owner')
	local original_owner = meta:get_string('original_owner')
	local pname          = player:get_player_name()

	if not minetest.check_player_privs(pname, { apartment = true }) then
		minetest.chat_send_player(pname, S('Sorry. You have not required privilege to dig it.'));
		return false
	end
	if original_owner == '' then
		return true
	end
	if not (original_owner == owner or owner == "") then
		minetest.chat_send_player(pname, S('The apartment is currently rented to @1. Please end that first.', owner));
		return false
	end
	return true
end

apartment.after_dig_node = function(pos, oldnode, oldmetadata, digger)
	if not (oldmetadata) or oldmetadata == "nil" or not (oldmetadata.fields) then
		minetest.chat_send_player(digger:get_player_name(),
			S("Error: Could not find information about the apartment panel that is to be removed."))
		return
	end

	local descr = oldmetadata.fields["descr"]
	local category = oldmetadata.fields["category"]
	if (apartment.apartments[category] and apartment.apartments[category][descr]) then
		-- actually remove the apartment
		oldmetadata.param2 = oldnode.param2
		apartment.rent(pos, '', oldmetadata, digger)
		apartment.apartments[category][descr] = nil
		if areas_mod_loaded then
			local meta = minetest.get_meta(pos)
			local area_ids = meta:get_string("area_id")
			area_ids = apartment.split_string(area_ids)
			for _, id in ipairs(area_ids) do
				apartment.areas[id] = nil
			end
		end
		apartment.data_modified = true
		minetest.chat_send_player(digger:get_player_name(), S("Removed apartment @1@@@2 successfully.", descr, category))
	end
end

apartment.on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
	if not apartment.working then return end
	if not clicker:is_player() then return end
	local name           = clicker:get_player_name()
	local meta           = minetest.get_meta(pos)

	local ctx            = { pos = pos, meta = meta }
	local owner          = meta:get_string('owner')
	local original_owner = meta:get_string('original_owner')
	local category       = meta:get_string('category')
	if original_owner == owner and category == "" then
		if itemstack:get_name() == "apartment:configuration_copier" then
			local imeta = itemstack:get_meta()
			ctx.defaults = {}
			ctx.defaults.category = imeta:get_string("category")
			ctx.defaults.descr = imeta:get_string("descr")

			if ctx.defaults.category == "" or ctx.defaults.descr == "" then
				ctx.defaults = nil -- Unconfigured copier
			else
				while apartment.apartments[ctx.defaults.category][ctx.defaults.descr] do
					local number = string.match(ctx.defaults.descr, '%d+$')
					local new_descr = ctx.defaults.descr .. "_1"
					if number then
						new_descr = string.sub(ctx.defaults.descr, 1, - #tostring(number) - 1) .. tostring(number + 1)
					end
					ctx.defaults.descr = new_descr
				end
				ctx.defaults.size_up    = imeta:get_int('size_up')
				ctx.defaults.size_down  = imeta:get_int('size_down')
				ctx.defaults.size_right = imeta:get_int('size_right')
				ctx.defaults.size_left  = imeta:get_int('size_left')
				ctx.defaults.size_front = imeta:get_int('size_front')
				ctx.defaults.size_back  = imeta:get_int('size_back')
			end
		end
		apartment.gui.configure_gui:show(clicker, ctx)
	else
		apartment.gui.panel_control:show(clicker, ctx)
	end
end

local function on_place(itemstack, placer, pointed_thing)
	if not placer or not placer:is_player() then
		return itemstack
	end
	local pname = placer:get_player_name()
	if not minetest.check_player_privs(pname, { apartment = true }) then
		minetest.chat_send_player(pname, S('Sorry. You have not required privilege to place it.'));
		return itemstack
	end

	return minetest.item_place(itemstack, placer, pointed_thing)
end

minetest.register_craftitem("apartment:configuration_copier", {
	description = S("Apartment Configuration Copier"),
	inventory_image = "apartment_configuration_copier.png",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if not user:is_player() then return end
		local name = user:get_player_name()
		if pointed_thing.type ~= "node" then return end
		local pos = pointed_thing.under
		local node = minetest.get_node(pos)
		if node.name ~= "apartment:apartment_free" and node.name ~= "apartment:apartment_occupied" then return end
		local meta = minetest.get_meta(pos)
		local category = meta:get_string("category")
		local descr = meta:get_string("descr")

		if category == "" or descr == "" then
			minetest.chat_send_player(name, S("Please configure the panel first before copying configurations from it."))
			return
		end

		local size_up    = meta:get_int('size_up')
		local size_down  = meta:get_int('size_down')
		local size_right = meta:get_int('size_right')
		local size_left  = meta:get_int('size_left')
		local size_front = meta:get_int('size_front')
		local size_back  = meta:get_int('size_back')

		local imeta      = itemstack:get_meta()

		imeta:set_string("category", category)
		imeta:set_string("descr", descr)

		imeta:set_int("size_up", size_up)
		imeta:set_int("size_down", size_down)
		imeta:set_int("size_right", size_right)
		imeta:set_int("size_left", size_left)
		imeta:set_int("size_front", size_front)
		imeta:set_int("size_back", size_back)

		imeta:set_string("description",
			S(
			"Apartment Configuaration Copier\nU:@1 D:@2 L:@3 R:@4 F:@5 B:@6\n@7@@@8\nRightclick on a panel to paste the configurations.",
				size_up, size_down, size_right, size_left, size_front, size_back, descr, category))

		minetest.chat_send_player(name, S("Configuration copied."))

		return itemstack
	end,
})

minetest.register_node("apartment:apartment_free", {
	description       = S("Apartment Management Panel"),
	drawtype          = "nodebox",
	tiles             = { "default_steel_block.png", "default_steel_block.png", "default_steel_block.png",
		"default_steel_block.png",
		"default_steel_block.png", "apartment_controls_vacant.png", "default_steel_block.png" },
	use_texture_alpha = "opaque",
	paramtype         = "light",
	paramtype2        = "facedir",
	light_source      = 14,
	groups            = { cracky = 2 },
	node_box          = {
		type = "fixed",
		fixed = {
			{ -0.5 + (1 / 16), -0.5 + (1 / 16), 0.5, 0.5 - (1 / 16), 0.5 - (1 / 16), 0.30 },

		}
	},
	on_construct      = apartment.on_construct,
	after_place_node  = apartment.after_place_node,
	can_dig           = apartment.can_dig,
	after_dig_node    = apartment.after_dig_node,
	on_rightclick     = apartment.on_rightclick,
	on_place          = on_place
})

minetest.register_node("apartment:apartment_occupied", {
	drawtype          = "nodebox",
	tiles             = { "default_steel_block.png", "default_steel_block.png", "default_steel_block.png",
		"default_steel_block.png",
		"default_steel_block.png", "apartment_controls_occupied.png", "default_steel_block.png" },
	use_texture_alpha = "opaque",
	paramtype         = "light",
	paramtype2        = "facedir",
	light_source      = 14,
	groups            = { cracky = 2, not_in_creative_inventory = 1 },
	node_box          = {
		type = "fixed",
		fixed = {
			{ -0.5 + (1 / 16), -0.5 + (1 / 16), 0.5, 0.5 - (1 / 16), 0.5 - (1 / 16), 0.30 },

		}
	},
	on_construct      = apartment.on_construct,
	after_place_node  = function(pos, placer)
		local node = minetest.get_node(pos)
		node.name = "apartment:apartment_free"
		minetest.swap_node(pos, node)
		return apartment.after_place_node(pos, placer)
	end,
	can_dig           = apartment.can_dig,
	after_dig_node    = apartment.after_dig_node,
	on_rightclick     = apartment.on_rightclick,
	on_place          = on_place
})

if apartment.enable_aphome_command then
	minetest.register_chatcommand("aphome", {
		params = S("[<category>]"),
		description = S("Teleports you back to the apartment you rented."),
		privs = { home = true },
		func = function(name, param)
			local category = (param == "" and "apartment" or param)
			local player = minetest.get_player_by_name(name)

			if not apartment.apartments[category] then
				return false, S("You do not have an apartment in category @1.", category)
			end

			for k, v in pairs(apartment.apartments[category]) do
				if v and v.owner == name then
					player:set_pos(v.pos)
					return true, S("Welcome back to your apartment @1@@@2.", k, category)
				end
			end

			return false, S("You do not have an apartment in category @1.", category)
		end
	})
end

-- old version of the node - will transform into _free or _occupied
if minetest.settings:get_bool("apartment.old_compact_codes", true) then
	minetest.register_node("apartment:apartment", {
		drawtype      = "nodebox",
		description   = "apartment management panel (transition state)",
		tiles         = { "default_steel_block.png", "default_steel_block.png", "default_steel_block.png",
			"default_steel_block.png",
			"default_steel_block.png", "apartment_controls_vacant.png", "default_steel_block.png" },
		paramtype     = "light",
		paramtype2    = "facedir",
		light_source  = 14,
		groups        = { cracky = 2, not_in_creative_inventory = 1 },
		node_box      = {
			type = "fixed",
			fixed = {
				{ -0.5 + (1 / 16), -0.5 + (1 / 16), 0.5, 0.5 - (1 / 16), 0.5 - (1 / 16), 0.30 },

			}
		},
		selection_box = {
			type = "fixed",
			fixed = {
				{ -0.5 + (1 / 16), -0.5 + (1 / 16), 0.5, 0.5 - (1 / 16), 0.5 - (1 / 16), 0.30 },
			}
		},
	})

	minetest.register_lbm({
		name = "apartment:upgrade",
		nodenames = { "apartment:apartment" },
		run_at_every_load = false,
		action = function(pos, node)
				local meta = minetest.get_meta(pos)
				local owner = meta:get_string('owner')
				local original_owner = meta:get_string('original_owner')
				if owner == '' or original_owner == owner then
					minetest.swap_node(pos, { name = 'apartment:apartment_free', param2 = node.param2 })
				else
					minetest.swap_node(pos, { name = 'apartment:apartment_occupied', param2 = node.param2 })
				end
				meta:set_string("formspec", "")
		
				local descr = meta:get_string("descr")
				local category = meta:get_string("category")

				local cat_data = apartment.apartments[category]
				if not cat_data then return end
				local ap_data = cat_data[descr]
				if not ap_data then return end

				if not vector.equals(ap_data.pos, pos) then -- Dulplicated!
					local new_data = table.copy(ap_data)
					new_data.pos = pos
					local number = string.match(descr, '%d+$')
					local new_descr = descr .. "_1"
					if number then
						new_descr = string.sub(descr, 1, - #tostring(number) - 1) .. tostring(number + 1)
					end
					meta:set_string("descr", new_descr)
					cat_data[new_descr] = new_data
					apartment.data_modified = true
				end		
		end
	})
end

apartment.restore_data()
