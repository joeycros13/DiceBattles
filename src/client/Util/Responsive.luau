--!strict
-- Responsive: viewport scaling + device-class helper for phone/desktop (R-P1, R-M2).
-- Derives a uniform UI scale factor from the current viewport relative to a base
-- design resolution, classifies the device (Phone/Tablet/Desktop), and notifies
-- listeners whenever any of those change. Pure client utility: no networking.

local UserInputService = game:GetService("UserInputService")

local Responsive = {}

export type DeviceClass = "Phone" | "Tablet" | "Desktop"

-- Design resolution the layouts are authored against.
local BASE = Vector2.new(1280, 720)
local MIN_SCALE = 0.65
local MAX_SCALE = 1.5
-- Viewport min-axis (px) thresholds used to classify touch devices.
local PHONE_MAX_MIN_AXIS = 550
local TABLET_MAX_MIN_AXIS = 1100

local deps: any = nil
local changedEvent: BindableEvent? = nil
local initialized = false

local currentViewport = BASE
local currentScale = 1
local currentClass: DeviceClass = "Desktop"

local function computeScale(viewport: Vector2): number
	local byWidth = viewport.X / BASE.X
	local byHeight = viewport.Y / BASE.Y
	return math.clamp(math.min(byWidth, byHeight), MIN_SCALE, MAX_SCALE)
end

local function computeClass(viewport: Vector2): DeviceClass
	-- A device with touch but no keyboard is treated as a mobile form factor.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if not touchOnly then
		return "Desktop"
	end
	local minAxis = math.min(viewport.X, viewport.Y)
	if minAxis <= PHONE_MAX_MIN_AXIS then
		return "Phone"
	elseif minAxis <= TABLET_MAX_MIN_AXIS then
		return "Tablet"
	end
	return "Desktop"
end

local function getViewportSize(): Vector2
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize
	end
	return BASE
end

local function recompute()
	local viewport = getViewportSize()
	local scale = computeScale(viewport)
	local class = computeClass(viewport)
	local didChange = viewport ~= currentViewport or scale ~= currentScale or class ~= currentClass
	currentViewport = viewport
	currentScale = scale
	currentClass = class
	if didChange and changedEvent then
		changedEvent:Fire()
	end
end

local function bindCamera(camera: Camera?)
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
	end
end

local function ensureInit()
	if initialized then
		return
	end
	initialized = true
	changedEvent = Instance.new("BindableEvent")
	recompute()

	bindCamera(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(workspace.CurrentCamera)
		recompute()
	end)
	-- Switching between touch and mouse/keyboard can change the device class.
	UserInputService.LastInputTypeChanged:Connect(recompute)
end

function Responsive.init(injected: any)
	deps = injected
	ensureInit()
end

function Responsive.start()
	ensureInit()
end

-- Current viewport size in pixels.
function Responsive.getViewport(): Vector2
	ensureInit()
	return currentViewport
end

-- Uniform UI scale factor for the current viewport (clamped).
function Responsive.scale(): number
	ensureInit()
	return currentScale
end

-- Convert design pixels to device pixels using the current scale (rounded).
function Responsive.scaled(px: number): number
	ensureInit()
	return math.round(px * currentScale)
end

-- Device classification derived from touch capability + viewport size.
function Responsive.getDeviceClass(): DeviceClass
	ensureInit()
	return currentClass
end

function Responsive.isPhone(): boolean
	return Responsive.getDeviceClass() == "Phone"
end

function Responsive.isTouch(): boolean
	return UserInputService.TouchEnabled
end

-- True when layouts should use the compact (single-column, taller controls) form.
function Responsive.isCompact(): boolean
	return Responsive.getDeviceClass() == "Phone"
end

-- Subscribe to viewport/scale/device-class changes. Returns the connection.
function Responsive.onChanged(callback: () -> ()): RBXScriptConnection
	ensureInit()
	return (changedEvent :: BindableEvent).Event:Connect(callback)
end

-- Attach a UIScale to a GuiObject that tracks the current scale automatically.
function Responsive.applyUIScale(guiObject: GuiObject): UIScale
	ensureInit()
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = currentScale
	uiScale.Parent = guiObject
	Responsive.onChanged(function()
		uiScale.Scale = currentScale
	end)
	return uiScale
end

return Responsive
