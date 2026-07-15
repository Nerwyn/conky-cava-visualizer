-- https://gist.github.com/fernandohenriques/12661bf250c8c2d8047188222cab7e28
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

return hex2rgb