--!strict
--[[
	Localization: shows the game in the player's own language.

	The game's code keeps writing English. client/LocalizationController passes every text a
	player sees (labels and buttons in PlayerGui and in world SurfaceGuis / BillboardGuis)
	through Translate(), so no other module needs to know about languages.

	Language files: Languages/<code>.luau return { [english] = translation }.
	  Keys are the English text as the game shows it. "{}" in a key stands for any text, e.g.
	    ["Sold {} item{} for {}!"] = "Vendiste {1} objeto{2} por {3}!"
	  In the translation "{}" are filled in order, "{1}", "{2}"... by number (any order,
	  a value may be left out). Every filled-in value is translated too, so item names inside a
	  message come out in the player's language; a player's name simply stays as it is.
	Lookup order: the exact text -> "{}" patterns (more specific ones first) -> rich text
	(each text run alone) -> parts between "·" alone -> each line alone. Nothing found: the
	English text stays.

	Language: LocalizationService.RobloxLocaleId (the player's Roblox language setting), the
	Studio override ReplicatedStorage attribute "ForceLanguage" (e.g. "es"), else English.
]]

local Localization = {}

-- code -> name in that language (order = how they are listed)
Localization.Languages = table.freeze({
	{ Code = "en", Name = "English" },
	{ Code = "es", Name = "Español" },
	{ Code = "pt", Name = "Português" },
	{ Code = "ru", Name = "Русский" },
	{ Code = "uk", Name = "Українська" },
	{ Code = "de", Name = "Deutsch" },
	{ Code = "fr", Name = "Français" },
	{ Code = "it", Name = "Italiano" },
	{ Code = "pl", Name = "Polski" },
	{ Code = "tr", Name = "Türkçe" },
	{ Code = "id", Name = "Bahasa Indonesia" },
	{ Code = "vi", Name = "Tiếng Việt" },
	{ Code = "th", Name = "ไทย" },
	{ Code = "ko", Name = "한국어" },
	{ Code = "ja", Name = "日本語" },
	{ Code = "zh", Name = "简体中文" },
})

-- Roblox locale id ("es-es", "pt-br", "zh-cn", ...) -> our language code, or "en".
function Localization.CodeFor(localeId: string?): string
	local id = string.lower(localeId or "")
	local base = string.match(id, "^(%a+)") or ""
	for _, language in Localization.Languages do
		if language.Code == base then
			return base
		end
	end
	return "en"
end

export type Translator = {
	Translate: (text: string) -> string,
	Missing: { [string]: boolean }, -- texts with no translation (filled only when recording)
	Code: string,
}

local MAX_CACHE = 4000

-- "Sold {} item{} for {}!" -> "^Sold (.-) item(.-) for (.-)!$"
local function compile(key: string): string
	local escaped = string.gsub(key, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. string.gsub(escaped, "{}", "(.-)") .. "$"
end

-- Puts the values into a translation: "{}" in order, "{n}" by number.
local function fill(template: string, values: { string }): string
	local nextIndex = 0
	return (string.gsub(template, "{(%d*)}", function(digits: string): string
		local index: number
		if digits == "" then
			nextIndex += 1
			index = nextIndex
		else
			index = tonumber(digits) :: number
		end
		return values[index] or ""
	end))
end

function Localization.NewTranslator(code: string, entries: { [string]: string }, record: boolean?): Translator
	local exact: { [string]: string } = {}
	local patterns: { { Pattern: string, Translation: string, Weight: number } } = {}
	for key, translation in entries do
		if string.find(key, "{}", 1, true) then
			local literal = #string.gsub(key, "{}", "")
			table.insert(patterns, { Pattern = compile(key), Translation = translation, Weight = literal })
		else
			exact[key] = translation
		end
	end
	-- More literal text first: "LV {}" must not swallow "LV {} · {}".
	table.sort(patterns, function(a, b)
		return a.Weight > b.Weight
	end)

	local cache: { [string]: string } = {}
	local cacheSize = 0
	local missing: { [string]: boolean } = {}
	local translate: (string, number?, boolean?) -> string

	local function lookup(text: string, depth: number): string?
		local hit = exact[text]
		if hit ~= nil then
			return hit
		end
		-- Leading / trailing spaces and line breaks are kept around the translation.
		local head, body, tail = string.match(text, "^(%s*)(.-)(%s*)$")
		if body ~= text and body ~= nil and body ~= "" then
			local inner = exact[body]
			if inner ~= nil then
				return (head :: string) .. inner .. (tail :: string)
			end
		end
		-- Patterns are tried on the text without its outer spaces, which are put back after.
		local outerHead, inner, outerTail = "", text, ""
		if body ~= nil and body ~= "" and body ~= text then
			outerHead, inner, outerTail = head :: string, body :: string, tail :: string
		end
		for _, entry in patterns do
			local values = { string.match(inner, entry.Pattern) }
			local joined = false
			for _, value in values do
				-- A "{}" never swallows a separator: "6 slots -> 7 slots" is two parts, not "{} slots".
				if string.find(value, "·", 1, true) or string.find(value, " -> ", 1, true) then
					joined = true
					break
				end
			end
			if #values > 0 and not joined then
				for index, value in values do
					values[index] = translate(value, depth + 1)
				end
				return outerHead .. fill(entry.Translation, values) .. outerTail
			end
		end
		return nil
	end

	-- own = this text stands on its own (a whole label, a rich-text run, a line), not a value
	-- caught by a "{}": player names and numbers are never recorded as missing.
	translate = function(text: string, depth: number?, own: boolean?): string
		local level = depth or 0
		if text == "" or level > 4 or not string.find(text, "%a") then
			return text
		end
		local cached = cache[text]
		if cached ~= nil then
			return cached
		end
		local result = lookup(text, level)
		if result == nil and string.find(text, "<[%a/]") then
			-- Rich text: translate every run of text between the tags on its own.
			local parts: { string } = {}
			local position = 1
			while position <= #text do
				local first, last = string.find(text, "<[^>]*>", position)
				if first == nil then
					table.insert(parts, translate(string.sub(text, position), level + 1, own))
					break
				end
				if first > position then
					table.insert(parts, translate(string.sub(text, position, first - 1), level + 1, own))
				end
				table.insert(parts, string.sub(text, first, last))
				position = (last :: number) + 1
			end
			result = table.concat(parts)
		end
		if result == nil and string.find(text, "·", 1, true) then
			-- "Common  ·  HANDS  ·  12 K": every part between the dots on its own.
			result = string.gsub(text, "([^·]+)", function(part: string): string
				return translate(part, level + 1, own)
			end)
		end
		if result == nil and string.find(text, " -> ", 1, true) then
			-- "6 slots -> 7 slots": both sides of the arrow on their own.
			local sides = string.split(text, " -> ")
			for index, side in sides do
				sides[index] = translate(side, level + 1, own)
			end
			result = table.concat(sides, " -> ")
		end
		if result == nil and string.find(text, "\n", 1, true) then
			local lines = string.split(text, "\n")
			for index, line in lines do
				lines[index] = translate(line, level + 1, own)
			end
			result = table.concat(lines, "\n")
		end
		if result == nil then
			if record and own and string.find(text, "%a%a") then -- amounts like "12 K" need nothing
				missing[text] = true
			end
			result = text
		end
		if cacheSize >= MAX_CACHE then
			table.clear(cache)
			cacheSize = 0
		end
		cache[text] = result
		cacheSize += 1
		return result :: string
	end

	return {
		Translate = function(text: string): string
			return translate(text, 0, true)
		end,
		Missing = missing,
		Code = code,
	}
end

-- The language file for a code, or nil for English / an unknown code.
function Localization.Load(code: string): { [string]: string }?
	local folder = script:FindFirstChild("Languages")
	local module = if folder ~= nil and code ~= "en" then folder:FindFirstChild(code) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, entries = pcall(require, module)
	if not ok or type(entries) ~= "table" then
		warn(`[Localization] could not load {code}: {tostring(entries)}`)
		return nil
	end
	return entries :: any
end

return Localization
