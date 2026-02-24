-- gui.lua — HUD countdown timer display

local noitreign_gui = nil

function noitreign_gui_update(player)
	if noitreign_gui == nil then
		noitreign_gui = GuiCreate()
	end

	GuiStartFrame(noitreign_gui)

	local screen_w, screen_h = GuiGetScreenDimensions(noitreign_gui)

	local state = GlobalsGetValue("NOITREIGN_STATE", "counting_down")
	local remaining = tonumber(GlobalsGetValue("NOITREIGN_REMAINING_SECONDS", "180")) or 180

	local text
	local r, g, b = 1, 1, 1

	if state == "overtime" or state == "overtime_safe" then
		-- Overtime: flashing red text
		local flash = math.floor(GameGetFrameNum() / 15) % 2 == 0
		r, g, b = flash and 1 or 0.6, flash and 0.1 or 0, flash and 0.1 or 0
		text = "OVERTIME"

		if state == "overtime_safe" then
			text = text .. " (safe)"
		end

		local ticks = tonumber(GlobalsGetValue("NOITREIGN_DAMAGE_TICKS", "0")) or 0
		if ticks > 0 then
			text = text .. " [x" .. tostring(ticks) .. "]"
		end

		-- Screen effect: desaturation + red tint during active overtime (not safe)
		if state == "overtime" then
			local intensity = math.min(math.sqrt(ticks / 20), 1.0)
			local desat = 0.15 + intensity * 0.45
			local cr = 1.0 - intensity * 0.3
			local cg = 1.0 - intensity * 0.7
			local cb = 1.0 - intensity * 0.7
			GameSetPostFxParameter("color_grading", cr, cg, cb, desat)
		else
			GameUnsetPostFxParameter("color_grading")
		end

	else
		GameUnsetPostFxParameter("color_grading")

		if state == "safe_zone" then
			-- Holy Mountain: show frozen timer in white
			local minutes = math.floor(remaining / 60)
			local seconds = math.floor(remaining % 60)
			text = string.format("%d:%02d (HM)", minutes, seconds)
			r, g, b = 1, 1, 1

		else -- counting_down (and fallback)
			local minutes = math.floor(remaining / 60)
			local seconds = math.floor(remaining % 60)
			text = string.format("%d:%02d", minutes, seconds)

			if remaining > 60 then
				r, g, b = 0.2, 1, 0.2  -- green
			elseif remaining > 30 then
				r, g, b = 1, 1, 0.2    -- yellow
			else
				r, g, b = 1, 0.2, 0.2  -- red
			end
		end
	end

	-- Position: top-center
	local text_w, text_h = GuiGetTextDimensions(noitreign_gui, text)
	local x = (screen_w - text_w) / 2
	local y = 2

	GuiZSetForNextWidget(noitreign_gui, -100)
	GuiColorSetForNextWidget(noitreign_gui, r, g, b, 1)
	GuiText(noitreign_gui, x, y, text)
end
