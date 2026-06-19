-- atena-bridge-pila — SERVER: own the cross-resource LINK between std-pila, the std-inventory ENGINE, and
-- std-custodia. The standalone is pure (identity STATE only, standalone-resource §2.0); this bridge
-- registers the pila item-type on the engine and orchestrates the GRAPH moves (create / sleeve / extract /
-- destroy — engine item id IS the pila id). No permanent bail (bridge-registration §2): gate at call-time,
-- re-arm on (re)start of either side (an engine restart resets its type registry).
local function bothUp() return GetResourceState('std-pila') == 'started' and GetResourceState('std-inventory') == 'started' end

local typeName = 'pila'   -- cached from the registered def (the standalone names the type)

local function register()
    if not bothUp() then return end
    pcall(function()
        local it = exports['std-pila']:itemType()
        if it and it.name then
            typeName = it.name
            exports['std-inventory']:inventoryRegisterType(it.name, it.def)
        end
    end)
end

CreateThread(function() while not bothUp() do Wait(250) end register() end)
AddEventHandler('onResourceStart', function(res)
    if res == 'std-pila' or res == 'std-inventory' or res == GetCurrentResourceName() then register() end
end)

-- Create an identity = engine item (the bridge owns the graph) + identity row keyed by that id.
local function spawn(accountRef, name)
    if not bothUp() then return nil, 'down' end
    local inv = exports['std-inventory']
    local item = inv:inventoryCreate(typeName, inv:inventoryLoc('owner', accountRef or 'unbound'))
    if not item or not item.id then return nil, 'create-failed' end
    return exports['std-pila']:pilaCreate(item.id, accountRef, name)
end

-- Sleeve a pila INTO a body's LOCKED `stack` slot. The engine validates acceptance (`stack` accepts
-- `pila`) and locks the placement (custodia's slot def has lock=true → no extraction in v1). Mirrors the
-- link on the body row so std-custodia knows which pila it carries.
local function sleeve(pilaId, custodiaId)
    if not bothUp() then return false, 'down' end
    if not exports['std-pila']:pilaExists(pilaId) then return false, 'no-pila' end
    local inv = exports['std-inventory']
    local ok, err = inv:inventoryMove(pilaId, inv:inventoryLoc('container', custodiaId, 'stack'))
    if ok then
        if GetResourceState('std-custodia') == 'started' then pcall(function() exports['std-custodia']:custodiaSetPila(custodiaId, pilaId) end) end
        TriggerEvent('std-pila:sleeved', pilaId, custodiaId)
    end
    return ok, err
end

-- Extract a pila from its body (RE-SLEEVE / admin). Unlocks the locked placement, moves the pila back to
-- its account-root, clears the body-row mirror. The caller (privileged) is gated upstream by atena.
local function extract(pilaId, ownerRef)
    if not bothUp() then return false, 'down' end
    if not exports['std-pila']:pilaExists(pilaId) then return false, 'no-pila' end
    local inv = exports['std-inventory']
    local cur = inv:inventoryGet(pilaId)
    local bodyId = cur and cur.loc and cur.loc.parent or nil
    inv:inventorySetLocked(pilaId, false)
    local row = exports['std-pila']:pilaGet(pilaId)
    local owner = ownerRef or (row and row.account) or 'unbound'
    local ok, err = inv:inventoryMove(pilaId, inv:inventoryLoc('owner', owner))
    if ok then
        if bodyId and GetResourceState('std-custodia') == 'started' then pcall(function() exports['std-custodia']:custodiaSetPila(bodyId, false) end) end
        TriggerEvent('std-pila:extracted', pilaId, owner)
    end
    return ok, err
end

-- Destroy a pila: drop the engine item + the identity row, AND clear the body-row mirror if it was sleeved
-- (so a destroyed pila never leaves a dangling custodia_bodies.pila_id). Capture the containing body BEFORE
-- the engine destroy (after it the location is gone), mirror-clear after — symmetric with sleeve (sets the
-- mirror) / extract (clears it). The std-custodia call is gated + pcall'd: a transient leaves the mirror to
-- the body's own removal (custodiaRemove drops the row anyway), never a crash.
local function destroy(id)
    if not id then return false, 'no-id' end
    local bodyId
    if GetResourceState('std-inventory') == 'started' then
        pcall(function()
            local cur = exports['std-inventory']:inventoryGet(id)
            bodyId = cur and cur.loc and cur.loc.parent or nil   -- the custodia this pila is sleeved in, if any
            exports['std-inventory']:inventoryDestroy(id)
        end)
    end
    if bodyId and GetResourceState('std-custodia') == 'started' then
        pcall(function() exports['std-custodia']:custodiaSetPila(bodyId, false) end)
    end
    if GetResourceState('std-pila') == 'started' then return exports['std-pila']:pilaDestroy(id) end
    return false, 'down'
end

exports('pilaSpawn', spawn)
exports('pilaSleeve', sleeve)
exports('pilaExtract', extract)
exports('pilaRemove', destroy)

-- ── In-game self-test: registers a temp `test_custodia` type (locked `stack` accepting `pila`), then
-- create -> sleeve (locked) -> blocked direct-move -> extract (re-sleeve) -> cleanup. Self-contained
-- (only needs std-pila + std-inventory). Gated with atena; console src=0 allowed.
local function canDebug(src)
    if src == 0 then return true end
    return GetResourceState('atena') == 'started' and exports.atena:can(src, 'debug')
end

local function runTest()
    if not bothUp() then print('[pila test] SKIP std-pila/std-inventory not started'); return end
    local inv, pila = exports['std-inventory'], exports['std-pila']
    local results = {}
    local function check(name, cond) results[#results + 1] = ((cond and 'PASS' or 'FAIL') .. ' ' .. name) end

    inv:inventoryRegisterType('test_custodia', { slots = { stack = { accept = { 'pila' }, lock = true } } })
    local body = inv:inventoryCreate('test_custodia', inv:inventoryLoc('owner', 'pila_test'))
    check('temp body created', body ~= nil and body.id ~= nil)

    local pilaId, err = spawn('acc_test', 'Takeshi Kovacs')
    check('create identity (engine item + row)', pilaId ~= nil)
    if not pilaId or not body then
        for _, l in ipairs(results) do print('[pila test] ' .. l) end
        print('[pila test] err=' .. tostring(err)); if body then inv:inventoryDestroy(body.id) end; return
    end

    local row = pila:pilaGet(pilaId)
    check('identity row stored', row ~= nil and row.name == 'Takeshi Kovacs' and row.blocked == false)
    check('sleeve into stack', sleeve(pilaId, body.id) == true)
    local placed = inv:inventoryGet(pilaId)
    check('pila inside body stack (LOCKED)', placed ~= nil and placed.loc.parent == body.id
        and placed.loc.slot == 'stack' and placed.loc.locked == true)
    check('locked pila cannot be moved directly', inv:inventoryMove(pilaId, inv:inventoryLoc('owner', 'acc_test')) == false)
    check('extract (re-sleeve) unlocks + moves out', extract(pilaId, 'acc_test') == true)
    local back = inv:inventoryGet(pilaId)
    check('pila back at account root', back ~= nil and back.loc.owner == 'acc_test')
    check('setBlocked toggles admin lock', pila:pilaSetBlocked(pilaId, true) and pila:pilaGet(pilaId).blocked == true)
    check('forAccount lists the identity', #pila:pilaForAccount('acc_test') == 1)
    check('destroy drops item + row', destroy(pilaId) and pila:pilaGet(pilaId) == nil and inv:inventoryGet(pilaId) == nil)
    inv:inventoryDestroy(body.id)

    for _, line in ipairs(results) do print('[pila test] ' .. line) end
end
RegisterCommand('pila_test', function(src) if canDebug(src) then runTest() end end, false)
