# Dicero Recreation — Architecture

Full documentation of the game's systems, module organization, data structures, networking, and combat resolution. Server-authoritative; the client is a thin UI layer.

---

## 1. High-Level Overview

```
┌────────────────────────────── Roblox DataModel ──────────────────────────────┐
│ ReplicatedStorage/Shared   → config, pure logic, remotes, types (client+srv)  │
│ ServerScriptService/Server → authoritative services (owns all state + saves)  │
│ StarterPlayerScripts/Client→ UI views + controllers (render + request only)   │
└────────────────────────────────────────────────────────────────────────────┘
```

- **Client** never decides outcomes. It sends intent (e.g., "reroll", "attack enemy #2") and renders whatever the server replicates.
- **Server** validates every request against authoritative state, mutates it, persists via `DataService`, and replicates results.
- **Shared** holds data-only config, pure deterministic logic (safely reusable on both sides for prediction/validation), remote definitions, and Luau types.

## 2. Folder & Module Layout

```
src/
  shared/
    Loader.luau            -- requires all ModuleScripts in a folder; small DI helper
    Remotes.luau           -- declares & fetches RemoteEvents/Functions by name
    Types.luau             -- Luau type aliases (PlayerData, CombatState, etc.)
    Config/
      Rarities.luau        -- rarity order + multipliers
      Slots.luau           -- 6 slots + which stat each provides
      Gear.luau            -- gear definitions (id, slot, rarity, base stat)
      Talents.luau         -- talent defs (id, rarity, effect type, per-level value)
      Traits.luau          -- per-battle trait pool
      Enemies.luau         -- enemy archetypes (stats, action weights)
      Chapters.luau        -- chapters → stages → enemy composition, boss flag
      Currencies.luau      -- currency ids + metadata
      Balance.luau         -- tunable constants (base HP, rerolls, XP curves, caps)
    Logic/
      DiceHands.luau       -- detect best hand + multiplier for N dice
      DamageFormula.luau   -- player damage + incoming-damage resolution
      LootTable.luau       -- weighted roll helper
  server/
    init.server.luau       -- bootstraps services in dependency order
    Services/
      DataService.luau        -- profile load/save, session lock, autosave, defaults
      CurrencyService.luau    -- add/spend coins, gems, materials, keys
      InventoryService.luau   -- gear inventory, equip/unequip, slot levels
      TalentService.luau      -- talent rolls (coin cost, rarity-weighted +1)
      GlobalLevelService.luau -- global XP/level, stat & starting-dice grants
      CombatService.luau      -- per-player combat state machine
      ChestService.luau       -- key spend, loot rolls (single chest, spin-all)
      ShopService.luau        -- stub for gems/Robux/gamepass/daily (extensible)
      LeaderboardService.luau -- generic OrderedDataStore stat tracking
  client/
    init.client.luau       -- bootstraps UI + controllers
    Util/
      Responsive.luau      -- scaling helper for phone/desktop
      AssetResolver.luau   -- logical id → placeholder visual (swap path)
      UIFactory.luau       -- helpers to build common Instances
    Controllers/
      DataController.luau  -- mirrors replicated player data client-side
      CombatController.luau-- mirrors combat state, sends combat intents
    UI/
      MenuShell.luau       -- ScreenGui + 3 tabs + switching
      EquipmentTab.luau    -- ViewportFrame rig, slots, grid, detail popup
      BattleTab.luau       -- current chapter, level list, start
      TalentsTab.luau      -- talent list + roll
      CombatUI.luau        -- dice, lock/reroll, enemy select, HP bars, traits
```

## 3. Module Conventions

- Every service/UI module returns a table with an `init(deps)` (wire dependencies) and optional `start()` (begin runtime behavior) method. `init.server`/`init.client` call these in order.
- `Loader.luau` requires all children of a folder and returns a name→module map, so bootstrap files stay short and adding a module needs no bootstrap edits.
- Config modules are pure data (no side effects). Logic modules are pure functions (no `game` state), making them unit-testable and reusable on both client and server.

## 4. Networking

`Remotes.luau` centralizes all RemoteEvent/RemoteFunction names so client/server never mistype a string. Categories:

- **Request (client→server):** `StartBattle`, `RollDice`, `ToggleLockDie`, `Reroll`, `AttackEnemy`, `EquipGear`, `UnequipGear`, `LevelSlot`, `RollTalent`, `OpenChest`, `ChooseTrait`.
- **Replication (server→client):** `ProfileUpdated`, `CombatStateUpdated`, `CombatEnded`, `TraitOffer`, `Toast` (feedback).

Rules:
- Server validates: ownership, affordability, legal action for current phase, cooldowns.
- Server is the single source of truth for RNG (dice, loot, crit, dodge, enemy actions). Client RNG, if any, is cosmetic only.

## 5. Data Structures

### 5.1 PlayerData (persisted)
```
PlayerData = {
  version: number,
  global = { level: number, xp: number },
  currencies = { coins: number, gems: number, materials: number, keys: number },
  startingDiceUpgrade: number,        -- pre-unlocked dice at chapter entry (>=0)
  gear = { [gearUid]: { id: string, rarity: string } },  -- owned instances
  equipped = { [slotId]: gearUid? },  -- slotId → owned gear uid
  slotLevels = { [slotId]: number },  -- level tied to slot
  talents = { [talentId]: number },   -- talentId → level (0+)
  progress = { currentChapter: number, chaptersCompleted: number },
  stats = { [statName]: number },     -- leaderboard-tracked values
}
```

### 5.2 CombatState (server, transient, per player)
```
CombatState = {
  chapterId: number,
  stageIndex: number,
  phase: "PlayerTurn" | "EnemyTurn" | "TraitPick" | "Won" | "Lost",
  enemies: { { uid, archetype, hp, maxHp, shield }... },   -- 1..3
  player = { hp, maxHp, shield },
  perChapter = { level: number, xp: number },
  dice = { { value: number, locked: boolean }... },        -- length = unlockedDice
  unlockedDice: number,                                    -- capped at 5
  rerollsLeft: number,
  activeTraits: { traitId... },                            -- battle-only
}
```

## 6. Combat Resolution (authoritative)

**Player attack**
1. Base = sum of current dice face values.
2. Apply equipment + talent bonuses: flat adds, then % adds, to Base → Adjusted.
3. Multiply by the hand multiplier from `DiceHands`.
4. Roll crit once (crit chance stat); if crit, ×2.
5. Apply lifesteal (talent) to the player from final damage if present.
6. Subtract from selected enemy: overflow past shield hits HP.

`final = (Base + flat) * (1 + pct) * handMult * (crit and 2 or 1)`

**Incoming enemy damage on player**
1. Roll dodge (player dodge chance); if dodged, damage = 0.
2. Apply % damage reduction.
3. Subtract from shield first; overflow carries to HP in the same hit.

**Enemy turn:** each living enemy rolls a weighted action (attack/heal/shield/nothing). Heal is self-only flat; shield adds to that enemy's buffer.

**Turn cycle:** PlayerTurn → (attack resolves) → EnemyTurn (all enemies act) → dice re-randomize, rerolls reset, locks clear → next PlayerTurn. Stage clears when all enemies dead → per-chapter XP already granted per kill; advance stageIndex. Final stage cleared → chapter complete.

**Dice unlock:** on chapter entry, `unlockedDice = clamp(1 + startingDiceUpgrade, 1, 5)`. Per-chapter level-ups (from kills) increment `unlockedDice` up to 5. Reaching 5 active dice triggers a one-time `TraitPick` offer of 3 random traits.

## 7. Persistence & Sessions

- `DataService` loads a profile on join (with session lock), provides read/mutate accessors to other services, autosaves on an interval and on leave, and releases the lock. Combat state is **not** persisted (transient); only its durable results (currency, XP, chapter progress, dropped gear) are written back.
- A `version` field enables future migrations.

## 8. Leaderboards

- `LeaderboardService` wraps OrderedDataStore keyed by stat name (`lb_<statName>`), exposing `Submit(statName, userId, value)` and `GetTop(statName, count)`. Stat updates flow from gameplay events (chapter reached, level up). Seed stats: `highestChapter`, `highestPlayerLevel`. Adding a stat = one config entry + one submit call.

## 9. Economy Flow

- `CurrencyService` is the sole mutator of balances (add/spend with validation).
- `ChestService.OpenChest(count)` spends keys, performs `count` weighted `LootTable` rolls, and grants results via `CurrencyService`/`InventoryService`. "Spin all" = `count = keys`.
- `InventoryService.LevelSlot(slotId)` spends materials and raises `slotLevels[slotId]`, which scales that slot's equipped-gear buff.
- `ShopService` is a thin, extensible stub reserving room for gamepasses, Robux products, and a daily shop.

## 10. Placeholder → Real Asset Swap Path

- All visuals resolve through `AssetResolver` by logical id (e.g., `gear/weapon`, `rig/idle`). v1 returns placeholder colors/shapes/free icons. Swapping in real assets = updating the resolver map only; UI and gameplay code are untouched.

## 11. Extensibility Notes

- New gear/talent/trait/enemy/chapter = add a config entry; systems read config generically.
- New currency = add to `Currencies` config + `CurrencyService` handles it generically.
- New remote = add a name to `Remotes`; both sides fetch by key.
