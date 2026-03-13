local QBCore = exports['qb-core']:GetCoreObject()

-- ====================|| CORE BUSINESS HELPERS || ==================== --

local function getPlayerCoords(source)
    local ped = GetPlayerPed(source)
    return ped and GetEntityCoords(ped)
end

local function getCoreBusinessClothingPrice(source)
    if not Config.CoreBusiness or not Config.CoreBusiness.enabled or not Config.CoreBusiness.consumeItems then return nil end

    local coords = getPlayerCoords(source)
    if not coords then return nil end

    local price = exports['core_business']:closestPropertyGetPrice(coords, Config.CoreBusiness.clothingItem, 'sell')
    return price
end

local function coreBusinessProcessClothing(source, changedCount, defaultMoney)
    if not Config.CoreBusiness or not Config.CoreBusiness.enabled then return defaultMoney, false end

    local coords = getPlayerCoords(source)
    if not coords then return defaultMoney, false end

    local clothingItem = Config.CoreBusiness.clothingItem

    if Config.CoreBusiness.consumeItems then
        if changedCount <= 0 then return 0, true end

        local itemCount = exports['core_business']:closestPropertyItemCount(coords, clothingItem)
        if itemCount == 1000.0 then return defaultMoney, false end

        local price = exports['core_business']:closestPropertyGetPrice(coords, clothingItem, 'sell')
        local pricePerItem = price or Config.ClothingCost
        local actualItems = math.min(changedCount, math.floor(itemCount))

        if actualItems <= 0 then return defaultMoney, false end

        exports['core_business']:closestPropertyRemoveItem(coords, clothingItem, actualItems)
        local saleAmount = pricePerItem * actualItems
        exports['core_business']:closestPropertyRegisterSale(coords, saleAmount, string.format("Clothing sale: %d items, $%d", actualItems, saleAmount))

        return saleAmount, true
    else
        local itemCount = exports['core_business']:closestPropertyItemCount(coords, clothingItem)
        if itemCount == 1000.0 then return defaultMoney, false end

        local saleAmount = math.floor(defaultMoney * (Config.CoreBusiness.salePercentage or 0.75))
        if saleAmount > 0 then
            exports['core_business']:closestPropertyRegisterSale(coords, saleAmount, string.format("Clothing sale: $%d", saleAmount))
        end

        return defaultMoney, true
    end
end

-- ====================|| PAYMENT HELPERS || ==================== --

local function getMoneyForShop(shopType, source)
    local money = 0
    if shopType == "clothing" then
        if source and Config.CoreBusiness and Config.CoreBusiness.enabled and Config.CoreBusiness.consumeItems then
            local price = getCoreBusinessClothingPrice(source)
            if price then return price end
        end
        money = Config.ClothingCost
    elseif shopType == "barber" then
        money = Config.BarberCost
    elseif shopType == "surgeon" then
        money = Config.SurgeonCost
    end
    return money
end

QBCore.Functions.CreateCallback('qb-clothing:server:hasMoney', function(source, cb, shopType)
    local money = getMoneyForShop(shopType, source)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player and Player.Functions.GetMoney('cash') >= money then
        cb(true, money)
    else
        cb(false, money)
    end
end)

RegisterServerEvent("qb-clothing:server:chargeCustomer", function(shopType, changedCount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local defaultMoney = getMoneyForShop(shopType)

    local money = defaultMoney
    if shopType == "clothing" then
        local cbMoney, handled = coreBusinessProcessClothing(src, changedCount or 0, defaultMoney)
        money = cbMoney
        if handled and money <= 0 then return end
    end

    if money > 0 then
        if Player.Functions.RemoveMoney('cash', money, 'clothing-purchase') then
            TriggerClientEvent('QBCore:Notify', src, 'Paid $' .. money .. ' for ' .. shopType, 'success')
        else
            TriggerClientEvent('QBCore:Notify', src, 'Not enough cash', 'error')
        end
    end
end)

-- ====================|| COREPAY INTEGRATION || ==================== --

RegisterServerEvent("qb-clothing:server:requestPayment", function(shopType, changedCount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local useCorePay = Config.CoreBusiness and Config.CoreBusiness.enabled and Config.CoreBusiness.useCorePay

    if shopType ~= "clothing" or not useCorePay then
        local money = getMoneyForShop(shopType)
        if money > 0 then
            if Player.Functions.RemoveMoney('cash', money, shopType .. '-purchase') then
                TriggerClientEvent('QBCore:Notify', src, 'Paid $' .. money .. ' for ' .. shopType, 'success')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
            else
                TriggerClientEvent('QBCore:Notify', src, 'Not enough cash', 'error')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, false)
            end
        else
            TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
        end
        return
    end

    local coords = getPlayerCoords(src)
    if not coords then
        TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
        return
    end

    local businessId = exports['core_business']:closestPropertyGetBusinessId(coords)
    if not businessId then
        local money = getMoneyForShop(shopType)
        if money > 0 then
            if Player.Functions.RemoveMoney('cash', money, 'clothing-purchase') then
                TriggerClientEvent('QBCore:Notify', src, 'Paid $' .. money .. ' for ' .. shopType, 'success')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
            else
                TriggerClientEvent('QBCore:Notify', src, 'Not enough cash', 'error')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, false)
            end
        else
            TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
        end
        return
    end

    local clothingItem = Config.CoreBusiness.clothingItem
    local amount = 0
    local itemsToConsume = 0

    if Config.CoreBusiness.consumeItems then
        if changedCount <= 0 then
            TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
            return
        end

        local itemCount = exports['core_business']:closestPropertyItemCount(coords, clothingItem)
        if itemCount == 1000.0 then
            local money = Config.ClothingCost
            if Player.Functions.RemoveMoney('cash', money, 'clothing-purchase') then
                TriggerClientEvent('QBCore:Notify', src, 'Paid $' .. money .. ' for clothing', 'success')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
            else
                TriggerClientEvent('QBCore:Notify', src, 'Not enough cash', 'error')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, false)
            end
            return
        end

        local price = exports['core_business']:closestPropertyGetPrice(coords, clothingItem, 'sell')
        local pricePerItem = price or Config.ClothingCost
        itemsToConsume = math.min(changedCount, math.floor(itemCount))

        if itemsToConsume <= 0 then
            TriggerClientEvent('QBCore:Notify', src, 'Store has no clothing in stock', 'error')
            TriggerClientEvent('qb-clothing:client:paymentResult', src, false)
            return
        end

        amount = pricePerItem * itemsToConsume
    else
        local itemCount = exports['core_business']:closestPropertyItemCount(coords, clothingItem)
        if itemCount == 1000.0 then
            local money = Config.ClothingCost
            if Player.Functions.RemoveMoney('cash', money, 'clothing-purchase') then
                TriggerClientEvent('QBCore:Notify', src, 'Paid $' .. money .. ' for clothing', 'success')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
            else
                TriggerClientEvent('QBCore:Notify', src, 'Not enough cash', 'error')
                TriggerClientEvent('qb-clothing:client:paymentResult', src, false)
            end
            return
        end
        amount = Config.ClothingCost
    end

    if amount <= 0 then
        TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
        return
    end

    exports['core_business']:requestCorePay(src, businessId, amount, "Clothing purchase", function(success, message)
        if success then
            if Config.CoreBusiness.consumeItems and itemsToConsume > 0 then
                exports['core_business']:closestPropertyRemoveItem(coords, clothingItem, itemsToConsume)
            end
            TriggerClientEvent('qb-clothing:client:paymentResult', src, true)
        else
            TriggerClientEvent('qb-clothing:client:paymentResult', src, false)
        end
    end)
end)

-- ====================|| ORIGINAL EVENTS || ==================== --

RegisterServerEvent("qb-clothing:saveSkin", function(model, skin)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if model ~= nil and skin ~= nil then
        -- TODO: Update primary key to be citizenid so this can be an insert on duplicate update query
        MySQL.query('DELETE FROM playerskins WHERE citizenid = ?', { Player.PlayerData.citizenid }, function()
            MySQL.insert('INSERT INTO playerskins (citizenid, model, skin, active) VALUES (?, ?, ?, ?)', {
                Player.PlayerData.citizenid,
                model,
                skin,
                1
            })
        end)
    end
end)

RegisterServerEvent("qb-clothes:loadPlayerSkin", function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', { Player.PlayerData.citizenid, 1 })
    if result[1] ~= nil then
        TriggerClientEvent("qb-clothes:loadSkin", src, false, result[1].model, result[1].skin)
    else
        TriggerClientEvent("qb-clothes:loadSkin", src, true)
    end
end)

RegisterServerEvent("qb-clothes:saveOutfit", function(outfitName, model, skinData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if model ~= nil and skinData ~= nil then
        local outfitId = "outfit-"..math.random(1, 10).."-"..math.random(1111, 9999)
        MySQL.insert('INSERT INTO player_outfits (citizenid, outfitname, model, skin, outfitId) VALUES (?, ?, ?, ?, ?)', {
            Player.PlayerData.citizenid,
            outfitName,
            model,
            json.encode(skinData),
            outfitId
        }, function()
            local result = MySQL.query.await('SELECT * FROM player_outfits WHERE citizenid = ?', { Player.PlayerData.citizenid })
            if result[1] ~= nil then
                TriggerClientEvent('qb-clothing:client:reloadOutfits', src, result)
            else
                TriggerClientEvent('qb-clothing:client:reloadOutfits', src, nil)
            end
        end)
    end
end)

RegisterServerEvent("qb-clothing:server:removeOutfit", function(outfitName, outfitId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    MySQL.query('DELETE FROM player_outfits WHERE citizenid = ? AND outfitname = ? AND outfitId = ?', {
        Player.PlayerData.citizenid,
        outfitName,
        outfitId
    }, function()
        local result = MySQL.query.await('SELECT * FROM player_outfits WHERE citizenid = ?', { Player.PlayerData.citizenid })
        if result[1] ~= nil then
            TriggerClientEvent('qb-clothing:client:reloadOutfits', src, result)
        else
            TriggerClientEvent('qb-clothing:client:reloadOutfits', src, nil)
        end
    end)
end)

QBCore.Functions.CreateCallback('qb-clothing:server:getOutfits', function(source, cb)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local anusVal = {}

    local result = MySQL.query.await('SELECT * FROM player_outfits WHERE citizenid = ?', { Player.PlayerData.citizenid })
    if result[1] ~= nil then
        for k, v in pairs(result) do
            result[k].skin = json.decode(result[k].skin)
            anusVal[k] = v
        end
        cb(anusVal)
    end
    cb(anusVal)
end)
