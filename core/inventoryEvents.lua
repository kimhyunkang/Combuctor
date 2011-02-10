--[[
	BagEvents
		A library of functions for accessing and updating bag slot information

	Based on SpecialEvents-Bags by Tekkub Stoutwrithe (tekkub@gmail.com)

	ITEM_SLOT_ADD
	args:		bag, slot, link, count, locked, coolingDown
		called when a new slot becomes available to the player

	ITEM_SLOT_REMOVE
	args:		bag, slot
		called when an item slot is removed from being in use

	ITEM_SLOT_UPDATE
	args:		bag, slot, link, count, locked, coolingDown
		called when an item slot's item or item count changes

	ITEM_SLOT_UPDATE_COOLDOWN
	args:		bag, slot, coolingDown
		called when an item's cooldown starts/ends

	BANK_OPENED
	args:		none
		called when the bank has opened and all of the bagnon events have SendMessaged

	BANK_CLOSED
	args:		none
		called when the bank is closed and all of the bagnon events have SendMessaged

	BAG_UPDATE_TYPE
	args:	bag, type
		called when the type of a bag changes (aka, what items you can put in it changes)

	Usage:
		Addon('InventoryEvents'):Register(frame, 'message', 'method' or function)
		Addon('InventoryEvents'):Unregister(frame, 'message')
		Addon('InventoryEvents'):UnregisterAlll(frame)
		playerAtBank = Addon('InventoryEvents'):AtBank()
--]]


local AddonName, Addon = ...

--[[ Module Town ]]--

local InventoryEvents = Addon:NewModule('InventoryEvents', Envoy:New())
local AtBank = false

function InventoryEvents:AtBank()
	return AtBank
end

local function sendMessage(msg, ...)
	InventoryEvents:Send(msg, ...)
end

--[[
	Update Functions
--]]

local Slots
do
	local function getIndex(bagId, slotId)
		return (bagId < 0 and bagId * 100 - slotId) or bagId * 100 + slotId
	end

	Slots = {
		Set = function(self, bagId, slotId, itemLink, count, isLocked, onCooldown)
			local index = getIndex(bagId, slotId)

			local item = self[index] or {}
			item[1] = itemLink
			item[2] = count
			item[3] = locked
			item[4] = onCooldown

			self[index] = item
		end,

		Remove = function(self, bagId, slotId)
			local index = getIndex(bagId, slotId)
			local item = self[index]

			if item then
				self[index] = nil
				return true
			end
		end,

		Get = function(self, bagId, slotId)
			return self[getIndex(bagId, slotId)]
		end,
	}

	setmetatable(Slots, {__call = Slots.Get})
end

local BagTypes = {}
local BagSizes = {}


--[[ Item Updating ]]--

local function addItem(bagId, slotId)
	local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bagId, slotId)
	local start, duration, enable = GetContainerItemCooldown(bagId, slotId)
	local onCooldown = (start > 0 and duration > 0 and enable > 0)

	Slots:Set(bagId, slotId, link, count, locked, onCooldown)
	sendMessage('ITEM_SLOT_ADD', bagId, slotId, link, count, locked, onCooldown)
end

local function removeItem(bagId, slotId)
	if Slots:Remove(bagId, slotId) then
		sendMessage('ITEM_SLOT_REMOVE', bagId, slotId, prevLink)
	end
end

local function updateItem(bagId, slotId)
	local item = Slots(bagId, slotId)

	if item then
		local prevLink = item[1]
		local prevCount = item[2]

		local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bagId, slotId)
		local start, duration, enable = GetContainerItemCooldown(bagId, slotId)
		local onCooldown = (start > 0 and duration > 0 and enable > 0)

		if not(prevLink == link and prevCount == count) then
			item[1] = link
			item[2] = count
			item[3] = locked
			item[4] = onCooldown

			sendMessage('ITEM_SLOT_UPDATE', bagId, slotId, link, count, locked, onCooldown)
		end
	end
end

local function updateItemCooldown(bagId, slotId)
	local item = Slots(bagId, slotId)

	if item and item[1] then
		local start, duration, enable = GetContainerItemCooldown(bagId, slotId)
		local onCooldown = (start > 0 and duration > 0 and enable > 0)

		if data[4] ~= onCooldown then
			data[4] = onCooldown
			sendMessage('ITEM_SLOT_UPDATE_COOLDOWN', bagId, slotId, onCooldown)
		end
	end
end

--[[ Bag Updating ]]--

local function getBagSize(bagId)
	if bagId == KEYRING_CONTAINER then
		return GetKeyRingSize()
	end
	return GetContainerNumSlots(bagId)
end

--bag sizes
local function updateBagSize(bagId)
	local prevSize = BagSizes[bagId] or 0
	local newSize = getBagSize(bagId)
	BagSizes[bagId] = newSize

	if prevSize > newSize then
		for slotId = newSize + 1, prevSize do
			removeItem(bagId, slotId)
		end
	elseif prevSize < newSize then
		for slotId = prevSize + 1, newSize do
			addItem(bagId, slotId)
		end
	end
end

local function updateBagType(bagId)
	local _, newType = GetContainerNumFreeSlots(bagId)
	local prevType = BagTypes[bagId]

	if newType ~= prevType then
		BagTypes[bagId] = newType
		sendMessage('BAG_UPDATE_TYPE', bagId, newType)
	end
end

--[[ metamethods ]]--

local function forEachItem(bagId, slotId, f, ...)
	for slot = 1, getBagSize(bagId) do
		f(bagId, slotId, ....)
	end
end

local function forEachBag(f, ...)
	if AtBank then
		for bagId = 1, NUM_BAG_SLOTS + GetNumBankSlots() do
			f(bagId, ...)
		end
	else
		for bag = 1, NUM_BAG_SLOTS do
			f(bagId, ...)
		end
	end
	f(KEYRING_CONTAINER, ...)
end


--[[ inventory event watcher ]]--

do
	local eventFrame = CreateFrame('Frame'); eventFrame:Hide()

	eventFrame:SetScript('OnEvent', function(self, event, ...)
		local a = self[event]
		if a then
			a(self, event, ...)
		end
	end)
	eventFrame:RegisterEvent('PLAYER_LOGIN')

	function eventFrame:PLAYER_LOGIN(event, ...)
		self:RegisterEvent('BAG_UPDATE')
		self:RegisterEvent('BAG_UPDATE_COOLDOWN')
		self:RegisterEvent('PLAYERBANKSLOTS_CHANGED')
		self:RegisterEvent('BANKFRAME_OPENED')
		self:RegisterEvent('BANKFRAME_CLOSED')

		updateBagSize(KEYRING_CONTAINER)
		updateItems(KEYRING_CONTAINER)

		updateBagSize(BACKPACK_CONTAINER)
		updateItems(BACKPACK_CONTAINER)
	end

	function eventFrame:BAG_UPDATE(event, bagId)
		forEachBag(updateBagType)
		forEachBag(updateBagSizes)
		forEachItem(bagId, updateItem)
	end

	function eventFrame:PLAYERBANKSLOTS_CHANGED(event, ...)
		forEachBag(updateBagType)
		forEachBag(updateBagSizes)
		forEachItem(BANK_CONTAINER, updateItem)
	end

	function eventFrame:BANKFRAME_OPENED(event, ...)
		AtBank = true
		forEachBag(updateBagType)
		forEachBag(updateBagSizes)
		forEachItem(BANK_CONTAINER, updateItem)
		sendMessage('BANK_OPENED')

		--redefine event for each successive call
		self[event] = function(self)
			AtBank = true
			sendMessage('BANK_OPENED')
		end
	end

	function eventFrame:BANKFRAME_CLOSED(event, ...)
		AtBank = false
		sendMessage('BANK_CLOSED')
	end

	function eventFrame:BAG_UPDATE_COOLDOWN(event, ...)
		forEachBag(forEachItem, updateItemCooldown)
	end
end