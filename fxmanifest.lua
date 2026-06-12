fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'w2f-inventory'
author 'w2f'
version '1.0.0'

shared_script '@ox_lib/init.lua'

shared_scripts {
    'shared/config.lua',
    'shared/items.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/main.lua',
    'server/callbacks.lua',
    'server/admin.lua',
}

client_scripts {
    'client/framework.lua',
    'client/main.lua',
    'client/status.lua',
    'client/interact.lua',
}

ui_page 'ui/inventory.html'

files {
    'ui/inventory.html',
    'images/*.png',
    'data/items.lua',
    'data/weapons.lua',
    'data/crafting.lua',
    'data/shops.lua',
}

-- Core framework (qbx_core / qb-core / es_extended) is detected at runtime via
-- the `inventory:framework` convar, so it is intentionally not a hard dependency.
dependencies {
    'ox_lib',
    'oxmysql',
}
