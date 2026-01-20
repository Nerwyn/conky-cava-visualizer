# conky-cava-visualizer

An audio visualizer made using Conky, Cava, Lua, and Cairo. No extra windows, just a cava visualizer on your desktop.

https://github.com/user-attachments/assets/e49a917a-a9d7-4def-ae24-2e2c62c7e40d

## Setup

1. Install [conky](https://github.com/brndnmtthws/conky) using the instructions provided in its repository or using a package manager.
  - You need to use the `conky-all` package variant which has cairo bindings for lua.
	- The command `conky -v` should include a lua bindings section which lists cairo.
2. Install [cava](https://github.com/karlstav/cava) using the instructions provided in its repository or using a package manager.
3. On this repository click `<> Code` and then `Download ZIP`.
4. Unzip the folder to your desired location. I recommend `~/.config/conky`.
5. Open a command line in the visualizer folder and run it using the command `conky -c ./visualizer.conf`.
  - You must run this command in the same folder as the files so the lua script can find the provided cava configuration file.

## Configuration

Configuration options exist in both the conky and cava configuration files.

### visualizer.conf

The conky configuration file.

#### Height and Width

Set `minimum_height` and `minimum_width` to your desired visualizer size. I found that I also needed to reduce width by 8px when making it full screen, otherwise conky would not load the configuration. For reference the default values are for a 4K (3840 x 2160) screen at 150% scale with the 8px width reduction, and the visualizer covers the entire screen.

#### Position

Set `gap_x` and `gap_y` to reposition the visualizer. DO NOT use non `_middle` alignments, doing so will break the visualizer lua script calculations.

#### Monitor

Set `xinerama_head` to the index of the monitor you want to display the visualizer on, starting with index 0.

### Cava config

The cava configuration file. Most options in this file are handled by cava itself. For those refer to the descriptions in file provided by the cava developers. You may also find the [cava example config file](https://github.com/karlstav/cava/blob/master/example_files/config) from its repository useful.

Some additional options have been added for use by the conky visualizer lua script, as there wasn't an equivalent or the equivalent could not be used. New options are in the `[conky]` section at the top of the file and described below. Do not surround your option values in quotes, as it will break the lua ini parser.

#### Orientation

NOT the cava orientation value, which has been removed from this file and must be left at its default value. Can be `top`, `bottom`, `horizontal`, `left`, `right`, or `vertical`. Defaults to `bottom`.

#### Color

The visualizer bar color. Similar to the original cava foreground option. Must be a hex color. Defaults to `#FFF`.

#### Opacity

The opacity of the bars. Must be a float between 0 and 1. Defaults to `1`.

#### Image Mask

Use an image mask instead of a solid color for the bars (see example video). Must be a png. Set `image_mask` to the full path to the image.
