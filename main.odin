package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import b2 "vendor:box2d"
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"


screen_width: f32 = 1200
screen_height: f32 = 800
player: rl.Rectangle = {screen_width / 2, screen_height / 2, 40, 40}
camera: rl.Camera2D = {
	target   = {player.x, player.y},
	offset   = {screen_width / 2, screen_height / 2},
	rotation = 0.0,
	zoom     = 1.0,
}


window_config :: proc() {
	rl.SetTargetFPS(0)
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.SetWindowMonitor(0)
	rl.InitWindow(
		rl.GetScreenWidth(),
		rl.GetScreenHeight(),
		"raylib [core] example - basic window",
	)
	rl.SetWindowPosition(0, 0)
	rl.SetMouseCursor(.CROSSHAIR)
}

rotation: f32
show_lines: bool = true
backgroundTexture: rl.Texture2D
main :: proc() {
	fmt.println("Hellope!")
	window_config()

	// Initialize our 'world' of boxes
	boxCount := 0
	boxes: [MAX_BOXES]rl.Rectangle = rl.Rectangle{}
	setup_boxes(&boxes, &boxCount)

	handle_window_resize()
	// Create a global light mask to hold all the blended lights
	lightMask: rl.RenderTexture = rl.LoadRenderTexture(rl.GetScreenWidth(), rl.GetScreenHeight())

	// Setup initial light
	setup_light(0, 200, 200, 500)
	next_light := 1

	for (!rl.WindowShouldClose()) {
		move_light(0, player.x, player.y)
		rl.BeginDrawing()
		// rl.ClearBackground({20, 50, 75, 255})
		rl.BeginMode2D(camera)
		camera.target = {player.x, player.y}
		if (rl.IsMouseButtonPressed(.RIGHT) && (next_light < MAX_LIGHTS)) {
			setup_light(next_light, rl.GetMousePosition().x, rl.GetMousePosition().y, 200)
			next_light += 1
		}
		update_dirty_lights(&boxes, &boxCount, lightMask)


		rl.DrawFPS(i32(screen_width) - 80, 10)
		rl.DrawText("Drag to move light #1", 10, 10, 10, rl.DARKGREEN)
		rl.DrawText("Right click to add new light", 10, 30, 10, rl.DARKGREEN)
		mousePos: rl.Vector2 = rl.GetMousePosition()

		// Calculate the angle between the rectangle's center and the mouse position
		// direction := atan2(mousePos.y - center.y, mousePos.x - rl.center.x) * rl.RAD2DEG


		// rl.DrawRectangleRec(player, rl.RED)

		handle_controls(&player)
		if rl.IsWindowResized() do handle_window_resize()
		draw_lighting(&boxes, &boxCount, lightMask, backgroundTexture)
		player_rotation :=
			math.atan2(mousePos.y - player.y, mousePos.x - player.x) * (180.0 / math.PI)
		rl.DrawRectanglePro(
			player,
			{player.width / 2, player.height / 2},
			player_rotation,
			rl.BLUE,
		)
		// draw tree with triangle and rectangle
		rl.DrawTriangle(
			rl.Vector2{screen_width / 2, 0},
			rl.Vector2{screen_width / 2 - 20, 80},
			rl.Vector2{screen_width / 2 + 20, 80},
			rl.GREEN,
		)
		rl.DrawText("Congrats! You created your first window!", 190, 200, 20, rl.LIGHTGRAY)

		rl.DrawFPS(200, 250)
		rl.EndDrawing()
	}
	// De-Initialization
	//--------------------------------------------------------------------------------------
	rl.UnloadTexture(backgroundTexture)
	rl.UnloadRenderTexture(lightMask)
	for i := 0; i < MAX_LIGHTS; i += 1 {
		if (lights[i].active) do rl.UnloadRenderTexture(lights[i].mask)
	}
}

handle_controls :: proc(player: ^rl.Rectangle) {
	if rl.IsKeyDown(.A) {
		player^.x -= 100 * rl.GetFrameTime()
	}
	if rl.IsKeyDown(.D) {
		player^.x += 100 * rl.GetFrameTime()
	}
	if rl.IsKeyDown(.S) {
		player^.y += 100 * rl.GetFrameTime()
	}
	if rl.IsKeyDown(.W) {
		player^.y -= 100 * rl.GetFrameTime()
	}
	// if rl.IsMouseButtonPressed(.LEFT) {
	// 	fmt.println("Mouse left button pressed", player.x, player.y, rl.GetMousePosition())
	// 	player.x = rl.GetMousePosition().x
	// 	player.y = rl.GetMousePosition().y
	// }
	if rl.IsKeyPressed(.F5) {
		fmt.println("f5")


	}
}

// Shadow geometry type
ShadowGeometry :: struct {
	vertices: [4]rl.Vector2,
}

// LIGHTING SHADOWS
// Custom Blend Modes
RLGL_SRC_ALPHA :: 0x0302
RLGL_MIN :: 0x8007
RLGL_MAX :: 0x8008

MAX_BOXES :: 20
MAX_SHADOWS :: MAX_BOXES * 3 // MAX_BOXES *3. Each box can cast up to two shadow volumes for the edges it is away from, and one for the box itself
MAX_LIGHTS :: 16

// Light info type
LightInfo :: struct {
	active:      bool, // Is this light slot active?;
	dirty:       bool, // Does this light need to be updated?
	valid:       bool, // Is this light in a valid position?
	position:    rl.Vector2, // Light position
	mask:        rl.RenderTexture, // Alpha mask for the light
	outerRadius: f32, // The distance the light toucheIs
	bounds:      rl.Rectangle, // A cached rectangle of the light bounds to help with culling
	shadows:     [MAX_SHADOWS]ShadowGeometry,
	shadowCount: int,
}

lights: [MAX_LIGHTS]LightInfo = {}

// Move a light and mark it as dirty so that we update it's mask next frame
move_light :: proc(slot: int, x: f32, y: f32) {
	lights[slot].dirty = true
	lights[slot].position.x = x
	lights[slot].position.y = y

	// update the cached bounds
	lights[slot].bounds.x = x - lights[slot].outerRadius
	lights[slot].bounds.y = y - lights[slot].outerRadius
}
// Compute a shadow volume for the edge
// It takes the edge and projects it back by the light radius and turns it into a quad
compute_shadow_volume_for_edge :: proc(slot: int, sp: rl.Vector2, ep: rl.Vector2) {
	if (lights[slot].shadowCount >= MAX_SHADOWS) do return

	extension := lights[slot].outerRadius * 2

	spVector := rl.Vector2Normalize((sp - lights[slot].position))
	spProjection := (sp + (spVector * extension))

	epVector := rl.Vector2Normalize((ep - lights[slot].position))
	epProjection := (ep + (epVector * extension))

	lights[slot].shadows[lights[slot].shadowCount].vertices[0] = sp
	lights[slot].shadows[lights[slot].shadowCount].vertices[1] = ep
	lights[slot].shadows[lights[slot].shadowCount].vertices[2] = epProjection
	lights[slot].shadows[lights[slot].shadowCount].vertices[3] = spProjection
	lights[slot].shadowCount += 1
}

// Draw the light and shadows to the mask for a light
draw_light_mask :: proc(slot: int) {
	// Use the light mask
	rl.BeginTextureMode(lights[slot].mask)

	rl.ClearBackground(rl.WHITE)

	// Force the blend mode to only set the alpha of the destination
	gl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
	gl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

	// If kwe are valid, then draw the light radius to the alpha mask
	if (lights[slot].valid) {
		rl.DrawCircleGradient(
			i32(lights[slot].position.x),
			i32(lights[slot].position.y),
			lights[slot].outerRadius,
			rl.ColorAlpha(rl.WHITE, 0),
			rl.WHITE,
		)
	}

	// Cut out the shadows from the light radius by forcing the alpha to maximum
	gl.SetBlendMode(i32(rl.BlendMode.ALPHA))
	gl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MAX)
	gl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

	// Draw the shadows to the alpha mask
	for i := 0; i < lights[slot].shadowCount; i += 1 {
		rl.DrawTriangleFan(&lights[slot].shadows[i].vertices[0], 4, rl.WHITE)
	}


	gl.DrawRenderBatchActive()
	// Go back to normal blend mode
	gl.SetBlendMode(i32(rl.BlendMode.ALPHA))

	rl.EndTextureMode()
}

// Setup a light
setup_light :: proc(slot: int, x: f32, y: f32, radius: f32) {
	lights[slot].active = true
	lights[slot].valid = false // The light must prove it is valid
	lights[slot].mask = rl.LoadRenderTexture(rl.GetScreenWidth(), rl.GetScreenHeight())
	lights[slot].outerRadius = radius
	lights[slot].bounds.width = radius * 2
	lights[slot].bounds.height = radius * 2

	move_light(slot, x, y)

	// Force the render texture to have something in it
	draw_light_mask(slot)
}

// See if a light needs to update it's mask
update_light :: proc(slot: int, boxes: ^[MAX_BOXES]rl.Rectangle, count: ^int) -> bool {
	if (!lights[slot].active || !lights[slot].dirty) do return false

	lights[slot].dirty = false
	lights[slot].shadowCount = 0
	lights[slot].valid = false
	for i := 0; i < count^; i += 1 {
		// // Are we in a box? if so we are not valid
		if rl.CheckCollisionPointRec(lights[slot].position, boxes^[i]) do return false

		// // If this box is outside our bounds, we can skip it
		if !rl.CheckCollisionRecs(lights[slot].bounds, boxes^[i]) do continue

		// // Check the edges that are on the same side we are, and cast shadow volumes out from them

		// // Top
		sp: rl.Vector2 = rl.Vector2{boxes[i].x, boxes[i].y}
		ep: rl.Vector2 = rl.Vector2{boxes[i].x + boxes[i].width, boxes^[i].y}
		if (lights[slot].position.y > ep.y) do compute_shadow_volume_for_edge(slot, sp, ep)
		// Right
		sp = ep
		ep.y += boxes^[i].height
		if (lights[slot].position.x < ep.x) do compute_shadow_volume_for_edge(slot, sp, ep)
		// Bottom
		sp = ep
		ep.x -= boxes^[i].width
		if (lights[slot].position.y < ep.y) do compute_shadow_volume_for_edge(slot, sp, ep)
		// Left
		sp = ep
		ep.y -= boxes^[i].height
		if (lights[slot].position.x > ep.x) do compute_shadow_volume_for_edge(slot, sp, ep)

		// The;box;itsel
		lights[slot].shadows[lights[slot].shadowCount].vertices[0] = rl.Vector2 {
			boxes^[i].x,
			boxes^[i].y,
		}
		lights[slot].shadows[lights[slot].shadowCount].vertices[1] = rl.Vector2 {
			boxes^[i].x,
			boxes^[i].y + boxes^[i].height,
		}
		lights[slot].shadows[lights[slot].shadowCount].vertices[2] = rl.Vector2 {
			boxes^[i].x + boxes^[i].width,
			boxes^[i].y + boxes^[i].height,
		}
		lights[slot].shadows[lights[slot].shadowCount].vertices[3] = rl.Vector2 {
			boxes^[i].x + boxes^[i].width,
			boxes^[i].y,
		}
		lights[slot].shadowCount += 1
	}

	lights[slot].valid = true

	draw_light_mask(slot)

	return true
}

// Set up some boxes
setup_boxes :: proc(boxes: ^[MAX_BOXES](rl.Rectangle), count: ^int) {
	boxes[0] = rl.Rectangle{150, 80, 40, 40}
	boxes[1] = rl.Rectangle{1200, 700, 40, 40}
	boxes[2] = rl.Rectangle{200, 600, 40, 40}
	boxes[3] = rl.Rectangle{1000, 50, 40, 40}
	boxes[4] = rl.Rectangle{500, 350, 40, 40}

	for i := 5; i < MAX_BOXES; i += 1 {
		boxes[i] = rl.Rectangle {
			f32(rl.GetRandomValue(0, rl.GetScreenWidth())),
			f32(rl.GetRandomValue(0, rl.GetScreenHeight())),
			f32(rl.GetRandomValue(10, 100)),
			f32(rl.GetRandomValue(10, 100)),
		}
	}
	count^ = MAX_BOXES
}

update_dirty_lights :: proc(
	boxes: ^[MAX_BOXES]rl.Rectangle,
	boxCount: ^int,
	light_mask: rl.RenderTexture,
) {
	// Update the lights and keep track if any were dirty so we know if we need to update the master light mask
	dirtyLights := false
	for i := 0; i < MAX_LIGHTS; i += 1 {
		if update_light(i, boxes, boxCount) do dirtyLights = true
	}
	// Update the light mask
	if (dirtyLights) {
		// Build up the light mask
		rl.BeginTextureMode(light_mask)

		rl.ClearBackground(rl.BLACK)

		// Force the blend mode to only set the alpha of the destination
		gl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
		gl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

		// Merge in all the light masks
		for i := 0; i < MAX_LIGHTS; i += 1 {
			if lights[i].active do rl.DrawTextureRec(lights[i].mask.texture, rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), -f32(rl.GetScreenHeight())}, rl.Vector2(0), rl.WHITE)
		}

		// gl.DrawRenderBatchActive()

		// Go back to normal blend
		gl.SetBlendMode(i32(rl.BlendMode.ALPHA))
		rl.EndTextureMode()
	}
}

draw_lighting :: proc(
	boxes: ^[MAX_BOXES]rl.Rectangle,
	boxCount: ^int,
	lightMask: rl.RenderTexture,
	backgroundTexture: rl.Texture2D,
) {
	// Draw the tile background
	rl.DrawTextureRec(
		backgroundTexture,
		rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
		rl.Vector2(0),
		rl.WHITE,
	)
	// Overlay the shadows from all the lights
	rl.DrawTextureRec(
		lightMask.texture,
		rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(-rl.GetScreenHeight())},
		rl.Vector2(0),
		rl.ColorAlpha(rl.WHITE, show_lines ? 0.75 : 1.0),
	)
	// Draw the lights
	for i := 0; i < MAX_LIGHTS; i += 1 {
		if lights[i].active do rl.DrawCircle(i32(lights[i].position.x), i32(lights[i].position.y), 5, (i == 0) ? rl.YELLOW : rl.WHITE)
	}
	if (show_lines) {
		for s := 0; s < 4; s += 1 {
			// rl.DrawTriangleFan(&lights[0].shadows[s].vertices[s], 4, rl.DARKPURPLE)
		}

		for b := 0; b < boxCount^; b += 1 {
			if rl.CheckCollisionRecs(boxes^[b], lights[0].bounds) do rl.DrawRectangleRec(boxes^[b], rl.BLACK)

			rl.DrawRectangleLines(
				i32(boxes^[b].x),
				i32(boxes^[b].y),
				i32(boxes^[b].width),
				i32(boxes^[b].height),
				rl.DARKBLUE,
			)
		}
		rl.DrawText("(F1) Hide Shadow Volumes", 10, 50, 10, rl.GREEN)
	} else {
		rl.DrawText("(F1) Show Shadow Volumes", 10, 50, 10, rl.GREEN)
	}
}

handle_window_resize :: proc() {
	backgroundTexture = backgroundTexture
	img: rl.Image = rl.GenImageColor(rl.GetRenderWidth(), rl.GetRenderHeight(), rl.DARKGRAY)
	backgroundTexture = rl.LoadTextureFromImage(img)
	// backgroundTexture := backgroundTexture
	rl.UnloadImage(img)

}
