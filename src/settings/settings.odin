// Player options, saved as `key = value` lines in the user config directory
// (~/.config/the-trial-of-psyche/settings.cfg on Linux). Unknown keys and bad
// values are ignored, so an old or hand-edited file never breaks the game.
package settings

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "../i18n"

APP_DIR :: "the-trial-of-psyche"
FILE_NAME :: "settings.cfg"

FPS_LIMITS := [?]i32{0, 30, 60, 120, 144, 240}
RESOLUTIONS := [?][2]i32{{1280, 720}, {1600, 900}, {1920, 1080}, {2560, 1440}, {3840, 2160}}

Settings :: struct {
	language:   i18n.Language,
	fullscreen: bool,
	resolution: [2]i32, // window size when not fullscreen
	vsync:      bool,
	fps_limit:  i32, // 0 = unlimited
	msaa:       bool, // applied at the next start
	master:     f32, // volumes, 0..1
	music:      f32,
	sfx:        f32,
	debug:      bool,
}

defaults :: proc() -> Settings {
	return {
		language = i18n.language_from_locale(os.get_env("LANG", context.temp_allocator)),
		fullscreen = false,
		resolution = {1600, 900},
		vsync = true,
		fps_limit = 0,
		msaa = true,
		master = 1,
		music = 1,
		sfx = 1,
		debug = false,
	}
}

// Full path of the settings file (temp allocator), or "" when unknown.
file_path :: proc() -> string {
	dir, err := os.user_config_dir(context.temp_allocator)
	if err != nil || dir == "" {
		return ""
	}
	return fmt.tprintf("%s/%s/%s", dir, APP_DIR, FILE_NAME)
}

load :: proc() -> Settings {
	s := defaults()
	path := file_path()
	if path == "" {
		return s
	}
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		return s
	}
	parse(string(data), &s)
	return s
}

save :: proc(s: Settings) -> bool {
	path := file_path()
	if path == "" {
		return false
	}
	dir := path[:strings.last_index_byte(path, '/')]
	if !os.exists(dir) && os.make_directory_all(dir) != nil {
		return false
	}
	return os.write_entire_file_from_string(path, serialize(s, context.temp_allocator)) == nil
}

serialize :: proc(s: Settings, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintln(&b, "# The Trial of Psyche - settings")
	fmt.sbprintfln(&b, "language = %s", i18n.LANGUAGE_CODE[s.language])
	fmt.sbprintfln(&b, "fullscreen = %v", s.fullscreen)
	fmt.sbprintfln(&b, "resolution = %dx%d", s.resolution.x, s.resolution.y)
	fmt.sbprintfln(&b, "vsync = %v", s.vsync)
	fmt.sbprintfln(&b, "fps_limit = %d", s.fps_limit)
	fmt.sbprintfln(&b, "msaa = %v", s.msaa)
	fmt.sbprintfln(&b, "master = %.2f", s.master)
	fmt.sbprintfln(&b, "music = %.2f", s.music)
	fmt.sbprintfln(&b, "sfx = %.2f", s.sfx)
	fmt.sbprintfln(&b, "debug = %v", s.debug)
	return strings.to_string(b)
}

// Read `key = value` lines into s, keeping the current value of anything
// missing or malformed.
parse :: proc(text: string, s: ^Settings) {
	rest := text
	for raw in strings.split_lines_iterator(&rest) {
		line := strings.trim_space(raw)
		if line == "" || line[0] == '#' {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq < 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		value := strings.trim_space(line[eq + 1:])

		boolean :: proc(v: string, out: ^bool) {
			switch v {
			case "true": out^ = true
			case "false": out^ = false
			}
		}
		volume :: proc(v: string, out: ^f32) {
			if f, ok := strconv.parse_f32(v); ok {
				out^ = clamp(f, 0, 1)
			}
		}

		switch key {
		case "language":
			for code, l in i18n.LANGUAGE_CODE {
				if code == value {
					s.language = l
				}
			}
		case "fullscreen":
			boolean(value, &s.fullscreen)
		case "resolution":
			x := strings.index_byte(value, 'x')
			if x > 0 {
				w, ok_w := strconv.parse_int(value[:x], 10)
				h, ok_h := strconv.parse_int(value[x + 1:], 10)
				if ok_w && ok_h && w >= 640 && h >= 360 && w <= 16384 && h <= 16384 {
					s.resolution = {i32(w), i32(h)}
				}
			}
		case "vsync":
			boolean(value, &s.vsync)
		case "fps_limit":
			if v, ok := strconv.parse_int(value, 10); ok && v >= 0 && v <= 1000 {
				s.fps_limit = i32(v)
			}
		case "msaa":
			boolean(value, &s.msaa)
		case "master":
			volume(value, &s.master)
		case "music":
			volume(value, &s.music)
		case "sfx":
			volume(value, &s.sfx)
		case "debug":
			boolean(value, &s.debug)
		}
	}
}
