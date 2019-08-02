dofile("table_show.lua")
dofile("urlcode.lua")

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

read_file = function(file)
    if file then
        local f = assert(io.open(file))
        local data = f:read("*all")
        f:close()
        return data
    end
    return ""
end

allowed = function(url, parenturl)
    if string.match(url, "https://instaudio.s3.amazonaws.com/")
        or string.match(url, "https://instaud.io/_/") then
        return true
    end
    return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
    local url = urlpos["url"]["url"]
    local html = urlpos["link_expect_html"]
    if (downloaded[url] ~= true and addedtolist[url] ~= true)
        and allowed(url, parent["url"]) then
        addedtolist[url] = true
        return true
    end
    return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
    downloaded[string.gsub(url, "https?://", "http://")] = true
    downloaded[string.gsub(url, "https?://", "https://")] = true
    if (string.match(url, "^https?://instaud%.io/[0-9a-zA-Z]+$")) then
        local urls = {}
        local body = read_file(file)
        local function check(urla)
            local origurl = url
            local url = string.match(urla, "^([^#]+)")
            local url_ = string.gsub(url, "&amp;", "&")
            if (downloaded[url_] ~= true and addedtolist[url_] ~= true) then
                table.insert(urls, { url=url_ })
                addedtolist[url_] = true
                addedtolist[url] = true
            end
        end
        local audio_url = string.match(body, "data%-instaudio%-player%-file=\"([^\"]+)\"")
        if audio_url then
            check(audio_url)
        else
            io.stdout:write("No audio URL found.")
            abortgrab = true
        end
        local waveform_url = string.match(body, "data%-instaudio%-player%-spectrogram=\"([^\"]+)\"")
        if waveform_url then
            check(waveform_url)
        else
            io.stdout:write("No waveform URL found.")
            abortgrab = true
        end
        return urls
    end
    return {}
end

wget.callbacks.httploop_result = function(url, err, http_stat)
    if abortgrab == true then
        io.stdout:write("ABORTING...\n")
        return wget.actions.ABORT
    end
    status_code = http_stat["statcode"]

    url_count = url_count + 1
    io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
    io.stdout:flush()

    if (status_code >= 300 and status_code <= 399) then
        local newloc = string.match(http_stat["newloc"], "^([^#]+)")
        if string.match(newloc, "^//") then
            newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
        elseif string.match(newloc, "^/") then
            newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
        elseif not string.match(newloc, "^https?://") then
            newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
        end
        if downloaded[newloc] == true or addedtolist[newloc] == true then
            return wget.actions.EXIT
        end
    end
    if (status_code >= 200 and status_code <= 399) then
        downloaded[string.gsub(url["url"], "https?://", "http://")] = true
        downloaded[string.gsub(url["url"], "https?://", "https://")] = true
    end
    if status_code >= 500
    or (status_code >= 400 and status_code ~= 403 and status_code ~= 404)
    or status_code  == 0 then
        io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
        io.stdout:flush()
        local maxtries = 8
        if not allowed(url["url"], nil) then
            maxtries = 2
        end
        if tries > maxtries then
            io.stdout:write("\nI give up...\n")
            io.stdout:flush()
            tries = 0
            if allowed(url["url"], nil) then
                return wget.actions.ABORT
            else
                return wget.actions.EXIT
            end
        else
            local backoff = math.floor(math.pow(2, tries))
            os.execute("sleep " .. backoff)
            tries = tries + 1
            return wget.actions.CONTINUE
        end
    end
    tries = 0
    return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
    if abortgrab == true then
        return wget.exits.IO_FAIL
    end
    return exit_status
end

