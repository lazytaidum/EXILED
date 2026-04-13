# Sturdy Services Snapshot

This is a short handoff for the current `sturdy`-style server service setup in EXILED.

## What exists right now

Boot order from [src/server/Boot.server.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Boot.server.luau):

1. `RemoteRegistry`
2. `PlayerService`
3. `CharacterService`
4. `SpawnService`
5. `ObjectiveService`
6. `InteractionService`
7. `EntityService`
8. `EscapeService`
9. `RoundManager`

Each service is loaded, added into a shared `Services` table, then run through:

- `Init(Services)`
- `Start()`

## Service map

### `RemoteRegistry`

File: [src/server/Services/RemoteRegistry.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/RemoteRegistry.luau)

- Ensures `ReplicatedStorage.Shared.Remotes` exists.
- Ensures core remotes exist from [src/shared/Constants/RemoteNames.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/shared/Constants/RemoteNames.luau).
- Main job: central remote lookup via `GetRemote(name)`.

Current remotes in code:

- `RoundStateChanged`
- `RoundTimerUpdated`
- `RequestInteract`
- `InteractionStateChanged`

Status:

- Stable enough for current boot flow.
- Additional remotes are still in progress.

### `PlayerService`

File: [src/server/Services/PlayerService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/PlayerService.luau)

- Tracks per-player runtime state in `PlayerStates`.
- Handles `PlayerAdded` and `PlayerRemoving`.
- Exposes:
  - `GetPlayerState(player)`
  - `GetPlayers()`
  - `SetAlive(player, isAlive)`

Current tracked state:

- `IsAlive`
- `HasEscaped`
- `IsLoaded`

Status:

- Lightweight and working.
- Persistence / richer player state is in progress.

### `CharacterService`

File: [src/server/Services/CharacterService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/CharacterService.luau)

- Wraps Roblox character models with `BaseCharacter`.
- Tracks characters by player and by model.
- Connects to `CharacterAdded`, `CharacterRemoving`, and humanoid death.
- Applies round-phase state when characters spawn.

Main responsibilities:

- Register / remove characters cleanly.
- Mark players alive or dead through `PlayerService`.
- Notify `RoundManager` when an active player dies.
- Support freeze / unfreeze behavior.

Important paired class:

- [src/server/Classes/BaseCharacter.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Classes/BaseCharacter.luau)

Current features in `BaseCharacter`:

- Freeze / unfreeze
- Invincibility toggle
- Speed multipliers
- Temporary haste on hit
- Damage application

Status:

- Core character wrapper is in place.
- More character-specific systems are in progress.

### `SpawnService`

File: [src/server/Services/SpawnService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/SpawnService.luau)

- Teleports players between lobby and reception spawns.
- Depends on workspace parts under:
  - `Workspace.Spawns.LobbySpawn`
  - `Workspace.Spawns.ReceptionSpawns`

Main functions:

- `TeleportPlayerToLobby`
- `TeleportPlayerToReception`
- bulk teleport helpers for groups / all players

Status:

- Functional for current round flow.
- Spawn rules, weighting, and map-specific handling are in progress.

### `ObjectiveService`

File: [src/server/Services/ObjectiveService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/ObjectiveService.luau)

- Builds objective objects from `Workspace.Objectives`.
- Uses shared definitions from [src/shared/Data/ObjectiveDefinitions.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/shared/Data/ObjectiveDefinitions.luau).
- Wraps instances with `BaseObjective`.

Main functions:

- `GetObjectives()`
- `GetObjectivesByPhase(phase)`
- `SetPhaseEnabled(phase, enabled)`
- `ResetObjectives()`
- `TryProgressObjectiveByName(name, amount)`
- `ProgressObjective(objective, amount)`

Current shipped objective data:

- `TestObjective`

Important paired class:

- [src/server/Classes/BaseObjective.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Classes/BaseObjective.luau)

Status:

- Core objective registration and progress loop support are working.
- Final objective list, phase rules, and map content are in progress.

### `InteractionService`

File: [src/server/Services/InteractionService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/InteractionService.luau)

- Handles player interaction start / stop requests.
- Owns `ActiveInteractions`.
- Runs a short update loop every `0.1` seconds.
- Talks to clients through remotes.

Current behavior:

- Only allows interactions during `Reception`.
- Finds the nearest valid interactable objective within `12` studs.
- Slows the player while interacting.
- Sends `Start`, `Update`, `Stop`, and `Complete` state updates to the client.
- Stops interaction if:
  - the target completes
  - the player moves too far away
  - the player takes damage from an entity
  - the round phase changes

Dependencies:

- `RemoteRegistry`
- `CharacterService`
- `ObjectiveService`
- `RoundManager`

Status:

- Core interaction loop is working.
- More interactable types beyond objectives are in progress.

### `EntityService`

File: [src/server/Services/EntityService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/EntityService.luau)

- Registers entities from `Workspace.Entities`.
- Uses shared definitions from [src/shared/Data/EntityDefinitions.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/shared/Data/EntityDefinitions.luau).
- Wraps entity models with `BaseEntity`.
- Runs an update loop every `0.2` seconds.

Current behavior:

- Finds the nearest active player character.
- Assigns target player.
- Moves toward players if the entity has the `Chase` attribute.
- Damages players in range.
- Interrupts interactions on successful hit.
- Resets entities to spawn when deactivated.

Current shipped entity data:

- `TestEntity`

Important paired class:

- [src/server/Classes/BaseEntity.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Classes/BaseEntity.luau)

Status:

- Basic hostile entity loop is in place.
- Variety, spawning rules, and advanced AI are in progress.

### `EscapeService`

File: [src/server/Services/EscapeService.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Services/EscapeService.luau)

- Watches `Workspace.EscapeZone`.
- Uses touch events to detect escape attempts.
- Only allows escaping during active `Reception`.

Current behavior:

- Debounces touches per player.
- Verifies the player is active and alive.
- Marks the player escaped through `RoundManager`.
- Freezes the escaped character.
- Moves them to `CFrame.new(0, -1000, 0)` as a temporary extraction method.

Status:

- Escape flow works for testing.
- Final extraction handling / polish is in progress.

### `RoundManager`

File: [src/server/Managers/RoundManager.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/server/Managers/RoundManager.luau)

- Orchestrates the game loop and phase transitions.
- Tracks active round roster and per-round player state.
- Controls entity activation, teleports, freeze/invincible state, and round end conditions.

Current phase flow:

1. `Lobby`
2. `Voting`
3. `Preparation`
4. `Reception`
5. `Results`

Current test durations from [src/shared/Data/RoundConfig.luau](C:/Users/lazyt/Development/Rojo/EXILED/src/shared/Data/RoundConfig.luau):

- `IntermissionDuration = 5`
- `VotingDuration = 5`
- `PreparationDuration = 5`
- `ReceptionDuration = 20`
- `ResultsDuration = 5`

Round outcome rules currently implemented:

- Majority escape threshold: `floor(activePlayers / 2) + 1`
- If enough players escape: `RemnantsWin`
- If no active players remain and nobody escaped: `EntitiesWin`
- If timer expires while players are still alive: `Draw`

Status:

- Core round loop is working for prototype flow.
- Voting logic, polish, and final balance values are in progress.

## Workspace things the services expect

These are required by the current server code:

- `Workspace.Spawns.LobbySpawn`
- `Workspace.Spawns.ReceptionSpawns`
- `Workspace.Objectives`
- `Workspace.Entities`
- `Workspace.EscapeZone`

If any of these are missing, boot will stall on `WaitForChild(...)`.

## Current prototype content

At the moment the project appears to be using placeholder content:

- `TestObjective`
- `TestEntity`
- short round timings for testing
- temporary escape extraction position

## In progress / safe to revisit later

These feel intentionally changeable and are good to treat as temporary:

- Final service API shape
- More remotes
- Real objective catalog
- Real entity catalog
- Voting system details
- Spawn rules and map-specific setup
- Escape presentation / cutscene flow
- Balance numbers
- Player persistence / progression

Recommendation for next week:

- Update this doc whenever a placeholder name becomes a real system name.
- Keep blank or unknown details marked as `In Progress` rather than filling them with guesses.
