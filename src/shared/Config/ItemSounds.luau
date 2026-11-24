--!strict
--[[
	ItemSounds: what every item sounds like (pickup, landing after a throw, placing, gadgets).

	Families are the recordings: all "ProSoundEffects" audio from the Roblox Creator Store (the
	Pro Sound Effects library Roblox licensed for experiences), each measured in Studio on
	2026-11-24. Volume brings them to the same quiet loudness, Start skips silence, Length keeps
	them short. client/AudioController also softens their high frequencies (no shrill clicks).

	Items: id -> { family, pitch }. Every real item needs an entry (checked by DevTests).
]]

export type Family = { SoundId: string, Volume: number, Start: number, Length: number }

local function family(id: number, volume: number, start: number, length: number): Family
	return table.freeze({ SoundId = `rbxassetid://{id}`, Volume = volume, Start = start, Length = length })
end

local Families: { [string]: Family } = {
	Can = family(9119375083, 0.3, 0.5, 0.5),
	Metal = family(9116756301, 0.45, 0.2, 0.6),
	Lid = family(9116736647, 0.55, 1.12, 0.6),
	Bar = family(9113290612, 0.28, 0.4, 0.5),
	Glass = family(9113559637, 0.8, 0, 0.6),
	Squeak = family(9125994570, 0.3, 0, 0.5),
	Wood = family(9126267420, 0.55, 0, 0.6),
	Knock = family(9120918534, 0.5, 0, 0.4),
	Zap = family(9114277757, 0.45, 0, 0.6),
	Cloth = family(9119079222, 1.2, 0, 0.6),
	Toy = family(9118272977, 1.4, 0, 0.8),
	Tech = family(9118272119, 1.1, 0.1, 0.8),
	Beep = family(9125935266, 2, 0, 0.5),
	Water = family(9125702803, 1, 0, 0.8),
	Snow = family(9125965260, 0.5, 0.35, 0.6),
	Plastic = family(9117453016, 0.45, 0.06, 0.5),
	Coin = family(9125509503, 0.35, 0.35, 0.7),
	Swish = family(9126283272, 1.4, 0.2, 0.4),
	Click = family(9119717523, 0.16, 0, 0.2),
	Tire = family(9126103903, 0.25, 0.7, 0.9),
	RobotVoice = family(9125850674, 0.8, 0, 0.7),
	RobotTalk = family(9125854887, 0.6, 0.2, 1),
	BikeBell = family(9125390321, 0.4, 0.2, 0.8),
	BikeDrop = family(9113423884, 0.3, 0, 0.4),
	Radio = family(9118027586, 0.8, 0, 0.5),
	Motor = family(80317022777602, 0.5, 0.4, 0.9),
	Ding = family(9126073026, 0.9, 0, 0.6),
}

local Items: { [string]: { any } } = {
	-- Junk
	rusty_can = { "Can", 1 }, soda_bottle = { "Glass", 1 }, old_tire = { "Plastic", 0.7 }, giant_fork = { "Bar", 1.1 },
	tin_bucket = { "Lid", 1 }, wooden_crate = { "Wood", 1 }, old_boot = { "Cloth", 0.8 }, pipe_segment = { "Bar", 0.85 },
	bike_wheel = { "Plastic", 1.2 }, paint_bucket = { "Lid", 0.85 }, broken_toaster = { "Metal", 1.2 }, cracked_monitor = { "Plastic", 0.9 },
	rubber_duck = { "Squeak", 1 }, bouncy_spring = { "Toy", 0.75 }, car_battery = { "Zap", 0.8 }, gear_wheel = { "Coin", 0.7 },
	broken_lamp = { "Glass", 0.8 }, old_radio = { "Beep", 0.8 }, dented_trophy = { "Bar", 1.3 }, toxic_barrel = { "Water", 0.7 },
	-- Materials
	metal_sheet = { "Metal", 0.9 }, bolt_pack = { "Coin", 1.1 }, copper_wire = { "Metal", 1.4 }, engine_part = { "Metal", 0.75 },
	circuit_board = { "Beep", 1.2 }, crystal_shard = { "Glass", 1.4 },
	-- Collectibles
	tin_robot = { "Tech", 1.1 }, snow_globe = { "Glass", 0.9 }, patched_mitten = { "Cloth", 1.2 }, copper_kettle = { "Lid", 1.2 },
	ice_skate = { "Metal", 1.3 }, spring_bot = { "Toy", 1.1 }, neon_gear = { "Zap", 1.2 }, arcade_joystick = { "Click", 0.8 },
	frost_lantern = { "Glass", 1.2 }, plasma_toaster = { "Zap", 0.9 }, crystal_snowman = { "Snow", 1.2 }, jet_sled = { "Metal", 1 },
	golden_wrench = { "Bar", 1.2 }, aurora_orb = { "Toy", 1.3 }, frozen_crown = { "Coin", 1.3 }, starforged_core = { "Toy", 0.9 },
	dragon_egg = { "Knock", 0.7 }, comet_shard = { "Glass", 1.6 },
	-- Components
	battery_pack = { "Zap", 1 }, metal_frame = { "Metal", 0.8 }, small_engine = { "Metal", 0.65 }, electric_motor = { "Zap", 0.7 },
	control_panel = { "Beep", 1 },
	-- Crafted
	wooden_sled = { "Wood", 1.2 }, bicycle = { "Metal", 1.15 }, metal_cart = { "Metal", 0.85 }, scooter = { "Metal", 1 },
	homemade_car = { "Metal", 0.6 }, turbo_kart = { "Metal", 0.7 }, jet_board = { "Plastic", 1 }, flashlight = { "Click", 1 },
	metal_detector = { "Beep", 1.4 }, scrap_magnet = { "Metal", 1.1 }, rocket_boots = { "Cloth", 0.9 }, storage_box = { "Wood", 0.85 },
	spring_launcher = { "Toy", 0.65 }, boombox_radio = { "Plastic", 0.95 }, generator = { "Metal", 0.6 }, scrap_snowman = { "Snow", 1 },
	junk_robot = { "Tech", 1 }, golden_trophy = { "Bar", 1.4 }, aurora_reactor = { "Toy", 0.8 }, glass_panel = { "Glass", 0.9 },
	neon_tv = { "Click", 0.9 }, disco_ball = { "Glass", 1.3 }, duck_fountain = { "Water", 1 }, snow_machine = { "Snow", 0.9 },
	frost_lamp = { "Click", 1.1 }, robot_band = { "Tech", 1.2 }, crystal_beacon = { "Glass", 1.1 }, toast_cannon = { "Metal", 1.25 },
	plasma_cannon = { "Zap", 0.75 }, high_five_machine = { "Cloth", 1.1 }, arcade_machine = { "Beep", 1.1 }, hologram_projector = { "Tech", 1.35 },
	teleport_pad = { "Tech", 0.8 }, golden_throne = { "Coin", 0.8 }, dragon_incubator = { "Knock", 0.8 }, cosmic_gate = { "Toy", 0.7 },
}

-- Taking an item into the hand (hotbar). Everything else uses its normal sound here.
local Equip: { [string]: { any } } = {
	old_tire = { "Tire", 1 }, bike_wheel = { "BikeDrop", 0.9 }, bicycle = { "BikeBell", 1 }, scooter = { "Motor", 1.5 },
	homemade_car = { "Motor", 0.9 }, turbo_kart = { "Tire", 1.15 }, jet_board = { "Motor", 1.9 }, small_engine = { "Motor", 1.1 },
	engine_part = { "Motor", 0.8 }, generator = { "Motor", 0.7 }, jet_sled = { "Motor", 1.7 }, electric_motor = { "Motor", 2 },
	tin_robot = { "RobotVoice", 1 }, spring_bot = { "RobotTalk", 1.15 }, junk_robot = { "RobotTalk", 0.85 }, robot_band = { "RobotVoice", 1.2 },
	old_radio = { "Radio", 0.9 }, boombox_radio = { "Radio", 1 }, neon_tv = { "Radio", 1.2 }, cracked_monitor = { "Radio", 0.75 },
	metal_detector = { "Beep", 1.6 }, dented_trophy = { "Ding", 0.7 }, golden_trophy = { "Ding", 0.9 }, frozen_crown = { "Ding", 1.1 },
	golden_throne = { "Ding", 0.8 }, arcade_machine = { "Beep", 1.3 }, arcade_joystick = { "Beep", 1.1 }, ice_skate = { "Swish", 1.5 },
	crystal_shard = { "Ding", 1.2 }, aurora_orb = { "Ding", 0.75 }, starforged_core = { "Ding", 0.65 }, comet_shard = { "Ding", 1 },
}

-- Sounds that are not an item.
local Events: { [string]: { any } } = {
	Throw = { "Swish", 1 },
	Sell = { "Coin", 1.15 },
	Button = { "Click", 1 },
	ChestOpen = { "Wood", 0.9 },
	Window = { "Swish", 1.3 },
	Toast = { "Metal", 1.5 },
	Eat = { "Toy", 1.2 },
	CreatureGone = { "Swish", 0.7 },
}

local ItemSounds = {}

ItemSounds.Families = table.freeze(Families)

local function resolve(entry: { any }?): (Family?, number)
	if entry == nil then
		return nil, 1
	end
	return Families[entry[1]], entry[2]
end

function ItemSounds.ForItem(itemId: string): (Family?, number)
	return resolve(Items[itemId])
end

function ItemSounds.ForEquip(itemId: string): (Family?, number)
	return resolve(Equip[itemId] or Items[itemId])
end

function ItemSounds.ForEvent(name: string): (Family?, number)
	return resolve(Events[name])
end

for id, entry in Items do
	assert(Families[entry[1]] ~= nil, `[ItemSounds] {id} uses unknown family {tostring(entry[1])}`)
end
for id, entry in Equip do
	assert(Items[id] ~= nil and Families[entry[1]] ~= nil, `[ItemSounds] bad equip entry {id}`)
end
for name, entry in Events do
	assert(Families[entry[1]] ~= nil, `[ItemSounds] {name} uses unknown family {tostring(entry[1])}`)
end

return table.freeze(ItemSounds)
