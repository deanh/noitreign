local _noitreign_orig_shop_item = generate_shop_item
function generate_shop_item(x, y, cheap_item, biomeid_, is_stealable)
    local eid = _noitreign_orig_shop_item(x, y, cheap_item, biomeid_, is_stealable)
    if eid == nil then return eid end

    local discount = ModSettingGet("noitreign.shop_discount") or 50
    if discount <= 0 then return eid end

    -- Adjust cost
    local cost_comps = EntityGetComponentIncludingDisabled(eid, "ItemCostComponent")
    if cost_comps then
        for _, comp in ipairs(cost_comps) do
            local cost = ComponentGetValue2(comp, "cost")
            local new_cost = math.max(math.floor(cost * (100 - discount) / 100), 5)
            ComponentSetValue2(comp, "cost", new_cost)
        end
    end

    -- Update price display
    local sprites = EntityGetComponentIncludingDisabled(eid, "SpriteComponent") 
    if sprites then
        for _, comp in ipairs(sprites) do
            local tags = ComponentGetValue2(comp, "_tags") or ""
            if string.find(tags, "shop_cost") and ComponentGetValue2(comp, "is_text_sprite") then
                local cc = EntityGetComponentIncludingDisabled(eid, "ItemCostComponent")
                if cc then
                    ComponentSetValue2(comp, "text", tostring(ComponentGetValue2(cc[1], "cost")))
                end
            end
        end
    end

    return eid
end

