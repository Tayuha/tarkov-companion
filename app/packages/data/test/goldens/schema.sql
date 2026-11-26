-- AppDatabase schema snapshot (schemaVersion 3).
-- Regenerate: (cd app/packages/data && UPDATE_GOLDENS=1 dart test)
-- FTS5 shadow tables (items_fts_data, _idx, _docsize,
-- _config) are omitted; items_fts and its triggers are part
-- of the contract.

index craftsProductItemId
CREATE INDEX craftsProductItemId ON crafts (productItemId);

index craftsStationId
CREATE INDEX craftsStationId ON crafts (stationId);

index gameRecordsKind
CREATE INDEX gameRecordsKind ON gameRecords (kind);

index itemsAvg24hPrice
CREATE INDEX itemsAvg24hPrice ON items (avg24hPrice);

index itemsLastLowPrice
CREATE INDEX itemsLastLowPrice ON items (lastLowPrice);

index itemsNormalizedName
CREATE INDEX itemsNormalizedName ON items (normalizedName);

index mapsNormalizedName
CREATE INDEX mapsNormalizedName ON maps (normalizedName);

index objectiveProgressQuestId
CREATE INDEX objectiveProgressQuestId ON objectiveProgress (questId);

index priceHistoryItemId
CREATE INDEX priceHistoryItemId ON priceHistory (itemId);

index questProgressQuestId
CREATE INDEX questProgressQuestId ON questProgress (questId);

index taskObjectivesTaskId
CREATE INDEX taskObjectivesTaskId ON taskObjectives (taskId);

index tasksMapId
CREATE INDEX tasksMapId ON tasks (mapId);

index tasksMinPlayerLevel
CREATE INDEX tasksMinPlayerLevel ON tasks (minPlayerLevel);

index tasksTraderId
CREATE INDEX tasksTraderId ON tasks (traderId);

index tradersNormalizedName
CREATE INDEX tradersNormalizedName ON traders (normalizedName);

table appSettings
CREATE TABLE "appSettings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));

table barters
CREATE TABLE "barters" ("id" TEXT NOT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table crafts
CREATE TABLE "crafts" ("id" TEXT NOT NULL, "stationId" TEXT NOT NULL, "productItemId" TEXT NOT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table datasetState
CREATE TABLE "datasetState" ("mode" TEXT NOT NULL, "dataset" TEXT NOT NULL, "checksum" TEXT NOT NULL, "schemaVersion" INTEGER NOT NULL, "records" INTEGER NOT NULL, "sourceUpdatedAt" INTEGER NULL, "appliedAt" INTEGER NOT NULL, PRIMARY KEY ("mode", "dataset"));

table gameRecords
CREATE TABLE "gameRecords" ("kind" TEXT NOT NULL, "id" TEXT NOT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("kind", "id"));

table hideoutStations
CREATE TABLE "hideoutStations" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table items
CREATE TABLE "items" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "shortName" TEXT NOT NULL, "normalizedName" TEXT NOT NULL, "weight" REAL NULL, "width" INTEGER NULL, "height" INTEGER NULL, "basePrice" INTEGER NULL, "avg24hPrice" INTEGER NULL, "lastLowPrice" INTEGER NULL, "changeLast48hPercent" REAL NULL, "iconLink" TEXT NULL, "gridImageLink" TEXT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table items_fts
CREATE VIRTUAL TABLE items_fts USING fts5(
  name,
  shortName,
  normalizedName,
  content = 'items',
  content_rowid = 'rowid',
  tokenize = 'unicode61 remove_diacritics 2'
);

table maps
CREATE TABLE "maps" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "normalizedName" TEXT NOT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table objectiveProgress
CREATE TABLE "objectiveProgress" ("profileId" TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE, "questId" TEXT NOT NULL, "objectiveId" TEXT NOT NULL, "count" INTEGER NOT NULL DEFAULT 0, "updatedAt" INTEGER NOT NULL, PRIMARY KEY ("profileId", "questId", "objectiveId"));

table priceHistory
CREATE TABLE "priceHistory" ("itemId" TEXT NOT NULL, "observedAt" INTEGER NOT NULL, "price" INTEGER NOT NULL, "priceMin" INTEGER NULL, PRIMARY KEY ("itemId", "observedAt"));

table profiles
CREATE TABLE "profiles" ("id" TEXT NOT NULL, "gameMode" TEXT NOT NULL UNIQUE, "playerLevel" INTEGER NOT NULL DEFAULT 1, "createdAt" INTEGER NOT NULL, "updatedAt" INTEGER NOT NULL, PRIMARY KEY ("id"));

table questProgress
CREATE TABLE "questProgress" ("profileId" TEXT NOT NULL REFERENCES profiles (id) ON DELETE CASCADE, "questId" TEXT NOT NULL, "state" TEXT NOT NULL, "updatedAt" INTEGER NOT NULL, PRIMARY KEY ("profileId", "questId"));

table remoteManifest
CREATE TABLE "remoteManifest" ("mode" TEXT NOT NULL, "etag" TEXT NULL, "lastModified" TEXT NULL, "manifestJson" TEXT NOT NULL, "manifestGeneratedAt" TEXT NULL, "lastCheckedAt" INTEGER NOT NULL, "lastChangedAt" INTEGER NULL, "contentHash" TEXT NOT NULL, PRIMARY KEY ("mode"));

table taskObjectives
CREATE TABLE "taskObjectives" ("id" TEXT NOT NULL, "taskId" TEXT NOT NULL REFERENCES tasks (id) ON DELETE CASCADE, "type" TEXT NOT NULL, "description" TEXT NOT NULL DEFAULT '', "count" INTEGER NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table tasks
CREATE TABLE "tasks" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "traderId" TEXT NULL, "mapId" TEXT NULL, "minPlayerLevel" INTEGER NULL, "experience" INTEGER NULL, "kappaRequired" INTEGER NOT NULL DEFAULT 0 CHECK ("kappaRequired" IN (0, 1)), "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

table traders
CREATE TABLE "traders" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "normalizedName" TEXT NOT NULL, "payload" TEXT NOT NULL, PRIMARY KEY ("id"));

trigger items_fts_ad
CREATE TRIGGER items_fts_ad AFTER DELETE ON items BEGIN
  INSERT INTO items_fts (items_fts, rowid, name, shortName, normalizedName)
  VALUES ('delete', old.rowid, old.name, old.shortName, old.normalizedName);
END;

trigger items_fts_ai
CREATE TRIGGER items_fts_ai AFTER INSERT ON items BEGIN
  INSERT INTO items_fts (rowid, name, shortName, normalizedName)
  VALUES (new.rowid, new.name, new.shortName, new.normalizedName);
END;

trigger items_fts_au
CREATE TRIGGER items_fts_au AFTER UPDATE ON items BEGIN
  INSERT INTO items_fts (items_fts, rowid, name, shortName, normalizedName)
  VALUES ('delete', old.rowid, old.name, old.shortName, old.normalizedName);
  INSERT INTO items_fts (rowid, name, shortName, normalizedName)
  VALUES (new.rowid, new.name, new.shortName, new.normalizedName);
END;

