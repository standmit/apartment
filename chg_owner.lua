local S_default = minetest.get_translator("default")
local S_doors = minetest.get_translator("doors")
local S_currency = minetest.get_translator("currency")
local S = minetest.get_translator("apartment")

local function sstarts(String, Start) -- http://stackoverflow.com/questions/22831701/ddg#22831842
	return string.sub(String, 1, string.len(Start)) == Start
end

apartment.chg_owner = function(panel_pos, pos, category, descr, original_owner, now_owner, owner, actor)
	local meta = minetest.get_meta(pos)
	local n = minetest.get_node(pos)
	if not meta then return false, "META_NF" end
	local node_now_owner = meta:get_string("owner")
	if node_now_owner == "" then
		node_now_owner = meta:get_string("doors_owner")
	end; if node_now_owner == "" then
		node_now_owner = original_owner
	end
	if node_now_owner == original_owner or node_now_owner == now_owner or node_now_owner == actor then
		local owner_or_orig = (owner ~= "" and owner) or original_owner
		if n.name == "locks:shared_locked_chest" then
			locks:lock_set_owner(pos, owner_or_orig, "Shared locked chest")
		elseif n.name == "locks:shared_locked_furnace" then
			locks:lock_set_owner(pos, owner_or_orig, "Shared locked furnace")
		elseif n.name == "locks:shared_locked_sign_wall" then
			locks:lock_set_owner(pos, owner_or_orig, "Shared locked sign")
		elseif sstarts(n.name, "locks:door") then
			locks:lock_set_owner(pos, owner_or_orig, "Shared locked door")
		elseif n.name == "vendor:vendor" or n.name == "vendor:depositor" then
			meta:set_string("owner", owner_or_orig)
			vendor.refresh(pos, nil)
		elseif n.name == "travelnet:travelnet" or n.name == "travelnet:elevator"
			or n.name == "locked_travelnet:elevator" or n.name == "locked_travelnet:travelnet" then
			local oldmetadata = meta:to_table()
			travelnet.remove_box(pos, nil, oldmetadata, actor)
			meta:set_string("owner", owner_or_orig)
			minetest.registered_nodes[n.name].after_place_node(pos, actor, nil)
		elseif string.find(n.name, "^smartshop:shop") then
			if smartshop.update_info then -- AiTechEye
				meta:set_string("owner", owner_or_orig)
				if meta:get_int("type") == 0 and not (minetest.check_player_privs(owner_or_orig, { creative = true }) or minetest.check_player_privs(owner_or_orig, { give = true })) then
					-- Avoid non-unlimited player taking unlimited player's smartshop'
					meta:set_int("creative", 0)
					meta:set_int("type", 1)
				end
				smartshop.update_info(pos)
			elseif smartshop.api and smartshop.api.get_object then -- flux
				local obj = smartshop.api.get_object(pos)
				obj:initialize_metadata(owner_or_orig)
				obj:set_unlimited(false)
				obj:initialize_inventory()
				obj:update_appearance()
			end
		else -- These does not require special processing
			local disp_pname = owner or "- vacant -"
			local disp_descr = descr .. "@" .. category
			local infotext = ""
			if n.name == "default:chest_locked" or n.name == "default:chest_locked_open" then
				if original_owner == owner then
					infotext = S_default("Locked Chest (owned by @1)", original_owner)
				else
					infotext = S("@1 in Ap. @2 (@3)", S_default("Locked Chest"), disp_descr, disp_pname)
				end
			elseif sstarts(n.name, "doors:door_steel_") then
				if original_owner == owner then
					infotext = S_doors("Steel Door") .. "\n" .. S_doors("Owned by @1", original_owner)
				else
					infotext = S("Apartment @1 (@2)", disp_descr, disp_pname)
				end
			elseif n.name == "locked_sign:sign_wall_locked" then
				if original_owner == owner then
					infotext = "\"\" (" .. original_owner .. ")"
				else
					infotext = "\"\" (" .. disp_pname .. ")"
				end
			elseif n.name == 'apartment:apartment_free' or n.name == 'apartment:apartment_occupied' then
				if vector.equals(panel_pos, pos) then
					if original_owner == owner then
						infotext = S("Rent apartment @1 here by right-clicking this panel!", disp_descr)
					else
						infotext = S("Apartment rental control panel for apartment @1 (@2)", disp_descr, disp_pname)
					end
				end
			elseif n.name == "technic:iron_locked_chest" then
				if original_owner == owner then
					infotext = "Iron Locked Chest (owned by " .. original_owner .. ")"
				else
					infotext = "Iron Locked Chest in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "technic:copper_locked_chest" then
				if original_owner == owner then
					infotext = "Copper Locked Chest (owned by " .. original_owner .. ")"
				else
					infotext = "Copper Locked Chest in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "technic:silver_locked_chest" then
				if original_owner == owner then
					infotext = "Silver Locked Chest (owned by " .. original_owner .. ")"
				else
					infotext = "Silver Locked Chest in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "technic:gold_locked_chest" then
				if original_owner == owner then
					infotext = "Gold Locked Chest (owned by " .. original_owner .. ")"
				else
					infotext = "Gold Locked Chest in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "technic:mithril_locked_chest" then
				if original_owner == owner then
					infotext = "Mithril Locked Chest (owned by " .. original_owner .. ")"
				else
					infotext = "Mithril Locked Chest in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "inbox:empty" then
				if original_owner == owner then
					infotext = original_owner .. "'s Mailbox";
				else
					infotext = disp_pname .. "'s Mailbox";
				end
			elseif n.name == "itemframes:frame" then
				if original_owner == owner then
					infotext = "Item frame (owned by" .. original_owner .. ")"
				else
					infotext = "Item frame in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "itemframes:pedestral" then
				if original_owner == owner then
					infotext = "Pedestral frame (owned by " .. original_owner .. ")"
				else
					infotext = "Pedestral frame in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "currency:safe" then
				if original_owner == owner then
					infotext = S_currency("Safe (owned by @1)", original_owner)
				else
					infotext = S("@1 in Ap. @2 (@3)", S_currency("Safe"), disp_descr, disp_pname)
				end
			elseif n.name == "currency:shop" then
				if original_owner == owner then
					infotext = S_currency("Exchange shop (owned by @1)", original_owner)
				else
					infotext = S("@1 in Ap. @2 (@3)", S_currency("Shop"), disp_descr, disp_pname)
				end
			elseif n.name == "bitchange:bank" then
				if original_owner == owner then
					infotext = "Bank (owned by " .. original_owner .. ")"
				else
					infotext = "Bank in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "bitchange:moneychanger" then
				if original_owner == owner then
					infotext = "Moneychanger (owned by " .. original_owner .. ")"
				else
					infotext = "Moneychanger in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "bitchange:warehouse" then
				if original_owner == owner then
					infotext = "Warehouse (owned by " .. original_owner .. ")"
				else
					infotext = "Warehouse in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			elseif n.name == "bitchange:shop" then
				local pname = disp_pname
				if original_owner == owner then
					pname = original_owner
				end
				if meta:get_string('title') ~= '' then
					infotext = "Exchange shop \"" .. (meta:get_string('title')) .. "\" (" .. pname .. ")";
				else
					infotext = "Exchange shop (" .. pname .. ")";
				end
			elseif n.name == "basic_signs:sign_wall_locked" then
				if original_owner == owner then
					infotext = "Locked sign, owned by " .. original_owner .. ")"
				else
					infotext = "Locked sign in Ap. " .. descr .. " (" .. disp_pname .. ")"
				end
			end
			if infotext ~= "" then
				meta:set_string("infotext", infotext)
				meta:set_string("owner", owner_or_orig)
				meta:set_string("doors_owner", owner_or_orig)
			end
		end
	end
end
