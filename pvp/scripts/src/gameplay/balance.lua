-- Global balance constants and configurable loot behavior.
-- This is a registration script and must be loaded with modimport.

TUNING.PANFLUTE_USES = 3

if GetModConfigData("extra_loot") == true then
    AddComponentPostInit("lootdropper", function(self)
        local DropLoot = self.DropLoot

        function self:DropLoot(...)
            -- [PATCH] 在保留原版 Boss 三倍掉落行为的基础上，增加递归防护与实体有效性检查。
            -- 避免与其他也包裹 DropLoot 的 Mod 叠加时产生无限递归或崩溃。
            if self._bird_extra_loot_running then
                return DropLoot(self, ...)
            end

            if self.inst:HasTag("epic") then
                self._bird_extra_loot_running = true
                DropLoot(self, ...)
                if self.inst:IsValid() then
                    DropLoot(self, ...)
                end
                if self.inst:IsValid() then
                    DropLoot(self, ...)
                end
                self._bird_extra_loot_running = nil
            else
                DropLoot(self, ...)
            end
        end
    end)
end
