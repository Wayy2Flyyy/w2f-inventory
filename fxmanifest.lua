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
    'server/main.lua',
    'server/callbacks.lua',
    'server/admin.lua',
    'server/commands.lua',
}

client_scripts {
    'client/main.lua',
    'client/status.lua',
    'client/interact.lua',
}

ui_page 'ui/inventory.html'

files {
    'ui/inventory.html',
    'images/*.png',
    'data/items.lua',
    'data/image_items.lua',
    'data/weapons.lua',
    'data/crafting.lua',
    'data/shops.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
}
