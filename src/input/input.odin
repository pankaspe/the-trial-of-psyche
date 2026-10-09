// The player's hands: a gamepad, or the keyboard and the mouse, whichever was
// used last (the HUD shows the controls of that one, the mouse cursor hides
// while the pad plays).
//
// Buttons are named by their place on the pad (South is A on an Xbox pad,
// Cross on a PlayStation one, B on a Nintendo one); `layout` tells the HUD
// which names and marks to show. One player: the state is the package's own,
// read through procs, like raylib's input.
package input

import "core:math"
import "core:strings"
import rl "vendor:raylib"

Vec2 :: [2]f32

Device :: enum u8 {
	Keyboard, // the keyboard and the mouse
	Pad,
}

Layout :: enum u8 {
	Xbox,
	PlayStation,
	Nintendo,
}

Button :: enum u8 {
	South,
	East,
	West,
	North,
	LB,
	RB,
	LT,
	RT,
	Start,
	Select,
	Up,
	Down,
	Left,
	Right,
}

Buttons :: bit_set[Button]

// What raylib calls each button.
@(private)
RL_BUTTON := [Button]rl.GamepadButton {
	.South  = .RIGHT_FACE_DOWN,
	.East   = .RIGHT_FACE_RIGHT,
	.West   = .RIGHT_FACE_LEFT,
	.North  = .RIGHT_FACE_UP,
	.LB     = .LEFT_TRIGGER_1,
	.RB     = .RIGHT_TRIGGER_1,
	.LT     = .LEFT_TRIGGER_2,
	.RT     = .RIGHT_TRIGGER_2,
	.Start  = .MIDDLE_RIGHT,
	.Select = .MIDDLE_LEFT,
	.Up     = .LEFT_FACE_UP,
	.Down   = .LEFT_FACE_DOWN,
	.Left   = .LEFT_FACE_LEFT,
	.Right  = .LEFT_FACE_RIGHT,
}

DEADZONE :: 0.25 // of the stick's travel
PUSH :: 0.5 // a stick pushed this far is a direction (menus, walking)
REPEAT_DELAY :: 0.4 // a direction held in a menu repeats after this...
REPEAT_EVERY :: 0.11 // ...this often

State :: struct {
	device:   Device,
	layout:   Layout,
	pad:      i32, // the gamepad in use, -1: none connected
	down:     Buttons,
	pressed:  Buttons, // went down this frame (and not consumed)
	consumed: Buttons, // already acted on this frame
	stick:    Vec2, // the left stick, past the dead zone (screen axes: y down)
	stick_on: bool, // the stick is pushed (past PUSH)
	stick_fresh: bool, // ...and was not last frame
	right_x:  f32, // the right stick, sideways
	right_on: bool,
	right_fresh: int, // -1 / +1: the right stick was just pushed that way
	nav:      [2]int, // a menu step this frame (d-pad or stick), with repeat
	nav_t:    f32, // how long the current menu direction has been held
	nav_held: [2]int,
	mouse:    Vec2,
	cursor_hidden: bool,
	forced:   bool, // screenshots: the pad's HUD, whatever is plugged in (`force`)
	chosen:   Maybe(Layout), // the player's choice of buttons (settings), over the pad's own
}

@(private)
state: State = {pad = -1}

// Read the pad, the keyboard and the mouse; switch device when the other one
// is used. Call once at the start of a frame. `scripted`: screenshots and
// tests, the cursor is left alone.
update :: proc(dt: f32, scripted := false) {
	s := &state
	if s.forced {
		s.device = .Pad
		s.down, s.pressed, s.consumed, s.stick, s.stick_on, s.nav = {}, {}, {}, {}, false, {}
		return
	}
	find_pad(s)
	s.consumed = {}
	prev := s.down
	s.down = {}
	if s.pad >= 0 {
		for b in Button {
			if rl.IsGamepadButtonDown(s.pad, RL_BUTTON[b]) {
				s.down += {b}
			}
		}
		// some pads report the triggers only as axes
		if rl.GetGamepadAxisMovement(s.pad, .LEFT_TRIGGER) > 0.5 {
			s.down += {.LT}
		}
		if rl.GetGamepadAxisMovement(s.pad, .RIGHT_TRIGGER) > 0.5 {
			s.down += {.RT}
		}
	}
	s.pressed = s.down - prev

	was_on := s.stick_on
	s.stick = {}
	s.right_x = 0
	if s.pad >= 0 {
		v := Vec2{rl.GetGamepadAxisMovement(s.pad, .LEFT_X), rl.GetGamepadAxisMovement(s.pad, .LEFT_Y)}
		if l := math.sqrt(v.x * v.x + v.y * v.y); l > DEADZONE {
			s.stick = v / l * min((l - DEADZONE) / (1 - DEADZONE), 1)
		}
		s.right_x = rl.GetGamepadAxisMovement(s.pad, .RIGHT_X)
	}
	s.stick_on = s.stick.x * s.stick.x + s.stick.y * s.stick.y > PUSH * PUSH
	s.stick_fresh = s.stick_on && !was_on
	s.right_fresh = 0
	if abs(s.right_x) > 0.6 {
		if !s.right_on {
			s.right_fresh = s.right_x < 0 ? -1 : 1
		}
		s.right_on = true
	} else if abs(s.right_x) < 0.3 {
		s.right_on = false
	}

	update_nav(s, dt)

	// who is playing: the last device touched
	pad_used := s.pressed != {} || s.stick_fresh || s.right_fresh != 0
	mouse := rl.GetMousePosition()
	moved := mouse - s.mouse
	s.mouse = mouse
	keys_used := moved.x * moved.x + moved.y * moved.y > 9 || rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) || rl.GetMouseWheelMove() != 0 || any_key_pressed()
	if pad_used {
		s.device = .Pad
	} else if keys_used {
		s.device = .Keyboard
	}
	if !scripted {
		hide := s.device == .Pad
		if hide != s.cursor_hidden {
			s.cursor_hidden = hide
			if hide {
				rl.HideCursor()
			} else {
				rl.ShowCursor()
			}
		}
	}
}

// The first pad connected (or the one being used, if several are).
@(private)
find_pad :: proc(s: ^State) {
	if s.pad >= 0 && rl.IsGamepadAvailable(s.pad) {
		return
	}
	s.pad = -1
	for i in i32(0) ..< 4 {
		if rl.IsGamepadAvailable(i) {
			s.pad = i
			s.layout = layout_of(string(rl.GetGamepadName(i)))
			return
		}
	}
	if s.device == .Pad {
		s.device = .Keyboard // unplugged: back to the keys
	}
}

// The family of a pad, from the name its driver gives.
layout_of :: proc(name: string) -> Layout {
	n := strings.to_lower(name, context.temp_allocator)
	for word in ([]string{"playstation", "sony", "dualshock", "dualsense", "ps3", "ps4", "ps5", "wireless controller"}) {
		if strings.contains(n, word) {
			return .PlayStation
		}
	}
	for word in ([]string{"nintendo", "switch", "pro controller", "joy-con"}) {
		if strings.contains(n, word) {
			return .Nintendo
		}
	}
	return .Xbox
}

@(private)
any_key_pressed :: proc() -> bool {
	for k in 32 ..< 349 {
		if rl.IsKeyPressed(rl.KeyboardKey(k)) {
			return true
		}
	}
	return false
}

// Menu steps: a press of the d-pad or a push of the stick, then a repeat while held.
@(private)
update_nav :: proc(s: ^State, dt: f32) {
	held: [2]int
	if .Left in s.down || s.stick.x < -PUSH {
		held.x = -1
	} else if .Right in s.down || s.stick.x > PUSH {
		held.x = 1
	}
	if .Up in s.down || s.stick.y < -PUSH {
		held.y = -1
	} else if .Down in s.down || s.stick.y > PUSH {
		held.y = 1
	}
	s.nav = {}
	if held != s.nav_held {
		// a new direction: one step at once (a diagonal steps the newer axis only)
		for k in 0 ..< 2 {
			if held[k] != 0 && held[k] != s.nav_held[k] {
				s.nav[k] = held[k]
			}
		}
		if s.nav.x != 0 && s.nav.y != 0 {
			s.nav.x = 0
		}
		s.nav_t = 0
	} else if held != {} {
		s.nav_t += dt
		if s.nav_t >= REPEAT_DELAY {
			s.nav_t -= REPEAT_EVERY
			s.nav = held
			if s.nav.x != 0 && s.nav.y != 0 {
				s.nav.x = 0
			}
		}
	}
	s.nav_held = held
}

// --- queries ------------------------------------------------------------------------

// Is the pad the device in use (the HUD shows its controls)?
using_pad :: proc() -> bool {
	return state.device == .Pad
}

device :: proc() -> Device {
	return state.device
}

layout :: proc() -> Layout {
	if l, ok := state.chosen.?; ok && !state.forced {
		return l
	}
	return state.layout
}

// The buttons the player wants shown, whatever the pad says it is (nil: its own).
choose_layout :: proc(l: Maybe(Layout)) {
	state.chosen = l
}

pad_connected :: proc() -> bool {
	return state.pad >= 0
}

down :: proc(b: Button) -> bool {
	return b in state.down
}

// The button went down this frame and nothing has acted on it yet.
pressed :: proc(b: Button) -> bool {
	return b in state.pressed && b not_in state.consumed
}

// Act on a press: nothing else sees it this frame (a card closed with South
// does not also send Psyche into a cave).
consume :: proc(b: Button) {
	state.consumed += {b}
}

// pressed, then consumed.
take :: proc(b: Button) -> bool {
	if pressed(b) {
		consume(b)
		return true
	}
	return false
}

// Any button at all went down this frame.
any_pressed :: proc() -> bool {
	return state.pressed - state.consumed != {}
}

// The left stick (screen axes, y down), 0 inside the dead zone.
stick :: proc() -> Vec2 {
	return state.stick
}

// The direction Psyche is steered in, on screen: the stick, or the d-pad
// turned an eighth clockwise (the palace's sides run diagonally on screen:
// up goes up and to the right). `fresh`: it has just been pushed.
steer :: proc() -> (dir: Vec2, fresh: bool) {
	s := &state
	if s.stick_on {
		return s.stick, s.stick_fresh
	}
	d: Vec2
	if .Up in s.down {d += {1, -1}}
	if .Right in s.down {d += {1, 1}}
	if .Down in s.down {d += {-1, 1}}
	if .Left in s.down {d += {-1, -1}}
	if d == {} {
		return {}, false
	}
	return d / math.sqrt(d.x * d.x + d.y * d.y), s.pressed & {.Up, .Down, .Left, .Right} != {}
}

// A step in a menu this frame: x -1/+1 (left, right), y -1/+1 (up, down).
nav :: proc() -> [2]int {
	return state.nav
}

// The right stick just flicked sideways: -1 or +1, else 0.
flick :: proc() -> int {
	return state.right_fresh
}

// Show the HUD of a pad of this family and read nothing (screenshots).
force :: proc(l: Layout) {
	state = {pad = -1, forced = true, device = .Pad, layout = l}
}

// Back to the keyboard and the mouse, reading the devices again (tests).
reset :: proc() {
	state = {pad = -1}
}
