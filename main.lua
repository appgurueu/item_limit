modlib.log.create_channel("item_limit") -- Create log channel

-- Load config
local config=modlib.conf.import("item_limit", {
    type = "table",
    children = {
        player_inventory_lists = {
            type = "table",
            keys = {type = "number"},
            values = {type = "string"}
        },
        limits={type="table", children= {
            by_item_name = {
                type = "table",
                keys = {type = "string"},
                values = {type = "number"}
            },
            by_group_name = {
                type = "table",
                keys = {type = "string"},
                values = {type = "number"}
            },
        }},
        disable_item_override = {type="boolean"},
        disable_node_drop_override = {type="boolean"},
        disable_on_craft = {type="boolean"},
        disable_on_inventory_action = {type="boolean"},
        disable_itemlimit_skip = {type="boolean"}
    }
})

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
    local min=modlib.table.min(max_allowed)
    if min then
        if min < 0 then
            min=0
        end
        return min
    end
end

if not disable_itemlimit_skip then
    minetest.register_privilege("itemlimit_skip",
            { name="Player can ignore item limit restrictions",give_to_singleplayer=false,
              on_grant=function(name, granter_name)
                  if not granter_name then
                      modlib.log.write("item_limit", "Player "..name.." was granted the itemlimit_skip privilege.")
                  else
                      modlib.log.write("item_limit", "Player "..granter_name.." granted player "..name.." the itemlimit_skip privilege.")
                  end
              end,
              on_revoke=function(name, revoker_name)
                  if not revoker_name then
                      modlib.log.write("item_limit", "Player "..name.." lost the itemlimit_skip privilege.")
                  else
                      modlib.log.write("item_limit", "Player "..revoker_name.." revoked the itemlimit_skip privilege of player "..name..".")
                  end
              end
            })
    function has_itemlimit_skip(player_or_name)
        local ret,_ minetest.check_player_privs(player_or_name, {"itemlimit_skip"})
        return ret
    end
else
    function has_itemlimit_skip()
        return false
    end
end

if not disable_item_override then
    -- Possible to exceed limits through picking up items, prevented by item override
    local builtin_item = minetest.registered_entities["__builtin:item"]
    local item = {
        set_item = function(self, itemstring)
            builtin_item.set_item(self, itemstring)

            self.stack = ItemStack(itemstring)
            local itemdef = minetest.registered_items[self.stack:get_name()]
            if itemdef and itemdef.groups.flammable ~= 0 then
                self.flammable = itemdef.groups.flammable
            end
        end,

        burn_up = function(self)
            builtin_item.burn_up(self)
        end,

        on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
            if has_itemlimit_skip(puncher) then -- if a player has itemlimit_skip, he can ignore it
                return builtin_item.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
            end
            local max_allowed=get_max_allowed(puncher:get_inventory(), self.stack:get_name()) or self.stack:get_count()
            local left=puncher:get_inventory():add_item("main", self.stack:peek_item(max_allowed))
            if not left then
                left=0
            else
                left=left:get_count()
            end

            if left == 0 then --Nothing left
                if self.stack:get_count() ==  max_allowed then -- Everything used up
                    self.object:remove() -- Remove
                    return
                else
                    if max_allowed > self.stack:get_count() then
                        self.object:remove() -- Remove
                        return
                    end
                    self.stack:set_count(self.stack:get_count()-max_allowed) -- Just take the items
                end
            else
                self.stack:set_count(self.stack:get_count()-max_allowed+left:get_count()) -- Add the items that are left
            end
            self:set_item(self.stack:to_string()) -- Set the item
        end,

        on_step = function(self, dtime, ...)
            builtin_item.on_step(self, dtime, ...)
        end
    }
    -- override, default builtin item as fallback
    setmetatable(item, builtin_item)
    minetest.register_entity(":__builtin:item", item)

end

if not disable_on_inventory_action then
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
end

if not disable_node_drop_override then
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
end

if not disable_on_craft then
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
end