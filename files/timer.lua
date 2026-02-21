-- timer.lua — State machine for biome tracking, countdown, and escalating curse damage

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
local function is_in_workshop(player)
	local px, py = EntityGetTransform(player)
	if px == nil then return false end
	local workshop = EntityGetClosestWithTag(px, py, "workshop")
	return workshop ~= nil and workshop ~= 0
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

	-- DEBUG: remove once biome names are confirmed
	GamePrint("BIOME: [" .. ctx.raw_biome .. "]")

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
		return "safe_zone"
	elseif ctx.biome_changed then
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
		return "overtime_safe"
	end

	-- Biome change during overtime = reprieve with bonus time
	if ctx.biome_changed then
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
		local base_damage = get_setting("damage_start", 5)
		local escalation = get_setting("damage_escalation", 2)
		local ticks = tonumber(GlobalsGetValue("NOITREIGN_DAMAGE_TICKS", "0")) or 0

		local damage = base_damage * escalation
		local internal_damage = damage / 25.0  -- Noita HP = display / 25

		local x, y = EntityGetTransform(player)
		EntityInflictDamage(
			player,
			internal_damage,
			"DAMAGE_CURSE",
			"The biome is rejecting you!",
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
	-- Timer frozen. Stay here until a biome transition confirms the next level.
	-- This covers the gap between the workshop and the next biome.
	if ctx.biome_changed then
		-- Leaving HM into new biome: full timer reset
		local timer_seconds = get_setting("timer_seconds", 180)
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(timer_seconds))
		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
		return "counting_down"
	end
	return "safe_zone"
end

state_handlers.overtime_safe = function(player, frame, ctx)
	-- Damage paused. Stay here until a biome transition.
	GlobalsSetValue("NOITREIGN_REMAINING_SECONDS", "0")
	if ctx.biome_changed then
		-- Leaving HM into new biome: full timer reset
		local timer_seconds = get_setting("timer_seconds", 180)
		GlobalsSetValue("NOITREIGN_TIMER_START_FRAME", tostring(frame))
		GlobalsSetValue("NOITREIGN_CURRENT_TIMER", tostring(timer_seconds))
		GlobalsSetValue("NOITREIGN_DAMAGE_TICKS", "0")
		GlobalsSetValue("NOITREIGN_LAST_DAMAGE_FRAME", "0")
		return "counting_down"
	end
	return "overtime_safe"
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

	handle_biome_transition(ctx)

	local handler = state_handlers[state]
	if handler == nil then handler = state_handlers.counting_down end
	local next_state = handler(player, frame, ctx)

	GlobalsSetValue("NOITREIGN_STATE", next_state)
end
