local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Menu = require("ui/widget/menu")
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local logger = require("logger")

local UI = {
    window_container = nil  -- Store the current response window container
}

function UI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function UI:showGptWindow(selected_text, tasks, callback)
    local window_width = math.floor(Screen:getWidth() * 0.8)
    local window_height = math.floor(Screen:getHeight() * 0.8)
    
    -- Create text display widget
    local text_widget = ScrollTextWidget:new{
        text = selected_text,
        width = window_width - 20,
        height = math.floor(window_height * 0.3),
        face = Font:getFace("x_smallinfofont"),
    }
    
    -- Create buttons for tasks
    local button_rows = {}
    local current_row = {}
    
    -- Add task buttons
    for _, task in ipairs(tasks) do
        table.insert(current_row, {
            text = task.name,
            callback = function()
                callback(task)
            end,
            width = math.floor((window_width - 40) / 2), -- 2 buttons per row with padding
            bordersize = 2,
            margin = 2,
            padding = 5,
            radius = 8,
            text_font_size = 18,
        })
        
        -- Start new row after 2 buttons
        if #current_row == 2 then
            table.insert(button_rows, current_row)
            current_row = {}
        end
    end
    
    -- Add custom prompt button in a new row
    if #current_row > 0 then
        table.insert(button_rows, current_row)
    end
    table.insert(button_rows, {
        {
            text = "✏️ Custom Prompt",
            callback = function()
                self:showCustomPromptDialog(selected_text, callback)
            end,
            width = math.floor((window_width - 40) / 2),
            bordersize = 2,
            margin = 2,
            padding = 5,
            radius = 8,
            text_font_size = 18,
        }
    })
    
    -- Create main window
    local window = FrameContainer:new{
        width = window_width,
        height = window_height,
        padding = 10,
        margin = 0,
        bordersize = 2,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text = "Selected Text:",
                face = Font:getFace("tfont", 20),
            },
            VerticalSpan:new{ width = 5 },
            text_widget,
            VerticalSpan:new{ width = 10 },
            -- Add button rows
            VerticalGroup:new{
                align = "center",
                button_rows,
            },
        }
    }
    
    local centered_window = CenterContainer:new{
        dimen = Screen:getSize(),
        window,
    }
    
    local movable_window = MovableContainer:new{
        centered_window,
    }
    
    UIManager:show(movable_window)
    return movable_window
end

function UI:showCustomPromptDialog(selected_text, callback)
    local dialog
    dialog = InputDialog:new{
        title = "Enter Custom Prompt",
        input = "",
        buttons = {
            {
                {
                    text = "Cancel",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = "Send",
                    callback = function()
                        local prompt = dialog:getInputText()
                        if prompt ~= "" then
                            UIManager:close(dialog)
                            callback(nil, prompt)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function UI:showResponse(response)
    local window_width = math.floor(Screen:getWidth() * 0.8)
    local window_height = math.floor(Screen:getHeight() * 0.8)
    
    -- Split response into pages (4000 chars per page)
    local page_size = 4000
    local pages = {}
    local current_page = 1
    
    for i = 1, #response, page_size do
        table.insert(pages, response:sub(i, i + page_size - 1))
    end
    
    local function showPage(page_num)
        if page_num < 1 or page_num > #pages then return end
        current_page = page_num
        
        local response_widget = ScrollTextWidget:new{
            text = pages[current_page],
            width = window_width - 20,
            height = window_height - 100, -- Reduced height to accommodate buttons
            face = Font:getFace("x_smallinfofont"),
        }
        
        -- Create navigation buttons
        local buttons = OverlapGroup:new{
            dimen = { w = window_width - 20, h = 40 },
            TextWidget:new{
                text = string.format("Page %d/%d", current_page, #pages),
                face = Font:getFace("tfont", 16),
            },
        }
        
        -- Add Previous button if not on first page
        if current_page > 1 then
            table.insert(buttons, TextWidget:new{
                text = "◀ Previous",
                face = Font:getFace("tfont", 16),
                callback = function()
                    showPage(current_page - 1)
                end,
            })
        end
        
        -- Add Next button if not on last page
        if current_page < #pages then
            table.insert(buttons, TextWidget:new{
                text = "Next ▶",
                face = Font:getFace("tfont", 16),
                callback = function()
                    showPage(current_page + 1)
                end,
            })
        end
        
        -- Add Close button
        table.insert(buttons, TextWidget:new{
            text = "✕ Close",
            face = Font:getFace("tfont", 16),
            callback = function()
                UIManager:close(window_container)
            end,
        })
        
        local window = FrameContainer:new{
            width = window_width,
            height = window_height,
            padding = 10,
            margin = 0,
            bordersize = 2,
            background = Blitbuffer.COLOR_WHITE,
            VerticalGroup:new{
                align = "center",
                TextWidget:new{
                    text = "GPT Response:",
                    face = Font:getFace("tfont", 20),
                },
                VerticalSpan:new{ width = 5 },
                response_widget,
                VerticalSpan:new{ width = 10 },
                buttons,
            }
        }
        
        local centered_window = CenterContainer:new{
            dimen = Screen:getSize(),
            window,
        }
        
        if window_container then
            UIManager:close(window_container)
        end
        
        window_container = MovableContainer:new{
            centered_window,
        }
        
        UIManager:show(window_container)
    end
    
    -- Show first page
    showPage(1)
    return window_container
end

return UI