Config						= {}

Config["BaseServer"] = {
	["clinet_shared_obj"] = 'esx:getSharedObject', --คุณสามารถแก้ไขทรัพยากร ของ BaseServer คุณได้ ส่วนของ ฝั้ง client
	["server_shared_obj"] = 'esx:getSharedObject', --คุณสามารถแก้ไขทรัพยากร ของ BaseServer คุณได้ ส่วนของ ฝั้ง Server
	
}

Config.DrawDistance = 20.0

Config["Security"] = {
	ShopInteractDistance = 15.0, -- รัศมีที่อนุญาตให้กดซื้อ/ทดลองขับ
	ShopSaveDistance = 40.0, -- รัศมีตอนบันทึกความเป็นเจ้าของรถหลังซื้อ
	StrictWebhookConvarOnly = true, -- true = ใช้ webhook จาก convar เท่านั้น
	PlateCacheTtlMs = 10000, -- cache ผลเช็คทะเบียนซ้ำ
	BuyCooldownMs = 1200, -- กัน spam callback ซื้อรถ
	SaveOwnedCooldownMs = 1500, -- กัน spam event setVehicleOwned
	WriteQueueBatchSize = 50, -- จำนวนงานบันทึก DB ต่อรอบ flush
	WriteQueueActiveTickMs = 1000, -- ตอนคิว DB ไม่ว่างจะ flush ถี่ขึ้น
	WriteQueueIdleTickMs = 10000, -- ตอนคิว DB ว่างจะผ่อนรอบ flush ลง
	WriteQueueWarnSize = 100, -- เตือนเมื่อคิว DB สะสมสูง
	WebhookWorkerTickMs = 250, -- จังหวะ worker ส่ง webhook ตอนมีงาน
	WebhookIdleTickMs = 1000, -- ตอนคิว webhook ว่างจะผ่อนรอบเช็คลงเพื่อลด resmon
	WebhookRetryBaseMs = 2000, -- หน่วงเริ่มต้นตอน retry
	WebhookRetryMaxMs = 60000, -- หน่วงสูงสุดตอน retry
	WebhookQueueWarnSize = 200 -- เตือนเมื่อคิวสะสมสูง
}

Config.PlateLetters  = 3
Config.PlateNumbers  = 3
Config.PlateUseSpace = true

Config['Class_Vehicle'] = {
	[0] = "รถขนาดเล็ก",
    [1] = "รถซีดาน",
    [2] = "รถ SUV",
    [3] = "รถคูเป้",
    [4] = "รถมัสเซิล",
    [5] = "รถสปอร์ตคลาสสิก",
    [6] = "รถสปอร์ต",
    [7] = "รถซูเปอร์คาร์",
    [8] = "รถมอเตอร์ไซค์",
    [9] = "รถออฟโรด",
    [10] = "รถอุตสาหกรรม",
    [11] = "รถอเนกประสงค์",
    [12] = "รถตู้",
    [13] = "จักรยาน",
    [14] = "เรือ",
    [15] = "เฮลิคอปเตอร์",
    [16] = "เครื่องบิน",
    [17] = "รถบริการ",
    [18] = "รถฉุกเฉิน",
    [19] = "รถทหาร",
    [20] = "รถเพื่อการพาณิชย์",
    [21] = "รถไฟ"
}

Config['ColorList'] = {
	[1] = {
		['blue'] = {
			background = '#5DB6E5',
			r = 93,
			g = 182,
			b = 229
		},
		['black'] = {
			background = '#2C2C2C',
			r = 44,
			g = 44,
			b = 44
		},
		['pink'] = {
			background = '#CB3694',
			r = 203,
			g = 54,
			b = 148
		},
		['red'] = {
			background = '#E03232',
			r = 224,
			g = 50,
			b = 50
		},
		['purple'] = {
			background = '#8466E2',
			r = 132,
			g = 102,
			b = 226
		},
		['white'] = {
			background = '#D4D4D4',
			r = 212,
			g = 212,
			b = 212
		},
	},
	[2] = {
		['blue'] = {
			background = '#5DB6E5',
			r = 93,
			g = 182,
			b = 229
		},
		['black'] = {
			background = '#2C2C2C',
			r = 44,
			g = 44,
			b = 44
		},
		['pink'] = {
			background = '#CB3694',
			r = 203,
			g = 54,
			b = 148
		},
		['red'] = {
			background = '#E03232',
			r = 224,
			g = 50,
			b = 50
		},
		['purple'] = {
			background = '#8466E2',
			r = 132,
			g = 102,
			b = 226
		},
		['white'] = {
			background = '#D4D4D4',
			r = 212,
			g = 212,
			b = 212
		},
	},
	
}

Config['ZONE_SHOP'] = {
	{
		shop = 'car',
		label = 'Premium Deluxe Motorsport',
		visibleJobs = nil, -- nil = ทุก job เห็นจุดนี้, หรือใส่ {'police', 'ambulance'} เฉพาะ job ที่ต้องการ
		vehicleSource = 'public', -- public = ใช้ Config['vehicles'], job = ใช้ Config['JobVehicles'], all = ใช้ทั้งสองชุด
		vehicleList = nil, -- nil = ใช้รถทั้งหมดจาก source ที่เลือก, หรือใส่ {'bati', 'police3'} เพื่อกำหนดรถเฉพาะจุดนี้
		ShopEnterShop = {
			Pos = vector4(-56.7774,-1096.98, 26.422,1.0),
			Size  = { x = 1.5, y = 1.5, z = 1.0 },
			colormarker = { r = 120, g = 120, b = 240,a = 100 },
			Type  = 20
		},
		ShopInside = {
			Pos     = vector4(-47.570, -1097.221, 25.422,-20.0),
			
		},
		ShopOutside = {
			Pos     = vector4(-11.54, -1083.38, 26.68,165.09),
			
		},
		TestDriveSpawn = nil, -- nil = ใช้ ShopOutside, หรือกำหนด vector4 จุดทดลองรถที่อยู่ไกลออกไปได้
		TestDriveReturn = nil, -- nil = ใช้ ShopEnterShop ตอนหมดเวลา/ลงรถ
		TestDriveDurationSec = 15 -- เวลาทดลองขับของจุดนี้
	},
	--[[
	{
		shop = 'car',
		label = 'Police Garage Shop',
		visibleJobs = {'police'},
		vehicleSource = 'job',
		vehicleList = {'police3', 'policeb'},
		ShopEnterShop = {
			Pos = vector4(441.0, -981.0, 30.0, 90.0),
			Size  = { x = 1.5, y = 1.5, z = 1.0 },
			colormarker = { r = 40, g = 120, b = 255, a = 100 },
			Type  = 20
		},
		ShopInside = {
			Pos = vector4(449.0, -986.0, 25.0, 180.0),
		},
		ShopOutside = {
			Pos = vector4(454.0, -1020.0, 28.0, 90.0),
		},
		TestDriveSpawn = vector4(1518.0, 3775.0, 34.0, 215.0),
		TestDriveReturn = vector4(441.0, -981.0, 30.0, 90.0),
		TestDriveDurationSec = 120
	}
	]]
}

Config['Category'] = {
	[1] = {
        label = "จักรยาน",
		index = 'cycles',
	},
	[2] = {
		label = "รถมอเตอร์ไซค์",
		index = 'motorcycles',
	},
	[3] = {
        label = "รถสปอร์ต",
		index = 'sport', 
	},
	[4] = {
        label = "รถบรรทุก KG",
		index = 'kgcar',
	},
	[5] = {
		label = "หน่วยแพทย์",
		index = 'ambulance', --หน่วยงานให้ใส่เป็นชื่อjob
      
	},
	[6] = {
		label = "ตำรวจ",
		index = 'police', --หน่วยงานให้ใส่เป็นชื่อjob
       
	},
	[7] = {
		label = "เทศบาล",
		index = 'council', --หน่วยงานให้ใส่เป็นชื่อjob
    
	},
}

	-- สำหรับหน่วยงาน
	-- ["ชื่อค่ายานพาหนะ"] = {
	-- 	name = "ชื่อที่จะแสดง",
	-- 	model = "ชื่อค่ายานพาหนะ",
	-- 	price = 0, --ราคาที่ขาย
	-- 	category = "police", --หมวดหมู่ หน่วยงานให้ใส่เป็นชื่อjob
	-- 	grade = 0, -- ลำดับยศถ้าไม่แบ่ง ยศไม่จำเป็นต้องใส่ (คำอธิบายสำหรับคน ไม่เข้าใจ)
	-- 	kg = 0, --นำหนักเก็บของท้ายรถ
	-- 	typecar = 'car' --ประเภทยานพาหนะ
	-- },

	-- สำหรับประชาชน
	-- ["ชื่อค่ายานพาหนะ"] = {
	-- 	name = "ชื่อที่จะแสดง",
	-- 	model = "ชื่อค่ายานพาหนะ",
	-- 	price = 0, --ราคาที่ขาย
	-- 	category = "sport", --หมวดหมู่
	-- 	grade = 0, -- ลำดับยศถ้าไม่แบ่ง ยศไม่จำเป็นต้องใส่ (คำอธิบายสำหรับคน ไม่เข้าใจ)
	-- 	kg = 0, --นำหนักเก็บของท้ายรถ
	-- 	typecar = 'car' --ประเภทยานพาหนะ
	-- },

	
Config['JobVehicles'] = {
	-- ตัวอย่างรถร้านหน่วยงาน แยกออกจาก Config['vehicles'] สำหรับร้าน job โดยเฉพาะ
	-- ["police3"] = {
	-- 	name = "Police Cruiser",
	-- 	model = "police3",
	-- 	price = 0,
	-- 	category = "police",
	-- 	grade = 0,
	-- 	kg = 0,
	-- 	typecar = 'car'
	-- },
	-- ["ambulance"] = {
	-- 	name = "Ambulance",
	-- 	model = "ambulance",
	-- 	price = 0,
	-- 	category = "ambulance",
	-- 	grade = 0,
	-- 	kg = 0,
	-- 	typecar = 'car'
	-- },
}

Config['vehicles'] = {
	["adm_porcaygt2"] = {
		name = "Porsche Cayenne Turbo GT",
		model = "adm_porcaygt2",
		price = 3500000,
		category = "sport",
		kg = 0,
		typecar = 'car'
	},
	["bmx"] = {
		name = "Bmx",
		model = "bmx",
		price = 500,
		category = "cycles",
		kg = 0,
		typecar = 'car'
	},
	["fixter"] = {
		name = "Fixter",
		model = "fixter",
		price = 3500,
		category = "cycles",
		kg = 0,
		typecar = 'car'
	},
	["tribike"] = {
		name = "Tribike",
		model = "tribike",
		price = 5000,
		category = "cycles",
		kg = 0,
		typecar = 'car'
	},
--------------------------------------------------------------
	["bati"] = {
		name = "Pegassi Bati 801",
		model = "bati",
		price = 300000,
		category = "motorcycles",
		kg = 10,
		typecar = 'car'
	},
	["bf400"] = {
		name = "Nagasaki BF400",
		model = "bf400",
		price = 500000,
		category = "motorcycles",
		kg = 10,
		typecar = 'car'
	},
	["faggio3"] = {
		name = "Pegassi Faggio Mod",
		model = "faggio3",
		price = 300000,
		category = "motorcycles",
		kg = 10,
		typecar = 'car'
	},
	
	
} 

Config["DiscordWebhook"] = {
	Enable = true,
	BuyVehicle = '', -- แนะนำ: ตั้งค่าใน server.cfg ด้วย `setr val_vehicleshop_webhook_buy "https://discord.com/api/webhooks/..."`
	BotName = 'VAL Legacy [LOG]',
	AvatarURL = ''
}
