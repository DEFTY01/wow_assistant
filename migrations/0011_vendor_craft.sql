-- Crafting to sell to a vendor: exact reagent costs need every auction, not just a summary.

-- Every buyout listing of the item, cheapest first: JSON [[unitPrice, quantity, whole], ...].
-- whole = 1 when the listing can only be bought as one stack (not a commodity).
ALTER TABLE prices ADD COLUMN book TEXT;
-- Quantity-weighted average unit price of all listings, ignoring ones over 3x the median.
ALTER TABLE prices ADD COLUMN avg_price INTEGER;

-- Vendor sell price according to the Wowhead Forever database, to cross-check the Blizzard API.
ALTER TABLE items ADD COLUMN wh_sell INTEGER;

-- Exact output range of a recipe (some make 1-3) and how it is learned (Wowhead source codes).
ALTER TABLE recipe_meta ADD COLUMN creates_min INTEGER;
ALTER TABLE recipe_meta ADD COLUMN creates_max INTEGER;
ALTER TABLE recipe_meta ADD COLUMN sources TEXT;
