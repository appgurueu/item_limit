return {
    type = "table",
    entries = {
        player_inventory_lists = {
            type = "table",
            keys = {type = "number", int = true, range = {min = 1}},
            values = {type = "string"},
			default = {"main", "craft"},
			description = "Which player inventory lists to take into account for item limits."
        },
        limits = {
			type = "table",
			entries = {
				by_item_name = {
					type = "table",
					keys = {type = "string"},
					values = {type = "number"},
					description = "Key: Technical item name; value: maximum total count in inventory"
				},
				by_group_name = {
					type = "table",
					keys = {type = "string"},
					values = {type = "number"},
					description = "Key: Technical group name; value: maximum total count in inventory"
				}
			}
		}
    }
}
