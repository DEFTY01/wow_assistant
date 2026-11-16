-- Drop chances for dungeon loot, and quest rewards as a second kind of loot source.
ALTER TABLE loot ADD COLUMN drop_pct REAL;                          -- NULL = unknown
ALTER TABLE loot ADD COLUMN source TEXT NOT NULL DEFAULT 'dungeon'; -- dungeon | quest
ALTER TABLE loot ADD COLUMN side INTEGER NOT NULL DEFAULT 0;        -- quests: 1 Alliance, 2 Horde, 0 both
ALTER TABLE loot ADD COLUMN quest_level INTEGER;                    -- level needed to take the quest
ALTER TABLE dungeons ADD COLUMN kind TEXT NOT NULL DEFAULT 'dungeon';
