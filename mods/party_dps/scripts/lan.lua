return function(mod, Meter, callbacks)
    local api = rawget(_G, "IsaacLAN")
    if not api or api.API_VERSION ~= 1 then
        return
    end
    local lan = api:RegisterMod(mod, { id = "isaac-mods.party-dps", integrationVersion = 1 })
    local adapter = { handle = lan, lastPoll = nil, pending = false, generation = 0 }
    lan:RegisterAction("snapshot", {
        version = 1,
        cooldownTicks = 12,
        validate = function(payload)
            return type(payload) == "table" and next(payload) == nil
        end,
        execute = function()
            return { status = "applied", code = Meter.encode(callbacks.snapshot()) }
        end,
    })
    lan:On("StateReset", function(context)
        adapter.generation = adapter.generation + 1
        adapter.pending, adapter.lastPoll, adapter.received = false, nil, nil
        adapter.receivedTick, adapter.status = nil, nil
        callbacks.reset(context)
    end)
    lan:On("ViewUpdated", function(context)
        callbacks.view(context, lan)
        if lan:IsAuthority() then
            return
        end
        if not lan:HasHostAction("snapshot", 1) then
            adapter.status = "Host needs Party DPS"
            return
        end
        if adapter.pending or (adapter.lastPoll and context.tick - adapter.lastPoll < 15) then
            return
        end
        adapter.pending, adapter.lastPoll = true, context.tick
        local generation = adapter.generation
        local request, reason = lan:RequestAction("snapshot", {}, function(result)
            if generation ~= adapter.generation then
                return
            end
            adapter.pending = false
            local snapshot = result.status == "applied" and Meter.decode(result.code)
            if snapshot then
                adapter.received, adapter.receivedTick = snapshot, context.tick
                adapter.status = nil
            else
                adapter.status = result.status == "applied" and "Invalid DPS snapshot"
                    or "Sync: " .. (result.code or result.status)
            end
        end)
        if not request then
            adapter.pending = false
            adapter.status = "Sync: " .. tostring(reason)
        end
    end)
    function adapter:active()
        return lan:IsActive()
    end
    function adapter:authority()
        return not lan:IsActive() or lan:IsAuthority()
    end
    function adapter:snapshot(tick)
        if not lan:IsReady() then
            return nil, "Waiting for LAN"
        end
        if lan:IsAuthority() then
            return callbacks.snapshot()
        end
        local status = self.status
        if self.receivedTick and tick - self.receivedTick > 90 then
            status = "Waiting for host"
        end
        return self.received, status or (not self.received and "Syncing with host" or nil)
    end
    return adapter
end
