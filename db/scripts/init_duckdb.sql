INSTALL httpfs; LOAD httpfs;
INSTALL sqlite; LOAD sqlite;
PRAGMA temp_directory='/tmp';
PRAGMA memory_limit='8GB';
SET preserve_insertion_order=false;
SET threads=1;
