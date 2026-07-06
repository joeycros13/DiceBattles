--!strict
-- InventoryLayout: pure grid math for the inventory tile display (R-E4).
-- Decides how many columns fit, the cell size that fills the row, and how many
-- placeholder "empty" tiles to show. The empty-tile rule: always fill out to at
-- least `minRows` (the visible area) so the inventory reads as having spare
-- capacity, and once items overflow that, grow by exactly the rows the items
-- require -- so only the last (partial) row is padded with empties, one new row
-- appearing at a time as rows fill. No Instances here so it is unit-testable.

local InventoryLayout = {}

export type FillPlan = {
	columns: number,
	totalRows: number,
	totalTiles: number,
	emptyCount: number,
}

-- How many fixed-size columns fit into `availableWidth` given inter-cell padding.
function InventoryLayout.columnCount(availableWidth: number, targetTile: number, padding: number): number
	if availableWidth <= 0 or targetTile <= 0 then
		return 1
	end
	return math.max(1, math.floor((availableWidth + padding) / (targetTile + padding)))
end

-- Cell size (square) that makes exactly `columns` cells fill `availableWidth`.
function InventoryLayout.cellSize(availableWidth: number, columns: number, padding: number): number
	columns = math.max(1, columns)
	return math.max(1, math.floor((availableWidth - (columns - 1) * padding) / columns))
end

-- Plan the tile grid for `itemCount` items across `columns`, filling at least
-- `minRows`. Returns the total rows/tiles and how many empty placeholders to add.
function InventoryLayout.plan(itemCount: number, columns: number, minRows: number): FillPlan
	columns = math.max(1, math.floor(columns))
	minRows = math.max(1, math.floor(minRows))
	itemCount = math.max(0, math.floor(itemCount))

	local rowsNeeded = math.ceil(itemCount / columns)
	local totalRows = math.max(minRows, rowsNeeded)
	local totalTiles = totalRows * columns
	local emptyCount = math.max(0, totalTiles - itemCount)

	return {
		columns = columns,
		totalRows = totalRows,
		totalTiles = totalTiles,
		emptyCount = emptyCount,
	}
end

return InventoryLayout
