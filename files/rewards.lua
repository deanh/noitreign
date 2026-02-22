-- rewards.lua — Holy Mountain rewards: HP boost + random perk

local function get_setting(key, default)
	local val = ModSettingGet("noitreign." .. key)
	if val == nil then return default end
	return val
end

-- Reuses the give_perk_to_player pattern from daily_practice
local function give_perk(perk_id, player)
	local perk_data = get_perk_with_id(perk_list, perk_id)
	if perk_data == nil then return end

	-- Progress flags
	local flag_name = get_perk_picked_flag_name(perk_id)
	local flag_name_persistent = string.lower(flag_name)
	if HasFlagPersistent(flag_name_persistent) == false then
		GameAddFlagRun("new_" .. flag_name_persistent)
	end
	GameAddFlagRun(flag_name)
	AddFlagPersistent(flag_name_persistent)

	-- Apply game effect
	if perk_data.game_effect ~= nil then
		local game_effect_comp = GetGameEffectLoadTo(player, perk_data.game_effect, true)
		if game_effect_comp ~= nil then
			ComponentSetValue(game_effect_comp, "frames", "-1")
		end
	end

	-- Apply perk function
	if perk_data.func ~= nil then
		perk_data.func(0, player, "")
	end

	-- Add UI icon
	local entity_ui = EntityCreateNew("")
	EntityAddComponent(entity_ui, "UIIconComponent", {
		name = perk_data.ui_name,
		description = perk_data.ui_description,
		icon_sprite_file = perk_data.ui_icon,
	})
	EntityAddChild(player, entity_ui)
end

-- Build filtered perk pool: default-pool perks the player doesn't already have
function noitreign_build_perk_pool(player)
	local pool = {}
	for i, perk in ipairs(perk_list) do
		if perk.not_in_default_perk_pool or GameHasFlagRun(get_perk_picked_flag_name(perk.id)) then
			goto continue
		end
		table.insert(pool, perk.id)
		::continue::
	end
	return pool
end

-- ============================================================
-- Check: called every frame, grants rewards on HM entry
-- ============================================================
local granted_workshops = {}  -- Lua-local guard (immune to Globals timing issues)

function noitreign_rewards_check(player)
	local state = GlobalsGetValue("NOITREIGN_STATE", "counting_down")
	if state ~= "safe_zone" and state ~= "overtime_safe" then return end

	-- Guard: one reward per holy mountain (keyed to workshop position)
	local workshop_key = GlobalsGetValue("NOITREIGN_CURRENT_WORKSHOP_KEY", "")
	if workshop_key == "" then return end
	if granted_workshops[workshop_key] then return end
	local grant_key = "NOITREIGN_HM_GRANTED_" .. workshop_key
	if GlobalsGetValue(grant_key, "0") == "1" then return end
	granted_workshops[workshop_key] = true
	GlobalsSetValue(grant_key, "1")

	-- HP Boost
	local bonus_hp = get_setting("bonus_hp", 50)
	if bonus_hp > 0 then
		local internal_hp = bonus_hp / 25.0
		local damagemodels = EntityGetComponent(player, "DamageModelComponent")
		if damagemodels ~= nil then
			for i, comp in ipairs(damagemodels) do
				local current_max = ComponentGetValue2(comp, "max_hp")
				ComponentSetValue2(comp, "max_hp", current_max + internal_hp)
			end
		end
		GamePrint("Noitreign: +" .. tostring(bonus_hp) .. " HP!")
	end

	-- Random Perk
	local grant_perk = get_setting("grant_perk", true)
	if grant_perk then
		local pool = noitreign_build_perk_pool(player)
		if #pool > 0 then
			SetRandomSeed(GameGetFrameNum(), GameGetFrameNum() * 137)
			local chosen_id = pool[Random(1, #pool)]
			give_perk(chosen_id, player)

			local perk_data = get_perk_with_id(perk_list, chosen_id)
			local name = perk_data and perk_data.ui_name or chosen_id
			GamePrint("Noitreign: Perk granted — " .. name)
		end
	end
end
