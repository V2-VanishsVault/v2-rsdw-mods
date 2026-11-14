-- The game's item definitions: the classes they're found under. Used by item tagging (tags); the developer
-- inventory dump uses it too.
local M = {}

-- ItemData and its script subclasses (from the type map). FindAllOf should already return subclasses (Frame Mage
-- relies on that for UserWidget); querying them too covers the case where it doesn't, and callers dedupe.
M.ITEM_DATA_CLASSES = { "ItemData", "BuffItemData", "BuildableItemData", "ConsumableItemData", "CraftableItemData",
    "DrinkItemData", "FoodItemData", "FuelItemData", "JournalItemData", "PotionItemData", "TrinketItemData",
    "WardstoneItemData", "WhetstoneItemData" }

return M
