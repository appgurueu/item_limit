# Item Limit - Configuration

## Locations

JSON Configuration : `<worldpath>/config/item_limit.json`

Text Logs : `<worldpath>/logs/item_limit/<date>.json`

Explaining document(this, Markdown) : `<modpath/gamepath>/item_limit/config_help.md`

Readme : `<modpath/gamepath>/item_limit/Readme.md`

## Default Configuration
Located under `<modpath/gamepath>/item_limit/default_config.json`
```json
{
  "player_inventory_lists": ["main", "craft"],
  "limits" : {
    "by_item_name" : {},
    "by_group_name" : {}
  },
  "disable_item_override" : false,
  "disable_node_drop_override" : false,
  "disable_on_craft" : false,
  "disable_on_inventory_action" : false,
  "disable_itemlimit_skip" : false
}
```

## Usage

### `player_inventory_lists`
A list. Specifies which inventory lists should be taken into account for item limits.
For instance, it makes almost no sense and is not recommended to include the craft preview list.
By default only the main inventory("main") and the crafting grid("craft") are considered.

### `by_item_name`
Limits items in the player's inventory by their name.
Key is the full item name, like `default:dirt`.
Value is the maximum amount that may be in a player's inventory, as number.

### `by_group_name`
Works similar to `by_item_name`, but instead of the per item, items are limited based on their *group*.
If you, for example, wanted to limit the maximum amount of sticks in a player's inventory, you can use `stick`, the full group name, as key.

### `disable_on_craft`
Disable dropping items which may not be taken directly when crafted. If set to `true`, the player will have to manually drop the items he can't put into his inventory.

### `disable_itemlimit_skip`
Disable the itemlimit skip privilege, which allows players to ignore the item limit.

### Other `disable_*` flags
Disable several barriers disallowing players to exceed their item limit, such as the item override(player can exceed limit through picking up items), the on_node_drop override(player can exceed limit through digging nodes), etc.
**It is not recommmended to set these to `true`.**