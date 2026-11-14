-- Talent trees per class, imported from the Wowhead Forever talent calculator data.
CREATE TABLE talent_data (
  class_id INTEGER PRIMARY KEY,
  json TEXT NOT NULL,            -- { trees: [{ id, name, talents: [{ id, name, row, col, max, requiredPoints, requires, desc[] }] }] }
  updated_at TEXT NOT NULL
);
