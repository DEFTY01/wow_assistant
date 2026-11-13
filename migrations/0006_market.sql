-- Item stats from the Blizzard item API, so gear that is not a dungeon drop (auction house,
-- crafted, already in your bags) can be scored by the same DPS model.
ALTER TABLE items ADD COLUMN slot TEXT;            -- Blizzard inventory type, NULL = not equippable
ALTER TABLE items ADD COLUMN item_class INTEGER;
ALTER TABLE items ADD COLUMN subclass INTEGER;
ALTER TABLE items ADD COLUMN req_level INTEGER;
ALTER TABLE items ADD COLUMN item_level INTEGER;
ALTER TABLE items ADD COLUMN quality TEXT;
ALTER TABLE items ADD COLUMN binding TEXT;
ALTER TABLE items ADD COLUMN stats TEXT;           -- JSON: agi, str, ap, crit, hit, weapon, classes

-- Everything fetched before this migration lacks the new columns: fetch it again.
UPDATE items SET api_status = NULL;

-- Cheapest buyout of fixed-stat gear you could equip, refreshed with the hourly price sync.
CREATE TABLE ah_gear (
  item_id INTEGER PRIMARY KEY,
  min_buyout INTEGER NOT NULL,
  listings INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);
