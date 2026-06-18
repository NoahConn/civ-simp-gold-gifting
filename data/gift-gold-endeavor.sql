-- ============================================================================
-- Civ Simp Gold Gifting: endeavor definition (Phase 1, flat values)
-- ============================================================================
--
-- STATUS: TEMPLATE. The identifiers wrapped in << >> below are schema specific
-- and MUST be replaced with the real table/column names used by 1.4.0. They are
-- intentionally written as invalid tokens so this file fails loudly rather than
-- loading a wrong guess silently.
--
-- HOW TO FILL THIS IN:
--   1. Open  <CivInstall>/Base/Modules  and find the module that defines the
--      existing cooperative endeavors (the data folder inside it).
--   2. Find how an endeavor type is declared, how an effect transfers Gold
--      between players, and how a relationship value is adjusted.
--   3. Replace every << TOKEN >> with the confirmed name, and delete this header
--      once the file loads cleanly in a new game.
--
-- Phase 1 behaviour: initiator picks a target and an amount of Gold; Gold moves
-- from initiator to target; a FLAT relationship improvement is applied to both
-- directions of the pair. No scaling. No third party war penalty (that is Phase 2).
-- ============================================================================


-- 1) Register the new endeavor type ------------------------------------------
-- Most Civ 7 content first declares a Type row, then references it everywhere.

INSERT INTO Types (Type, Kind)
VALUES ('ENDEAVOR_GIFT_GOLD', '<<KIND_ENDEAVOR>>');
-- ^ VERIFY: confirm the Kind value used by base endeavors (e.g. the endeavor /
--   diplomatic-action kind enum), and confirm Types is the right table.


-- 2) Define the endeavor itself ----------------------------------------------
-- Insert into whatever table the base game uses to define endeavors, wiring in
-- the name/description LOC tags from text/en_us/gift-gold-text.sql.

INSERT INTO <<ENDEAVOR_DEFINITION_TABLE>>
  (EndeavorType, Name, Description, <<COST_OR_INFLUENCE_COLUMNS>>)
VALUES
  ('ENDEAVOR_GIFT_GOLD',
   'LOC_ENDEAVOR_GIFT_GOLD_NAME',
   'LOC_ENDEAVOR_GIFT_GOLD_DESCRIPTION',
   <<COST_OR_INFLUENCE_VALUES>>);


-- 3) Gold transfer effect ----------------------------------------------------
-- Find the effect type the base game uses to move Gold to/from a player's
-- treasury (look for something like an ADJUST_PLAYER_GOLD / yield effect), and
-- bind it so the chosen amount leaves the initiator and arrives at the target.

INSERT INTO <<EFFECT_TABLE>>
  (EffectType, <<EFFECT_ARG_COLUMNS>>)
VALUES
  ('<<EFFECT_TRANSFER_GOLD>>', <<EFFECT_ARG_VALUES>>);


-- 4) Relationship improvement effect -----------------------------------------
-- Find the effect/modifier the base game uses to change a relationship score
-- between two leaders. Apply a flat positive amount to both directions.

INSERT INTO <<EFFECT_TABLE>>
  (EffectType, <<EFFECT_ARG_COLUMNS>>)
VALUES
  ('<<EFFECT_ADJUST_RELATIONSHIP>>', <<RELATIONSHIP_FLAT_AMOUNT>>);


-- 5) Attach effects to the endeavor ------------------------------------------
-- Whatever the base game's pattern is for binding effects/modifiers to an
-- endeavor type, replicate it so the two effects above fire when this endeavor
-- resolves.

-- <<BIND ENDEAVOR_GIFT_GOLD -> the gold transfer + relationship effects>>


-- ----------------------------------------------------------------------------
-- LOAD TEST (optional, use while bringing the mod up):
-- Before any of the above is correct, you can prove the file parses and applies
-- by making ONE trivial change to a table you have confirmed exists in the base
-- modules, then checking it shows up in a new game. Replace the line below with
-- a confirmed table/column, run a new game, then remove it.
--
-- UPDATE <<SOME_CONFIRMED_TABLE>> SET <<COLUMN>> = <<VALUE>> WHERE <<KEY>> = <<X>>;
-- ----------------------------------------------------------------------------
