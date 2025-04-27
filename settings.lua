local Device = require("device")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local _ = require("gettext")

local Settings = InputContainer:extend{
    default_settings = {
        api_key = "",
        selected_model = "",
        system_prompt = "You are an AI assistant helping users better understand any text they select. ",
        models = {},
        task_prompts = {
            {
                name = "Explain",
                prompt = "Explain this text in simple terms"
            },
            {
                name = "Summarize",
                prompt = "Provide a concise summary of this text"
            },
            {
                name = "Translate",
                prompt = "Translate this text to English"
            }
        }
    }
}

function Settings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    -- Create deep copy of default settings
    self.data = {
        api_key = self.default_settings.api_key,
        selected_model = self.default_settings.selected_model,
        system_prompt = self.default_settings.system_prompt,
        models = {},
        task_prompts = {}
    }
    
    -- Deep copy default task prompts
    for _, task in ipairs(self.default_settings.task_prompts) do
        table.insert(self.data.task_prompts, {
            name = task.name,
            prompt = task.prompt
        })
    end
    
    -- Safely try to load saved settings
    if G_reader_settings then
        logger.dbg("KoGPT: Loading saved settings")
        local ok, settings = pcall(function()
            return G_reader_settings:readSetting("kogpt")
        end)
        if ok and settings then
            logger.dbg("KoGPT: Successfully loaded saved settings")
            -- Only merge non-default settings
            if settings.api_key and settings.api_key ~= "" then
                self.data.api_key = settings.api_key
            end
            if settings.selected_model and settings.selected_model ~= "" then
                self.data.selected_model = settings.selected_model
            end
            if settings.models then
                self.data.models = settings.models
            end
            if settings.task_prompts then
                -- Validate and merge saved task prompts
                for _, task in ipairs(settings.task_prompts) do
                    if task.name and task.prompt then
                        -- Find matching default task
                        for i, default_task in ipairs(self.data.task_prompts) do
                            if default_task.name == task.name then
                                -- Update prompt for existing task
                                self.data.task_prompts[i].prompt = task.prompt
                                break
                            end
                        end
                    end
                end
            end
            
            -- Always use the latest default system prompt
            self.data.system_prompt = self.default_settings.system_prompt
            
            -- Save merged settings back
            G_reader_settings:saveSetting("kogpt", self.data)
            logger.dbg("KoGPT: Saved merged settings with latest default prompt")
        else
            logger.warn("KoGPT: Failed to load saved settings, using defaults")
            -- Save defaults
            G_reader_settings:saveSetting("kogpt", self.data)
            logger.dbg("KoGPT: Saved default settings")
        end
    else
        logger.warn("KoGPT: G_reader_settings not available, using defaults")
    end
    
    function Settings:getTaskPrompts()
        return self.data.task_prompts
    end
    
    function Settings:getTaskPrompt(name)
        for _, task in ipairs(self.data.task_prompts) do
            if task.name == name then
                return task.prompt
            end
        end
        return nil
    end
    
    return o
end

function Settings:getApiKey()
    return self.data.api_key
end

function Settings:getSelectedModel()
    return self.data.selected_model
end

function Settings:getSystemPrompt()
    return self.data.system_prompt
end

function Settings:getModels()
    return self.data.models
end

function Settings:fetchModels()
    local response_body = {}
    local request = {
        url = "https://openrouter.ai/api/v1/models",
        method = "GET",
        sink = ltn12.sink.table(response_body)
    }
    
    local success, status_code = http.request(request)
    
    if not success then
        logger.warn("KoGPT: Failed to fetch models:", status_code)
        UIManager:show(InfoMessage:new{
            text = _("Failed to fetch models from OpenRouter"),
            timeout = 2,
        })
        return false
    end
    
    local response_text = table.concat(response_body)
    local ok, response = pcall(require("json").decode, response_text)
    
    if not ok then
        logger.warn("KoGPT: Failed to parse models response:", response)
        UIManager:show(InfoMessage:new{
            text = _("Failed to parse models response"),
            timeout = 2,
        })
        return false
    end
    
    if response and response.data then
        logger.info("KoGPT: Successfully fetched", #response.data, "models")
        self.data.models = response.data
        if G_reader_settings then
            G_reader_settings:saveSetting("kogpt", self.data)
        end
        return true
    end
    
    logger.warn("KoGPT: Invalid response format")
    UIManager:show(InfoMessage:new{
        text = _("Invalid response from OpenRouter"),
        timeout = 2,
    })
    return false
end

function Settings:formatPrice(price)
    if not price or price == "0" or price == 0 then
        return "Free"
    end
    
    local num_price = tonumber(price)
    if not num_price then
        return "Unknown"
    end
    
    -- Convert to price per million tokens
    return string.format("$%.3f", num_price * 1000000)
end

function Settings:onCloseWidget()
    -- Nothing to do on close
end

-- Helper function to truncate text
function Settings:truncateText(text, maxLength)
    if #text <= maxLength then
        return text
    end
    return text:sub(1, maxLength) .. "..."
end

function Settings:showSettingsDialog()
    logger.dbg("KoGPT: Opening settings dialog")
    
    -- Prepare fields array
    local fields = {
        {
            text = self:truncateText(self.data.api_key, 30),
            hint = _("Enter your OpenRouter API key"),
            description = _("API key"),
        },
        {
            text = self:truncateText(self.data.system_prompt, 150),
            input_type = "multiline",
            description = _("System prompt (max 150char.)"),
            -- height = Screen:getHeight() * 0.2,  -- About 6 lines
        },
    }
    
    -- Add field for Translate task only
    for i, task in ipairs(self.data.task_prompts) do
        if task.name == "Translate" then
            table.insert(fields, {
                text = task.prompt,
                input_type = "multiline",
                description = "Translate prompt", 
                hint = _("Enter prompt for ") .. task.name,
                height = Screen:getHeight() * 0.15,
            })
            break  -- Exit loop after finding Translate task
        end
    end
    
    local dialog
    dialog = MultiInputDialog:new{
        title = _("GPT Plugin Settings"),
        width = Screen:getWidth() * 0.8,  -- 80% of screen width
        height = Screen:getHeight() * 0.8, -- 80% of screen height to fit task fields
        fields = fields,
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        local fields = dialog:getFields()
                        local api_key = fields[1]
                        local system_prompt = fields[2]
                        
                        -- Update settings
                        self.data.api_key = api_key
                        self.data.system_prompt = system_prompt
                        
                        -- Save settings
                        if G_reader_settings then
                            G_reader_settings:saveSetting("kogpt", self.data)
                            logger.dbg("KoGPT: Saved settings - API key length:", #api_key)
                            logger.dbg("KoGPT: Saved settings - System prompt length:", #system_prompt)
                        else
                            logger.warn("KoGPT: Could not save settings - G_reader_settings not available")
                        end
                        
                        -- Update Translate task prompt
                        for i, task in ipairs(self.data.task_prompts) do
                            if task.name == "Translate" then
                                task.prompt = fields[3]  -- Field 3 is Translate prompt
                                break
                            end
                        end
                        
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Select Model"),
                    callback = function()
                        -- Hide keyboard if visible
                        dialog:onCloseKeyboard()
                        
                        if self:fetchModels() then
                            -- Do NOT close the main settings dialog
                            self:showModelSelector(function()
                                -- After model selection, refresh dialog fields if needed
                            end)
                        end
                    end,
                }
            },
        },
    }
    UIManager:show(dialog)
end


function Settings:showModelSelector(on_model_selected)
    logger.dbg("KoGPT: Opening model selector")
    
    if not self.data.models or #self.data.models == 0 then
        logger.warn("KoGPT: No models available")
        UIManager:show(InfoMessage:new{
            text = _("No models available. Please try fetching models again."),
            timeout = 2,
        })
        return
    end
    
    -- Store menu reference at object level
    if self.model_menu then
        UIManager:close(self.model_menu)
    end
    
    -- Create menu items with safe model data handling
    local menu_items = {}
    for _, model in ipairs(self.data.models) do
        -- Validate model data first
        if not model or not model.id then
            logger.warn("KoGPT: Skipping invalid model entry")
            goto next_model
        end
        
        -- Create local copy of validated model data
        local model_data = {
            id = model.id,
            name = model.name or model.id,
            description = model.description,
            context_length = model.context_length,
            pricing = model.pricing
        }
        
        -- Format pricing info
        local pricing_text = ""
        if model_data.pricing then
            local prompt_price = self:formatPrice(model_data.pricing.prompt or 0)
            local completion_price = self:formatPrice(model_data.pricing.completion or 0)
            -- Only show pricing if not both free
            if prompt_price ~= "Free" or completion_price ~= "Free" then
                pricing_text = string.format(" (%s / %s)", prompt_price, completion_price)
            end
        end

        -- Create display text with pricing
        local text = model_data.name .. pricing_text
        if model_data.id == self.data.selected_model then
            text = "✓ " .. text
        end
        
        table.insert(menu_items, {
            text = text,
            callback = function()
                -- Get fresh translation function
                local _ = require("gettext")
                
                logger.dbg("KoGPT: Selecting model", model.id)
                
                -- Validate model data
                if not model or not model.id then
                    logger.warn("KoGPT: Invalid model data")
                    UIManager:show(InfoMessage:new{
                        text = _("Error: Invalid model data"),
                        timeout = 2,
                    })
                    return
                end
                
                -- Update selected model
                self.data.selected_model = model_data.id
                
                -- Save settings
                if G_reader_settings then
                    G_reader_settings:saveSetting("kogpt", self.data)
                    logger.dbg("KoGPT: Saved model selection:", model.id)
                    logger.dbg("KoGPT: Current settings state:", {
                        api_key_length = #self.data.api_key,
                        selected_model = self.data.selected_model,
                        system_prompt_length = #self.data.system_prompt,
                        models_count = #self.data.models
                    })
                else
                    logger.warn("KoGPT: Could not save model selection - G_reader_settings not available")
                end
                
                -- Show confirmation
                local display_name = model.name or model.id or "Unknown"
                UIManager:show(InfoMessage:new{
                    text = _("Model selected") .. ": " .. display_name,
                    timeout = 2,
                })
                
                -- Close the model selector menu
                if self.model_menu then
                    UIManager:close(self.model_menu)
                end
                
                -- Call the callback if provided
                if on_model_selected then
                    on_model_selected()
                end
            end,
            hold_callback = function()
                -- Get fresh translation function
                local _ = require("gettext")
                
                logger.dbg("KoGPT: Showing details for model", model.id)
                logger.dbg("KoGPT: Model pricing data:", require("json").encode(model.pricing or {}))
                
                -- Create a local copy of model data
                local model_data = {
                    id = model.id,
                    name = model.name,
                    description = model.description,
                    context_length = model.context_length,
                    pricing = model.pricing
                }
                
                -- Validate model data
                if not model_data or not model_data.id then
                    logger.warn("KoGPT: Invalid model data in hold callback")
                    UIManager:show(InfoMessage:new{
                        text = _("Error: Could not load model details"),
                        timeout = 2,
                    })
                    return
                end
                
                -- Build description with safe concatenation
                local desc = {}
                table.insert(desc, model_data.description or _("No description available"))
                table.insert(desc, "\n\nContext Length: " .. (tonumber(model_data.context_length) or 0) .. " tokens")
                
                -- Add pricing section
                table.insert(desc, "\n\nPRICING")
                table.insert(desc, "\n--------")
                
                -- Always show pricing info, defaulting to "Unknown" if not available
                local prompt_price = "Unknown"
                local completion_price = "Unknown"
                
                if model_data.pricing then
                    if model_data.pricing.prompt then
                        prompt_price = self:formatPrice(model_data.pricing.prompt)
                    end
                    if model_data.pricing.completion then
                        completion_price = self:formatPrice(model_data.pricing.completion)
                    end
                end
                
                table.insert(desc, "\nPrompt: " .. prompt_price)
                table.insert(desc, "\nCompletion: " .. completion_price)
                
                -- Show info message with longer timeout and better visibility
                UIManager:show(InfoMessage:new{
                    text = table.concat(desc),
                    timeout = 10,
                    width = Screen:getWidth() * 0.8,
                    height = Screen:getHeight() * 0.6,
                    face = Font:getFace("cfont", 16),
                    padding = 10,
                })
            end,
        })
    end


    
    -- Create menu with explicit positioning
    local menu_width = Screen:getWidth() * 1.0  -- Make wider
    local menu_height = Screen:getHeight() * 1.0
    local menu_x = math.floor((Screen:getWidth() - menu_width) / 2)
    local menu_y = math.floor((Screen:getHeight() - menu_height) / 2)

    self.model_menu = Menu:new{
        title = _("Select Model (Hold for details)"),
        item_table = menu_items,
        is_borderless = false,
        is_popout = false,
        width = menu_width,
        height = menu_height,
        face = Font:getFace("cfont", 18),
        no_keyboard = true,
        perpage = 10,
        close_callback = function()
            logger.dbg("KoGPT: Model selector closed")
            collectgarbage()
        end,
        overlap_align = "center",
        position_center = true,
        pos_x = menu_x,
        pos_y = menu_y,
    }
    UIManager:show(self.model_menu)
    
    ::next_model::
end

return Settings