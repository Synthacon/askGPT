local http = require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("json")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local GPT = {
    api_url = "https://openrouter.ai/api/v1/chat/completions",
    cache_file = DataStorage:getDataDir() .. "/gpt_cache.json",
    cache = {},
    cache_size_limit = 100  -- Maximum number of cached responses
}

function GPT:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    -- Ensure settings is initialized
    if o.settings then
        self.settings = o.settings
    else
        logger.warn("KoGPT: No settings provided to GPT module")
    end
    
    self:loadCache()
    return o
end

function GPT:loadCache()
    local f = io.open(self.cache_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local ok, data = pcall(JSON.decode, content)
        if ok and type(data) == "table" then
            self.cache = data
        else
            logger.warn("KoGPT: Failed to load cache, using empty cache")
            self.cache = {}
        end
    else
        self.cache = {}
    end
end

function GPT:saveCache()
    local f = io.open(self.cache_file, "w")
    if f then
        f:write(JSON.encode(self.cache))
        f:close()
    end
end

function GPT:getCacheKey(text, prompt)
    return text .. "||" .. prompt
end

function GPT:addToCache(key, response)
    -- Add new response to cache with timestamp
    self.cache[key] = {
        response = response.response,
        timestamp = response.timestamp or os.time()
    }
    
    -- Remove oldest entries if cache exceeds size limit
    local keys = {}
    for k, v in pairs(self.cache) do
        -- Validate cache entry has timestamp
        if type(v) == "table" and v.timestamp then
            table.insert(keys, k)
        else
            -- Fix invalid entries by adding timestamp
            self.cache[k] = {
                response = type(v) == "table" and v.response or v,
                timestamp = os.time()
            }
            table.insert(keys, k)
        end
    end
    
    if #keys > self.cache_size_limit then
        -- Sort by timestamp, with validation
        table.sort(keys, function(a, b)
            local a_time = self.cache[a].timestamp or 0
            local b_time = self.cache[b].timestamp or 0
            return a_time > b_time
        end)
        
        -- Remove excess entries
        for i = self.cache_size_limit + 1, #keys do
            self.cache[keys[i]] = nil
        end
    end
    
    self:saveCache()
end

function GPT:query_with_history(messages, callback)
    -- Validate settings
    if not self.settings then
        UIManager:show(InfoMessage:new{
            text = _("Error: Settings not initialized"),
            timeout = 2,
        })
        return
    end

    local api_key = self.settings:getApiKey()
    if not api_key or api_key == "" then
        logger.warn("KoGPT: No API key found")
        UIManager:show(InfoMessage:new{
            text = _("Please set your OpenRouter API key in settings"),
            timeout = 2,
        })
        return
    end
    
    local model = self.settings:getSelectedModel()
    if not model or model == "" then
        UIManager:show(InfoMessage:new{
            text = _("Please select a model in settings"),
            timeout = 2,
        })
        return
    end

    -- Create cache key from last message
    local cache_key = self:getCacheKey(messages[#messages].content, "history")
    
    -- Check cache first
    if self.cache[cache_key] then
        callback(self.cache[cache_key].response)
        return
    end
    
    -- Show loading message
    local loading = InfoMessage:new{
        text = _("Processing request..."),
        timeout = 0,
    }
    UIManager:show(loading)
    
    -- Prepare request
    local request_body = {
        model = model,
        messages = messages
    }
    
    local response_body = {}
    local request = {
        url = self.api_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key
        },
        source = ltn12.source.string(JSON.encode(request_body)),
        sink = ltn12.sink.table(response_body)
    }
    
    -- Make API request
    logger.info("KoGPT: Sending request to OpenRouter API with model: " .. model)
    local success, status_code = http.request(request)
    
    -- Hide loading message
    UIManager:close(loading)
    logger.info("KoGPT: Request completed with status code: " .. (status_code or "nil"))
    
    if not success then
        UIManager:show(InfoMessage:new{
            text = _("Network error: Could not connect to API"),
            timeout = 2,
        })
        return
    end
    
    local ok, response = pcall(function()
        local response_text = table.concat(response_body)
        logger.info("KoGPT: Raw API response: " .. response_text:sub(1, 100) .. "...")
        return JSON.decode(response_text)
    end)
    
    if not ok or not response then
        logger.error("KoGPT: Failed to parse API response:", ok, response)
        UIManager:show(InfoMessage:new{
            text = _("Error: Invalid response from API"),
            timeout = 2,
        })
        return
    end
    
    if status_code ~= 200 then
        local error_msg = "Unknown error"
        if type(response) == "table" then
            if response.error then
                if type(response.error) == "table" and response.error.message then
                    error_msg = response.error.message
                elseif type(response.error) == "string" then
                    error_msg = response.error
                end
            elseif response.message then
                error_msg = response.message
            end
        end
        logger.error("KoGPT: API error:", error_msg)
        UIManager:show(InfoMessage:new{
            text = _("API error") .. ": " .. error_msg,
            timeout = 2,
        })
        return
    end
    
    if not response.choices or not response.choices[1] or not response.choices[1].message then
        logger.error("KoGPT: Invalid response structure:", response)
        UIManager:show(InfoMessage:new{
            text = _("Error: Invalid response structure from API"),
            timeout = 2,
        })
        return
    end
    
    local response_content = response.choices[1].message.content
    logger.info("KoGPT: Successfully received response")
    
    -- Cache the response
    self:addToCache(cache_key, {
        response = response_content,
        timestamp = os.time()
    })
    
    callback(response_content)
end

function GPT:query(text, prompt, callback)
    local cache_key = self:getCacheKey(text, prompt)
    
    -- Check cache first
    if self.cache[cache_key] then
        callback(self.cache[cache_key].response)
        return
    end
    
    -- Prepare API request
    -- Validate settings
    if not self.settings then
        UIManager:show(InfoMessage:new{
            text = _("Error: Settings not initialized"),
            timeout = 2,
        })
        return
    end

    local api_key = self.settings:getApiKey()
    if not api_key or api_key == "" then
        logger.warn("KoGPT: No API key found")
        UIManager:show(InfoMessage:new{
            text = _("Please set your OpenRouter API key in settings"),
            timeout = 2,
        })
        return
    end
    
    -- Log that we have a valid API key (without showing the key itself)
    logger.dbg("KoGPT: Using API key (length: " .. #api_key .. ")")

    local model = self.settings:getSelectedModel()
    if not model or model == "" then
        UIManager:show(InfoMessage:new{
            text = _("Please select a model in settings"),
            timeout = 2,
        })
        return
    end

    local system_prompt = self.settings:getSystemPrompt()
    
    local request_body = {
        model = model,
        messages = {
            {
                role = "system",
                content = system_prompt
            },
            {
                role = "user",
                content = prompt .. "\n\nText: " .. text
            }
        }
    }
    
    -- Show loading message
    local loading = InfoMessage:new{
        text = _("Processing request..."),
        timeout = 0,  -- No timeout
    }
    UIManager:show(loading)
    
    -- Log request start
    logger.dbg("KoGPT: Sending request to API")
    
    local response_body = {}
    local request = {
        url = self.api_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key
        },
        source = ltn12.source.string(JSON.encode(request_body)),
        sink = ltn12.sink.table(response_body)
    }
    
    -- Make API request
    logger.info("KoGPT: Sending request to OpenRouter API with model: " .. model)
    local success, status_code = http.request(request)
    
    -- Hide loading message and log completion
    UIManager:close(loading)
    logger.info("KoGPT: Request completed with status code: " .. (status_code or "nil"))
    
    if not success then
        UIManager:close(loading)
        UIManager:show(InfoMessage:new{
            text = _("Network error: Could not connect to API"),
            timeout = 2,
        })
        return
    end
    
    local ok, response
    ok, response = pcall(function()
        local response_text = table.concat(response_body)
        logger.info("KoGPT: Raw API response: " .. response_text:sub(1, 100) .. "...")
        return JSON.decode(response_text)
    end)
    
    if not ok or not response then
        logger.error("KoGPT: Failed to parse API response:", ok, response)
        UIManager:show(InfoMessage:new{
            text = _("Error: Invalid response from API"),
            timeout = 2,
        })
        return
    end
    
    if status_code ~= 200 then
        local error_msg = "Unknown error"
        if type(response) == "table" then
            if response.error then
                if type(response.error) == "table" and response.error.message then
                    error_msg = response.error.message
                elseif type(response.error) == "string" then
                    error_msg = response.error
                end
            elseif response.message then
                error_msg = response.message
            end
        end
        logger.error("KoGPT: API error:", error_msg)
        UIManager:show(InfoMessage:new{
            text = _("API error") .. ": " .. error_msg,
            timeout = 2,
        })
        return
    end
    
    -- Extract response text with error handling
    if not response.choices or not response.choices[1] or not response.choices[1].message then
        logger.error("KoGPT: Invalid response structure:", response)
        UIManager:show(InfoMessage:new{
            text = _("Error: Invalid response structure from API"),
            timeout = 2,
        })
        return
    end
    
    local response_content = response.choices[1].message.content
    logger.info("KoGPT: Successfully received response")
    
    -- Cache the response
    self:addToCache(cache_key, {
        response = response_content,
        timestamp = os.time()
    })
    
    -- Return response via callback
    callback(response_content)
end

return GPT