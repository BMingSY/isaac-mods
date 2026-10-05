-- Run with Lua 5.3 and the installed game's resources/scripts directory as arg[1].
-- This exercises callback/state behavior; it does not emulate Isaac's engine or renderer.
local scripts = assert(arg[1], "Pass the game's resources/scripts directory")
package.path = scripts .. "/?.lua;" .. package.path
function BitSet128(low) return low end
ItemConfig, RoomDescriptor = {}, {}
dofile(scripts .. "/enums.lua")

local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, message)
    checks = checks + 1
    assert(math.abs(actual - expected) < 0.00001, message or "numeric mismatch")
end

-- The engine appends "collectibles/" to gfxroot; checking the XML alone
-- missed a doubled directory that made the real pocket icon invisible.
local function readFile(path)
    local file=assert(io.open(path,"rb"),"Missing game resource: "..path)
    local data=file:read("*a");file:close();return data
end
local itemXML=readFile("mods/poop_boss_forms/content/items.xml")
local icon=readFile("mods/poop_boss_forms/resources/"..assert(itemXML:match('gfxroot="([^"]+)"'))
    .."collectibles/"..assert(itemXML:match('gfx="([^"]+)"')))
eq(icon:sub(1,8),"\137PNG\r\n\26\n","icon is a PNG at the engine-resolved path")
local iconWidth,iconHeight,iconDepth,iconType=string.unpack(">I4I4BB",icon,17)
eq(iconWidth,32,"collectible icon width")
eq(iconHeight,32,"collectible icon height")
eq(iconDepth,8,"collectible icon bit depth")
eq(iconType,6,"collectible icon has full RGBA channels")

local vm = {}; vm.__index = vm
Vector = setmetatable({}, {__call = function(_, x, y) return setmetatable({X=x,Y=y},vm) end})
Vector.Zero = Vector(0,0)
function vm.__add(a,b) return Vector(a.X+b.X,a.Y+b.Y) end
function vm.__sub(a,b) return Vector(a.X-b.X,a.Y-b.Y) end
function vm.__unm(a) return Vector(-a.X,-a.Y) end
function vm.__mul(a,b) return Vector(a.X*b,a.Y*b) end
function vm:LengthSquared() return self.X*self.X+self.Y*self.Y end
function vm:Normalized() local l=math.sqrt(self:LengthSquared()); return l>0 and self*(1/l) or Vector.Zero end
function vm:Rotated(degrees)
    local r=math.rad(degrees); return Vector(self.X*math.cos(r)-self.Y*math.sin(r),self.X*math.sin(r)+self.Y*math.cos(r))
end
function vm:GetAngleDegrees() return math.deg(math.atan(self.Y,self.X)) end
function Color(...) return {...} end
function KColor(...) return {...} end
function EntityRef(entity) return {Entity=entity} end
function GetPtrHash(entity) return entity.hash end
local renders, labels = {}, {}
Options = {HUDOffset=0}
function Font() return {Load=function() end,DrawStringScaledUTF8=function(_,text) labels[#labels+1]=text end} end
function Sprite()
    return { Load=function(self,path) self.path=path end, Play=function(self,name) self.anim=name end,
        SetFrame=function(self,name,frame) self.anim=name;self.frame=frame end,
        GetAnimation=function(self) return self.anim end, GetFrame=function(self) return self.frame or 0 end,
        IsPlaying=function(self,name) return self.anim==name end,
        IsFinished=function() return false end, Render=function(self,pos)
            renders[#renders+1]={position=pos,color=self.Color,path=self.path}
        end }
end
function SFXManager() return {Play=function() end} end

local callbacks, mod = {}, {}
local simulateReentry = false
local saveText, frame, startSeed, players, entities, grids, deferredRemoval = "", 0, 123, {}, {}, {}, {}
function RegisterMod() return mod end
function mod:AddCallback(id,fn,param) callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],{fn=fn,param=param}) end
function mod:SaveData(text) saveText=text end
function mod:LoadData() return saveText end
function mod:HasData() return saveText~="" end
function include(path) return dofile("mods/poop_boss_forms/"..path..".lua") end
local nextHash = 0
local function entity(kind, variant, subtype, position, spawner)
    nextHash=nextHash+1
    local e={hash=nextHash,Type=kind,Variant=variant,SubType=subtype,FrameCount=0,Position=position or Vector.Zero,
        Velocity=Vector.Zero,SpawnerEntity=spawner,Size=10,data={},sprite=Sprite(),SpriteScale=Vector(1,1),SpriteOffset=Vector.Zero}
    function e:Exists() return not self.removed end
    function e:Remove() self.removed=true end
    function e:GetData() return self.data end
    function e:GetSprite() return self.sprite end
    function e:ToPlayer() return self.Type==EntityType.ENTITY_PLAYER and self or nil end
    function e:ToEffect() return self.Type==EntityType.ENTITY_EFFECT and self or nil end
    function e:ToFamiliar() return self.Type==EntityType.ENTITY_FAMILIAR and self or nil end
    function e:ToTear() return self.Type==EntityType.ENTITY_TEAR and self or nil end
    function e:ToKnife() return self.Type==EntityType.ENTITY_KNIFE and self or nil end
    function e:ChangeVariant(value) self.Variant=value end
    function e:Update() end
    function e:IsVulnerableEnemy() return self.enemy and not self.removed end
    function e:HasEntityFlags() return self.friendly or false end
    function e:TakeDamage(amount) self.totalDamage=(self.totalDamage or 0)+amount end
    function e:AddTearFlags(flags) self.Flags=(self.Flags or 0)|flags end
    table.insert(entities,e)
    return e
end
local function newPlayer(controller)
    local p=entity(EntityType.ENTITY_PLAYER,0,0,Vector(240,160))
    p.ControllerIndex=controller or 0; p.InitSeed=p.hash; p.Damage=3.5; p.MaxFireDelay=10; p.ShotSpeed=1;p.TearRange=260
    p.Visible=true; p.items={}; p.charges={}; p.batteries={}; p.control=true; p.extraFinished=true
    function p:IsDead() return self.dead or false end
    function p:IsCoopGhost() return self.ghost or false end
    function p:AreControlsEnabled() return self.control end
    function p:IsExtraAnimationFinished() return self.extraFinished end
    function p:GetSubPlayer() return self.sub end
    function p:GetActiveItem(slot) return self.items[slot] or 0 end
    function p:GetActiveCharge(slot) return self.charges[slot] or 0 end
    function p:GetBatteryCharge(slot) return self.batteries[slot] or 0 end
    function p:GetCard(slot) return slot==0 and (self.selectedCard or 0) or 0 end
    function p:GetPill(slot) return slot==0 and (self.selectedPill or 0) or 0 end
    function p:SetPocketActiveItem(id,slot)
        self.pocketWrites=(self.pocketWrites or 0)+1
        self.items[slot]=id;self.charges[slot]=0;self.batteries[slot]=0
    end
    function p:SetActiveCharge(charge,slot) self.charges[slot]=charge;self.batteries[slot]=0 end
    function p:AddCollectible(id,charge) self.items[0]=id;self.charges[0]=charge end
    function p:GetMovementInput() return self.movement or Vector.Zero end
    function p:GetDamageCooldown() return self.invincible or 0 end
    function p:SetMinDamageCooldown(value) self.invincible=value end
    function p:SetShootingCooldown(value) self.shootingCooldown=value end
    function p:HasWeaponType(kind) return kind==(self.weapon or WeaponType.WEAPON_TEARS) end
    function p:GetColor() return Color(1,1,1,1) end
    function p:CollidesWithGrid() return self.colliding or false end
    function p:GetCollectibleRNG() return {RandomInt=function() return 1 end} end
    function p:FireTear(pos,velocity,eye,noTractor,streak,source,multiplier)
        local tear=entity(EntityType.ENTITY_TEAR,TearVariant.BLUE,0,pos,self)
        tear.Parent=self;tear.Velocity=velocity;tear.CollisionDamage=self.Damage*multiplier
        tear.TearFlags=self.TearFlags or 0
        tear.Color=Color(1,1,1,1);tear.Scale=1
        tear.Height=-23;tear.FallingSpeed=0;tear.FallingAcceleration=0.05
        for name,value in pairs(self.nativeTear or {}) do tear[name]=value end
        if simulateReentry then tear.FrameCount=1;mod:OnTearUpdate(tear) end
        return tear
    end
    function p:FireBrimstone(direction,source,multiplier)
        local shot=entity(EntityType.ENTITY_LASER,1,0,self.Position,self)
        shot.AngleDegrees=direction:GetAngleDegrees();shot.CollisionDamage=self.Damage*multiplier
        shot.TearFlags=self.TearFlags or 0;return shot
    end
    function p:FireKnife(parent,offset,cantOverwrite,subtype,variant)
        local shot=entity(EntityType.ENTITY_KNIFE,variant,subtype,self.Position,self)
        shot.Parent=parent;shot.RotationOffset=offset;shot.cantOverwrite=cantOverwrite
        shot.CollisionDamage=self.Damage;shot.TearFlags=self.TearFlags or 0
        function shot:Shoot(charge,range) self.Charge=charge;self.MaxDistance=range;self.flying=true end
        function shot:IsFlying() return self.flying or false end
        if simulateReentry then mod:OnKnifeUpdate(shot) end
        return shot
    end
    function p:FireTechLaser(position,offset,direction,leftEye,oneHit,source,multiplier)
        local shot=self:FireBrimstone(direction,source,multiplier)
        shot.Position=position;shot.OneHit=oneHit;return shot
    end
    function p:FireTechXLaser(position,velocity,radius,source,multiplier)
        local shot=self:FireBrimstone(velocity,source,multiplier)
        shot.Position=position;shot.Velocity=velocity;shot.Radius=radius;return shot
    end
    function p:AddFriendlyDip(subtype,pos)
        local f=entity(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP,subtype,pos,self);f.Player=self;return f
    end
    function p:AddBlueSpider(pos)
        local f=entity(EntityType.ENTITY_FAMILIAR,FamiliarVariant.BLUE_SPIDER,0,pos,self);f.Player=self;return f
    end
    return p
end
local room={}
function room:GetGridWidth() return 13 end
function room:GetGridSize() return 91 end
function room:GetGridIndex(pos) return math.floor(pos.Y/40)*13+math.floor(pos.X/40) end
function room:GetGridPosition(index) return Vector(index%13*40, math.floor(index/13)*40) end
function room:GetGridEntity(index) return grids[index] end
function room:GetGridEntityFromPos(pos) return grids[self:GetGridIndex(pos)] end
function room:RemoveGridEntity(index) deferredRemoval[index]=true end
function room:GetGridCollisionAtPos(pos) return self.wall and GridCollisionClass.COLLISION_WALL or GridCollisionClass.COLLISION_NONE end
function room:IsPositionInRoom(pos) return pos.X>=0 and pos.X<=480 and pos.Y>=0 and pos.Y<=240 end
function room:FindFreePickupSpawnPosition(pos) return pos end
local game={}
function Game() return game end
function game:GetNumPlayers() return #players end
function game:GetSeeds() return {GetStartSeed=function() return startSeed end} end
function game:GetFrameCount() return frame end
function game:GetRoom() return room end
function game:IsPaused() return self.paused or false end
function game:GetHUD() return {IsVisible=function() return game.hudVisible~=false end} end
local inputs={}
Input={GetActionValue=function(action,controller) return (inputs[controller] or {})[action] or 0 end,
    IsButtonPressed=function() return false end}
Isaac={}
function Isaac.GetPlayer(index) return players[index+1] end
function Isaac.GetItemIdByName() return 8000 end
function Isaac.GetEntityVariantByName() return 900 end
function Isaac.DebugString() end
function Isaac.ConsoleOutput() end
function Isaac.GetScreenWidth() return 640 end
function Isaac.WorldToScreen(pos) return pos end
function Isaac.Spawn(kind,variant,subtype,pos,velocity,spawner)
    local e=entity(kind,variant,subtype,pos,spawner);e.Velocity=velocity;return e
end
function Isaac.GridSpawn(kind,variant,pos)
    local g={State=0,Position=pos,CollisionClass=GridCollisionClass.COLLISION_OBJECT,
        GetType=function() return kind end,GetVariant=function() return variant end}
    function g:SetVariant(value) variant=value end
    function g:ToPoop() return self end
    function g:Hurt(damage)
        self.lastDamage=damage
        if self.rejectDamage then return false end
        self.State=math.min(1000,self.State+damage)
        if self.State>=1000 then self.CollisionClass=GridCollisionClass.COLLISION_NONE end
        return true
    end
    grids[room:GetGridIndex(pos)]=g;return g
end
function Isaac.GetRoomEntities()
    local found={};for _,e in ipairs(entities) do if e:Exists() then found[#found+1]=e end end;return found
end
function Isaac.FindByType(kind,variant)
    local found={}
    for _,e in ipairs(entities) do if e:Exists() and e.Type==kind and (variant==-1 or variant==e.Variant) then found[#found+1]=e end end
    return found
end

dofile("mods/poop_boss_forms/main.lua")
local POOP,DASH=CollectibleType.COLLECTIBLE_POOP,8000
local key="PoopBossForms"
local forms=include("scripts/forms")
local rules=include("scripts/rules")
local weapons=include("scripts/weapons")
local function reset()
    entities,players,inputs,grids,deferredRemoval={},{},{},{},{}
    players[1]=newPlayer(0);players[1]:AddCollectible(POOP,1)
    frame=0;game.paused=false;game.hudVisible=true;room.wall=false
    renders,labels={},{};Options.HUDOffset=0
    mod:OnStarted(false)
    return players[1]
end
local function setInput(p,action,value) inputs[p.ControllerIndex]=inputs[p.ControllerIndex] or {};inputs[p.ControllerIndex][action]=value end
local function tick(p,count)
    for _=1,count or 1 do
        frame=frame+1
        for index in pairs(deferredRemoval) do grids[index]=nil end
        deferredRemoval={}
        mod:OnPlayerUpdate(p)
        mod:OnPlayerVisualUpdate(p)
    end
end
local function usePoop(p) mod:OnPrePoop(POOP,nil,p,0);return p:GetData()[key] end
local function tap(p)
    setInput(p,ButtonAction.ACTION_DROP,1);tick(p)
    setInput(p,ButtonAction.ACTION_DROP,0);tick(p)
end
local function count(kind,variant) return #Isaac.FindByType(kind,variant or -1) end

eq(#forms,4,"all vanilla forms")
near(rules.dashDamage(3.5,3)*3,97.5,"dash combo balance")
near(rules.segmentDistanceSquared(0,2,-10,0,10,0),4,"swept collision")
near(rules.segmentDistanceSquared(15,0,-10,0,10,0),25,"segment endpoint")
eq(rules.touchingPoop(0,0,30,0,10),true,"poop contact")
eq(rules.touchingPoop(0,0,40,40,10),false,"no diagonal remote conversion")
eq(rules.interval(10,2.2),24,"base attack cooldown")
eq(rules.interval(-0.9,2.2),8,"bounded attack rate")

local p=reset()
eq(p:GetData()[key].form,nil,"no automatic transformation")
tap(p);eq(p:GetData()[key].selected,2,"Ctrl cycles selection")
setInput(p,ButtonAction.ACTION_DROP,1);tick(p,20)
eq(mod:OnInput(p,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_DROP),nil,"long hold allows vanilla drop")
setInput(p,ButtonAction.ACTION_DROP,0);tick(p)
eq(p:GetData()[key].selected,2,"long hold does not change form")
local state=usePoop(p)
eq(state.form,2,"use selected form")
eq(p:GetActiveItem(ActiveSlot.SLOT_POCKET),DASH,"pocket dash granted")
eq(p:GetActiveCharge(ActiveSlot.SLOT_POCKET),1,"initial one charge")
eq(mod:OnUsePoop().Discharge,true,"Poop consumes charge")
mod:OnPrePoop(POOP,nil,p,UseFlag.USE_CARBATTERY)
eq(state.form,2,"Car Battery does not transform twice")
for _,action in ipairs({ButtonAction.ACTION_LEFT,ButtonAction.ACTION_RIGHT,ButtonAction.ACTION_UP,ButtonAction.ACTION_DOWN}) do
    eq(mod:OnInput(p,InputHook.GET_ACTION_VALUE,action),nil,"normal movement passes through")
end
for _,action in ipairs({ButtonAction.ACTION_SHOOTLEFT,ButtonAction.ACTION_SHOOTRIGHT,ButtonAction.ACTION_SHOOTUP,ButtonAction.ACTION_SHOOTDOWN}) do
    eq(mod:OnInput(p,InputHook.GET_ACTION_VALUE,action),0,"native charge weapons cannot read direction during player update")
    eq(mod:OnInput(p,InputHook.IS_ACTION_PRESSED,action),false,"native firing stays blocked while holding shoot")
    eq(mod:OnInput(p,InputHook.IS_ACTION_TRIGGERED,action),false,"native firing stays blocked on a new press")
end
mod:OnPlayerVisualUpdate(p)
for _,action in ipairs({ButtonAction.ACTION_SHOOTLEFT,ButtonAction.ACTION_SHOOTRIGHT,ButtonAction.ACTION_SHOOTUP,ButtonAction.ACTION_SHOOTDOWN}) do
    eq(mod:OnInput(p,InputHook.GET_ACTION_VALUE,action),nil,"tear steering reads direction after the player update")
end
frame=frame+1
eq(mod:OnInput(p,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_SHOOTRIGHT),0,"new frame blocks weapons before the first player callback")
for _,hook in ipairs({InputHook.GET_ACTION_VALUE,InputHook.IS_ACTION_PRESSED,InputHook.IS_ACTION_TRIGGERED}) do
    eq(mod:OnInput(p,hook,ButtonAction.ACTION_DROP),nil,"Ctrl is always available to the native pocket queue")
    eq(mod:OnInput(p,hook,ButtonAction.ACTION_PILLCARD),nil,"Q is always handled by the native pocket queue")
end
tick(p)
eq(p.Visible,false,"boss appearance hides player")
p.extraFinished=false;tick(p);eq(p.Visible,false,"native pickup and use poses stay hidden")
eq(state.avatar.Visible,true,"boss remains visible throughout extra animation")
eq(state.avatar:GetSprite().anim,"Idle","unavailable special poses use existing boss idle")
p.Visible=true;mod:OnPlayerVisualUpdate(p);eq(p.Visible,false,"late native visibility reset is suppressed")
p.extraFinished=true;tick(p);eq(p.Visible,false,"boss restored after pickup")
p.invincible=10;tick(p,4);eq(p.Visible,false,"hurt flashing never reveals original player")
p.invincible=0;p.dead=true;mod:OnDeathUpdate()
eq(p.Visible,false,"death never reveals original player")
eq(state.avatar:GetSprite().anim,"Death","existing boss death animation is reused")
eq(state.avatar.Visible,true,"dead boss is visible despite invulnerability")
mod:OnDeathUpdate();eq(state.avatar:GetSprite().anim,"Death","death does not revert to idle")
p.dead=false;tick(p);eq(state.avatar:GetSprite().anim,"Idle","revival restores boss idle")
mod:OnNewRoom();eq(state.form,2,"form persists through room")
eq(p.Visible,false,"room transition does not expose original player")
tick(p);eq(p.Visible,false,"avatar recreated after room")

for index,form in ipairs(forms) do
    p=reset();state=p:GetData()[key];state.selected=index;usePoop(p)
    state.cooldown=0;setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p)
    eq(count(EntityType.ENTITY_TEAR),form.shots,form.name.." bullet count")
    for _,tear in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR,-1)) do near(tear.CollisionDamage,p.Damage,"damage scales with player") end
    for _=1,3 do state.cooldown=0;tick(p) end
    if form.summon=="red" then
        local red=room:GetGridEntityFromPos(p.Position+Vector(65,0));eq(red:GetVariant(),1,"red champion creates red poop")
    elseif form.summon=="spider" then eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.BLUE_SPIDER),2,"black summons spiders")
    else
        local dips=Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP)
        eq(#dips,2,"summon two seeded dips");eq(dips[1].SubType,form.summon=="corn" and 20 or 0,"correct dip variant")
    end
    local enemy=entity(20,0,0,p.Position);enemy.enemy=true
    setInput(p,ButtonAction.ACTION_SHOOTRIGHT,0)
    eq(mod:OnUseDash(DASH,nil,p,0).Discharge,true,"dash activates")
    eq(mod:OnUseDash(DASH,nil,p,0).Discharge,false,"dash cannot restart mid-combo")
    eq(mod:OnUseDash(DASH,nil,p,UseFlag.USE_CARBATTERY).Discharge,false,"no duplicate battery dash")
    tick(p,form.dashes*(form.dashFrames+6)+2)
    eq(state.dash,nil,"dash finishes")
    near(enemy.totalDamage,97.5,"each enemy hit once per segment, combo matches cannon")
    if form.skin=="dangle" then eq(count(EntityType.ENTITY_EFFECT,EffectVariant.PLAYER_CREEP_BLACK)>0,true,"slippery form leaves friendly creep") end
end

p=reset();state=usePoop(p)
local modes={
    {kind="brimstone",weapon=WeaponType.WEAPON_BRIMSTONE,type=EntityType.ENTITY_LASER},
    {kind="knife",weapon=WeaponType.WEAPON_KNIFE,type=EntityType.ENTITY_KNIFE},
    {kind="technology",weapon=WeaponType.WEAPON_LASER,type=EntityType.ENTITY_LASER},
    {kind="techx",weapon=WeaponType.WEAPON_TECH_X,type=EntityType.ENTITY_LASER},
}
for _,mode in ipairs(modes) do
    for index,form in ipairs(forms) do
        p=reset();state=usePoop(p);state.form=index;state.cooldown=0
        p.weapon=mode.weapon;p.Damage=7;p.TearFlags=TearFlags.TEAR_HOMING|TearFlags.TEAR_POISON
        setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1)
        if weapons.charged(mode.kind) then
            tick(p,weapons.chargeFrames(p,mode.kind,form))
            eq(count(mode.type),0,"charged weapons wait for release: "..mode.kind)
            setInput(p,ButtonAction.ACTION_SHOOTRIGHT,0)
        end
        tick(p)
        eq(count(mode.type),form.shots,mode.kind.." uses the boss projectile count")
        eq(count(EntityType.ENTITY_TEAR),0,"special weapons replace the tear volley")
        eq(state.volleys,1,"weapon spread counts as one volley")
        for i,shot in ipairs(Isaac.FindByType(mode.type,-1)) do
            near(shot.CollisionDamage,7,"weapon damage inherits the panel")
            eq(shot.TearFlags,p.TearFlags,"native weapon effects retained")
            local expected=form.shots==8 and (i-1)*45 or (i-2)*13
            local actual=mode.kind=="knife" and shot.Rotation+shot.RotationOffset or shot.AngleDegrees
            near((actual-expected+180)%360-180,0,"weapon spread has the correct angle")
            if mode.kind=="knife" then
                eq(shot.cantOverwrite,true,"throw does not replace original knife")
                near(shot.MaxDistance,p.TearRange,"knife inherits player range")
                shot.flying=false;mod:OnKnifeUpdate(shot)
                eq(shot:Exists(),false,"returned bonus knives are removed")
            end
        end
    end
end

p=reset();state=usePoop(p);state.cooldown=0;p.weapon=WeaponType.WEAPON_BRIMSTONE
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p,3)
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,0);tick(p)
eq(count(EntityType.ENTITY_LASER),0,"partial brimstone charge cancels without a volley")
eq(state.volleys,0,"cancelled charge cannot trigger summons")
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p,5)
mod:OnNewRoom();eq(state.weaponCharge,0,"room change cancels weapon charge")
tick(p,5);mod:OnUseDash(DASH,nil,p,0)
eq(state.weaponCharge,0,"dash cancels weapon charge")
state.dash=nil;tick(p,5);p.extraFinished=false;tick(p)
eq(state.weaponCharge,0,"item animation cancels stale weapon charge")
p.extraFinished=true;tick(p,5);p.weapon=WeaponType.WEAPON_TEARS;tick(p)
eq(state.weaponCharge,0,"losing the weapon discards its charge")
eq(count(EntityType.ENTITY_TEAR),3,"losing the weapon restores boss tears")

p=reset();state=usePoop(p);state.cooldown=0;p.weapon=WeaponType.WEAPON_KNIFE
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p,4)
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,0);tick(p)
local thrown=Isaac.FindByType(EntityType.ENTITY_KNIFE,-1)
eq(#thrown,3,"partial knife charge still throws a fan")
eq(thrown[1].Charge<1,true,"partial knife charge retains its charge fraction")
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p,40)
eq(state.weaponCharge,0,"knives must return before charging another volley")
for _,knife in ipairs(thrown) do knife.flying=false;mod:OnKnifeUpdate(knife) end
tick(p);eq(state.weaponCharge,1,"next knife charge starts after return")
local ordinaryKnife=p:FireKnife(p,0,false,0,0)
mod:OnKnifeUpdate(ordinaryKnife);eq(ordinaryKnife:Exists(),true,"other knives are not cleaned up")

p=reset();state=usePoop(p);state.cooldown=0;p.weapon=WeaponType.WEAPON_BRIMSTONE
state.volleys=3;setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1)
tick(p,weapons.chargeFrames(p,"brimstone",forms[1]))
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,0);tick(p)
eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),2,"fourth weapon volley still summons")

-- Native fetus/sword attacks must retain controls and their engine metadata.
for _,weapon in ipairs({WeaponType.WEAPON_FETUS,WeaponType.WEAPON_SPIRIT_SWORD,
    WeaponType.WEAPON_BOMBS,WeaponType.WEAPON_ROCKETS,WeaponType.WEAPON_MONSTROS_LUNGS,
    WeaponType.WEAPON_LUDOVICO_TECHNIQUE,WeaponType.WEAPON_BONE,WeaponType.WEAPON_NOTCHED_AXE,
    WeaponType.WEAPON_URN_OF_SOULS,WeaponType.WEAPON_UMBILICAL_WHIP}) do
    p=reset();state=usePoop(p);state.cooldown=0;p.weapon=weapon
    setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p)
    eq(count(EntityType.ENTITY_TEAR),0,"native weapon is not replaced with ordinary tears")
    for _,hook in ipairs({InputHook.GET_ACTION_VALUE,InputHook.IS_ACTION_PRESSED,InputHook.IS_ACTION_TRIGGERED}) do
        eq(mod:OnInput(p,hook,ButtonAction.ACTION_SHOOTRIGHT),nil,"native weapon receives its actual controls")
    end
    mod:OnUseDash(DASH,nil,p,0)
    eq(mod:OnInput(p,InputHook.IS_ACTION_PRESSED,ButtonAction.ACTION_SHOOTRIGHT),false,"dash still blocks native firing")
end
for index,form in ipairs(forms) do
    p=reset();state=usePoop(p);state.form=index;p.weapon=WeaponType.WEAPON_FETUS
    local source=p:FireTear(p.Position,Vector(9,0),true,false,true,p,1)
    source.Variant=TearVariant.FETUS;source.FrameCount=1;source.CollisionDamage=8.25
    source.TearFlags=1234;source.Height=-15;source.FallingAcceleration=0;source.Scale=1.7
    simulateReentry=true;mod:OnTearUpdate(source);simulateReentry=false
    eq(count(EntityType.ENTITY_TEAR),form.shots,"native fetus expanded to boss pattern")
    eq(state.volleys,1,"one fetus spread counts as one volley")
    for _,tear in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR,-1)) do
        eq(tear.Variant,TearVariant.FETUS,"fetus variant copied")
        eq(tear.TearFlags,1234,"fetus synergy flags copied from engine")
        near(tear.CollisionDamage,8.25,"fetus native damage multiplier retained")
        near(tear.Height,-15,"fetus height retained")
        near(tear.Scale,1.7,"fetus scale retained")
        mod:OnTearUpdate(tear)
    end
    eq(count(EntityType.ENTITY_TEAR),form.shots,"fetus expansion cannot recurse")
    eq(state.volleys,1,"repeated tear update does not count another volley")
    local child=p:FireTear(p.Position,Vector(9,0),false,false,false,p,1);child.Parent=source
    mod:OnTearUpdate(child)
    eq(count(EntityType.ENTITY_TEAR),form.shots+1,"fetal child attacks not duplicated")
    child.Parent=p;child.Variant=TearVariant.SWORD_BEAM;child.FrameCount=1
    tick(p);mod:OnTearUpdate(child)
    eq(count(EntityType.ENTITY_TEAR),form.shots+1,"fetus sword beams attributed to player are not expanded again")
    eq(state.volleys,1,"fetus child beam cannot count as another volley")

    p=reset();state=usePoop(p);state.form=index;p.weapon=WeaponType.WEAPON_SPIRIT_SWORD
    local held=p:FireKnife(p,0,false,0,10);mod:OnKnifeUpdate(held)
    eq(count(EntityType.ENTITY_KNIFE),1,"held sword is not copied")
    local swing=p:FireKnife(p,0,true,4,10);swing.Rotation=90;swing.FrameCount=1
    swing:GetSprite():SetFrame("SpinDown",1);swing.CollisionDamage=8.5;swing.TearFlags=123
    simulateReentry=true;mod:OnKnifeUpdate(swing);simulateReentry=false
    eq(count(EntityType.ENTITY_KNIFE),2,"native sword melee is preserved")
    eq(state.volleys,1,"sword pattern counts once")
    for _,knife in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE,-1)) do
        if knife.SubType==4 then
            eq(knife:GetSprite():GetAnimation(),"SpinDown","native spin animation retained")
            near(knife.CollisionDamage,8.5,"sword damage retained")
            eq(knife.TearFlags,123,"sword effects retained")
            mod:OnKnifeUpdate(knife)
        end
    end
    eq(count(EntityType.ENTITY_KNIFE),2,"sword does not recursively expand")
    local beam=p:FireTear(p.Position,Vector(0,12),false,false,false,p,1);beam.Variant=TearVariant.SWORD_BEAM;beam.FrameCount=1
    mod:OnTearUpdate(beam)
    eq(count(EntityType.ENTITY_TEAR),form.shots,"sword beams use matching boss pattern")
    eq(state.volleys,1,"sword beams do not double count summons")
    swing:Remove();mod:OnKnifeUpdate(held)
    eq(held:Exists(),true,"mod never removes the native held sword")
end

p=reset();state=usePoop(p)
p.movement=Vector(1,0);tick(p)
eq(state.avatar:GetSprite().FlipX,true,"native left-facing sheet flips when moving right")
p.movement=Vector(-1,0);tick(p)
eq(state.avatar:GetSprite().FlipX,false,"moving left restores native orientation")
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p)
eq(state.avatar:GetSprite().FlipX,true,"attack direction takes priority over opposite movement")
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,0);p.movement=Vector.Zero;tick(p)
eq(state.avatar:GetSprite().FlipX,true,"idle retains the last facing direction")
state.avatar:GetSprite().FlipX=false;mod:OnAvatarUpdate(state.avatar)
eq(state.avatar:GetSprite().FlipX,true,"effect update preserves facing after native animation update")

p=reset();state=usePoop(p)
local effectColor=Color(0.4,0.9,0.2,1)
p.nativeTear={Variant=TearVariant.TOOTH,CollisionDamage=p.Damage*3.2,
    TearFlags=TearFlags.TEAR_HOMING|TearFlags.TEAR_POISON|TearFlags.TEAR_PIERCING,
    Color=effectColor,Scale=1.8,Height=-28,FallingSpeed=-2,FallingAcceleration=0.01}
state.cooldown=0;setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1);tick(p)
for _,tear in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR,-1)) do
    eq(tear.TearFlags,p.nativeTear.TearFlags,"native tear effect flags preserved")
    eq(tear.Variant,TearVariant.TOOTH,"native proc variant preserved")
    near(tear.CollisionDamage,p.Damage*3.2,"native proc damage not overwritten by panel damage")
    eq(tear.Color,effectColor,"native effect color preserved")
    near(tear.Scale,1.8,"native effect size preserved")
    near(tear.FallingAcceleration,0.01,"native range trajectory preserved")
end

p=reset();state=usePoop(p);mod:OnRender()
eq(#renders,4,"HUD renders all four choices")
eq(#labels,0,"selector has no labels or key hints")
local first=renders[1].position
p.Position=Vector(450,220);renders={};mod:OnRender()
near(renders[1].position.X,first.X,"HUD X is independent of player position")
near(renders[1].position.Y,first.Y,"HUD Y is independent of player position")
Options.HUDOffset=1;renders={};mod:OnRender()
near(renders[1].position.X-first.X,20,"selector follows native HUD horizontal offset")
near(renders[1].position.Y-first.Y,12,"selector follows native HUD vertical offset")
tap(p);renders={};mod:OnRender()
eq(renders[2].color[4],1,"selected HUD icon is highlighted")
eq(renders[1].color[4]<1,true,"previous HUD icon dims after Ctrl")
game.hudVisible=false;renders={};mod:OnRender()
eq(#renders,0,"selector hides with native HUD")

p=reset();state=usePoop(p)
local enemy=entity(20,0,0,p.Position+Vector(45,0));enemy.enemy=true;enemy.Size=3
setInput(p,ButtonAction.ACTION_SHOOTRIGHT,1)
mod:OnUseDash(DASH,nil,p,0);p.Position=p.Position+Vector(90,0);tick(p)
eq((enemy.totalDamage or 0)>0,true,"fast dash swept hit does not tunnel")
room.wall=true;p.colliding=true;tick(p)
eq(state.dash.aim.X<0,true,"dash bounces on grid")
mod:OnNewRoom();eq(state.dash,nil,"room transition cancels dash")

p=reset();state=usePoop(p)
for variant=0,6 do
    local g=Isaac.GridSpawn(GridEntityType.GRID_POOP,variant,p.Position)
    local before=count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP)
    mod:OnPlayerUpdate(p);mod:OnPlayerUpdate(p)
    eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),before+1,"one dip from repeated contact")
    eq(room:GetGridEntityFromPos(p.Position),g,"broken poop grid is retained, not removed")
    eq(g.State,1000,"poop is fully destroyed")
    eq(g.CollisionClass,GridCollisionClass.COLLISION_NONE,"broken remnant does not block movement")
    if variant==1 then
        eq(g:GetVariant(),0,"spent red poop becomes non-regenerating rubble")
        eq(g.ReviveTimer,-1,"red regeneration timer is stopped")
    end
    local dips=Isaac.FindByType(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP)
    eq(dips[#dips].SubType,variant,"poop flavor preserved")
    mod:OnNewRoom();tick(p)
    eq(room:GetGridEntityFromPos(p.Position),g,"returning room keeps the broken grid")
    eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),before+1,"returning room never recruits broken poop twice")
end
local partial=Isaac.GridSpawn(GridEntityType.GRID_POOP,3,p.Position);partial.State=700
local partialBefore=count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP);tick(p)
eq(partial.State,1000,"partly damaged gold poop is completely broken")
eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),partialBefore+1,"new poop at the same tile can be recruited")
local rejected=Isaac.GridSpawn(GridEntityType.GRID_POOP,0,p.Position);rejected.rejectDamage=true
local rejectedBefore=count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP);tick(p)
eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),rejectedBefore,"unsuccessful destruction does not create free dips")
local broken=Isaac.GridSpawn(GridEntityType.GRID_POOP,0,p.Position);broken.State=1000
local before=count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP);tick(p)
eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),before,"broken poop does not duplicate dips")
eq(mod:OnDamage(p,1,DamageFlag.DAMAGE_POOP),false,"red poop safe during conversion")
eq(mod:OnDamage(p,1,DamageFlag.DAMAGE_EXPLOSION),nil,"other damage unaffected")
for _=1,20 do p:AddFriendlyDip(0,p.Position) end
Isaac.GridSpawn(GridEntityType.GRID_POOP,2,p.Position);before=count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP)
tick(p);eq(count(EntityType.ENTITY_FAMILIAR,FamiliarVariant.DIP),before+1,"contact conversion works above whistle summon limit")

local bomb=entity(EntityType.ENTITY_BOMB,BombVariant.BOMB_NORMAL,0,p.Position,p)
mod:OnBombUpdate(bomb);eq(bomb.Flags&TearFlags.TEAR_BUTT_BOMB,TearFlags.TEAR_BUTT_BOMB,"butt explosion flag")
local replacement=mod:OnPreBomb(EntityType.ENTITY_BOMB,BombVariant.BOMB_NORMAL,0,p.Position,Vector.Zero,p,888)
eq(replacement[2],BombVariant.BOMB_BUTT,"native butt bomb appearance")
eq(replacement[4],888,"bomb seed preserved")
eq(mod:OnPreBomb(EntityType.ENTITY_BOMB,BombVariant.BOMB_ROCKET,0,p.Position,Vector.Zero,p,888),nil,"special bomb identity preserved")
local rocket=entity(EntityType.ENTITY_BOMB,BombVariant.BOMB_ROCKET,0,p.Position,p)
mod:OnBombUpdate(rocket);eq(rocket.Flags&TearFlags.TEAR_BUTT_BOMB,TearFlags.TEAR_BUTT_BOMB,"special bombs also get butt effect")
local hostile=entity(EntityType.ENTITY_BOMB,BombVariant.BOMB_NORMAL,0,p.Position,nil)
mod:OnBombUpdate(hostile);eq(hostile.Flags,nil,"hostile bombs untouched")

local json=require("json")
for _,charge in ipairs({0,1,2}) do
    p=reset();p.items[2]=CollectibleType.COLLECTIBLE_DARK_ARTS;p.charges[2]=180
    saveText=json.encode({version=1,seed=startSeed,players={["0"]={form=2,selected=3,pocketInstalled=true,
        otherPocket={id=7777,isDash=true,charge=math.min(charge,1),battery=math.max(charge-1,0)}}}})
    mod:OnStarted(true);state=p:GetData()[key]
    eq(p.items[2],DASH,"legacy original active is replaced by rush on continue")
    eq(p.charges[2],charge,"legacy stashed rush keeps its own charge and battery bar")
    eq(state.form,2,"legacy form survives migration")
    eq(state.selected,3,"legacy selector survives migration")
    mod:OnExit(true)
    local migrated=json.decode(saveText)
    eq(migrated.version,2,"migration writes the simplified save format")
    eq(migrated.players["0"].otherPocket,nil,"migration discards the original active stash")
end
p=reset();p.items[2]=DASH;p.charges[2]=0
saveText=json.encode({version=1,seed=startSeed,players={["0"]={form=1,selected=1,pocketInstalled=true,
    otherPocket={id=CollectibleType.COLLECTIBLE_DARK_ARTS,charge=180}}}})
mod:OnStarted(true)
eq(p.charges[2],0,"equipped legacy rush is not recharged on upgrade")
eq(p.pocketWrites,nil,"equipped legacy rush is not reinstalled on upgrade")

p=reset();p.items[2]=CollectibleType.COLLECTIBLE_YUM_HEART;p.charges[2]=3;p.batteries[2]=2
state=usePoop(p)
eq(p.items[2],DASH,"transformation replaces the old permanent active")
eq(p.charges[2],1,"first transformation gives one rush charge")
eq(state.otherPocket,nil,"old active is not retained for swapping")
p.charges[2]=0
local writes=p.pocketWrites
tap(p);eq(state.selected,2,"Ctrl still cycles boss selection")
eq(p.items[2],DASH,"Ctrl does not restore the old active")
eq(p.charges[2],0,"Ctrl does not refill rush")
eq(state.form,1,"Ctrl only selects the next transformation")
tick(p,3);eq(state.selected,2,"one release only cycles once")
p.selectedCard=Card.CARD_HIEROPHANT;tap(p)
eq(p.selectedCard,Card.CARD_HIEROPHANT,"selected card remains available to native Q")
p.selectedCard=0;p.selectedPill=PillColor.PILL_BLUE_BLUE;tap(p)
eq(p.selectedPill,PillColor.PILL_BLUE_BLUE,"selected pill remains available to native Q")
p.selectedPill=0;tap(p)
eq(p.pocketWrites,writes,"Ctrl never reinstalls rush over the native pocket queue")
eq(p.charges[2],0,"card and pill selection does not recharge rush")
p.items[0]=0;local selected=state.selected;tap(p)
eq(state.selected,selected,"losing The Poop disables boss selection")
eq(p.items[2],DASH,"rush remains after losing The Poop")
p.items[0]=POOP

state.selected=4;usePoop(p);mod:OnExit(true)
eq(p.Visible,true,"exit restores player visibility")
mod:OnStarted(true);state=p:GetData()[key]
eq(state.form,4,"continue restores form")
eq(state.selected,4,"continue restores selector")
eq(state.otherPocket,nil,"continue does not restore the old active stash")
eq(p.charges[2],0,"continue does not recharge dash")
local q=newPlayer(1);players[2]=q;tick(q)
eq(q:GetData()[key].form,nil,"co-op state independent")
q:AddCollectible(POOP,1);tap(q);usePoop(q)
eq(q:GetData()[key].form,2,"co-op own selector")
eq(p:GetData()[key].form,4,"co-op leaves player one alone")
local oldp=p;p=newPlayer(0);p.items=oldp.items;p.charges=oldp.charges;players[1]=p;tick(p)
eq(p:GetData()[key].form,4,"replacement player instance retains transformation")
local sub=newPlayer(2);p.sub=sub;sub:AddCollectible(POOP,1);tick(sub);usePoop(sub)
eq(sub:GetData()[key].form,1,"sub-player state is independent")
eq(p:GetData()[key].form,4,"sub-player does not overwrite main")
mod:OnExit(true);startSeed=456;mod:OnStarted(true)
eq(p:GetData()[key].form,nil,"different run seed rejects stale save")
saveText="invalid json";mod:OnStarted(true)
eq(p:GetData()[key].form,nil,"invalid save handled")
usePoop(p);tick(p);mod:OnStarted(false)
eq(p:GetData()[key].form,nil,"new run clears transformation")
eq(p.Visible,true,"quick restart clears avatar invisibility")

mod:OnRender()
print("Poop Boss Forms: "..checks.." regression assertions passed (mocked engine).")
