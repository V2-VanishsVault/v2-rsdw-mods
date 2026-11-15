-- Storage Mage's developer features: loaded only when this folder is installed (tools\deploy.ps1 -Link links it
-- into the game as Mods\StorageMage\dev). Release zips never contain it. Each name is a module under
-- storagemage/features/ in this folder, started after the mod's own features, in this order.
return { "probe", "uidump", "dragprobe", "pagetest", "beltprobe" }
