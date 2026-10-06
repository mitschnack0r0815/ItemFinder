local _, ns = ...

-- The choices of the stat filter, in menu order. Edit freely:
--   - remove a line (or put -- in front) to hide that stat from the menu
--   - move lines to change the order
--   - add a line to show another stat
--
-- code   the game's stat key without "ITEM_MOD_" and "_SHORT", so ITEM_MOD_STAMINA_SHORT
--        becomes "STAMINA". Keys without that prefix stay as they are ("RESISTANCE0_NAME").
--        Type /itemfinder stats in game to list every code your saved items have.
-- label  optional; without it the menu shows the game's own (translated) name
--
-- Items always save all their stats, so changing this list never needs a rescan.

ns.STATS = {
	-- Primary stats
	{ code = "STAMINA" },
	{ code = "STRENGTH" },
	{ code = "AGILITY" },
	{ code = "INTELLECT" },
	{ code = "SPIRIT" },

	-- Armor and resistances
	-- { code = "RESISTANCE0_NAME", label = "Armor" },
	-- { code = "RESISTANCE2_NAME", label = "Fire Resistance" },
	-- { code = "RESISTANCE3_NAME", label = "Nature Resistance" },
	-- { code = "RESISTANCE4_NAME", label = "Frost Resistance" },
	-- { code = "RESISTANCE5_NAME", label = "Shadow Resistance" },
	-- { code = "RESISTANCE6_NAME", label = "Arcane Resistance" },

	-- Combat
	{ code = "ATTACK_POWER" },
	{ code = "SPELL_POWER" },
	{ code = "CRIT_RATING" },
	{ code = "HIT_RATING" },
	{ code = "DEFENSE_SKILL_RATING" },
	{ code = "MANA_REGENERATION" },
	{ code = "DAMAGE_PER_SECOND", label = "Weapon DPS" },
}
