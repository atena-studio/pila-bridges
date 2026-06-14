# pila-bridges

Integration bridges for the `std-pila` standalone resource, one per framework.

| Framework | Bridge | Status |
|-----------|--------|--------|
| atena     | `atena-bridge-pila` | present |
| ESX       | `esx-bridge-pila`   | planned |
| QBCore    | `qbcore-bridge-pila`| planned |
| OX        | `ox-bridge-pila`    | planned |

Each bridge is integration glue: it fills the standalone's seams (authorizer, inbound guard, persistence
backend), applies its shipped DB schema, registers the `pila` item-type on the `std-inventory` engine, and
orchestrates the graph moves (create / sleeve / extract / destroy). The standalone stays pure/agnostic.

Install the standalone (`std-pila`) + `std-inventory` + the ONE bridge matching your framework.

## Get the standalone (required)

This bridge is free integration glue and needs the **std-pila** standalone resource (sold separately):

➡️ **https://github.com/atena-studio/std-pila**
