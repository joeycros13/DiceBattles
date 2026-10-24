--!strict
-- CenterRow: keeps an icon + text truly centred in its box, both ways (the user,
-- 2026-10-12: "every UI text that is put inside of a box needs to be centered
-- horizontally and vertically").
--
-- A centred row is a hand-built Frame with the attribute CenterRow = true and a
-- horizontal UIListLayout centred both ways; its icons are square
-- (SizeConstraint RelativeYY) and its TextLabels have AutomaticSize X and
-- TextScaled off, so the layout can measure them. TextScaled can't sit in a
-- layout like that, so this sets each label's TextSize from the row's height:
-- row height x the row's "TextScale" attribute (default 0.62). If that makes the
-- row wider than its box (a long name in a chip), the text shrinks to fit, with
-- the row's "Margin" (default 0.06 of its width) left free. It follows every
-- PlayerGui row, including clones made later, and refits when a row resizes or a
-- label's text changes.
--
-- Rows sharing a "SizeGroup" attribute (the VIP perks, the reward chips) all use
-- the group's smallest fit, so siblings read at one size. Luckiest Guy draws its
-- letters high in their box (roblox-ui-text-centering: 0.14 x TextSize) and an
-- icon + Luckiest Guy group sits 0.1 x TextSize right, so those are corrected here.

local Players = game:GetService("Players")

local CenterRow = {}

local watched: { [Instance]: boolean } = {}
-- each row's last shrink-to-fit ratio, applied at once on every refit: text sizes
-- scale with the row, so the ratio holds while a hover or pop UIScale grows the
-- row, and the text never flashes at full size for a frame (user, 2026-10-12)
local ratios: { [Instance]: number } = {}
local groupRatios: { [string]: { [Instance]: number } } = {}

local function groupOf(row: Instance): string?
	local g = row:GetAttribute("SizeGroup")
	return if type(g) == "string" and g ~= "" then g else nil
end

-- a row the player can actually see: on screen with a size, and no hidden
-- ancestor. A hidden chip collapses to 0 x 0, its fit comes out at the 0.3
-- floor, and it must not drag its whole group down: the quest reward chips'
-- Coins / EXP text drew at size 5 while the unused Weapon / Item chips hid
-- (user, 2026-10-12, both questlines).
local function shown(row: Instance): boolean
	if not row:IsA("GuiObject") or row.AbsoluteSize.X <= 1 or row.AbsoluteSize.Y <= 1 then
		return false
	end
	local node: Instance? = row
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

-- the ratio a row draws at: its own, or its group's smallest among the shown rows
local function ratioOf(row: Instance): number
	local g = groupOf(row)
	if g and groupRatios[g] then
		local low = 1
		for other, r in groupRatios[g] do
			if other.Parent and shown(other) then
				low = math.min(low, r)
			end
		end
		return low
	end
	return ratios[row] or 1
end

local function isLuckiest(label: TextLabel): boolean
	return label.FontFace.Family:find("LuckiestGuy") ~= nil
end

local function labels(row: Instance): { TextLabel }
	local out = {}
	for _, child in row:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(out, child)
		end
	end
	return out
end

-- The UIScale the row is drawn at: every UIScale on it and its ancestors (a card's
-- hover grow, a panel's pop). AbsoluteSize already includes it, and so does the drawn
-- text, so a text size worked out from AbsoluteSize grew twice as a card grew and
-- jumped a whole size at a time (the VIP card's "1.25× Coins" on hover, 2026-10-21).
local function drawnScale(row: Instance): number
	local s = 1
	local node: Instance? = row
	while node and not node:IsA("LayerCollector") do
		local u = node:FindFirstChildOfClass("UIScale")
		if u then
			s *= u.Scale
		end
		node = node.Parent
	end
	return s
end

-- True while a panel the row is in pops open or shut (its PopScale away from 1): its
-- AbsoluteSize then lags the scale by a frame, and a fit flashed the text at nearly
-- twice its size. The row keeps its last size and refits when the pop settles.
local function popping(row: Instance): boolean
	local node: Instance? = row
	while node and not node:IsA("LayerCollector") do
		local pop = node:FindFirstChild("PopScale")
		if pop and pop:IsA("UIScale") and math.abs(pop.Scale - 1) > 0.001 then
			return true
		end
		node = node.Parent
	end
	return false
end

-- `fromGroup`: a refit because another row of its group changed; it doesn't pass its own change
-- back (two rows refitting each other could bounce forever: "Maximum re-entrancy depth", 2026-10-24).
function CenterRow.fit(row: GuiObject, fromGroup: boolean?)
	local scale = row:GetAttribute("TextScale")
	local uiScale = drawnScale(row)
	if uiScale < 0.05 or popping(row) then
		return
	end
	local size = math.max(1, math.floor(row.AbsoluteSize.Y / uiScale * (if type(scale) == "number" then scale else 0.62) + 0.5))
	local function apply(ratio: number)
		local textSize = math.max(1, math.floor(size * ratio))
		local luckiest = false
		for _, label in labels(row) do
			label.TextSize = textSize
			if isLuckiest(label) then
				luckiest = true
				local pad = label:FindFirstChild("InkDrop") or Instance.new("UIPadding")
				pad.Name = "InkDrop"
				pad:SetAttribute("NoDrop", true) -- this sets the drop itself; Util.FontDrop leaves it alone
				local d = math.floor(textSize * 0.14 + 0.5)
				pad.PaddingTop = UDim.new(0, d)
				pad.PaddingBottom = UDim.new(0, -d)
				pad.Parent = label
			end
		end
		-- an icon beside Luckiest Guy text: pull the whole group back to the centre
		local hasIcon = false
		for _, child in row:GetChildren() do
			if (child:IsA("ImageLabel") or child:IsA("Frame")) and child.Visible then
				hasIcon = true
			end
		end
		local base = row:GetAttribute("BaseX")
		if type(base) ~= "number" then
			base = row.Position.X.Offset
			row:SetAttribute("BaseX", base)
		end
		local pull = if luckiest and hasIcon then -math.floor(textSize * 0.1 + 0.5) else 0
		row.Position = UDim2.new(row.Position.X.Scale, (base :: number) + pull, row.Position.Y.Scale, row.Position.Y.Offset)
	end
	apply(ratioOf(row))
	-- then correct the ratio once the layout has measured the row
	task.defer(function()
		local layout = row:FindFirstChildOfClass("UIListLayout")
		if not (layout and row.Parent) then
			return
		end
		if not shown(row) then
			-- hidden: it has no width to fit, so it leaves its group until it shows again
			local g = groupOf(row)
			if g and groupRatios[g] and groupRatios[g][row] ~= nil then
				groupRatios[g][row] = nil
				for other in groupRatios[g] do
					if other.Parent then
						CenterRow.fit(other :: GuiObject, true)
					end
				end
			end
			return
		end
		local margin = row:GetAttribute("Margin")
		local room = row.AbsoluteSize.X * (1 - (if type(margin) == "number" then margin else 0.06))
		local used = layout.AbsoluteContentSize.X
		-- only the text scales; the icons keep their size
		local textWidth = 0
		for _, label in labels(row) do
			textWidth += label.AbsoluteSize.X
		end
		if textWidth <= 0 or used <= 0 then
			return
		end
		-- what this row alone would need, from the ratio it is drawn at now
		local drawn = ratioOf(row)
		local fixed = used - textWidth
		local own = math.clamp(drawn * (room - fixed) / textWidth, 0.3, 1)
		local g = groupOf(row)
		if g then
			groupRatios[g] = groupRatios[g] or {}
			local before = groupRatios[g][row]
			if before == nil or math.abs(before - own) > 0.02 then
				groupRatios[g][row] = own
				-- the group's size may have changed: refit every row in it (once)
				if not fromGroup then
					for other in groupRatios[g] do
						if other ~= row and other.Parent then
							CenterRow.fit(other :: GuiObject, true)
						end
					end
				end
				apply(ratioOf(row))
			end
		elseif math.abs(own - drawn) > 0.02 then
			ratios[row] = own
			apply(own)
		end
	end)
end

local function watch(row: Instance)
	if watched[row] or not row:IsA("GuiObject") or row:GetAttribute("CenterRow") ~= true then
		return
	end
	watched[row] = true
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		CenterRow.fit(row)
	end)
	for _, label in labels(row) do
		label:GetPropertyChangedSignal("Text"):Connect(function()
			-- new words keep the last ratio; the deferred check grows or shrinks it
			CenterRow.fit(row)
		end)
	end
	-- a chip shown or hidden (the row's own frame or its chip) changes which rows
	-- count in the group, so the whole group refits
	local node: Instance? = row
	for _ = 1, 2 do
		if not (node and node:IsA("GuiObject")) then
			break
		end
		local gui = node :: GuiObject
		gui:GetPropertyChangedSignal("Visible"):Connect(function()
			CenterRow.fit(row)
			local g = groupOf(row)
			if g and groupRatios[g] then
				for other in groupRatios[g] do
					if other ~= row and other.Parent then
						CenterRow.fit(other :: GuiObject, true)
					end
				end
			end
		end)
		node = node.Parent
	end
	row.Destroying:Connect(function()
		watched[row] = nil
		ratios[row] = nil
		local g = groupOf(row)
		if g and groupRatios[g] then
			groupRatios[g][row] = nil
		end
	end)
	CenterRow.fit(row)
end

function CenterRow.init(_injected: any) end

function CenterRow.start()
	task.spawn(function()
		local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
		for _, d in gui:GetDescendants() do
			watch(d)
		end
		gui.DescendantAdded:Connect(watch)
	end)
end

return CenterRow
