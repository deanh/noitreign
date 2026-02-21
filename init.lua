dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/perks/perk_list.lua")
dofile_once("data/scripts/perks/perk.lua")

ModLuaFileAppend("data/scripts/items/generate_shop_item.lua",
    "mods/noitreign/files/shop_discount.lua")

dofile_once("mods/noitreign/files/timer.lua")
dofile_once("mods/noitreign/files/rewards.lua")
dofile_once("mods/noitreign/files/gui.lua")

function OnPlayerSpawned(player_entity)
	local key = "NOITREIGN_INIT_DONE"
	local is_initialized = GlobalsGetValue(key, "0")

	if is_initialized == "1" then
		-- Reload: reconstruct timer from saved remaining seconds
		noitreign_timer_restore(player_entity)
		return
	end
	GlobalsSetValue(key, "1")

	-- First spawn: initialize timer state
	noitreign_timer_init(player_entity)

	GamePrint("Noitreign: The clock is ticking...")
end

function OnWorldPostUpdate()
	local player = EntityGetWithTag("player_unit")
	if player == nil or #player == 0 then return end
	player = player[1]

	noitreign_timer_update(player)
	noitreign_rewards_check(player)
	noitreign_gui_update(player)
end
