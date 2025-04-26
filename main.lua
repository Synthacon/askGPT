--[[--
This plugin adds GPT capabilities to KOReader through OpenRouter API integration.
@module koplugin.KoGPT
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MovableContainer = require("ui/widget/container/movablecontainer")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local GPT = require("gpt")
local Settings = require("settings")

local KoGPT = WidgetContainer:extend{
    name = "kogpt",
    is_doc_only = false,
}

function KoGPT:cleanupSelectedText(text)
    if not text then return "" end
    
    -- Handle case where text is a table (KOReader selection)
    if type(text) == "table" then
        logger.dbg("KoGPT: Selected text is a table:", text)
        text = text.text or text.content or text.selected_text or ""
    end
    
    -- Ensure we have a string
    if type(text) ~= "string" then
        logger.warn("KoGPT: Selected text is not a string, got:", type(text))
        return ""
    end
    
    -- Clean up the text
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    return text
end

function KoGPT:splitTextIntoPages(text, max_chars_per_page)
    max_chars_per_page = max_chars_per_page or 1000
    local pages = {}
    local current_page = ""
    
    -- Split text into words to avoid breaking mid-word
    for word in text:gmatch("%S+") do
        if #current_page + #word + 1 > max_chars_per_page then
            table.insert(pages, current_page:gsub("^%s+", ""):gsub("%s+$", ""))
            current_page = ""
        end
        
        current_page = current_page .. (current_page ~= "" and " " or "") .. word
    end
    
    -- Add last page if not empty
    if current_page ~= "" then
        table.insert(pages, current_page)
    end
    
    return pages
end

function KoGPT:showGptWindow(text, tasks, callback)
    -- Clean up existing windows
    if self.gpt_window then
        UIManager:close(self.gpt_window)
    end
    
    -- Store task callback at object level
    self.task_callback = callback
    
    -- Format selected text nicely
    local formatted_text = text
    if #text > 200 then
        formatted_text = text:sub(1, 197) .. "..."
    end
    
    -- Create buttons array
    local buttons = {}
    local current_row = {}
    
    -- Add task buttons
    for _, task in ipairs(tasks) do
        local task_data = {
            name = task.name,
            prompt = task.prompt
        }
        table.insert(current_row, {
            text = task_data.name,
            callback = function()
                logger.info("KoGPT: Selected task: " .. task_data.name)
                if self.task_callback then
                    self.task_callback(task_data)
                end
                if self.gpt_window then
                    UIManager:close(self.gpt_window)
                end
            end,
        })
        
        -- Start new row after 2 buttons
        if #current_row == 2 then
            table.insert(buttons, current_row)
            current_row = {}
        end
    end
    
    -- Add remaining buttons in the last row
    if #current_row > 0 then
        table.insert(buttons, current_row)
    end
    
    -- Add custom prompt and close buttons in the last row
    table.insert(buttons, {
        {
            text = _("Custom Prompt"),
            callback = function()
                self:showCustomPromptDialog(text, self.task_callback)
            end,
        },
        {
            text = _("Close"),
            callback = function()
                if self.gpt_window then
                    UIManager:close(self.gpt_window)
                end
            end,
        },
    })
    
    -- Create dialog
    self.gpt_window = MultiInputDialog:new{
        title = _("AskGPT"),
        fields = {
            {
                text = formatted_text,
                hint = _("Selected text"),
                input_type = "text",
                readonly = true,
                text_height = 3,  -- Reduced height
            },
        },
        buttons = buttons,
    }
    
    UIManager:show(self.gpt_window)
end


function KoGPT:showCustomPromptDialog(text, callback)
    -- Clean up existing windows and dialogs
    if self.prompt_dialog then
        UIManager:close(self.prompt_dialog)
        self.prompt_dialog = nil
    end
    
    self.prompt_dialog = InputDialog:new{
        title = _("Enter Custom Prompt"),
        input = "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.prompt_dialog)
                        self.prompt_dialog = nil
                    end,
                },
                {
                    text = _("Send"),
                    callback = function()
                        local prompt = self.prompt_dialog:getInputText()
                        if prompt ~= "" then
                            UIManager:close(self.prompt_dialog)
                            self.prompt_dialog = nil
                            -- Match callback signature with task callback
                            callback({
                                name = "Custom Prompt",
                                prompt = prompt
                            }, prompt)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(self.prompt_dialog)
end

function KoGPT:splitResponseIntoPages(response, max_chars_per_page)
    -- Extensive logging for debugging
    logger.dbg("KoGPT: splitResponseIntoPages called")
    logger.dbg("Response type: " .. type(response))
    logger.dbg("Max chars type: " .. type(max_chars_per_page))
    
    -- Validate and sanitize input
    -- Input validation and debug logging
    if response == nil then
        logger.error("KoGPT: Nil response passed to splitResponseIntoPages")
        return {[1] = "No response available"}
    end

    logger.info("KoGPT: Original response type: " .. type(response))
    logger.info("KoGPT: Original response length: " .. (type(response) == "string" and #response or "unknown"))
    
    -- Force max_chars_per_page to be a number, with a safe default
    local safe_max_chars = 2000  -- Increased from 1000
    if type(max_chars_per_page) == "number" then
        safe_max_chars = max_chars_per_page
        logger.info("KoGPT: Using provided max_chars_per_page: " .. safe_max_chars)
    else
        logger.info("KoGPT: Using default max_chars_per_page: " .. safe_max_chars)
    end
    
    -- Convert to string, handling potential non-string inputs
    local safe_response = tostring(response)
    logger.info("KoGPT: Converted response length: " .. #safe_response)
    logger.info("KoGPT: First 100 chars: " .. safe_response:sub(1, 100))
    
    -- Handle empty response
    if safe_response:match("^%s*$") then
        return {[1] = "No content"}
    end
    
    local pages = {}
    local current_page = ""
    local page_count = 0
    
    -- Split response into words to avoid breaking mid-word
    for word in safe_response:gmatch("%S+") do
        -- Check if adding this word would exceed page limit
        if #current_page + #word + 1 > safe_max_chars then
            -- Trim and add current page
            local trimmed_page = current_page:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed_page ~= "" then
                page_count = page_count + 1
                pages[page_count] = trimmed_page
                logger.dbg(string.format("KoGPT: Added page %d, length: %d", page_count, #trimmed_page))
            end
            current_page = ""
        end
        
        -- Add word to current page
        current_page = current_page .. (current_page ~= "" and " " or "") .. word
    end
    
    -- Add last page if not empty
    if current_page ~= "" then
        local trimmed_page = current_page:gsub("^%s+", ""):gsub("%s+$", "")
        page_count = page_count + 1
        pages[page_count] = trimmed_page
        logger.dbg(string.format("KoGPT: Added final page %d, length: %d", page_count, #trimmed_page))
    end
    
    -- Fallback for unexpected scenarios
    if page_count == 0 then
        logger.warn("KoGPT: No pages created, using full text")
        pages[1] = safe_response
        page_count = 1
    end
    
    logger.dbg("KoGPT: Created " .. page_count .. " pages")
    return pages
end

-- Constant for maximum characters per page (adjusted for typical screen size)
local MAX_CHARS_PER_PAGE = 900

function KoGPT:showResponse(response)
    -- Debug logging for incoming response
    logger.info("KoGPT:showResponse called with response type: " .. type(response))
    
    -- Clean up existing windows and dialogs
    if self.response_window then
        UIManager:close(self.response_window)
        self.response_window = nil
    end
    if self.prompt_dialog then
        UIManager:close(self.prompt_dialog)
        self.prompt_dialog = nil
    end
    if self.gpt_window then
        UIManager:close(self.gpt_window)
        self.gpt_window = nil
    end
    
    -- Input validation
    if not response then
        logger.error("KoGPT: Nil response in showResponse")
        return
    end

    -- Split response into pages
    local response_pages = self:splitResponseIntoPages(response, MAX_CHARS_PER_PAGE)
    local current_page = 1
    
    -- Validate pages
    if not response_pages or #response_pages == 0 then
        logger.error("KoGPT: No pages created from response")
        response_pages = {response}  -- Use full response as fallback
    end
    
    -- Debug logging
    logger.info("KoGPT: Number of pages: " .. #response_pages)
    
    -- Create dialog with dynamic page handling
    local function updateDialog()
        if self.response_window then
            UIManager:close(self.response_window)
        end
        
        -- Create navigation buttons
        local nav_buttons = {}
        
        -- Previous button
        if current_page > 1 then
            table.insert(nav_buttons, {
                text = _("Previous"),
                callback = function()
                    current_page = current_page - 1
                    updateDialog()
                end,
            })
        end
        
        -- Next button
        if current_page < #response_pages then
            table.insert(nav_buttons, {
                text = _("Next"),
                callback = function()
                    current_page = current_page + 1
                    updateDialog()
                end,
            })
        end
        
        -- Add Ask Follow-up and Close buttons
        table.insert(nav_buttons, {
            text = _("Ask Follow-up"),
            callback = function()
                self:showFollowUpDialog(response)
            end,
        })
        
        table.insert(nav_buttons, {
            text = _("Close"),
            callback = function()
                if self.response_window then
                    UIManager:close(self.response_window)
                    self.response_window = nil
                end
            end,
        })

        -- Create dialog with MultiInputDialog
        self.response_window = MultiInputDialog:new{
            title = string.format(_("GPT Response (Page %d/%d)"), current_page, #response_pages),
            fields = {
                {
                    text = response_pages[current_page],
                    hint = _("Response text"),
                    input_type = "text",
                    scroll = true,
                    text_height = 15,
                    justified = true,
                    readonly = true,
                    face = Font:getFace("x_smallinfofont"),
                    alignment = "left",
                },
            },
            buttons = {nav_buttons},  -- Single row of navigation buttons
            width = math.floor(Screen:getWidth() * 0.8),
            height = math.floor(Screen:getHeight() * 0.8),
            persistent = true,  -- Keep dialog open
        }
        
        UIManager:show(self.response_window)
    end
    
    -- Initial dialog display
    updateDialog()
    return self.response_window
end

function KoGPT:init()
    logger.info("KoGPT: Initializing plugin")
    
    if not G_reader_settings then
        logger.warn("KoGPT: G_reader_settings not available")
        return
    end
    
    if not self.ui then
        logger.warn("KoGPT: No UI object available")
        return
    end
    
    -- Initialize components
    self.settings = Settings:new()
    self.gpt = GPT:new{
        settings = self.settings
    }
    
    -- Initialize conversation history
    self.conversation_history = {}
    
    -- Load settings
    self.settings_data = G_reader_settings:readSetting("kogpt", {})
    
    -- Store UI reference
    self.reader_ui = self.ui
    
    -- Register menu items
    if self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    if self.ui.highlight then
        self:addToHighlightDialog()
    end
    
    logger.info("KoGPT: Plugin initialized")
end

function KoGPT:addToMainMenu(menu_items)
    menu_items.kogpt = {
        text = _("GPT Settings"),
        sorting_hint = "more_tools",
        callback = function()
            self.settings:showSettingsDialog()
        end,
    }
end

function KoGPT:onFlushSettings()
    if self.settings_data then
        G_reader_settings:saveSetting("kogpt", self.settings_data)
    end
end

function KoGPT:resetConversationHistory(selected_text, prompt)
    self.conversation_history = {
        {role = "system", content = self.settings and self.settings:getSystemPrompt() or "You are a helpful assistant."},
        {role = "user", content = prompt .. "\n\nText: " .. selected_text}
    }
end

function KoGPT:showFollowUpDialog(last_response)
    self:showCustomPromptDialog("", function(task, prompt)
        if not prompt or prompt == "" then
            UIManager:show(InfoMessage:new{
                text = _("Error: Empty prompt"),
                timeout = 2,
            })
            return
        end
        -- Clean up all windows before showing new response
        if self.response_window then
            UIManager:close(self.response_window)
            self.response_window = nil
        end
        if self.prompt_dialog then
            UIManager:close(self.prompt_dialog)
            self.prompt_dialog = nil
        end
        if self.gpt_window then
            UIManager:close(self.gpt_window)
            self.gpt_window = nil
        end
        -- Append user follow-up to conversation history
        table.insert(self.conversation_history, {role="user", content=prompt})
        -- Use conversation history for query
        self.gpt:query_with_history(self.conversation_history, function(new_response)
            if new_response then
                table.insert(self.conversation_history, {role="assistant", content=new_response})
                self:showResponse(new_response)
            else
                UIManager:show(InfoMessage:new{
                    text = _("Error: No response received for follow-up"),
                    timeout = 2,
                })
            end
        end)
    end)
end

function KoGPT:addToHighlightDialog()
    if not self.reader_ui or not self.reader_ui.highlight then
        logger.warn("KoGPT: Highlight feature not available")
        return
    end

    self.reader_ui.highlight:addToHighlightDialog("ask_gpt", function(this)
        return {
            text = _("Ask GPT"),
            callback = function()
                -- Safely get selected text
                local text = ""
                if this and this.selected_text then
                    text = self:cleanupSelectedText(this.selected_text.text)
                end
                
                if text and text ~= "" then
                    logger.info("KoGPT: Processing selected text:", text:sub(1, 50), "...")
                    self:showGptWindow(text, self.settings:getTaskPrompts(), function(task, custom_prompt)
                        local prompt
                        if custom_prompt then
                            prompt = custom_prompt
                            logger.info("KoGPT: Using custom prompt: " .. prompt:sub(1, 50) .. "...")
                        elseif task and task.prompt then
                            prompt = task.prompt
                            logger.info("KoGPT: Using task prompt: " .. prompt:sub(1, 50) .. "...")
                        else
                            logger.error("KoGPT: No valid prompt found")
                            UIManager:show(InfoMessage:new{
                                text = _("Error: No valid prompt found"),
                                timeout = 2,
                            })
                            return
                        end
                        
                        -- Validate GPT instance
                        if not self.gpt then
                            logger.error("KoGPT: GPT not initialized")
                            UIManager:show(InfoMessage:new{
                                text = _("Error: GPT not initialized"),
                                timeout = 2,
                            })
                            return
                        end
                        
                        -- Initialize conversation history
                        self:resetConversationHistory(text, prompt)
                        
                        -- Use conversation history for query
                        self.gpt:query_with_history(self.conversation_history, function(response)
                            if response then
                                -- Add assistant response to history
                                table.insert(self.conversation_history, {role="assistant", content=response})
                                self:showResponse(response)
                            else
                                logger.error("KoGPT: No response received from query")
                                UIManager:show(InfoMessage:new{
                                    text = _("Error: No response received from API"),
                                    timeout = 2,
                                })
                            end
                        end)
                    end)
                    this:onClose()
                else
                    logger.warn("KoGPT: No text selected")
                    UIManager:show(InfoMessage:new{
                        text = _("Please select some text first."),
                    })
                end
            end,
        }
    end)
end

return KoGPT
