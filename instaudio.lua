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
    else
        return ""
    end
end

allowed = function(url, parenturl)
    if string.match(url, "https://instaudio.s3.amazonaws.com/")
    or string.match(url, "https://instaud.io/_/") then
        return true
    else
        return false
    end
end

if not wget then
    wget = {
        callbacks = {}
    }
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
    local url = urlpos["url"]["url"]
    local html = urlpos["link_expect_html"]
    if (downloaded[url] ~= true and addedtolist[url] ~= true) and (allowed(url, parent["url"]) or (html == 0 and math.floor(math.random() * 100) == 0)) then
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
            if (downloaded[url_] ~= true and addedtolist[url_] ~= true) and allowed(url_, origurl) then
                table.insert(urls, { url=url_ })
                addedtolist[url_] = true
                addedtolist[url] = true
            end
        end
        local audio_url = string.match(body, "data%-instaudio%-player%-file=\"([^\"]+)\"")
        if audio_url then
            check(audio_url)
        end
        local waveform_url = string.match(body, "data%-instaudio%-player%-spectrogram=\"([^\"]+)\"")
        if waveform_url then
            check(waveform_url)
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

--
-- wget.callbacks.get_urls = function(file, url, is_css, iri)
--   local urls = {}
--   local html = nil
--
--   downloaded[url] = true
--
--   local function check(urla)
--     local origurl = url
--     local url = string.match(urla, "^([^#]+)")
--     local url_ = string.gsub(url, "&amp;", "&")
--     if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
--        and allowed(url_, origurl) then
--       table.insert(urls, { url=url_ })
--       addedtolist[url_] = true
--       addedtolist[url] = true
--     end
--   end
--
--   local function checknewurl(newurl)
--     if string.match(newurl, "^https?:////") then
--       check(string.gsub(newurl, ":////", "://"))
--     elseif string.match(newurl, "^https?://") then
--       check(newurl)
--     elseif string.match(newurl, "^https?:\\/\\?/") then
--       check(string.gsub(newurl, "\\", ""))
--     elseif string.match(newurl, "^\\/\\/") then
--       check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
--     elseif string.match(newurl, "^//") then
--       check(string.match(url, "^(https?:)")..newurl)
--     elseif string.match(newurl, "^\\/") then
--       check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
--     elseif string.match(newurl, "^/") then
--       check(string.match(url, "^(https?://[^/]+)")..newurl)
--     end
--   end
--
--   local function checknewshorturl(newurl)
--     if string.match(newurl, "^%?") then
--       check(string.match(url, "^(https?://[^%?]+)")..newurl)
--     elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
--        or string.match(newurl, "^[/\\]")
--        or string.match(newurl, "^[jJ]ava[sS]cript:")
--        or string.match(newurl, "^[mM]ail[tT]o:")
--        or string.match(newurl, "^vine:")
--        or string.match(newurl, "^android%-app:")
--        or string.match(newurl, "^ios%-app:")
--        or string.match(newurl, "^%${")) then
--       check(string.match(url, "^(https?://.+/)")..newurl)
--     end
--   end
--
--   if string.match(url, "^https?://www%.flickr%.com/photos/[^/]+/[0-9]+/$") then
--     users[string.match(url, "^https?://[^/]+/[^/]+/[^/]+/([0-9]+)/")] = true
--   end
--
--   if allowed(url, nil)
--       and not (string.match(url, "^https?://[^/]*staticflickr%.com/")
--                or string.match(url, "^https?://[^/]*cdn%.yimg%.com/")) then
--     html = read_file(file)
--     if string.match(html, "<h3>We're having some trouble displaying this photo at the moment%. Please try again%.</h3>") then
--       print("Flickr is having problems!")
--       abortgrab = true
--     end
--     if item_type == "disco" and string.match(url, "^https?://api%.flickr%.com/services/rest") then
--       local json = load_json_file(html)
--       if string.match(url, "&page=1&") then
--         for i=1,json["photos"]["pages"] do
--           check(string.gsub(url, "&page=[0-9]+", "&page=" .. tostring(i)))
--         end
--       end
--       for _, photo in pairs(json["photos"]["photo"]) do
--         discovered_photos[photo["id"]] = true
--       end
--       return urls
--     end
--     if string.match(html, '"sizes":{.-}}') then
--       local sizes = load_json_file(string.match(html, '"sizes":({.-}})'))
--       local largest = nil
--       if sizes["o"] then
--         largest = "o"
--       end
--       for size, data in pairs(sizes) do
--         if largest == nil then
--           largest = size
--         else
--           if data["width"] > sizes[largest]["width"] then
--             largest = size
--           end
--         end
--       end
--       checknewurl(sizes[largest]["displayUrl"])
--       checknewurl(sizes[largest]["url"])
--     end
--     for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
--       if not string.match(newurl, "^\\/\\/") then
--         checknewurl(newurl)
--       end
--     end
--     for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
--       checknewurl(newurl)
--     end
--     for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
--       checknewurl(newurl)
--     end
--     for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
--       checknewshorturl(newurl)
--     end
--     for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
--       checknewshorturl(newurl)
--     end
--     for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
--       checknewurl(newurl)
--     end
--   end
--
--   return urls
-- end

-- wget.callbacks.httploop_result = function(url, err, http_stat)
--   status_code = http_stat["statcode"]
--
--   url_count = url_count + 1
--   io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
--   io.stdout:flush()
--
--   if (status_code >= 300 and status_code <= 399) then
--     local newloc = string.match(http_stat["newloc"], "^([^#]+)")
--     if string.match(newloc, "^//") then
--       newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
--     elseif string.match(newloc, "^/") then
--       newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
--     elseif not string.match(newloc, "^https?://") then
--       newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
--     end
--     if downloaded[newloc] == true or addedtolist[newloc] == true then
--       return wget.actions.EXIT
--     end
--   end
--
--   if (status_code >= 200 and status_code <= 399) then
--     downloaded[url["url"]] = true
--     downloaded[string.gsub(url["url"], "https?://", "http://")] = true
--   end
--
--   if abortgrab == true then
--     io.stdout:write("ABORTING...\n")
--     return wget.actions.ABORT
--   end
--
--   if status_code >= 500
--       or (status_code >= 400 and status_code ~= 403 and status_code ~= 404)
--       or status_code  == 0 then
--     io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
--     io.stdout:flush()
--     local maxtries = 8
--     if not allowed(url["url"], nil) then
--         maxtries = 2
--     end
--     if tries > maxtries then
--       io.stdout:write("\nI give up...\n")
--       io.stdout:flush()
--       tries = 0
--       if allowed(url["url"], nil) then
--         return wget.actions.ABORT
--       else
--         return wget.actions.EXIT
--       end
--     else
--       os.execute("sleep " .. math.floor(math.pow(2, tries)))
--       tries = tries + 1
--       return wget.actions.CONTINUE
--     end
--   end
--
--   tries = 0
--
--   local sleep_time = 0
--
--   if sleep_time > 0.001 then
--     os.execute("sleep " .. sleep_time)
--   end
--
--   return wget.actions.NOTHING
-- end

-- wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
--   if item_type == "disco" then
--     local file = io.open(item_dir .. '/' .. warc_file_base .. '_data.txt', 'w')
--     for photo, _ in pairs(discovered_photos) do
--       file:write("photo:" .. item_value .. "/" .. photo .. "\n")
--     end
--     file:close()
--   end
-- end

-- wget.callbacks.before_exit = function(exit_status, exit_status_string)
--   if abortgrab == true then
--     return wget.exits.IO_FAIL
--   end
--   return exit_status
-- end
