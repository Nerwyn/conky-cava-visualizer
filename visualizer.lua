-- Read config
local inifile = require 'inifile'
local config = inifile.parse('./config')

local orientation = string.gsub(config['conky']['orientation'] or 'bottom', '%s+', '')
local sideways = {'left', 'right', 'vertical'}
local is_sideways = false
for _, o in ipairs(sideways) do
    if orientation == o then
        is_sideways = true
        break
    end
end

local n_bars = tonumber(config['general']['bars'] or 512)
local bar_spacing = tonumber(config['general']['bar_spacing'] or 1)
local bar_max = tonumber(config['output']['ascii_max_range'] or 1000)

local color = string.gsub(config['color']['color'] or '#FFF', '%s+', '')
local opacity = tonumber(config['color']['opacity'] or 1)

-- Cairo setup
local cairo = require('cairo')
local cairo_xlib = require('cairo_xlib')

-- Hex color parsing https://gist.github.com/fernandohenriques/12661bf250c8c2d8047188222cab7e28
function hex2rgb(hex)
    local hex = hex:gsub("#", "")
    if hex:len() == 3 then
        return {(tonumber("0x" .. hex:sub(1, 1)) * 17) / 255, (tonumber("0x" .. hex:sub(2, 2)) * 17) / 255,
                (tonumber("0x" .. hex:sub(3, 3)) * 17) / 255}
    else
        return {tonumber("0x" .. hex:sub(1, 2)) / 255, tonumber("0x" .. hex:sub(3, 4)) / 255,
                tonumber("0x" .. hex:sub(5, 6)) / 255}
    end
end
local rgb = hex2rgb(color)

-- Cava pipe setup
local pipe = io.popen('cava -p ./config', 'r')
local last_line = ''
function read_cava()
    for line in pipe:lines() do
        last_line = line
        coroutine.yield()
    end
end
local co = coroutine.create(read_cava)

-- Visualizer mode setup
local incrementors = {
    horizontal = function(x, y, bar_width)
        return x + bar_width + bar_spacing, y
    end,

    vertical = function(x, y, bar_width)
        return x, y + bar_width + bar_spacing
    end
}
local incrementor = incrementors[is_sideways and 'vertical' or 'horizontal']

local bar_width_getters = {
    horizontal = function()
        return ((conky_window.width - bar_spacing) / n_bars) - bar_spacing
    end,

    vertical = function()
        return ((conky_window.height - bar_spacing) / n_bars) - bar_spacing
    end
}
local get_bar_width = bar_width_getters[is_sideways and 'vertical' or 'horizontal']

local bar_height_getters = {
    horizontal = function(i)
        return math.floor((i / bar_max) * conky_window.height)
    end,

    vertical = function(i)
        return math.floor((i / bar_max) * (conky_window.width))
    end
}
local get_bar_height = bar_height_getters[is_sideways and 'vertical' or 'horizontal']

function draw(cr, x0, y0, draw_bar)
    local x = x0
    local y = y0
    local bar_width = get_bar_width()
    for i in string.gmatch(last_line, "([^;]+)") do
        i = tonumber(i or 0)
        if i > 0 then
            local bar_height = get_bar_height(i)
            draw_bar(cr, x, y, bar_height, bar_width)
        end
        x, y = incrementor(x, y, bar_width)
    end
end

local visualizers = {
    top = function(cr)
        draw(cr, bar_spacing, 0, function(cr, x, y, height, width)
            cairo_rectangle(cr, x, y, width, height)
        end)
    end,

    bottom = function(cr)
        draw(cr, bar_spacing, conky_window.height, function(cr, x, y, height, width)
            cairo_rectangle(cr, x, y - height, width, height)
        end)
    end,

    horizontal = function(cr)
        draw(cr, bar_spacing, math.floor(conky_window.height / 2), function(cr, x, y, height, width)
            cairo_rectangle(cr, x, y - (height / 2), width, height)
        end)
    end,

    left = function(cr)
        draw(cr, 0, bar_spacing, function(cr, x, y, height, width)
            cairo_rectangle(cr, x, y, height, width)
        end)
    end,

    right = function(cr)
        draw(cr, conky_window.width, bar_spacing, function(cr, x, y, height, width)
            cairo_rectangle(cr, x - height, y, height, width)
        end)
    end,

    vertical = function(cr)
        draw(cr, math.floor(conky_window.width / 2), bar_spacing, function(cr, x, y, height, width)
            cairo_rectangle(cr, x - (height / 2), y, height, width)
        end)
    end
}
local visualizer = visualizers[orientation] or draw_bottom

-- Main method
function conky_visualizer()
    coroutine.resume(co)

    if (conky_window.height or 0 > 0 and conky_window.width or 0 > 0) then
        -- Cairo setup
        local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual,
            conky_window.width, conky_window.height)
        local cr = cairo_create(cs)
        cairo_set_source_rgba(cr, rgb[1], rgb[2], rgb[3], opacity)

        -- Draw using user selected visualizer
        visualizer(cr)
        cairo_fill(cr)

        -- Cair teardown
        cairo_destroy(cr)
        cairo_surface_destroy(cs)
        cr = nil
    end

    return ''
end
