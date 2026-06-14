-- atena-bridge-pila — SERVER: fill std-pila's seams with atena's policy + apply its shipped DB schema via
-- atena's dbMigrate. NO permanent bail at load (bridge-registration §5a): bind handlers ALWAYS, gate
-- cross-resource calls at call-time, re-arm on (re)start. pcall swallows the mid-restart transient.

-- Fill the auth + inbound-guard seams with atena's policy (deny-by-default perms + centralized guard).
-- The privileged identity ops (admin block, re-sleeve extraction) resolve through can(); rank gating
-- (atena-security §4.1) applies on the atena side for coercive admin actions.
local function armSeams()
    if GetResourceState('atena') ~= 'started' or GetResourceState('std-pila') ~= 'started' then return end
    pcall(function()
        exports['std-pila']:setAuthorizer(function(src, action) return exports.atena:can(src, action) end)
        exports['std-pila']:setGuard(function(opts, src, args) return exports.atena:checkInbound(opts, src, args) end)
    end)
end

-- Apply the resource's shipped, versioned schema to atena's DB (idempotent — resource_migrations).
local function armSchema()
    if GetResourceState('atena') ~= 'started' or GetResourceState('std-pila') ~= 'started' then return end
    pcall(function()
        local schema = exports['std-pila']:schema()
        if schema then exports.atena:dbMigrate('std-pila', schema) end
    end)
end

-- Swap std-pila's persistence to Atena.DB on a bridge-side bounded poll of pool readiness (a function
-- passed across the resource boundary into atena is NOT reliably invoked back, so control flow never
-- depends on a cross-resource callback). setPersistence reloads the identity registry internally.
local arming, swapped = false, false
local function armPersistence()
    if arming or swapped then return end                 -- one waiter; skip once the swap has happened
    arming = true
    CreateThread(function()
        for _ = 1, 600 do                                -- ~120s bounded (the DB pool can be slow on a cold boot)
            if GetResourceState('atena') == 'started' and GetResourceState('std-pila') == 'started'
               and exports.atena:dbIsReady() then
                pcall(function()
                    local schema = exports['std-pila']:schema()
                    if schema then exports.atena:dbMigrate('std-pila', schema) end   -- ensure (idempotent)
                    exports['std-pila']:setPersistence(Bridge.pilaBackend())          -- swaps + reloads internally
                end)
                swapped, arming = true, false
                return
            end
            Wait(200)
        end
        arming = false                                   -- deps never came up → allow a later re-arm
    end)
end

-- TODO (in-game / Atena.Players): bind identities to Atena.Accounts — account ↔ pile roster,
-- character-select picks the active pila, admin block surfaces in the admin menu (rank-gated).

local function arm() armSeams() armSchema() armPersistence() end

arm()
AddEventHandler('onResourceStart', function(res)
    if res == 'std-pila' then swapped = false end        -- std reset to its KVP default → must re-swap
    if res == 'atena' or res == 'std-pila' then arm() end
end)
