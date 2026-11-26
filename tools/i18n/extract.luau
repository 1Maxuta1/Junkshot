--[[
	tools/i18n/extract: lists every piece of text in src that a player might see, as English
	source keys for src/shared/Localization.

	  lune run tools/i18n/extract            -> prints a report (new keys not translated yet)
	  lune run tools/i18n/extract -- --all   -> prints every key

	Keys: plain string literals as they are; `templates` with {expr} become "{}" (any text).
	A literal counts as visible text when it has a letter and looks like words (a space or a
	capital letter), and is not an id, path, asset, attribute or enum name. The filter is a
	heuristic: anything it lets through that is never shown simply stays untranslated.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local SKIP_DIRS = {
	["src/shared/Localization"] = true,
	["src/server/Packages"] = true,
	["src/server/Dev"] = true,
}
local SKIP_FILES = { ["ItemSounds.luau"] = true, ["Remotes.luau"] = true, ["Types.luau"] = true }

-- A literal on a line like these is code, not text for players.
local CODE_LINE = {
	"warn%(", "print%(", "error%(", "assert%(", "FindFirstChild", "WaitForChild", "GetAttribute",
	"SetAttribute", "Instance%.new", ":IsA%(", "GetService", "require%(", "%.Name ==?", "^%s*Name =",
	"FindFirstAncestor", "CollectionService", "HasTag", "AddTag", "GetTagged", "AttributeChanged",
	"PropertyChangedSignal", "GetEvent%(", "GetFunction%(", "SoundId", "Texture =", "Image =",
	"Font%.", "FontFace", "debug%.", "%.Tag ", "Kind ==", "Id ==", "== \"", "~= \"", "Category ==",
	"SoundGroup", "TweenInfo",
}

local function walk(dir: string, out: { string })
	if SKIP_DIRS[dir] then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, out)
		elseif name:match("%.luau$") and not name:match("DevTests") and not SKIP_FILES[name] then
			table.insert(out, path)
		end
	end
end

-- Returns { text, isTemplate, line } for every literal outside comments.
local function literals(source: string): { { any } }
	local found = {}
	local i, n, line = 1, #source, 1
	while i <= n do
		local c = source:sub(i, i)
		if c == "\n" then
			line += 1
			i += 1
		elseif source:sub(i, i + 1) == "--" then
			local long = source:match("^%-%-%[(=*)%[", i)
			if long ~= nil then
				local close = "]" .. long .. "]"
				local stop = source:find(close, i, true) or n
				for _ in source:sub(i, stop):gmatch("\n") do
					line += 1
				end
				i = stop + #close
			else
				local stop = source:find("\n", i, true) or n + 1
				i = stop
			end
		elseif c == "[" and source:match("^%[=*%[", i) then
			local eq = source:match("^%[(=*)%[", i)
			local close = "]" .. eq .. "]"
			local stop = source:find(close, i, true) or n
			for _ in source:sub(i, stop):gmatch("\n") do
				line += 1
			end
			i = stop + #close
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			local buf = {}
			local depth = 0
			while j <= n do
				local d = source:sub(j, j)
				if d == "\\" then
					local e = source:sub(j + 1, j + 1)
					table.insert(buf, if e == "n" then "\n" elseif e == "t" then "\t" else e)
					j += 2
				elseif c == "`" and d == "{" then
					depth = 1
					local k = j + 1
					while k <= n and depth > 0 do
						local x = source:sub(k, k)
						if x == "{" then
							depth += 1
						elseif x == "}" then
							depth -= 1
						end
						k += 1
					end
					table.insert(buf, "{}")
					j = k
				elseif d == c then
					break
				else
					if d == "\n" then
						line += 1
					end
					table.insert(buf, d)
					j += 1
				end
			end
			table.insert(found, { table.concat(buf), c == "`", line })
			i = j + 1
		else
			i += 1
		end
	end
	return found
end

local function visible(text: string): boolean
	if not text:match("%a") or #text < 2 then
		return false
	end
	if text:match("^rbxasset") or text:match("^https?:") or text:match("^%%") then
		return false
	end
	if text:match("^[%l%d_]+$") then -- ids, attribute names in lower/snake case
		return false
	end
	if text:match("^%u%l+%u") and not text:match("%s") then -- CamelCase names: PromptAnchor, GadgetMode
		return false
	end
	if text:match("^Enum%.") or text:match("^[%w_]+%.[%w_.]+$") then
		return false
	end
	if text:match("^[%w_]+:[%w_:.]+$") then -- Item:storage_box:1.8 and similar keys
		return false
	end
	if text:match("^#%x+$") or text:match("^%x%x%x%x%x%x$") then
		return false
	end
	if text:match("^[%a_][%w_]*$") then
		-- a single word: keep only words that look like UI (all caps or capitalized)
		return text:match("^%u") ~= nil and #text >= 2
	end
	return true
end

local files = {}
walk("src", files)
local keys: { [string]: string } = {}
local order = {}
for _, path in files do
	local source = fs.readFile(path):gsub("\r\n", "\n")
	local lines = source:split("\n")
	for _, entry in literals(source) do
		local text = entry[1]
		local lineText = lines[entry[3]] or ""
		local code = false
		for _, pattern in CODE_LINE do
			if lineText:find(pattern) then
				code = true
				break
			end
		end
		if code then
			continue
		end
		local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
		if visible(trimmed) and keys[text] == nil then
			keys[text] = `{path}:{entry[3]}`
			table.insert(order, text)
		end
	end
end

local known: { [string]: boolean } = {}
if fs.isFile("src/shared/Localization/Languages/ru.luau") then
	for key in fs.readFile("src/shared/Localization/Languages/ru.luau"):gmatch('%[%s*"(.-)"%s*%]%s*=') do
		known[key] = true
	end
end

local all = table.find(process.args, "--all") ~= nil
local count = 0
for _, text in order do
	if all or not known[text] then
		count += 1
		print(`{keys[text]}\t{text:gsub("\n", "\\n")}`)
	end
end
print(`-- {count} keys ({#order} total)`)
