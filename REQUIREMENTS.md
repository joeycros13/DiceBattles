# Dicero Recreation — Requirements

Complete functional and design requirements for the first playable build. Numbers are **placeholders** to be tuned later; systems are the focus.

---

## 1. Platform & Technical

- **R-P1** Support PC and mobile (exclude console). UI must be responsive for both touch and mouse.
- **R-P2** UI is built entirely with vanilla Roblox `Instance`-based objects, created in code (no external UI framework).
- **R-P3** Built with Rojo 7.7.0, Luau. Source lives under `src/{shared,server,client}`.
- **R-P4** Single-player; one save per user.
- **R-P5** Server-authoritative: the server owns and validates all core state (combat, economy, progression, saves). The client only renders UI and requests actions.
- **R-P6** No sound, settings menu, or tutorials in v1.

## 2. Persistence

- **R-D1** Use DataStore to persist all progression: global level/XP, currencies, gear inventory, equipped gear, slot levels, talents, starting-dice upgrade, chapters completed / current chapter, leaderboard stats.
- **R-D2** Use session locking to prevent concurrent writes; autosave periodically and on leave.
- **R-D3** A new player receives a well-defined default profile.

## 3. Main Menu

- **R-M1** Bottom tabs: Equipment, Battle, Talents, Shop. Player can freely switch between them.
- **R-M2** Layout adapts to phone and desktop viewports.

### Equipment Tab
- **R-E1** Character shown as a real 3D rig in a `ViewportFrame` with an idle animation.
- **R-E2** Six equipment slots around the character: Left (top→bottom) Helmet, Weapon, Belt; Right (top→bottom) Charm, Chestplate, Boots.
- **R-E3** Each slot displays the equipped gear's icon and the **slot's level** (level is tied to the slot, not the gear piece).
- **R-E4** A grid (not list) shows all **unequipped** gear, sorted descending by rarity, showing icons only.
- **R-E5** Clicking any gear (grid or slot) opens a detail popup with all stats, an X (close) button, and an Equip button — or Unequip if already equipped.
- **R-E6** Rarities (low→high): Common, Uncommon, Rare, Epic, Legendary. Rarity scales the magnitude of the slot's buff.
- **R-E7** Each slot provides a specific buff type. Stat types: HP, attack, crit chance, dodge chance, damage reduction, heal amount.
- **R-E8** Slots level up by spending slot materials.

### Battle Tab
- **R-B1** Default view shows the player's current chapter with a Start Battle button.
- **R-B2** Clicking the level (not Start Battle) opens a scrollable list of all chapters: scroll up = upcoming (locked), scroll down = beaten.
- **R-B3** After beating a chapter, the default view advances to the next chapter.

### Talents Tab
- **R-T1** Shows all talents with their current level and rarity (all talents present from the start at level 0).
- **R-T2** A Roll Talent button costs coins; each roll picks one talent (weighted by rarity — rarer = less likely) and increases its level by 1.
- **R-T3** Talent levels are uncapped. All talents are passive, permanent effects.
- **R-T4** Talent effect categories (initial): flat attack, % attack, crit chance, extra reroll, extra dice (caps at level 4 = the 5th die), HP, lifesteal.

## 4. Combat — Structure

- **R-C1** Hierarchy: LEVEL (chapter) → STAGE → TURN. First build: 3 chapters × 5 stages each.
- **R-C2** Each stage spawns 1–3 enemies (random). The last stage of each chapter is a boss (more HP/attack; same action set for now).
- **R-C3** Player selects which enemy to attack; damage applies to the selected target.
- **R-C4** Any character/enemy at 0 HP dies. Player must kill all enemies in a stage to advance.
- **R-C5** Clearing the final stage completes the chapter, returns the player to the menu, and unlocks the next chapter.

## 5. Combat — Turn Loop

- **R-C6** Each turn: (1) player attacks one selected enemy; (2) each living enemy takes exactly one action; (3) return to player. Repeat until the stage is cleared.
- **R-C7** Enemy action is random: attack, heal (self only, flat), shield, or nothing. Enemies share behavior; only stats differ.

## 6. Combat — Dice System

- **R-C8** Dice faces are 1–6. Player starts with 1 die; **hard cap is 5** across all sources combined.
- **R-C9** At the start of each turn all dice re-randomize.
- **R-C10** The player can lock/unlock individual dice; a locked die persists locked for the whole turn (through rerolls) and auto-unlocks at the next turn's start.
- **R-C11** Base 3 rerolls per turn, modifiable by talents/traits. Rerolling re-rolls only unlocked dice.
- **R-C12** Hand multipliers: high card 1x, one pair 1.5x, two pair 2x, three of a kind 2.5x, straight 3x, full house 4x, four of a kind 5x, five of a kind 8x.
- **R-C13** Hands are evaluated on the current number of dice; hands requiring more dice than owned are unavailable (straight & full house need 5, four of a kind needs 4, etc.).

## 7. Combat — Damage & Resolution

- **R-C14** Player damage = `(dice total + flat & % bonuses from talents/equipment) × hand multiplier × (2 if crit)`. Crit is rolled once per attack, after the multiplier.
- **R-C15** Incoming enemy damage resolves in order: `% damage reduction → shield buffer → HP`. If a hit exceeds shield, the overflow carries to HP in the same hit.
- **R-C16** Dodge is a player-only stat that fully avoids an incoming enemy attack.
- **R-C17** Shield is a temporary HP buffer.
- **R-C18** Player has a single HP pool; all enemy attacks hit the player directly.

## 8. Combat — HP, Death, Leveling

- **R-C19** Player HP carries across all stages within a chapter (no per-stage refill).
- **R-C20** On player death: return to menu, chapter not completed, retry allowed.
- **R-C21** Per-chapter level is transient, resets on each chapter entry, and gains XP from killing enemies. Leveling unlocks additional dice up to the cap for that run.
- **R-C22** Global/account level persists, gains from chapter completions and milestones, and grants stat increases, talent rolls, and permanent starting-dice upgrades (begin a run with more of the 5 pre-unlocked).
- **R-C23** When the player has 5 active dice, offer a pick-3 of per-battle traits (temporary, current-battle only).

## 9. Economy

- **R-Y1** Currencies: coins (talent rolls), slot materials (slot leveling), gems (+Robux) for the shop/chest, keys (open chest).
- **R-Y2** One chest type; one key = one loot-table roll. When keys > 1, a "spin all" option is available.
- **R-Y3** Chest rolls yield a mix (gear, materials, coins, etc.) via a loot table.
- **R-Y4** For v1, all currencies may share the same source set (chapter completions / chests / purchases); per-currency tuning deferred.

## 10. Leaderboards

- **R-L1** Generic, extensible leaderboard system backed by OrderedDataStore, tracking arbitrary named stats.
- **R-L2** Seed with two stats: highest chapter reached, highest player (global) level.

## 11. Extensibility (architect room, not fully built in v1)

- **R-X1** Shop supporting gamepasses, Robux purchases, chests, and a daily shop.
- **R-X2** Additional leaderboard stats.
- **R-X3** Additional talent/trait effect categories, unique enemy behaviors, boss signature actions.
- **R-X4** Clean placeholder→real asset swap path (icons, meshes, animations).
