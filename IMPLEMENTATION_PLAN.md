# Dicero Recreation — Implementation Plan

Dependency-ordered, small build steps. Each step has three parts: a **Description** of what is built, a copy-ready **AI Prompt** (in a code block), and **Verify** checks. Numbers are placeholders to be tuned later.

> Legend: `[ ]` pending, `[~]` in progress, `[x]` done.

---

## [ ] Step 1 — Scaffold & conventions

**Description:** Project skeleton, `Loader` (requires all modules in a folder), `Remotes` registry, `Types` aliases, service/UI stubs each with `init`/`start`.

**AI Prompt:**
```text
Create the Rojo folder structure and module conventions: Shared/Loader, Shared/Remotes, Shared/Types, empty Config/ and Logic/ folders, server Services/ stubs, and client Util/, Controllers/, UI/ stubs. Wire init.server.luau and init.client.luau to require and bootstrap them in order.
```

**Verify:** `rojo build -o build.rbxlx` succeeds; on play, server and client bootstrap logs list all loaded modules with no require errors.

## [ ] Step 2 — Config data (placeholders)

**Description:** Pure data modules defining all game content and tunables.

**AI Prompt:**
```text
Fill Shared/Config modules: Rarities, Slots, Gear, Talents, Traits, Enemies, Chapters (3x5, boss on last stage), Currencies, Balance. Use placeholder values.
```

**Verify:** A scratch script requires each module and prints counts/sample lookups matching expectations (5 rarities, 6 slots, 3 chapters × 5 stages, boss flagged last).

## [ ] Step 3 — Pure combat logic

**Description:** Deterministic, side-effect-free combat math + `LootTable` helper.

**AI Prompt:**
```text
Implement Shared/Logic/DiceHands (best hand + multiplier for 1-5 dice) and DamageFormula (player damage ordering + incoming-damage resolution). Add a test script covering every hand and formula ordering including crit.
```

**Verify:** Test script asserts: each hand type detected & multiplied correctly; five-of-a-kind=8x; straight/full house require 5 dice; `(base+flat)*(1+pct)*mult*crit` matches; incoming order DR→shield→HP with overflow.

## [ ] Step 4 — DataService & schema

**Description:** Authoritative persistence layer other services depend on.

**AI Prompt:**
```text
Implement DataService: default PlayerData per Types, DataStore load with session lock, mutate accessors, autosave interval + on leave. Support Studio mock.
```

**Verify:** New player gets default profile; a mutation persists across rejoin; session lock prevents double-load; logs confirm autosave.

## [ ] Step 5 — Menu shell + responsive scaling

**Description:** Menu container, tab bar, tab switching, scaling utilities, asset resolver stub.

**AI Prompt:**
```text
Build Util/Responsive, Util/UIFactory, Util/AssetResolver, and UI/MenuShell: a ScreenGui with three bottom tabs (Equipment, Battle, Talents) and switching. Make it responsive for phone and desktop.
```

**Verify:** Tabs switch on click/tap; layout adapts when emulating phone vs desktop; only one tab visible at a time.

## [ ] Step 6 — Equipment tab

**Description:** Full equipment UI + server-side equip/unequip + slot-level display.

**AI Prompt:**
```text
Build UI/EquipmentTab: a ViewportFrame character rig with idle animation, 6 slots (icon + slot level) positioned around it, an unequipped gear grid (rarity-descending, icons only), and a detail popup (stats, X, Equip/Unequip). Wire EquipGear/UnequipGear remotes through InventoryService.
```

**Verify:** Equipping moves gear from grid to slot and updates stats; unequip reverses; popup shows Equip vs Unequip correctly; grid stays rarity-sorted; changes persist.

## [ ] Step 7 — Talents tab

**Description:** Talent display + authoritative rarity-weighted roll with coin cost.

**AI Prompt:**
```text
Build UI/TalentsTab and TalentService: list all talents with level + rarity; a Roll Talent button that spends coins and rarity-weighted +1s a talent.
```

**Verify:** Roll deducts coins, increments one talent, persists; rarer talents roll less often over many samples; insufficient coins blocks roll.

## [ ] Step 8 — Battle tab

**Description:** Chapter selection UI reflecting progress.

**AI Prompt:**
```text
Build UI/BattleTab: show current chapter with a Start Battle button; clicking the level opens a scrollable chapter list (up=locked upcoming, down=beaten). Start Battle calls StartBattle.
```

**Verify:** Current chapter matches profile; list scroll shows locked vs beaten correctly; Start Battle triggers combat entry.

## [ ] Step 9 — CombatService state machine

**Description:** The authoritative combat engine.

**AI Prompt:**
```text
Implement CombatService: chapter/stage/turn flow, spawn 1-3 enemies (boss on last stage), dice roll/lock/reroll (3 base), hand eval + damage via Logic, enemy weighted actions, incoming-damage order (dodge -> DR -> shield -> HP), crit, deaths, per-chapter XP from kills + dice unlock, HP carryover, stage advance, chapter completion + rewards, death -> menu. Replicate CombatStateUpdated/CombatEnded.
```

**Verify:** A server-only simulation plays a full 5-stage chapter: enemies die, stages advance, dice unlock as per-chapter level rises, HP carries over, boss on stage 5, completion grants rewards, death ends run.

## [ ] Step 10 — Combat UI

**Description:** Player-facing combat interface bound to replicated state.

**AI Prompt:**
```text
Build UI/CombatUI + CombatController: render dice with lock toggles and a reroll button (shows rerolls left), enemy selection + attack, player/enemy HP + shield bars, current hand/multiplier feedback, and victory/defeat screens.
```

**Verify:** A full battle is playable via UI end-to-end; UI matches server state exactly; locks/rerolls/targeting behave per rules.

## [ ] Step 11 — Pick-3 traits at 5 dice

**Description:** Battle-only trait draft.

**AI Prompt:**
```text
When a run reaches 5 active dice, have CombatService send TraitOffer (3 random traits); apply the chosen trait for the current battle only. Add the pick UI in CombatUI.
```

**Verify:** Offer triggers exactly once at 5 dice; chosen trait's effect applies during the battle and clears at battle end.

## [ ] Step 12 — Global level & rewards

**Description:** Persistent account progression.

**AI Prompt:**
```text
Implement GlobalLevelService: grant global XP on chapter completion/milestones, level-ups grant stat increases, talent-roll grants, and permanent starting-dice upgrades. Reflect starting dice at chapter entry in CombatService.
```

**Verify:** Completing a chapter grants global XP/level; a starting-dice upgrade makes the next run begin with more pre-unlocked dice (still capped at 5).

## [ ] Step 13 — Economy: chest/shop + slot leveling

**Description:** Currency flows, chest loot, slot leveling.

**AI Prompt:**
```text
Implement ChestService (single chest, 1 key = 1 loot roll, spin-all when keys>1, weighted LootTable), CurrencyService mutations, and InventoryService.LevelSlot (spend materials). Add minimal shop/chest UI. Stub ShopService for gamepasses/Robux/daily.
```

**Verify:** Opening consumes keys and grants loot; spin-all consumes all keys; leveling a slot spends materials and increases that slot's buff; balances persist.

## [ ] Step 14 — Leaderboards

**Description:** Extensible leaderboard system + two seeded stats.

**AI Prompt:**
```text
Implement LeaderboardService (generic OrderedDataStore by stat name) and submit highestChapter and highestPlayerLevel; add a simple display.
```

**Verify:** Stats submit and read back ranked; values update as the player progresses.

## [ ] Step 15 — Polish & swap-path pass

**Description:** Consistent placeholder resolution + future-proofing.

**AI Prompt:**
```text
Finalize AssetResolver logical-id mapping, add extensibility hooks for daily shop/gamepasses, and clean up placeholders.
```

**Verify:** All visuals resolve through `AssetResolver`; no real asset ids are hard-coded; swapping a logical id changes visuals without touching UI logic.
