fx_version 'adamant'
games {'gta5' }

name 'APEX-VehicleShop'
description 'APEX-VehicleShop'

client_scripts {
	'config.lua',
	'config-notify.lua',
	'config-image.lua',
	'core/client.lua',
	'core/utils.lua',
	'function/function_client.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'config.lua',
	'core/server.lua',
	'function/function_server.lua'
}

ui_page 'html/ui.html'

files {
	'html/ui.html',
	'html/css/style.css',
	'html/js/*.js',
	'html/img/*.png',
	'html/font/*.ttf',
	'html/images/vehicles/*.png',
	'html/images/vehicles/*.jpg',
	'html/images/vehicles/*.webp',
}
lua54 'yes'
