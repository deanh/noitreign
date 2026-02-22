dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "noitreign"
mod_settings_version = 1
mod_settings =
{
	{
		category_id = "timer_settings",
		ui_name = "TIMER",
		ui_description = "Biome countdown timer settings",
		foldable = true,
		_folded = false,
		settings = {
			{
				id = "timer_seconds",
				ui_name = "Timer per biome",
				ui_description = "Seconds before curse damage begins in each biome.",
				value_default = 180,
				value_min = 30,
				value_max = 600,
				value_display_multiplier = 1,
				value_display_formatting = " $0 sec",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
			{
				id = "damage_start",
				ui_name = "Starting curse damage",
				ui_description = "HP lost per tick at 100 max HP. Scales with player max HP.",
				value_default = 4,
				value_min = 1,
				value_max = 50,
				value_display_multiplier = 1,
				value_display_formatting = " $0 HP",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
			{
				id = "damage_escalation",
				ui_name = "Damage escalation multiplier",
				ui_description = "Each tick multiplies damage by this amount. 2 = doubling (5, 10, 20, 40...).",
				value_default = 2,
				value_min = 1,
				value_max = 4,
				value_display_multiplier = 1,
				value_display_formatting = " $0x",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
			{
				id = "damage_interval_frames",
				ui_name = "Damage tick interval",
				ui_description = "Frames between each curse damage tick (60 = 1 second).",
				value_default = 120,
				value_min = 30,
				value_max = 300,
				value_display_multiplier = 1,
				value_display_formatting = " $0 frames",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
			{
				id = "biome_bonus_seconds",
				ui_name = "Biome transition bonus",
				ui_description = "Seconds added to the timer when entering a new biome.",
				value_default = 90,
				value_min = 0,
				value_max = 300,
				value_display_multiplier = 1,
				value_display_formatting = " $0 sec",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
		},
	},
	{
		category_id = "shop_settings",
		ui_name = "SHOP",
		ui_description = "Shop price settings",
		foldable = true,
		_folded = false,
		settings = {
			{
				id = "shop_discount",
				ui_name = "Shop discount",
				ui_description = "Percentage discount applied to all shop prices.",
				value_default = 50,
				value_min = 0,
				value_max = 90,
				value_display_multiplier = 1,
				value_display_formatting = " $0%",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
		},
	},
	{
		category_id = "reward_settings",
		ui_name = "REWARDS",
		ui_description = "Holy Mountain reward settings",
		foldable = true,
		_folded = false,
		settings = {
			{
				id = "bonus_hp",
				ui_name = "Bonus HP per Holy Mountain",
				ui_description = "Extra HP granted when entering each Holy Mountain.",
				value_default = 50,
				value_min = 0,
				value_max = 200,
				value_display_multiplier = 1,
				value_display_formatting = " $0 HP",
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
			{
				id = "grant_perk",
				ui_name = "Grant bonus perk",
				ui_description = "Give a random perk at each Holy Mountain.",
				value_default = true,
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
		},
	},
}

function ModSettingsUpdate(init_scope)
	local old_version = mod_settings_get_version(mod_id)
	mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
