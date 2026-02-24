-- timer.lua — State machine for biome tracking, countdown, and curse damage

local DEBOUNCE_FRAMES = 30  -- 0.5s at 60fps to avoid biome flicker

-- ============================================================
-- Helpers
-- ============================================================

local function get_setting(key, default)
	local val = ModSettingGet("noitreign." .. key)
	if val == nil then return default end
	return val
end

local function get_player_biome(player)
	local x, y = EntityGetTransform(player)
	if x == nil then return "" end
	local biome = BiomeMapGetName(x, y)
	return biome or ""
end

local function is_holy_mountain(biome_name)
	return string.find(biome_name, "holymountain") ~= nil
end

local function is_trackable_biome(biome_name)
	if biome_name == nil or biome_name == "" then return false end
	if string.find(biome_name, "_EMPTY_") ~= nil then return false end
	if string.find(biome_name, "empty") ~= nil then return false end
	return true
end

-- Workshop detection: "workshop" entities only exist in HM interior
-- Distance-gated so a surviving (non-collapsed) workshop doesn't trap the player in safe_zone
local WORKSHOP_MAX_DIST_SQ = 300 * 300  -- ~300 px radius

local function is_in_workshop(player)
	local px, py = EntityGetTransform(player)
	if px == nil then return false end
	local workshop = EntityGetClosestWithTag(px, py, "workshop")
	if workshop == nil or workshop == 0 then return false end
	local wx, wy = EntityGetTransform(workshop)
	if wx == nil then return false end
	local dx, dy = px - wx, py - wy
	return (dx * dx + dy * dy) <= WORKSHOP_MAX_DIST_SQ
end

-- Workshop identity: unique key + Y position for direction detection
local function get_workshop_key(player)
	local px, py = EntityGetTransform(player)
	if px == nil then return nil, nil end
	local workshop = EntityGetClosestWithTag(px, py, "workshop")
	if workshop == nil or workshop == 0 then return nil, nil end
	local wx, wy = EntityGetTransform(workshop)
	if wx == nil then return nil, nil end
	return tostring(workshop), wy
end

-- Visited biomes: comma-separated string in Globals
local function get_visited_biomes()
	local raw = GlobalsGetValue("NOITREIGN_VISITED_BIOMES", "")
	if raw == "" then return {} end
	local biomes = {}
	for b in string.gmatch(raw, "[^,]+") do
		biomes[b] = true
	end
	return biomes
end

local function add_visited_biome(biome_name)
	local raw = GlobalsGetValue("NOITREIGN_VISITED_BIOMES", "")
	if raw == "" then
		GlobalsSetValue("NOITREIGN_VISITED_BIOMES", biome_name)
	else
		-- Check if already present
		for b in string.gmatch(raw, "[^,]+") do
			if b == biome_name then return end
		end
		GlobalsSetValue("NOITREIGN_VISITED_BIOMES", raw .. "," .. biome_name)
	end
end

-- ============================================================
-- Context: built once per frame, shared across all handlers
-- ============================================================

local function build_context(player, frame)
	local raw_biome = get_player_biome(player)
	return {
		frame = frame,
		raw_biome = raw_biome,
		in_workshop = is_in_workshop(player),
		in_holy_mountain = is_holy_mountain(raw_biome),
		is_trackable = is_trackable_biome(raw_biome),
		biome_changed = false,
		new_biome = nil,
		is_backtrack = false,
	}
end

-- ============================================================
-- Biome transition: debounce + visited tracking
-- Mutates ctx: sets biome_changed, new_biome, is_backtrack
-- ============================================================

local function handle_biome_transition(ctx)
	GlobalsSetValue("NOITREIGN_RAW_BIOME", ctx.raw_biome)

	-- Debounce: require DEBOUNCE_FRAMES consecutive frames in the same biome
	local debounce_biome = GlobalsGetValue("NOITREIGN_DEBOUNCE_BIOME", "")
	local debounce_count = tonumber(GlobalsGetValue("NOITREIGN_DEBOUNCE_COUNT", "0")) or 0

	if ctx.raw_biome ~= debounce_biome then
		GlobalsSetValue("NOITREIGN_DEBOUNCE_BIOME", ctx.raw_biome)
		GlobalsSetValue("NOITREIGN_DEBOUNCE_COUNT", "1")
		return
	end

	debounce_count = debounce_count + 1
	GlobalsSetValue("NOITREIGN_DEBOUNCE_COUNT", tostring(debounce_count))

	if debounce_count < DEBOUNCE_FRAMES then return end

	-- HM biomes don't trigger biome transitions (but workshop detection
	-- handles the safe zone separately via entity check)
	if is_holy_mountain(ctx.raw_biome) then return end
	if not ctx.is_trackable then return end

	local level_biome = GlobalsGetValue("NOITREIGN_LEVEL_BIOME", "")
	if ctx.raw_biome == level_biome then return end

	-- First biome of the run: just record it, no transition event
	if level_biome == "" then
		GlobalsSetValue("NOITREIGN_LEVEL_BIOME", ctx.raw_biome)
		add_visited_biome(ctx.raw_biome)
		return
	end

	-- Confirmed biome transition
	ctx.biome_changed = true
	ctx.new_biome = ctx.raw_biome

	-- Track visited biomes
	local visited = get_visited_biomes()
	ctx.is_backtrack = visited[ctx.raw_biome] == true
	add_visited_biome(ctx.raw_biome)

	-- Update level biome
	GlobalsSetValue("NOITREIGN_LEVEL_BIOME", ctx.raw_biome)

	if ctx.is_backtrack then
		GamePrint("Noitreign: Backtracking to " .. ctx.raw_biome)
	else
		GamePrint("Noitreign: New biome — bonus time!")
	end
end

-- ============================================================
-- State handlers: each returns next state name
-- ============================================================

local state_handlers = {}

state_handlers.counting_down = function(player, frame, ctx)
	-- Calculate remaining time
	local current_timer = tonumber(GlobalsGetValue("NOITREIGN_CURRENT_TIMER", "180")) or 180
	local start_frame = tonumber(GlobalsGetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))) or frame
	local elapsed = (frame - start_frame) / 60.0
	local remaining = current_timer - elapsed

	GlobalsSetValue("NOITREIGN_REMAINING_SECONDS", tostring(math.max(remaining, 0)))

	-- Transitions (checked in priority order)
	if remaining <= 0 then
		return "overtime"
	elseif ctx.in_workshop then
		-- Freeze timer: snapshot remaining as new budget
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(remaining))
		-- Store workshop identity for rewards + direction detection
		local wk, wy = get_workshop_key(player)
		GlobalsSetValue("NOITREIGN_CURRENT_WORKSHOP_KEY", wk or "")
		GlobalsSetValue("NOITREIGN_CURRENT_WORKSHOP_Y", tostring(wy or 0))
		return "safe_zone"
	elseif ctx.biome_changed and not ctx.is_backtrack then
		-- Direct biome → biome: add bonus time to remaining
		local bonus = get_setting("biome_bonus_seconds", 90)
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(remaining + bonus))
		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
	end

	return "counting_down"
end

state_handlers.overtime = function(player, frame, ctx)
	-- Still update remaining (clamped to 0) for GUI
	GlobalsSetValue("NOITREIGN_REMAINING_SECONDS", "0")

	-- Workshop = pause damage
	if ctx.in_workshop then
		local wk, wy = get_workshop_key(player)
		GlobalsSetValue("NOITREIGN_CURRENT_WORKSHOP_KEY", wk or "")
		GlobalsSetValue("NOITREIGN_CURRENT_WORKSHOP_Y", tostring(wy or 0))
		return "overtime_safe"
	end

	-- Biome change during overtime = reprieve with bonus time (new biomes only)
	if ctx.biome_changed and not ctx.is_backtrack then
		local bonus = get_setting("biome_bonus_seconds", 90)
		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(bonus))
		return "counting_down"
	end

	-- Deal escalating damage on interval
	local damage_interval = get_setting("damage_interval_frames", 120)
	local last_damage_frame = tonumber(GlobalsGetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")) or 0

	if last_damage_frame == 0 or (frame - last_damage_frame) >= damage_interval then
		local damagemodels = EntityGetComponent(player, "DamageModelComponent")
		local max_hp = 4  -- default: 100 display HP / 25
		if damagemodels ~= nil then
			max_hp = ComponentGetValue2(damagemodels[1], "max_hp")
		end

		local base_damage = get_setting("damage_start", 6)  -- display HP at 100 max
		local ticks = tonumber(GlobalsGetValue("NOITREIGN_DAMAGE_TICKS", "0")) or 0

		local damage = base_damage * (math.floor(ticks / 5) + 1)
		local internal_damage = (damage / 100.0) -- * max_hp  -- scale relative to max HP

		local x, y = EntityGetTransform(player)
		EntityInflictDamage(
			player,
			internal_damage,
			"DAMAGE_CURSE",
			"Get out quick!",
			"NONE",
			0, 0,
			player,
			x, y,
			0
		)

		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", tostring(ticks + 1))
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", tostring(frame))
	end

	return "overtime"
end

state_handlers.safe_zone = function(player, frame, ctx)
	-- Stay safe while in workshop or anywhere in HM biome area (covers exit gap)
	if ctx.in_workshop or ctx.in_holy_mountain then
		return "safe_zone"
	end

	-- Player left HM area — determine direction via Y comparison
	local workshop_y = tonumber(GlobalsGetValue("NOITREIGN_CURRENT_WORKSHOP_Y", "0")) or 0
	local _, py = EntityGetTransform(player)
	local went_forward = (py or 0) > workshop_y

	-- Immediate biome check (don't wait for debounce) to detect new vs same biome
	local level_biome = GlobalsGetValue("NOITREIGN_LEVEL_BIOME", "")
	local is_new_biome = ctx.is_trackable and ctx.raw_biome ~= level_biome

	if went_forward then
		if is_new_biome then
			-- New biome below: full timer reset
			local timer_seconds = get_setting("timer_seconds", 180)
			GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
			GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(timer_seconds))
			GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
			GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
			-- Update level biome now so debounced transition doesn't double-grant
			GlobalsSetValue("NOITREIGN_LEVEL_BIOME", ctx.raw_biome)
			add_visited_biome(ctx.raw_biome)
			return "counting_down"
		end
		-- Same biome (wand edit roundtrip): resume from frozen
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		return "counting_down"
	else
		-- Went upward: backtrack penalty → overtime
		GlobalsSetValue("NOITREIGN_REMAINING_SECONDS", "0")
		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
		return "overtime"
	end
end

state_handlers.overtime_safe = function(player, frame, ctx)
	GlobalsSetValue("NOITREIGN_REMAINING_SECONDS", "0")

	-- Stay safe while in workshop or HM biome area
	if ctx.in_workshop or ctx.in_holy_mountain then
		return "overtime_safe"
	end

	-- Left HM area — check direction
	local workshop_y = tonumber(GlobalsGetValue("NOITREIGN_CURRENT_WORKSHOP_Y", "0")) or 0
	local _, py = EntityGetTransform(player)
	local went_forward = (py or 0) > workshop_y

	-- Immediate biome check (don't wait for debounce)
	local level_biome = GlobalsGetValue("NOITREIGN_LEVEL_BIOME", "")
	local is_new_biome = ctx.is_trackable and ctx.raw_biome ~= level_biome

	if went_forward and is_new_biome then
		-- New biome: full timer reset
		local timer_seconds = get_setting("timer_seconds", 180)
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(timer_seconds))
		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
		-- Update level biome now so debounced transition doesn't double-grant
		GlobalsSetValue("NOITREIGN_LEVEL_BIOME", ctx.raw_biome)
		add_visited_biome(ctx.raw_biome)
		return "counting_down"
	end

	-- All other exits: resume overtime damage
	return "overtime"
end

-- ============================================================
-- Init: called on first spawn
-- ============================================================

function noitreign_timer_init(player)
	local frame = GameGetFrameNum()
	local timer_seconds = get_setting("timer_seconds", 180)

	GlobalsSetValue("NOITREIGN_STATE", "counting_down")
	GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
	GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(timer_seconds))
	GlobalsSetValue("NOITREIGN_LEVEL_BIOME", "")
	GlobalsSetValue("NOITREIGN_RAW_BIOME", "")
	GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
	GlobalsSetValue("NOITREIGN_REMAINING_SECONDS", tostring(timer_seconds))
	GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
	GlobalsSetValue("NOITREIGN_DEBOUNCE_BIOME", "")
	GlobalsSetValue("NOITREIGN_DEBOUNCE_COUNT", "0")
	GlobalsSetValue("NOITREIGN_VISITED_BIOMES", "")
	GlobalsSetValue("NOITREIGN_CURRENT_WORKSHOP_KEY", "")
	GlobalsSetValue("NOITREIGN_CURRENT_WORKSHOP_Y", "0")
end

-- ============================================================
-- Restore: called on reload (save/load)
-- ============================================================

function noitreign_timer_restore(player)
	local remaining = tonumber(GlobalsGetValue("NOITREIGN_REMAINING_SECONDS", "180")) or 180
	local frame = GameGetFrameNum()
	local current_timer = tonumber(GlobalsGetValue("NOITREIGN_CURRENT_TIMER", "180")) or 180
	local elapsed = current_timer - remaining
	GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame - math.floor(elapsed * 60)))
end

-- ============================================================
-- Update: called every frame from OnWorldPostUpdate
-- ============================================================

function noitreign_timer_update(player)
	local frame = GameGetFrameNum()
	local state = GlobalsGetValue("NOITREIGN_STATE", "counting_down")
	local ctx = build_context(player, frame)

	-- Skip biome transition tracking in safe states — the safe_zone/overtime_safe
	-- handlers do their own immediate biome detection on exit. Running it here would
	-- let the debounce update NOITREIGN_LEVEL_BIOME while still in safe_zone
	-- (e.g. when a non-collapsed workshop keeps is_in_workshop true into the next biome).
	if state ~= "safe_zone" and state ~= "overtime_safe" then
		handle_biome_transition(ctx)
	end

	local handler = state_handlers[state]
	if handler == nil then handler = state_handlers.counting_down end
	local next_state = handler(player, frame, ctx)

	GlobalsSetValue("NOITREIGN_STATE", next_state)
end
