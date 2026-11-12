-- Dungeon loot imported from the Wowhead Forever zone pages.
CREATE TABLE dungeons (
  zone_id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  min_level INTEGER NOT NULL DEFAULT 0,   -- 0 = unknown (new Forever dungeons)
  max_level INTEGER NOT NULL DEFAULT 0,
  req_level INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE loot (
  item_id INTEGER NOT NULL,
  zone_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  quality INTEGER NOT NULL,
  item_level INTEGER NOT NULL,
  req_level INTEGER NOT NULL,
  slot INTEGER NOT NULL,        -- Wowhead inventory type
  item_class INTEGER NOT NULL,  -- 2 weapon, 4 armor
  subclass INTEGER NOT NULL,
  boss TEXT,
  stats TEXT NOT NULL,          -- JSON of Wowhead jsonequip numbers
  PRIMARY KEY (item_id, zone_id)
);
CREATE INDEX idx_loot_zone ON loot (zone_id);
