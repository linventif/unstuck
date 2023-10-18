/*
This is a very simple script, to allow players to unstuck themselves if they get stuck in a wall or something.
All the configuration can be in game, and the script is very easy to use.

Created by: Linventif and Akinitawa with love <3
If you need help contact us on discord: https://linv.dev/discord
This script is under the CC BY-NC-SA 4.0 license.
*/

// Variables
local version = "0.1.0"
local config = {}
local lang = {}

// Config Genral
config.useDataConfig = true // use
config.language = "english" // see https://api.linv.dev/addons/unstuck/language/avaliable.json for all available language

// Config Api
config.getLangFromAPI = true // get more language from api
config.getWordFromAPI = true // get more word from api

// Config Unstuck
// command list
config.word = { 
    ["!unstuck"] = true,
    ["!stuck"] = true,
}
config.cooldown = 60 // in seconds
config.maxDistance = 96 // max distance form player
config.maxTry = 20 // max try to unstuck

// Language
lang.english = {
    ["unstuck"] = "You have been unstuck!",
    ["not_stuck"] = "You don't seem to be stuck. Maybe try again?",
    ["dead"] = "You are dead!", // should we also add a check for dead players?
    ["cooldown"] = "You have to wait %s seconds before using this command again!",
    ["fail"] = "We can't unstuck you, try again later or contact an admin!",
    ["no_perm"] = "You don't have the permission to use this command!",
    ["save_config"] = "Configuration saved, and send to all players!",
    ["show_possible_lang"] = "This are the list of all possible language.",
    ["show_config"] = "This are the current config of unstuck, to edit them do {1}",
    ["invalid_setting"] = "The setting you try to edit do not exist!",
    ["use_cmd_word"] = "To edit this setting use {1} or {2}"
}

//
// DO NOT EDIT BELOW THIS LINE
//

// Variables
config.version = version // don't touch this

// Get Trad func
local function getTrad(str, opt)
    if (!lang[config.language] || !lang[config.language][str]) then
        return str
    end
    str = lang[config.language][str]
    // if opt, remplace every {x} by opt[x]
    if (opt) then
        for k, v in pairs(opt) do
            str = string.Replace(str, "{" .. k .. "}", v)
        end
    end
    return str
end

// load language
local function loadLanguage()
    if (!config.getLangFromAPI) then return end
    http.Fetch("https://api.linv.dev/addons/unstuck/language/" .. config.language .. ".json", function(body, len, headers, code)
        local startCode = string.sub(code, 1, 1)
        if (startCode == "2") then
            lang[config.language] = util.JSONToTable(body)
        else
            print("[Unstuck] Can't get language from api, using default language.")
        end
    end)
end

// load word
local function loadWord()
    if (!config.getWordFromAPI) then return end
    http.Fetch("https://api.linv.dev/addons/unstuck/word.json", function(body, len, headers, code)
        local startCode = string.sub(code, 1, 1)
        if (startCode == "2") then
            config.word = util.JSONToTable(body)
        else
            print("[Unstuck] Can't get word from api, using default word.")
        end
    end)
end

if SERVER then
    // Verify data folder
    if (!file.IsDir("unstuck", "DATA")) then
        file.CreateDir("unstuck")
    end

    // Load config from data
    if (config.useDataConfig) then
        if (file.Exists("unstuck/config.json", "DATA")) then
            oldConfig = util.JSONToTable(file.Read("unstuck/config.json", "DATA"))
            if (config.version < version) then
                table.Merge(config, oldConfig) // merge old config with new config
                file.Write("unstuck/config.json", util.TableToJSON(config, true)) // save new config
            else
                config = oldConfig
            end
        else
            file.Write("unstuck/config.json", util.TableToJSON(config, true))
        end
    end

    // Functions
    local function isValidPlyPos(pos)
        // check if in the world with util.IsInWorld
        if !util.IsInWorld(pos) then
            return false
        end

        // made a box trace to check if the position is available
        local trace = util.TraceHull({
            start = pos + Vector(-16, -16, 0), -- start the trace from the bottom-front-left
            endpos = pos + Vector(16, 16, 72), -- end the trace at the top-back-right
        })

        // if the trace hit something, then the position is not available
        if trace.Hit then
            // identify the entity that was hit
            local ent = trace.Entity
            -- print("[unstuck] " .. ent:GetClass() .. " is blocking the spawn position.")
            return false
        end

        return pos
    end

    local function findValidPos(initPos, radius, maxChecks)
        // get info from the arguments
        local searchRadius = radius || 180
        local maxAttempts = maxChecks || 60

        // check if the spawn position is valid
        if isValidPlyPos(initPos) then
            return initPos
        end

        // try to find a valid position in a random direction
        for i = 1, maxAttempts do
            local genPos = initPos + Vector(math.random(-searchRadius, searchRadius), math.random(-searchRadius, searchRadius), math.random(-searchRadius, searchRadius) )
            local validPos = isValidPlyPos(genPos)
            if validPos then
                return validPos
            end
        end

        // if no valid position was found, return false
        return false
    end

    // Net
    util.AddNetworkString("Unstuck")

    /* Net from client
        1: Get config
        2: Unstuck
        3: Save Config
        4: add or remove word
    */

    local function sendNet(ply, id, func)
        net.Start("Unstuck")
        net.WriteUInt(id, 8)
        if func then func() end
        net.Send(ply)
    end

    local function sendMsg(ply, id, opt)
        sendNet(ply, 2, function()
            net.WriteString(getTrad(id, opt))
        end)
    end

    local function sendConfig(ply)
        sendNet(ply, 1, function()
            net.WriteString(util.TableToJSON(config))
        end)
    end

    local function saveConfig()
        // save config
        file.Write("unstuck/config.json", util.TableToJSON(config, true))
        // Send config to all player
        for _, ply in pairs(player.GetAll()) do
            sendConfig(ply)
        end
    end

    local netFunc = {
        [1] = function(ply)
            // send config
            sendConfig(ply)
        end,
        [2] = function(ply)
            // verify if valid player
            if (!IsValid(ply) || !ply:IsPlayer()) then return end
            // verify if the player is in fact stuck
            // verify if the player is on the ground as well to disallow fall damage/death prevention
            if !ply:GetPhysicsObject():IsPenetrating() and !ply:IsOnGround() then
                sendMsg(ply, "not_stuck")

                return 
            end
            // verify if cooldown
            if (ply.lastUnstuck && ply.lastUnstuck > CurTime()) then
                local rest = math.Round(ply.lastUnstuck - CurTime())
                sendMsg(ply, "cooldown", { rest })
                return
            end
            ply.lastUnstuck = CurTime() + config.cooldown
            // find a valid pos
            local pos = findValidPos(ply:GetPos(), config.maxDistance, config.maxTry)
            if (pos) then
                ply:SetPos(pos)
                sendMsg(ply, "unstuck")
            else
                sendMsg(ply, "fail")
            end
        end,
        [3] = function(ply)
            // verify perm
            if (!ply:IsSuperAdmin()) then
                sendMsg(ply, "no_perm")
                return
            end
            // get data
            local setting = net.ReadString()
            local value = net.ReadString()
            // verify data
            if !config[setting] then
                sendMsg(ply, "invalid_setting")
                return
            end
            // if word verify if value is not empty
            if (setting == "word") then
                sendMsg(ply, "use_cmd_word" , {"/unstuck_setting_word_add", "/unstuck_setting_word_remove"})
                return
            end
            // set data
            config[setting] = value
            // if language reload language
            if (setting == "language") then
                loadLanguage()
            end
            // save config
            saveConfig()
            sendMsg(ply, "save_config")
        end,
        [4] = function(ply)
            // verify perm
            if (!ply:IsSuperAdmin()) then
                sendMsg(ply, "no_perm")
                return
            end
            // get data
            local word = net.ReadString()
            local add = net.ReadBool()

            if (add) then
                config.word[word] = true
                sendMsg(ply, "add_word", {word})
            else
                config.word[word] = nil
                sendMsg(ply, "remove_word", {word})
            end
            // save config
            saveConfig()
        end
    }

    net.Receive("Unstuck", function(len, ply)
        local type = net.ReadUInt(8)
        if (netFunc[type]) then
            netFunc[type](ply)
        end
    end)

    // Other
    timer.Simple(0.1, function() // wait for all addons to load
        loadLanguage() // load language
        loadWord() // load word
    end)
else
    // Net
    hook.Add("InitPostEntity", "UnstuckInit", function()
        // Load config from server
        net.Start("Unstuck")
        net.WriteUInt(1, 8)
        net.SendToServer()
    end)

    /* Net from server
        1: Config
        2: Message
    */

    local function sendNet(id, func)
        net.Start("Unstuck")
        net.WriteUInt(id, 8)
        if func then func() end
        net.SendToServer()
    end

    local netFunc = {
        [1] = function()
            config = util.JSONToTable(net.ReadString())
            loadLanguage()
        end,
        [2] = function()
            local msg = net.ReadString()
            chat.AddText(Color(228, 188, 57), "[Unstuck] ", Color(255, 255, 255), msg)
        end
    }

    local function unstuckMe()
        sendNet(2)
    end

    net.Receive("Unstuck", function(len)
        local type = net.ReadUInt(8)
        if (netFunc[type]) then
            netFunc[type]()
        end
    end)

    // Chat
    hook.Add("OnPlayerChat", "UnstuckChat", function(ply, text)
        
        if (ply != LocalPlayer()) then return end
        // if player message is one of the commands on the config
        if !ultimate_unstuck.config.command[string.lower(text)] then return end
    
        unstuckMe()
        return true
    end)

    // Concommand
    concommand.Add("unstuck", unstuckMe)

    // Admin Concommand
    concommand.Add("unstuck_setting", function(ply, cmd, args)
        sendNet(3, function()
            net.WriteString(args[1])
            net.WriteString(args[2])
        end)
    end)

    concommand.Add("unstuck_setting_show", function()
        print(getTrad("show_config", { "/unstuck_setting the_setting the_value" }))
        PrintTable(config)
    end)

    concommand.Add("unstuck_possible_language", function()
        http.Fetch("https://api.linv.dev/addons/unstuck/language/available.json", function(body, len, headers, code)
            local startCode = string.sub(code, 1, 1)
            if (startCode == "2") then
                print(getTrad("show_possible_lang", { "/unstuck_setting language the_language" }))
                local data = util.JSONToTable(body)
                local keys = table.GetKeys(data)
                print(table.concat(keys, ", "))
            else
                print("[Unstuck] Error while fetching language list")
            end
        end)
    end)

    concommand.Add("unstuck_setting_word_add", function(cmd, args)
        sendNet(4, function()
            net.WriteString(args[1])
            net.WriteBool(true)
        end)
    end)

    concommand.Add("unstuck_setting_word_remove", function(cmd, args)
        sendNet(4, function()
            net.WriteString(args[1])
            net.WriteBool(false)
        end)
    end)
end

print("[Unstuck] Finished Loading, Version: " .. version)
