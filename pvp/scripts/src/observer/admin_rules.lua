-- Server-side rules for OB/referee world privileges.
local observer_privileges = require("src/observer/privileges")
local function has_legacy_world_immunity(player)
    local fn = observer_privileges.has_legacy_world_immunity or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local function is_excluded_from_pve_targeting(player)
    local fn = observer_privileges.is_excluded_from_pve_targeting or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end
local OBSERVER_EXCLUDED_TARGETING_PREFABS = {
    mandrake_active = true,
}

local function is_monkey_curse_item(item)
    return item ~= nil
        and item.components ~= nil
        and item.components.curseditem ~= nil
        and item.components.curseditem.curse == "MONKEY"
end

local function is_observer_target(self)
    return has_legacy_world_immunity(self.inst)
end

local function install_curse_immunity()
    AddComponentPostInit("cursable", function(self)
        local IsCursable = self.IsCursable
        function self:IsCursable(item)
            if is_monkey_curse_item(item) and is_observer_target(self) then
                return false
            end
            return IsCursable(self, item)
        end

        local ApplyCurse = self.ApplyCurse
        function self:ApplyCurse(item)
            if is_monkey_curse_item(item) and is_observer_target(self) then
                item:RemoveTag("applied_curse")
                item.components.curseditem.cursed_target = nil
                return
            end
            return ApplyCurse(self, item)
        end

        local ForceOntoOwner = self.ForceOntoOwner
        function self:ForceOntoOwner(item)
            if is_monkey_curse_item(item) and is_observer_target(self) then
                return
            end
            return ForceOntoOwner(self, item)
        end
    end)
end

local function install_item_restrictions()
    AddPrefabPostInit("telestaff", function(inst)
        if inst.components.spellcaster == nil then
            return
        end

        local CastSpell = inst.components.spellcaster.spell
        inst.components.spellcaster.spell = function(staff, caster, target, position)
            if has_legacy_world_immunity(caster) then
                return false
            end
            return CastSpell(staff, caster, target, position)
        end
    end)
end

local function find_closest_non_observer_player(x, y, z, range_sq, must_match_ghost_state)
    local closest_player = nil
    for _, player in ipairs(AllPlayers) do
        if (must_match_ghost_state == nil or must_match_ghost_state ~= IsEntityDeadOrGhost(player))
            and player.entity:IsVisible()
            and player.Network ~= nil
            and not is_excluded_from_pve_targeting(player) then
            local distance_sq = player:GetDistanceSqToPoint(x, y, z)
            if distance_sq < range_sq then
                range_sq = distance_sq
                closest_player = player
            end
        end
    end
    return closest_player, closest_player ~= nil and range_sq or nil
end

local function install_targeting_exclusion()
    local OriginalFindClosestPlayerToInst = FindClosestPlayerToInst
    GLOBAL.FindClosestPlayerToInst = function(inst, range, must_match_ghost_state)
        if inst ~= nil and OBSERVER_EXCLUDED_TARGETING_PREFABS[inst.prefab] then
            local x, y, z = inst.Transform:GetWorldPosition()
            return find_closest_non_observer_player(x, y, z, range * range, must_match_ghost_state)
        end
        return OriginalFindClosestPlayerToInst(inst, range, must_match_ghost_state)
    end
end

install_curse_immunity()
install_item_restrictions()
install_targeting_exclusion()
