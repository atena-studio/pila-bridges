-- atena-bridge-pila — glue between the standalone `std-pila` and atena. Fills the resource's auth/guard
-- seams with atena's policy, applies its shipped DB schema via atena's dbMigrate, and (later) swaps its
-- persistence backend to Atena.DB + binds identities to Atena.Accounts (account ↔ pile, character select,
-- admin block). Inert unless the resources are up (runtime-detection, no hard deps).
-- atena-framework §6 — bridge is EXEMPT from vouch anti-bias.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'atena-bridge-pila'
author 'SirTheo'
description 'Bridge: std-pila ↔ atena. Seams + DB schema migration (identity persistence).'
version '0.1.0'

server_scripts {
    'server/persistence.lua',   -- Atena.DB-backed persistence backend (pila_identities)
    'server/main.lua',          -- seams (authorizer + inbound guard) + dbMigrate + persistence swap
    'server/inventory.lua',     -- LINK to the std-inventory engine: register type + create/sleeve/extract
}
