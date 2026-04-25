# EXILED Roadmap

Source board: `C:\Users\lazyt\Downloads\lMWWVyay - exiled-developer-board.json`

Last updated: 2026-04-25

## Description

EXILED is an 11-player asymmetrical survival horror game built around
Receptions. Remnants complete objectives, survive Entities, fight back when they
can, and escape or suppress the threat.

The Trello board is the full creative/content bible. This roadmap is the simple
implementation checklist.

## Prototype Foundations

- [x] Class/data modules for Remnants, Entities, Weapons, Items, Objectives, Status Effects, and Round config.
- [x] Input mapping and action resolution.
- [x] Movement system: walking, sprinting, running, stamina, fatigue, crouch, and aim movement.
- [x] Entity AI framework: perception, sight checks, chase, scout, attacks, pathing, and movement smoothing.
- [x] Combat foundations.
- [x] Weapon pickups and weapon lab testing.
- [x] Status effect service and status HUD support.
- [x] Interaction framework and interactable debug tools.
- [x] Round skeleton: lobby, voting, preparation, reception, results.
- [x] Developer/debug tools.
- [x] Fix missing or mismatched shared modules/enums.
- [ ] Add a repeatable build and playtest checklist.
- [ ] Confirm animation hooks.
- [ ] Confirm SFX hooks.
- [ ] Convert debug-only flows into player-facing flows where needed.

## Core Reception Loop

- [x] Create a tiny test Reception map.
- [x] Add reliable spawn points.
- [x] Add one complete objective.
- [x] Add one escape/win interaction.
- [x] Add entity navigation coverage to the test map.
- [ ] Finalize round start and return-to-lobby flow.
- [ ] Finalize voting flow.
- [ ] Finalize preparation phase.
- [ ] Finalize active Reception timer and state flow.
- [x] Finalize win/loss resolution.
- [ ] Add results screen data.
- [ ] Add temporary reward stubs.
- [ ] Add match outcome logging/debug output.

## Remnant Systems

- [ ] Choose the first vertical-slice Remnant.
- [x] Implement Remnant health states.
- [x] Implement damage feedback.
- [x] Implement injured/shattered presentation.
- [x] Implement healing.
- [x] Implement self-healing.
- [x] Implement recovery.
- [x] Implement death and elimination.
- [ ] Implement Remnant abilities for the first test Remnant.
- [x] Implement Remnant HUD basics.
- [x] Implement stamina, health, objective, status effect, prompt, and inventory HUD elements.
- [ ] Implement communication menu basics.
- [ ] Implement backpack.
- [ ] Implement radial tools.
- [ ] Implement materials and ammo storage.
- [ ] Implement inventory limits.

## Entity Systems

- [ ] Lock entity movement feel after the anti-psychic targeting pass.
- [ ] Add heartbeat/terror-radius feedback.
- [ ] Add entity warning presentation.
- [x] Implement entity health.
- [x] Implement suppression.
- [ ] Implement stun/counterplay.
- [ ] Implement entity reward hooks.
- [ ] Tune chase readability.
- [ ] Tune lost-sight behavior.
- [ ] Tune patrol/scout behavior.
- [ ] Add entity SFX pass.
- [ ] Add entity animation pass.
- [ ] Lock one to three Entities for the first vertical slice.

## Objectives And Interactions

- [x] Fix objective enum/source consistency.
- [x] Implement first full objective chain.
- [x] Add objective progress.
- [x] Add objective interruption.
- [x] Add objective feedback.
- [ ] Add objective phase rules.
- [ ] Add co-op objective behavior.
- [ ] Add proficiency and deficiency modifiers.
- [x] Add vaults.
- [x] Add doors.
- [ ] Add wedges.
- [ ] Add environmental hazards.
- [ ] Add crates and chests.
- [ ] Add pickups and map item spawning.
- [ ] Add noise events.
- [ ] Add blood/soul pools or equivalent chase traces.

## Combat, Tools, And Items

- [ ] Tune gun damage.
- [ ] Tune melee damage.
- [ ] Tune reloads.
- [ ] Tune recoil.
- [ ] Tune spread.
- [ ] Tune critical hits.
- [ ] Add durability.
- [ ] Add ammo economy.
- [ ] Add tool charges.
- [ ] Add tool crafting.
- [ ] Add material pickups.
- [ ] Add first-pass item spawn rules.
- [ ] Add first-pass combat UI feedback.
- [ ] Add hit confirmation feedback.
- [ ] Add weapon SFX pass.
- [ ] Add weapon animation pass.

## Lobby And UI

- [ ] Create test lobby area.
- [ ] Add lobby timer display.
- [ ] Add inventory UI.
- [ ] Add Remnant menu.
- [ ] Add bestiary UI.
- [ ] Add settings UI.
- [ ] Add profile UI.
- [ ] Add tracked stats UI.
- [ ] Add store button/flow.
- [ ] Add Azazel/Nebueil shop area.
- [ ] Add shopkeeper dialogue.
- [ ] Add shop UI.
- [ ] Add purchase button flow.
- [ ] Polish prompts.
- [ ] Polish status HUD.
- [ ] Polish round HUD.
- [ ] Polish results UI.

## Progression And Economy

- [ ] Add player leveling.
- [ ] Add medals.
- [ ] Add score events.
- [ ] Add Reception rewards.
- [ ] Add currencies.
- [ ] Add codes.
- [ ] Add gamepasses.
- [ ] Add career statistics.
- [ ] Add devotion.
- [ ] Add Remnant leveling.
- [ ] Add Constellation UI.
- [ ] Add Starpaths.
- [ ] Add Remnant prestige.
- [ ] Add Remnant mastery.
- [ ] Add mastery rewards.
- [ ] Add Essence slots.
- [ ] Add Essence point costs.
- [ ] Add Essence tiers.
- [ ] Add Mastery Shards.
- [ ] Add Catalysts.
- [ ] Add Refractions.
- [ ] Add daily rituals.
- [ ] Add weekly rituals.
- [ ] Add persistent DataStores for relevant player data.

## Content Expansion

- [ ] Add first official Remnant.
- [ ] Add first official Entity set.
- [ ] Add first official realm.
- [ ] Add first official objective set.
- [ ] Add first official relics.
- [ ] Add first official Essences.
- [ ] Add first official Catalysts.
- [ ] Add first official Refractions.
- [ ] Add starter Remnants.
- [ ] Add achievement Remnants.
- [ ] Add exclusive Remnants.
- [ ] Add tiered Entities.
- [ ] Add group Entities.
- [ ] Add Entity summons.
- [ ] Add Remnant summons.
- [ ] Add more realms.
- [ ] Add general achievements.
- [ ] Add Remnant achievements.
- [ ] Add Entity achievements.
- [ ] Add Tome/lore unlocks.
- [ ] Add item Refractions.
- [ ] Add Remnant Refractions.

## Testing And Release

- [ ] Solo internal test pass.
- [ ] Small-group internal test pass.
- [ ] Closed alpha.
- [ ] Tester-only code.
- [ ] Public stress test.
- [ ] Open alpha code.
- [ ] Data persistence audit.
- [ ] Balance pass.
- [ ] Accessibility pass.
- [ ] UI clarity pass.
- [ ] SFX clarity pass.
- [ ] Bug triage pass.
- [ ] Known issues list.
- [ ] Public beta.
- [ ] Open beta code.
- [ ] Final release polish.
- [ ] Public release.
- [ ] Day One code.
- [ ] Release code.
- [ ] Tester-exclusive rewards.

## Later / Do Not Rush

- [ ] Full Remnant roster.
- [ ] Full Entity roster.
- [ ] Full realm catalogue.
- [ ] Full Constellation randomness.
- [ ] Full mastery economy.
- [ ] Full relic library.
- [ ] Full catalyst library.
- [ ] Full refraction library.
- [ ] Full Essence library.
- [ ] Full achievement web.
- [ ] Full Tome/lore web.
- [ ] Large-scale shop expansion.
- [ ] Monetization polish.
