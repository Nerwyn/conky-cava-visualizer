require 'cairo'
require 'cairo_xlib'

local cava_config_file = './config'
local inifile = require 'inifile'
local hex2rgb = require 'hex2rgb'

-- Set on conky load and config read
local cs
local cr

local window_height
local window_width

local n_bars
local bar_spacing
local bar_max

local bar_width
local bar_width_getters = {
  horizontal = function()
    return (((window_width or 0) - bar_spacing) // n_bars) - bar_spacing
  end,

  vertical = function()
    return (((window_height or 0) - bar_spacing) // n_bars) - bar_spacing
  end
}

local orientation
local is_sideways

local incrementor
local incrementors = {
  horizontal = function(x, y)
    return x + bar_width + bar_spacing, y
  end,

  vertical = function(x, y)
    return x, y + bar_width + bar_spacing
  end
}

local get_bar_height
local bar_height_getters = {
  horizontal = function(value)
    return value * window_height // bar_max
  end,

  vertical = function(value)
    return value * window_width // bar_max
  end
}

local bit_format
local byte_format
local byte_size

local color
local rgb
local opacity

local image_mask
local function apply_image_mask_to_cr()
  if image_mask ~= '' and cr ~= nil then
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
  else
    cr = cairo_create(cs)
    cairo_set_source_rgba(cr, rgb[1], rgb[2], rgb[3], opacity)
  end
end

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
local visualizer

local function read_config()
  local config = inifile.parse(cava_config_file)

  -- Orientation, number of bars, and spacing
  local orientation_new = string.gsub(config['conky']['orientation'] or 'bottom', '%s+', '')
  local n_bars_new = tonumber(config['general']['bars'] or 512)
  local bar_spacing_new = tonumber(config['general']['bar_spacing'] or 1)
  if orientation ~= orientation_new or n_bars ~= n_bars_new or bar_spacing ~= bar_spacing_new then
    orientation = orientation_new
    n_bars = n_bars_new
    bar_spacing = bar_spacing_new
    local sideways = { 'left', 'right', 'vertical' }
    is_sideways = false
    for _, o in ipairs(sideways) do
      if orientation == o then
        is_sideways = true
        break
      end
    end
    incrementor = incrementors[is_sideways and 'vertical' or 'horizontal']
    get_bar_height = bar_height_getters[is_sideways and 'vertical' or 'horizontal']
    bar_width = bar_width_getters[is_sideways and 'vertical' or 'horizontal']()
    visualizer = visualizers[orientation] or visualizers['bottom']
  end

  -- Bit format
  local bit_format_new = string.gsub(config['output']['bit_format'] or '16bit', '%s+', '')
  if bit_format_new ~= bit_format then
    bit_format = bit_format_new
    if bit_format == '8bit' then
      bar_max = 255
      byte_format = '<B'
      byte_size = 1
    else
      bar_max = 65535
      byte_format = '<H'
      byte_size = 2
    end
  end

  -- Color and opacity
  local color_new = string.gsub(config['conky']['color'] or '#FFF', '%s+', '')
  local opacity_new = tonumber(config['conky']['opacity'] or 1)
  if color ~= color_new or opacity ~= opacity_new then
    color = color_new
    rgb = hex2rgb(color)
    opacity = opacity_new
    if (cr ~= nil) then
      cairo_set_source_rgba(cr, rgb[1], rgb[2], rgb[3], opacity)
    end
  end

  -- Image mask
  local image_mask_new = string.gsub(config['conky']['image_mask'] or '', '%s+', '')
  if image_mask ~= image_mask_new then
    image_mask = image_mask_new
    apply_image_mask_to_cr()
  end
end

read_config()

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
  bar_width = bar_width_getters[is_sideways and 'vertical' or 'horizontal']()

  -- Use an image mask instead of color if set in cava config
  apply_image_mask_to_cr()
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
    read_config()
    visualizer()
    cairo_fill(cr)
  end
  return ''
end
