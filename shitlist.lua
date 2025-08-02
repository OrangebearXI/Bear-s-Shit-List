_addon.name = "Bear's Shit List"
_addon.author = "Orangebear"
_addon.version = "2.0"
_addon.commands = {"shitlist", "sl", "shit", "playernotes", "pn"}

-- Name highlighting functionality inspired by Balloon's highlight addon

local texts = require("texts")
local os = require("os")
local chat = require("chat")

-- Paths
local data_path = windower.addon_path .. "data.lua"
local settings_path = windower.addon_path .. "settings.lua"
local shared_data_path = windower.windower_path .. "shitlist_shared.lua"

-- Settings
local settings = {
    pos = {x = 200, y = 200},
    bg = {red = 0, green = 0, blue = 0, alpha = 0},
    font = 'Arial',
    size = 10,
    color = {red = 255, green = 255, blue = 255, alpha = 255},
    header_color = {red = 120, green = 180, blue = 255, alpha = 255},
    party_overlay_pos = {x = 500, y = 200},
    target_overlay_pos = {x = 100, y = 300},
    colors = {
        positive = {red = 120, green = 255, blue = 120},
        negative = {red = 255, green = 120, blue = 120},
        neutral = {red = 200, green = 200, blue = 200}
    },
    max_display = 20,
    case_sensitive = false,
    party_notes_enabled = true,
    target_lookup_enabled = true,
    target_bg = {red = 0, green = 0, blue = 0, alpha = 127},
    auto_highlight = true,
    addon_enabled = true
}

-- Data
local notes = {}
local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

-- State
local main_overlay, party_overlay, target_overlay
local last_message = "Use //sl help for commands"
local last_player, last_note, last_time, last_category = "", "", "", "neutral"
local current_target = ""

-- Chat colors by category
local chat_colors = {
    positive = 158,
    negative = 167,
    neutral = 0,
    system = 0
}

-- Keywords for auto-categorization
local keywords = {
    positive = {"good", "great", "awesome", "helpful", "friendly", "excellent", "reliable", "skilled", "nice", "trust", "cool"},
    negative = {"bad", "rude", "ninja", "drama", "avoid", "terrible", "awful", "toxic", "grief", "asshole", "dick", "shit", "scammer", "troll", "warning", "watch", "suspicious", "gil seller", "rmt", "bot", "questionable", "careful", "sketchy"}
}

-- Name highlight colors for chat (using highlight addon color scheme)
local highlight_colors = {
    positive = 204,
    negative = 167,
    neutral = 1,
}

-- Color conversion function (taken from Balloon's highlight addon)
function colconv(str_or_num)
    local strnum = tonumber(str_or_num)
    if strnum >= 256 and strnum < 509 then
        return string.char(0x1E, strnum - 254)
    elseif strnum > 0 then
        return string.char(0x1F, strnum)
    end
    return chat.controls.reset
end

-- Utility functions
function normalize_name(name)
    if not name then return "" end
    local normalized = tostring(name):gsub("^%s*(.-)%s*$", "%1"):gsub("\"", "")
    return settings.case_sensitive and normalized or normalized:lower()
end

function capitalize_name(name)
    if not name or name == "" then return name end
    return name:sub(1,1):upper() .. name:sub(2):lower()
end

function create_timestamp()
    local date = os.date("*t")
    return string.format("%s-%02d", months[date.month], date.year % 100)
end

function categorize_note(note)
    if not note then return "neutral" end
    local lower_note = note:lower()
    
    for category, word_list in pairs(keywords) do
        for _, keyword in ipairs(word_list) do
            if lower_note:find(keyword, 1, true) then
                return category
            end
        end
    end
    return "neutral"
end

function get_color(category)
    return settings.colors[category] or settings.colors.neutral
end

function get_chat_color(category)
    return chat_colors[category] or chat_colors.neutral
end

function truncate(text, max_len)
    return string.len(text) <= max_len and text or (string.sub(text, 1, max_len - 3) .. "...")
end

function get_latest_note(player_notes)
    if not player_notes or not player_notes.notes or #player_notes.notes == 0 then
        return nil
    end
    return player_notes.notes[#player_notes.notes]
end

function get_player_category(player_notes)
    local latest = get_latest_note(player_notes)
    return latest and latest.category or "neutral"
end

function pad(text, length, align)
    local padding = length - string.len(text)
    if padding <= 0 then return text end
    
    if align == "center" then
        local left = math.floor(padding / 2)
        return string.rep(" ", left) .. text .. string.rep(" ", padding - left)
    elseif align == "right" then
        return string.rep(" ", padding) .. text
    else
        return text .. string.rep(" ", padding)
    end
end

function get_category_counts()
    local counts = {positive = 0, negative = 0, neutral = 0}
    for name, player_data in pairs(notes) do
        if player_data and player_data.notes and #player_data.notes > 0 then
            local category = get_player_category(player_data)
            if category and counts[category] then
                counts[category] = counts[category] + 1
            else
                counts.neutral = counts.neutral + 1
            end
        end
    end
    return counts
end

-- Data management
function load_settings()
    if windower.file_exists(settings_path) then
        local ok, file = pcall(loadfile, settings_path)
        if ok and type(file) == "function" then
            local status, user_settings = pcall(file)
            if status and type(user_settings) == "table" then
                for k, v in pairs(user_settings) do
                    if type(settings[k]) == "table" and type(v) == "table" then
                        for kk, vv in pairs(v) do
                            settings[k][kk] = vv
                        end
                    else
                        settings[k] = v
                    end
                end
            end
        end
    end
end

function save_settings()
    local success = pcall(function()
        local file = io.open(settings_path, "w")
        if not file then return false end
        
        local main_x, main_y = 200, 200
        if main_overlay then
            local x, y = main_overlay:pos()
            if x and y then main_x, main_y = math.floor(x), math.floor(y) end
        end
        
        local party_x, party_y = 500, 200
        if party_overlay then
            local x, y = party_overlay:pos()
            if x and y then party_x, party_y = math.floor(x), math.floor(y) end
        end
        
        local target_x, target_y = 100, 300
        if target_overlay then
            local x, y = target_overlay:pos()
            if x and y then target_x, target_y = math.floor(x), math.floor(y) end
        end
        
        file:write("return {\n")
        file:write("    pos = {x = " .. main_x .. ", y = " .. main_y .. "},\n")
        file:write("    party_overlay_pos = {x = " .. party_x .. ", y = " .. party_y .. "},\n")
        file:write("    target_overlay_pos = {x = " .. target_x .. ", y = " .. target_y .. "},\n")
        file:write("    party_notes_enabled = " .. tostring(settings.party_notes_enabled) .. ",\n")
        file:write("    target_lookup_enabled = " .. tostring(settings.target_lookup_enabled) .. ",\n")
        file:write("    auto_highlight = " .. tostring(settings.auto_highlight) .. ",\n")
        file:write("    addon_enabled = " .. tostring(settings.addon_enabled) .. ",\n")
        file:write("    target_bg = {red = 0, green = 0, blue = 0, alpha = 127}\n")
        file:write("}\n")
        file:close()
        
        settings.pos.x, settings.pos.y = main_x, main_y
        settings.party_overlay_pos.x, settings.party_overlay_pos.y = party_x, party_y
        settings.target_overlay_pos.x, settings.target_overlay_pos.y = target_x, target_y
        
        return true
    end)
    return success
end

function load_notes()
    -- Clear existing notes first to ensure clean reload
    notes = {}
    
    -- First try to load from shared location
    local shared_path = shared_data_path
    if not windower.file_exists(shared_path) then
        -- Fall back to local file for backwards compatibility
        shared_path = data_path
    end
    
    if not windower.file_exists(shared_path) then return end
    
    local ok, file = pcall(loadfile, shared_path)
    if not ok or type(file) ~= "function" then return end
    
    local status, data = pcall(file)
    if not status or type(data) ~= "table" then return end
    
    for name, info in pairs(data) do
        local norm_name = normalize_name(name)
        if norm_name ~= "" and type(info) == "table" then
            if info.note and type(info.note) == "string" then
                local timestamp = info.timestamp or create_timestamp()
                local category = info.category or categorize_note(info.note)
                notes[norm_name] = {
                    notes = {{
                        note = info.note,
                        timestamp = timestamp,
                        category = category
                    }}
                }
            elseif info.notes and type(info.notes) == "table" then
                notes[norm_name] = info
            end
        end
    end
end

function save_notes()
    -- Save to shared location so all instances can access
    local file = io.open(shared_data_path, "w")
    if not file then return false end
    
    file:write("return {\n")
    for name, player_data in pairs(notes) do
        if type(player_data) == "table" and player_data.notes and #player_data.notes > 0 then
            file:write(string.format("    [\"%s\"] = {\n", name))
            file:write("        notes = {\n")
            for _, note_entry in ipairs(player_data.notes) do
                if type(note_entry) == "table" and type(note_entry.note) == "string" then
                    local category = note_entry.category or "neutral"
                    local timestamp = note_entry.timestamp or create_timestamp()
                    file:write(string.format("            {note = %q, timestamp = \"%s\", category = \"%s\"},\n", 
                        note_entry.note, timestamp, category))
                end
            end
            file:write("        }\n")
            file:write("    },\n")
        end
    end
    file:write("}\n")
    file:close()
    
    -- Notify other instances that database was updated
    notify_other_instances("database_updated")
    
    return true
end

-- Notify other instances of changes
function notify_other_instances(message)
    pcall(function()
        windower.send_ipc_message(message)
    end)
end

-- Handle sync messages from other instances
windower.register_event('ipc message', function(message)
    if message == "database_updated" then
        -- Another instance updated the database, reload it
        load_notes()
        update_party_overlay()
        update_target_overlay()
        windower.add_to_chat(chat_colors.system, "[BSL] Database synced from another instance")
    end
end)

-- Display functions
function update_main_overlay()
    local hc = settings.header_color
    local counts = get_category_counts()
    
    local display = string.format("\\cs(%d,%d,%d)╔══════════════════════════════════════════════════════════════╗\\cr\n", hc.red, hc.green, hc.blue)
    display = display .. string.format("\\cs(%d,%d,%d)║%s║\\cr\n", hc.red, hc.green, hc.blue, pad("Bear's Shit List v2.0", 62, "center"))
    display = display .. string.format("\\cs(%d,%d,%d)╠══════════════════════════════════════════════════════════════╣\\cr\n", hc.red, hc.green, hc.blue)
    
    if last_player ~= "" then
        local cc = get_color(last_category)
        display = display .. string.format("\\cs(%d,%d,%d)║ %-18s │ %-10s │ %8s ║\\cr\n", 
            cc.red, cc.green, cc.blue, 
            "Player: " .. truncate(last_player, 12), 
            "Cat: " .. last_category, 
            last_time)
        display = display .. string.format("\\cs(255,255,255)║ %-58s ║\\cr\n", "Note: " .. truncate(last_note, 52))
        display = display .. string.format("\\cs(%d,%d,%d)╠══════════════════════════════════════════════════════════════╣\\cr\n", hc.red, hc.green, hc.blue)
    end
    
    display = display .. string.format("\\cs(120,255,120)║ Good: %-3d \\cs(255,120,120)│ Bad: %-3d \\cs(%d,%d,%d)│ Total: %-3d ║\\cr\n", 
        counts.positive, counts.negative, hc.red, hc.green, hc.blue, counts.positive + counts.negative + counts.neutral)
    display = display .. string.format("\\cs(180,180,180)║ %-60s ║\\cr\n", truncate(last_message, 60))
    display = display .. string.format("\\cs(%d,%d,%d)╚══════════════════════════════════════════════════════════════╝\\cr", hc.red, hc.green, hc.blue)
    main_overlay:text(display)
end

function update_party_overlay()
    if not settings.party_notes_enabled or not settings.addon_enabled then
        party_overlay:visible(false)
        return
    end
    
    local party = windower.ffxi.get_party()
    local party_members = {}
    
    for i = 0, 17 do
        local member = party['p' .. i]
        if member and member.name then
            local norm_name = normalize_name(member.name)
            if notes[norm_name] then
                table.insert(party_members, {
                    name = member.name,
                    data = notes[norm_name],
                    category = get_player_category(notes[norm_name]),
                    is_party = i <= 5
                })
            end
        end
    end
    
    if #party_members == 0 then
        party_overlay:visible(false)
        return
    end
    
    local white = {red = 255, green = 255, blue = 255}
    
    local text = string.format("\\cs(%d,%d,%d)Shit List\\cr\n", white.red, white.green, white.blue)
    text = text .. string.format("\\cs(%d,%d,%d)%s\\cr\n", white.red, white.green, white.blue, string.rep("─", 9))
    
    for _, member in ipairs(party_members) do
        local color = get_color(member.category)
        local prefix = member.is_party and "" or "A:"
        text = text .. string.format("\\cs(%d,%d,%d)%s%s\\cr\n",
            color.red, color.green, color.blue, 
            prefix, capitalize_name(member.name))
    end
    
    party_overlay:text(text)
    party_overlay:visible(true)
end

function update_target_overlay()
    if not settings.target_lookup_enabled or not settings.addon_enabled then
        target_overlay:visible(false)
        return
    end
    
    local target = windower.ffxi.get_mob_by_target('t')
    local new_target = ""
    
    if target and target.name then
        new_target = target.name
    end
    
    if new_target == current_target then
        return
    end
    
    current_target = new_target
    target_overlay:visible(false)
    
    if new_target ~= "" then
        local norm_name = normalize_name(new_target)
        if notes[norm_name] then
            local player_data = notes[norm_name]
            local category = get_player_category(player_data)
            local color = get_color(category)
            local latest = get_latest_note(player_data)
            local note_preview = latest and truncate(latest.note, 30) or ""
            local text = string.format("\\cs(%d,%d,%d)%s\\cr\n\\cs(200,200,200)%s\\cr", 
                color.red, color.green, color.blue, capitalize_name(new_target), note_preview)
            target_overlay:text(text)
            target_overlay:visible(true)
        end
    end
end

function create_overlays()
    main_overlay = texts.new('', {
        pos = {x = settings.pos.x, y = settings.pos.y},
        bg = settings.bg,
        font = settings.font,
        size = settings.size,
        color = settings.color
    })
    main_overlay:visible(false)

    party_overlay = texts.new('', {
        pos = {x = settings.party_overlay_pos.x, y = settings.party_overlay_pos.y},
        bg = settings.bg,
        font = 'Arial',
        size = 10,
        color = settings.color
    })
    party_overlay:font('Arial')
    party_overlay:size(10)
    party_overlay:visible(false)

    target_overlay = texts.new('', {
        pos = {x = settings.target_overlay_pos.x, y = settings.target_overlay_pos.y},
        bg = settings.target_bg,
        font = settings.font,
        size = settings.size,
        color = settings.color
    })
    target_overlay:visible(false)
    
    windower.add_to_chat(chat_colors.system, "[BSL] Bear's Shit List v2.0 loaded successfully")
    
    if settings.addon_enabled then
        update_party_overlay()
        update_target_overlay()
    end
end

-- Search with wildcards
function search_players(term)
    local matches = {}
    local norm_term = normalize_name(term)
    
    local starts_with = norm_term:match("^(.-)%*$")
    local ends_with = norm_term:match("^%*(.-)$")
    local contains = norm_term:gsub("%*", "")
    
    for name, player_data in pairs(notes) do
        local match = false
        
        if starts_with then
            match = name:sub(1, #starts_with) == starts_with
        elseif ends_with then
            match = name:sub(-#ends_with) == ends_with
        elseif norm_term:find("%*") then
            match = name:find(contains, 1, true)
        else
            if name == norm_term then
                match = true
            else
                match = name:find(norm_term, 1, true)
            end
        end
        
        if match then
            table.insert(matches, {name = name, data = player_data})
        end
    end
    
    return matches
end

-- Commands
function cmd_add(args)
    if not args[1] or not args[2] then
        windower.add_to_chat(chat_colors.system, '[BSL] Usage: add "playername" "note"')
        return
    end
    
    local name = normalize_name(args[1])
    local display_name = capitalize_name(name)
    local note = table.concat(args, " ", 2):gsub("\"", "")
    local timestamp = create_timestamp()
    local category = categorize_note(note)
    
    if not notes[name] then
        notes[name] = {notes = {}}
    end
    
    table.insert(notes[name].notes, {
        note = note,
        timestamp = timestamp,
        category = category
    })
    
    save_notes()
    
    last_message = "Added note for " .. display_name .. " (Total: " .. #notes[name].notes .. ")"
    last_player, last_note, last_time, last_category = display_name, note, timestamp, category
    
    windower.add_to_chat(get_chat_color(category), string.format('[BSL] Added note for %s: %s (%s)', display_name, note, category))
    update_main_overlay()
end

function cmd_search(args)
    if not args[1] then
        windower.add_to_chat(chat_colors.system, '[BSL] Usage: search "name" (supports wildcards: *, name*, *name)')
        return
    end
    
    local search_term = args[1]
    local matches = search_players(search_term)
    
    if #matches == 1 then
        local match = matches[1]
        local player_data = match.data
        local display_name = capitalize_name(match.name)
        local latest = get_latest_note(player_data)
        local category = get_player_category(player_data)
        
        last_message = "Found: " .. display_name .. " (" .. #player_data.notes .. " notes)"
        last_player = display_name
        last_note = latest and latest.note or ""
        last_time = latest and latest.timestamp or "unknown"
        last_category = category
        
        windower.add_to_chat(get_chat_color(category), string.format('[BSL] %s (%d notes):', display_name, #player_data.notes))
        
        for i, note_entry in ipairs(player_data.notes) do
            windower.add_to_chat(get_chat_color(note_entry.category), 
                string.format('[BSL] %d. %s (%s)', i, note_entry.note, note_entry.category))
        end
        
        update_main_overlay()
    elseif #matches > 1 then
        windower.add_to_chat(chat_colors.system, string.format('[BSL] Found %d matches:', #matches))
        for i, match in ipairs(matches) do
            if i > 15 then
                windower.add_to_chat(chat_colors.system, string.format('[BSL] ... and %d more', #matches - 15))
                break
            end
            local display_name = capitalize_name(match.name)
            local category = get_player_category(match.data)
            local note_count = #match.data.notes
            windower.add_to_chat(get_chat_color(category), string.format('[BSL] %s (%s, %d notes)', display_name, category, note_count))
        end
        last_message = #matches .. " matches found"
        update_main_overlay()
    else
        windower.add_to_chat(chat_colors.system, '[BSL] No matches found')
        last_message = "No matches found"
        update_main_overlay()
    end
end

function cmd_remove(args)
    if not args[1] then
        windower.add_to_chat(chat_colors.system, '[BSL] Usage: remove "playername"')
        return
    end
    
    local name = normalize_name(args[1])
    local display_name = capitalize_name(name)
    
    if notes[name] then
        local category = get_player_category(notes[name])
        notes[name] = nil
        save_notes()
        last_message = "Removed all notes for " .. display_name
        windower.add_to_chat(get_chat_color(category), '[BSL] Removed all notes for ' .. display_name)
        last_player, last_note, last_time, last_category = "", "", "", "neutral"
    else
        last_message = "No notes found for " .. display_name
        windower.add_to_chat(chat_colors.system, '[BSL] No notes found for ' .. display_name)
    end
    
    update_main_overlay()
end

function cmd_stats(args)
    local counts = get_category_counts()
    local total = counts.positive + counts.negative + counts.neutral
    
    windower.add_to_chat(chat_colors.system, "[BSL] Bear's Shit List Statistics:")
    windower.add_to_chat(get_chat_color("positive"), string.format("[BSL] Good Players: %d", counts.positive))
    windower.add_to_chat(get_chat_color("negative"), string.format("[BSL] Bad Players: %d", counts.negative))
    windower.add_to_chat(chat_colors.neutral, string.format("[BSL] Neutral Players: %d", counts.neutral))
    windower.add_to_chat(chat_colors.system, string.format("[BSL] Total Players: %d", total))
end

function cmd_list(args)
    local category = args[1] and args[1]:lower()
    if not category or not (category == "positive" or category == "negative" or category == "good" or category == "bad") then
        windower.add_to_chat(chat_colors.system, '[BSL] Usage: list <good|bad>')
        return
    end
    
    if category == "good" then category = "positive" end
    if category == "bad" then category = "negative" end
    
    local matches = {}
    for name, player_data in pairs(notes) do
        if get_player_category(player_data) == category then
            table.insert(matches, {name = name, data = player_data})
        end
    end
    
    if #matches == 0 then
        windower.add_to_chat(chat_colors.system, string.format('[BSL] No %s players found', category))
        return
    end
    
    windower.add_to_chat(get_chat_color(category), string.format('[BSL] %s Players (%d):', category:gsub("^%l", string.upper), #matches))
    for i, match in ipairs(matches) do
        if i > 20 then
            windower.add_to_chat(chat_colors.system, string.format('[BSL] ... and %d more (use search for specific names)', #matches - 20))
            break
        end
        local display_name = capitalize_name(match.name)
        local latest = get_latest_note(match.data)
        local note_preview = latest and truncate(latest.note, 40) or ""
        windower.add_to_chat(get_chat_color(category), string.format('[BSL] %s: %s', display_name, note_preview))
    end
end

function cmd_on()
    settings.addon_enabled = true
    settings.party_notes_enabled = true
    settings.target_lookup_enabled = true
    settings.auto_highlight = true
    update_party_overlay()
    update_target_overlay()
    windower.add_to_chat(chat_colors.system, "[BSL] Addon enabled (party, target, and highlighting on)")
end

function cmd_off()
    settings.addon_enabled = false
    settings.party_notes_enabled = false
    settings.target_lookup_enabled = false
    settings.auto_highlight = false
    party_overlay:visible(false)
    target_overlay:visible(false)
    windower.add_to_chat(chat_colors.system, "[BSL] Addon disabled (party, target, and highlighting off)")
end

function cmd_party(args)
    local mode = args and args[1] and args[1]:lower()
    if mode == "on" then
        settings.party_notes_enabled = true
        update_party_overlay()
        windower.add_to_chat(chat_colors.system, "[BSL] Party notes: enabled")
    elseif mode == "off" then
        settings.party_notes_enabled = false
        party_overlay:visible(false)
        windower.add_to_chat(chat_colors.system, "[BSL] Party notes: disabled")
    else
        windower.add_to_chat(chat_colors.system, "[BSL] Usage: party on|off")
    end
end

function cmd_target(args)
    local mode = args and args[1] and args[1]:lower()
    if mode == "on" then
        settings.target_lookup_enabled = true
        windower.add_to_chat(chat_colors.system, "[BSL] Target lookup: enabled")
    elseif mode == "off" then
        settings.target_lookup_enabled = false
        target_overlay:visible(false)
        windower.add_to_chat(chat_colors.system, "[BSL] Target lookup: disabled")
    else
        windower.add_to_chat(chat_colors.system, "[BSL] Usage: target on|off")
    end
end

function cmd_highlight(args)
    local mode = args and args[1] and args[1]:lower()
    if mode == "on" then
        settings.auto_highlight = true
        windower.add_to_chat(chat_colors.system, "[BSL] Name highlighting: enabled")
    elseif mode == "off" then
        settings.auto_highlight = false
        windower.add_to_chat(chat_colors.system, "[BSL] Name highlighting: disabled")
    else
        windower.add_to_chat(chat_colors.system, "[BSL] Usage: highlight on|off")
    end
end

function cmd_savepos()
    local success = save_settings()
    if success then
        windower.add_to_chat(chat_colors.system, "[BSL] Positions saved!")
    else
        windower.add_to_chat(chat_colors.system, "[BSL] Save failed!")
    end
end

function cmd_help()
    windower.add_to_chat(chat_colors.system, "[BSL] Bear's Shit List v2.0 Commands:")
    windower.add_to_chat(chat_colors.system, "Commands work with: //sl, //pn, //shit")
    windower.add_to_chat(chat_colors.system, "")
    windower.add_to_chat(chat_colors.system, "add \"name\" \"note\"      - Add note to player")
    windower.add_to_chat(chat_colors.system, "search \"name\"            - Find player (wildcards: *, name*, *name)")
    windower.add_to_chat(chat_colors.system, "list <good|bad>           - List players by category")
    windower.add_to_chat(chat_colors.system, "remove \"name\"            - Delete all notes for player")
    windower.add_to_chat(chat_colors.system, "stats                     - Show statistics")
    windower.add_to_chat(chat_colors.system, "sync                      - Manual sync with other instances")
    windower.add_to_chat(chat_colors.system, "on                        - Enable addon (party + target on)")
    windower.add_to_chat(chat_colors.system, "off                       - Disable addon (party + target off)")
    windower.add_to_chat(chat_colors.system, "party on/off              - Toggle party notes overlay")
    windower.add_to_chat(chat_colors.system, "target on/off             - Toggle target lookup")
    windower.add_to_chat(chat_colors.system, "highlight on/off          - Toggle name highlighting")
    windower.add_to_chat(chat_colors.system, "savepos                   - Save overlay positions")
    windower.add_to_chat(chat_colors.system, "help                      - Show this help")
    windower.add_to_chat(chat_colors.system, "")
    windower.add_to_chat(chat_colors.system, "Categories: positive(good), negative(bad)")
    windower.add_to_chat(chat_colors.system, "Name highlighting: positive=green, negative=red")
    windower.add_to_chat(chat_colors.system, "Database syncs automatically across all instances!")
end

-- Manual sync command
function cmd_sync()
    load_notes()
    update_party_overlay()
    update_target_overlay()
    windower.add_to_chat(chat_colors.system, "[BSL] Manually synced database from shared file")
end

-- Command routing
local commands = {
    add = cmd_add,
    search = cmd_search,
    find = cmd_search,
    list = cmd_list,
    remove = cmd_remove,
    delete = cmd_remove,
    stats = cmd_stats,
    sync = cmd_sync,
    on = cmd_on,
    off = cmd_off,
    party = cmd_party,
    target = cmd_target,
    highlight = cmd_highlight,
    savepos = cmd_savepos,
    help = cmd_help
}

-- Event handlers
windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = (cmd or ""):lower()
    
    if commands[cmd] then
        commands[cmd](args)
    else
        windower.add_to_chat(chat_colors.system, '[BSL] Unknown command: ' .. tostring(cmd) .. '. Use help')
    end
end)

-- Name highlighting functionality (inspired by Balloon's highlight addon)
windower.register_event('incoming text', function(original, modified, original_mode, modified_mode, blocked)
    -- Exit immediately if highlighting is disabled
    if blocked or not settings.auto_highlight then
        return modified
    end
    
    local new_text = modified
    
    for name, player_data in pairs(notes) do
        if player_data and player_data.notes and #player_data.notes > 0 then
            local category = get_player_category(player_data)
            local display_name = capitalize_name(name)
            
            if category ~= "neutral" then
                local color_code = highlight_colors[category] or highlight_colors.neutral
                local color_start = colconv(color_code)
                local colored_name = color_start .. display_name .. chat.controls.reset
                
                local escaped_name = display_name:gsub("([^%w])", "%%%1")
                
                new_text = new_text:gsub("(%d+)(" .. escaped_name .. ")", function(server_id, matched_name)
                    return server_id .. colored_name
                end)
                
                new_text = new_text:gsub("(%W)(" .. escaped_name .. ")(%W)", function(before, matched_name, after)
                    return before .. colored_name .. after
                end)
                
                new_text = new_text:gsub("^(" .. escaped_name .. ")(%W)", function(matched_name, after)
                    return colored_name .. after
                end)
                
                new_text = new_text:gsub("(%W)(" .. escaped_name .. ")$", function(before, matched_name)
                    return before .. colored_name
                end)
            end
        end
    end
    
    return new_text
end)

windower.register_event('prerender', function()
    if settings.addon_enabled then
        if settings.target_lookup_enabled then
            update_target_overlay()
        end
        if settings.party_notes_enabled then
            update_party_overlay()
        end
    end
end)

windower.register_event('zone change', function()
    if settings.addon_enabled and settings.party_notes_enabled then
        update_party_overlay()
    end
end)

windower.register_event('unload', function()
    pcall(save_settings)
end)

-- Initialize
load_settings()
load_notes()
create_overlays()

if settings.addon_enabled then
    update_party_overlay()
    update_target_overlay()
end