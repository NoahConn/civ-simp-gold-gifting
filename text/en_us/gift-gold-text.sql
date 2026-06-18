-- Civ Simp Gold Gifting: localized text
--
-- Civ 7 localization follows the Civ 6 pattern of inserting rows into the
-- LocalizedText table keyed by Tag + Language. Confirm the exact table and
-- column names against the base modules if the game logs a text load error,
-- but this is the standard shape.

INSERT INTO LocalizedText (Tag, Language, Text)
VALUES
  ('LOC_ENDEAVOR_GIFT_GOLD_NAME', 'en_US', 'Gift Gold'),
  ('LOC_ENDEAVOR_GIFT_GOLD_DESCRIPTION', 'en_US',
    'Send Gold directly to another leader as a gift. Improves your relationship with them.');
