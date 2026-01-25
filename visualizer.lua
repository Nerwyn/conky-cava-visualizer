require 'cairo'
require 'cairo_xlib'

-- Read config
local cava_config_file = './config'
local inifile = require 'inifile'
local config = inifile.parse(cava_config_file)

local orientation = string.gsub(config['conky']['orientation'] or 'bottom', '%s+', '')
local sideways = { 'left', 'right', 'vertical' }
local is_sideways = false
for _, o in ipairs(sideways) do
  if orientation == o then
    is_sideways = true
    break
  end
end

local n_bars = tonumber(config['general']['bars'] or 512)
local bar_spacing = tonumber(config['general']['bar_spacing'] or 1)

local bar_max = 65535
local byte_format = '<H'
local byte_size = 2
local bit_format = string.gsub(config['output']['bit_format'] or '16bit', '%s+', '')
if bit_format == '8bit' then
  bar_max = 255
  byte_format = '<B'
  byte_size = 1
end

local color = string.gsub(config['conky']['color'] or '#FFF', '%s+', '')
local opacity = tonumber(config['conky']['opacity'] or 1)
local image_mask = string.gsub(config['conky']['image_mask'] or '', '%s+', '')

-- Set on conky load
local cs
local cr
local window_height
local window_width
local bar_width

-- Hex color parsing https://gist.github.com/fernandohenriques/12661bf250c8c2d8047188222cab7e28
local function hex2rgb(hex)
  hex = hex:gsub('#', '')
  if hex:len() == 3 then
    return { (tonumber('0x' .. hex:sub(1, 1)) * 17) / 255, (tonumber('0x' .. hex:sub(2, 2)) * 17) / 255,
      (tonumber('0x' .. hex:sub(3, 3)) * 17) / 255 }
  else
    return { tonumber('0x' .. hex:sub(1, 2)) / 255, tonumber('0x' .. hex:sub(3, 4)) / 255,
      tonumber('0x' .. hex:sub(5, 6)) / 255 }
  end
end

local rgb = hex2rgb(color)

-- Cava pipe setup
local function read_cava()
  local pipe = io.popen('cava -p ' .. cava_config_file, 'r')
  if pipe == nil then
    print('Cava pipe failed')
    return
  end

  while true do
    local chunk = pipe:read(n_bars * byte_size)
    for i = 1, n_bars * byte_size, byte_size do
      local value = string.unpack(byte_format, chunk, i)
      coroutine.yield(value)
    end
  end
end
local co = coroutine.create(read_cava)

-- Visualizer mode setup
local incrementors = {
  horizontal = function(x, y)
    return x + bar_width + bar_spacing, y
  end,

  vertical = function(x, y)
    return x, y + bar_width + bar_spacing
  end
}
local incrementor = incrementors[is_sideways and 'vertical' or 'horizontal']

local bar_height_getters = {
  horizontal = function(value)
    return value * window_height // bar_max
  end,

  vertical = function(value)
    return value * window_width // bar_max
  end
}
local get_bar_height = bar_height_getters[is_sideways and 'vertical' or 'horizontal']

local function draw(x, y, draw_bar)
  for i = 1, n_bars do
    local _, value = coroutine.resume(co)
    local bar_height = get_bar_height(value)
    draw_bar(x, y, bar_height, bar_width)
    x, y = incrementor(x, y)
  end
end

local visualizers = {
  top = function()
    draw(bar_spacing, 0, function(x, y, height, width)
      cairo_rectangle(cr, x, y, width, height)
    end)
  end,

  bottom = function()
    draw(bar_spacing, window_height, function(x, y, height, width)
      cairo_rectangle(cr, x, y - height, width, height)
    end)
  end,

  horizontal = function()
    draw(bar_spacing, window_height // 2, function(x, y, height, width)
      cairo_rectangle(cr, x, y - (height // 2), width, height)
    end)
  end,

  left = function()
    draw(0, bar_spacing, function(x, y, height, width)
      cairo_rectangle(cr, x, y, height, width)
    end)
  end,

  right = function()
    draw(window_width, bar_spacing, function(x, y, height, width)
      cairo_rectangle(cr, x - height, y, height, width)
    end)
  end,

  vertical = function()
    draw(window_width // 2, bar_spacing, function(x, y, height, width)
      cairo_rectangle(cr, x - (height // 2), y, height, width)
    end)
  end
}
local visualizer = visualizers[orientation] or visualizers['bottom']

-- Setup/teardown
function conky_setup_visualizer()
  -- Conky window width/height is 0 for the first few renders which causes errors
  window_height = conky_window.height
  window_width = conky_window.width
  if (window_height <= 0 or window_width <= 0) then
    return
  end

  -- Cairo setup
  cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, window_width,
    window_height)
  cr = cairo_create(cs)
  cairo_set_source_rgba(cr, rgb[1], rgb[2], rgb[3], opacity)

  -- Bar width calculation
  if is_sideways then
    bar_width = ((window_height - bar_spacing) // n_bars) - bar_spacing
  else
    bar_width = ((window_width - bar_spacing) // n_bars) - bar_spacing
  end

  -- Use an image mask instead of color if set in cava config
  if image_mask ~= '' then
    local img_cs = cairo_image_surface_create_from_png(image_mask)
    local img_width = cairo_image_surface_get_width(img_cs);
    local img_height = cairo_image_surface_get_height(img_cs);

    local scaled_img_cs = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, window_width, window_height)
    local scaled_img_cr = cairo_create(scaled_img_cs)

    local scale_x = window_width / img_width
    local scale_y = window_height / img_height

    cairo_scale(scaled_img_cr, scale_x, scale_y)
    cairo_set_source_surface(scaled_img_cr, img_cs, 0, 0)
    cairo_paint_with_alpha(scaled_img_cr, opacity)
    cairo_set_source_surface(cr, scaled_img_cs, 0, 0)

    cairo_destroy(scaled_img_cr)
    cairo_surface_destroy(scaled_img_cs)
    cairo_surface_destroy(img_cs)
  end
end

function conky_shutdown_visualizer()
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end

function conky_preload_visualizer()
  if conky_window == nil then
    return
  end

  -- Conky window width/height is 0 for the first few renders which causes errors
  if conky_window.height ~= window_height or conky_window.width ~= window_width then
    conky_shutdown_visualizer()
    conky_setup_visualizer()
  end
end

-- Main method
function conky_visualizer()
  if (cr ~= nil) then
    visualizer()
    cairo_fill(cr)
  end
  return ''
end
