local assets =
{
    Asset("ANIM", "anim/bird_duiwufx.zip"),
}

local function makefx(num)
    local function PlayRingAnim()
        local inst = CreateEntity()
    
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()
    
        inst:AddTag("FX")
    
        inst.AnimState:SetBank("qiaoer_duiwufx")
        inst.AnimState:SetBuild("qiaoer_duiwufx")
        inst.AnimState:PlayAnimation("idle" .. num)
        inst.AnimState:SetFinalOffset(3)
    
        inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
        inst.AnimState:SetLayer(LAYER_BACKGROUND)
        inst.AnimState:SetSortOrder(3)
    
        inst.entity:SetPristine()
    
        if not TheWorld.ismastersim then
            return inst
        end
    
        inst.entity:SetCanSleep(false)

        inst.persists = false

        return inst
    end 

    return Prefab("bird_duiwufx" .. num, PlayRingAnim, assets)
end

local prefabs = {}
table.insert(prefabs, makefx(1))
table.insert(prefabs, makefx(2))
return unpack(prefabs)
