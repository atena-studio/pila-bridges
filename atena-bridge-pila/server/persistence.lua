-- atena-bridge-pila — Atena.DB-backed persistence backend for std-pila. Implements the seam shape
-- (save/load/loadAll/delete, callback form) against `pila_identities`; main.lua injects it via
-- setPersistence. Parameterized queries; nullable account via nullif(''). The identity row is flat
-- (id/account/name/blocked) — the engine owns the pila item + its location, this owns the identity.
Bridge = Bridge or {}

-- DB row -> the seam's row shape std-pila understands ({ id, account, name, blocked }). An unbound pila
-- stores account = false (mirrors the resource's `account or false`).
local function mapRow(r)
    if not r then return nil end
    return { id = r.id, account = r.account or false, name = r.name, blocked = r.blocked == true }
end

function Bridge.pilaBackend()
    local B = {}

    function B.save(uid, row, cb)   -- engine-assigned text id -> UPSERT by id
        exports.atena:dbExecute(
            'insert into pila_identities (id, account, name, blocked) '
            .. "values ($1, nullif($2,''), $3, $4) "
            .. "on conflict (id) do update set account=nullif($2,''), name=$3, blocked=$4",
            { tostring(uid), row.account or '', row.name or 'Unknown', row.blocked == true },
            function() if cb then cb(uid) end end)
    end

    function B.load(uid, cb)
        exports.atena:dbSingle('select * from pila_identities where id=$1', { tostring(uid) },
            function(r) if cb then cb(mapRow(r)) end end)
    end

    function B.loadAll(cb)
        exports.atena:dbQuery('select * from pila_identities', {}, function(rs)
            if not rs then if cb then cb(nil) end; return end   -- query error -> nil (registry kept)
            local out = {}
            for i = 1, #rs do out[i] = mapRow(rs[i]) end
            if cb then cb(out) end
        end)
    end

    function B.delete(uid, cb)
        exports.atena:dbExecute('delete from pila_identities where id=$1', { tostring(uid) },
            function() if cb then cb(true) end end)
    end

    return B
end
