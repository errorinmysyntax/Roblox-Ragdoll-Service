# SimpleRagdollService

A modular ragdoll system for Roblox (R6 + R15) with configurable joint limits, script management during ragdoll, smooth recovery, and network ownership handling.

Designed for other developers to drop into their game and call `Ragdoll()` / `Unragdoll()` on characters.

## Versioning

The module exposes `SimpleRagdollService.VERSION` (currently `2.0.0`). Treat releases/tags as the source of truth when you publish to GitHub.

## Requirements

- Roblox server runtime (this module uses network ownership APIs)
- Characters with a `Humanoid` (R6 or R15)

## Install

### Option A: Manual (Roblox Studio)

1. Copy `src/SimpleRagdollService.lua` into a `ModuleScript` named `SimpleRagdollService`.
2. Put it somewhere server code can require it (commonly `ServerScriptService` or `ReplicatedStorage`).

### Option B: Rojo

This repo includes `default.project.json` so you can build a `.rbxm` containing the ModuleScript:

```sh
rojo build default.project.json -o SimpleRagdollService.rbxm
```

Then import the `.rbxm` into Studio and move `SimpleRagdollService` where you want it.

## Super Simple Player Test (kid-friendly)

If you want players to test it without any setup, the easiest option is to publish a Roblox “demo place” and put the link here.

This repo also includes ready-to-drop demo scripts in `examples/`:

1. Put the module `SimpleRagdollService` in `ReplicatedStorage`.
2. Copy `examples/ServerScriptService/RagdollTest.server.lua` into `ServerScriptService`.
3. Copy `examples/StarterPlayer/StarterPlayerScripts/RagdollButton.client.lua` into `StarterPlayerScripts`.
4. Play: press `R` to toggle ragdoll (2s cooldown). You can also click the on-screen button.

## Usage (server)

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimpleRagdollService = require(ReplicatedStorage:WaitForChild("SimpleRagdollService"))
local ragdollService = SimpleRagdollService.new({
	stiffnessMultiplier = 1.0,
	-- scriptsToDisable = { "Animate" },
})

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.delay(2, function()
			-- Ragdoll for 1 second, then recover
			ragdollService:Ragdoll(character)
			task.delay(1, function()
				ragdollService:Unragdoll(character)
			end)
		end)
	end)
end)
```

## Usage (with RemoteEvent)

If you let clients request ragdolls, validate on the server (cooldowns, permissions, and that `character` belongs to the player).

## API

- `SimpleRagdollService.new(config?)` -> service instance
- `service:IsRagdolled(character)` -> boolean
- `service:Ragdoll(character)` -> `(ok: boolean, err: string?)`
- `service:Unragdoll(character)` -> `(ok: boolean, err: string?)`
- `service:Toggle(character, enabled?)` -> `(ok: boolean, err: string?)`

## Configuration

You can pass a partial config table to `new()`; anything omitted uses defaults.

- `scriptsToDisable`: `{string}` names of character scripts to disable while ragdolled (default `{}`)
- `stiffnessMultiplier`: `number` from `0.1` to `5.0` (default `1.0`)
- `hotbarLockReason`: `string?` set a reason to lock tools/hotbar during ragdoll (default `nil`)
- `recoveryLiftOffset`: `number` (default `1.15`)
- `recoveryBlendDuration`: `number` seconds (default `0.24`)
- `recoveryMobilityLock`: `number` seconds (default `0.3`)

For advanced tuning (limits, collision behavior, attachment/socket names), see `DEFAULT_CONFIG` in `src/SimpleRagdollService.lua`.

## Notes

- Intended to be required and run on the server (it uses network ownership APIs).
- Works best when you treat ragdoll as an authoritative server state (clients can request it, but server decides).
- If you store the module in `ServerScriptService`, just change the `require(...)` path in the examples.

## License

MIT (see `LICENSE`).
