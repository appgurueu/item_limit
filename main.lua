-- Load config
local config = modlib.mod.configuration()

modlib.table.add_all(getfenv(1), config)

function count(inv_ref, match_function) -- Calls match function with the item name
    local count=0
    for _,listname in pairs(player_inventory_lists) do
        local list=inv_ref:get_list(listname)
        for i=1, #list do
            if match_function(list[i]:get_name()) then
                count=count+list[i]:get_count()
            end
        end
    end
    return count
end

function count_item_by_name(inv_ref, item_name)
    return count(inv_ref, function(item_name_b)
        if item_name_b==item_name then
            return true
        end
        return false
    end)
end

function count_item_by_group(inv_ref, group_name)
    return count(inv_ref, function(item_name_b)
        return minetest.registered_items[item_name_b].groups[group_name] ~= nil
    end)
end

function get_max_allowed(inv_ref, item_name)
    local max_allowed={}
    if limits.by_item_name[item_name] then
        local item_limit=limits.by_item_name[item_name]
        table.insert(max_allowed, item_limit-count_item_by_name(inv_ref, item_name))
    end

    local groups=minetest.registered_items[item_name].groups
    if groups then
        for group_name,_ in pairs(groups) do
            local group_limit=limits.by_group_name[group_name]
            if group_limit then
                table.insert(max_allowed, group_limit-count_item_by_group(inv_ref, group_name))
            end
        end
    end
	if #max_allowed == 0 then return end
    return math.max(0, math.max(unpack(max_allowed)))
end

minetest.register_privilege("itemlimit_skip", {
	name = "Player can ignore item limit restrictions",
	give_to_singleplayer = false
})
function has_itemlimit_skip(player_or_name)
	return (minetest.check_player_privs(player_or_name, {"itemlimit_skip"}))
end

-- Possible to exceed limits through picking up items, prevented by item override
local builtin_item = minetest.registered_entities["__builtin:item"]
local original_on_punch = builtin_item.on_punch
function builtin_item:on_punch(puncher, time_from_last_punch, tool_capabilities, dir)
	if has_itemlimit_skip(puncher) then -- if a player has itemlimit_skip, he can ignore it
		return original_on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	end
	local stack = ItemStack(self.itemstring)
	local max_allowed=get_max_allowed(puncher:get_inventory(), stack:get_name()) or stack:get_count()
	print(max_allowed)
	local left=puncher:get_inventory():add_item("main", stack:peek_item(max_allowed))
	if not left then
		left=0
	else
		left=left:get_count()
	end

	if left == 0 then --Nothing left
		if stack:get_count() ==  max_allowed then -- Everything used up
			self.object:remove() -- Remove
			return
		else
			if max_allowed > stack:get_count() then
				self.object:remove() -- Remove
				return
			end
			stack:set_count(stack:get_count()-max_allowed) -- Just take the items
		end
	else
		stack:set_count(stack:get_count()-max_allowed+left:get_count()) -- Add the items that are left
	end
	self:set_item(stack:to_string()) -- Set the item
end

-- Inventory actions, such as taking items from furnance/chest. Only as much may be taken as allowed.
minetest.register_allow_player_inventory_action(function(player, action, _, inventory_info)
	if has_itemlimit_skip(player) then -- if a player has itemlimit_skip, he can ignore it
		return
	end
	local allowed
	if action=="put" then
		allowed=get_max_allowed(player:get_inventory(), inventory_info.stack:get_name())
	elseif action=="move" then
		allowed=get_max_allowed(player:get_inventory(), player:get_inventory():get_stack(inventory_info.from_list, inventory_info.from_index):get_name())
	end
	return allowed
end)

-- Digging a node may result in obtaining a limited item, handle_node_drops needs to be overridden. Drops left are dropped.
local builtin_handle_node_drops = minetest.handle_node_drops
minetest.handle_node_drops=function(pos, drops, digger)
	if has_itemlimit_skip(digger) then -- if a player has itemlimit_skip, he can ignore it
		return builtin_handle_node_drops(pos, drops, digger)
	end
	for _, itemstring in pairs(drops) do
		local stack=ItemStack(itemstring)
		local max_allowed=get_max_allowed(digger:get_inventory(), stack:get_name()) or stack:get_count()
		local left=digger:get_inventory():add_item("main", stack:peek_item(max_allowed))
		if left and left:get_count() then
			if left:get_count() == 0 then
				if stack:get_count() ==  max_allowed then
					return
				end
				stack:set_count(stack:get_count()-max_allowed)
			else
				stack:set_count(stack:get_count()-max_allowed+left:get_count())
			end
		end
		minetest.add_item(pos, stack:to_string())
	end
end

-- Crafting can also lead to limited items, which possibly exceed the limits. Items which exceed the limits are dropped.
minetest.register_on_craft(function(itemstack, player, _, craft_inv)
	if has_itemlimit_skip(player) then -- if a player has itemlimit_skip, he can ignore it
		return
	end
	local max_allowed=get_max_allowed(player:get_inventory(), itemstack:get_name()) or itemstack:get_count()
	if max_allowed < itemstack:get_count() then
		itemstack:set_count(itemstack:get_count()-max_allowed)
		minetest.add_item(player:get_pos(), itemstack:to_string())
		itemstack:set_count(max_allowed)
	end
	return itemstack
end)
