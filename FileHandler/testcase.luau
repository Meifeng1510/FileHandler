-- Luau Value Compressor Test Suite
local HttpService = game:GetService("HttpService")

local module = require("Compressor")
local compress = module.Compress
local decompress = module.Decompress

-- Utility functions
local function deepEquals(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "buffer" then return buffer.tostring(a) == buffer.tostring(b) end
	if type(a) ~= "table" then return a == b end

	-- Check tables have same keys and values
	for k, v in a do
		if not deepEquals(v, b[k]) then return false end
	end

	-- Check b doesn't have extra keys
	for k in b do
		if a[k] == nil then return false end
	end

	return true
end

local function calcCompressionRatio(compressed, original)
	local compressedSize = #compressed
	local originalSize = #HttpService:JSONEncode(original)
	return compressedSize / originalSize
end

local function benchmarkCompression(value, iterations)
	iterations = iterations or 1000

	-- Benchmark JSON encoding
	local jsonStart = os.clock()
	for i = 1, iterations do
		HttpService:JSONEncode(value)
	end
	local jsonTime = os.clock() - jsonStart

	-- Benchmark compression for each level
	local compressionTimes = {}
	local compressionSizes = {}

	for level = 1, 3 do
		local startTime = os.clock()
		local compressedValue

		for i = 1, iterations do
			compressedValue = compress(value, level)
		end

		local endTime = os.clock()
		compressionTimes[level] = endTime - startTime
		compressionSizes[level] = #compressedValue
	end

	-- Benchmark decompression
	local level3Compressed = compress(value, 3)
	local decompStart = os.clock()
	for i = 1, iterations do
		decompress(level3Compressed)
	end
	local decompTime = os.clock() - decompStart

	-- Calculate JSON size for comparison
	local jsonSize = #HttpService:JSONEncode(value)

	return {
		jsonTime = jsonTime,
		jsonSize = jsonSize,
		compressionTimes = compressionTimes,
		compressionSizes = compressionSizes,
		decompTime = decompTime,
		ratios = {
			compressionSizes[1] / jsonSize,
			compressionSizes[2] / jsonSize,
			compressionSizes[3] / jsonSize,
		},
	}
end

-- Large Data Generator for Luau Value Compressor Performance Testing
local function generateLargeTestData()
	local largeData = {}

	-- Generate large array with 10,000 numbers (mix of integers and doubles)
	local largeNumberArray = {}
	for i = 1, 10000 do
		if i % 10 == 0 then
			largeNumberArray[i] = i / 3.14159 -- some doubles
		else
			largeNumberArray[i] = i -- integers across various ranges
		end
	end
	largeData.largeNumberArray = largeNumberArray

	-- Generate large string array with 5,000 entries of varying length
	local largeStringArray = {}
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	for i = 1, 5000 do
		local length = (i % 50) + 5 -- strings between 5 and 54 characters
		local str = ""
		for j = 1, length do
			local randomIndex = (i * j) % #chars + 1
			str = str .. string.sub(chars, randomIndex, randomIndex)
		end
		largeStringArray[i] = str
	end
	largeData.largeStringArray = largeStringArray

	-- Generate large dictionary with 2,000 entries
	local largeDictionary = {}
	for i = 1, 2000 do
		local key = "key_" .. tostring(i)
		if i % 4 == 0 then
			largeDictionary[key] = i
		elseif i % 4 == 1 then
			largeDictionary[key] = "value_" .. tostring(i)
		elseif i % 4 == 2 then
			largeDictionary[key] = (i % 2 == 0)
		else
			-- Nested small table
			largeDictionary[key] = {
				id = i,
				name = "item_" .. tostring(i),
				value = i * 10.5,
			}
		end
	end
	largeData.largeDictionary = largeDictionary

	-- Generate deep nested structure (20 levels deep)
	local deepNested = {}
	local current = deepNested
	for i = 1, 20 do
		current.level = i
		current.values = {}
		for j = 1, 10 do
			current.values[j] = {
				id = j,
				name = "level_" .. tostring(i) .. "_item_" .. tostring(j),
			}
		end
		current.next = {}
		current = current.next
	end
	largeData.deepNested = deepNested

	-- Generate mixed-type array with 3,000 items
	local mixedArray = {}
	for i = 1, 3000 do
		local mod = i % 10
		if mod == 0 then
			mixedArray[i] = i
		elseif mod == 1 then
			mixedArray[i] = "string_" .. tostring(i)
		elseif mod == 2 then
			mixedArray[i] = (i % 2 == 0)
		elseif mod == 3 then
			mixedArray[i] = i / 3.3333
		elseif mod == 4 then
			mixedArray[i] = { simple = "table", id = i }
		elseif mod == 5 then
			mixedArray[i] = {}
			for j = 1, 5 do
				mixedArray[i][j] = j * i
			end
		else
			-- More complex nested structure
			mixedArray[i] = {
				id = i,
				tags = { "tag1", "tag2", "tag3" },
				metadata = {
					created = i * 1000,
					modified = i * 1000 + 500,
					flags = {
						active = true,
						visible = (i % 2 == 0),
						priority = (i % 5) + 1,
					},
				},
			}
		end
	end
	largeData.mixedArray = mixedArray

	-- Generate data that simulates a game world with many entities
	local gameWorld = {
		worldName = "PerformanceTestWorld",
		seed = 12345678,
		version = "1.0.0",
		timestamp = os.time(),
		dimensions = { width = 4000, height = 2000, depth = 1000 },
		entities = {},
		chunks = {},
		playerData = {
			inventory = {},
			stats = {
				health = 100,
				mana = 200,
				strength = 15,
				dexterity = 18,
				intelligence = 22,
				charisma = 14,
				wisdom = 16,
				constitution = 19,
				experiencePoints = 7650,
				level = 12,
			},
			equipment = {
				head = {
					id = 101,
					name = "Steel Helmet",
					defense = 8,
					durability = 120,
					enchantments = { "Protection II" },
				},
				chest = {
					id = 102,
					name = "Dragonscale Armor",
					defense = 15,
					durability = 200,
					enchantments = { "Fire Resistance", "Unbreaking III" },
				},
				legs = {
					id = 103,
					name = "Reinforced Leggings",
					defense = 10,
					durability = 150,
					enchantments = { "Swift Movement I" },
				},
				feet = {
					id = 104,
					name = "Boots of Haste",
					defense = 6,
					durability = 100,
					enchantments = { "Speed III", "Feather Fall II" },
				},
				mainHand = {
					id = 105,
					name = "Sword of Glory",
					damage = 25,
					durability = 180,
					enchantments = { "Sharpness V", "Knockback II", "Fire Aspect I" },
				},
				offHand = {
					id = 106,
					name = "Shield of Warding",
					defense = 12,
					durability = 160,
					enchantments = { "Projectile Protection IV" },
				},
			},
			quests = {},
			achievements = {},
			skills = {},
		},
	}

	-- Add 500 entities to the game world
	for i = 1, 500 do
		local entityType = i % 6
		local entity = {
			id = 10000 + i,
			position = { x = (i % 40) * 100, y = math.floor(i / 40) * 100, z = (i % 5) * 20 },
			rotation = { x = 0, y = (i % 360), z = 0 },
			scale = { x = 1 + (i % 5) * 0.1, y = 1 + (i % 3) * 0.1, z = 1 + (i % 4) * 0.1 },
			velocity = { x = (i % 10) - 5, y = (i % 6) - 3, z = (i % 8) - 4 },
			active = (i % 10 ~= 0),
		}

		if entityType == 0 then -- NPC
			entity.type = "npc"
			entity.name = "NPC_" .. tostring(i)
			entity.health = 50 + (i % 50)
			entity.level = 1 + (i % 10)
			entity.hostile = (i % 3 == 0)
			entity.dialog = {
				greeting = "Hello traveler! I am NPC number " .. tostring(i),
				farewell = "Goodbye and good luck on your journey!",
				options = {
					{ text = "Tell me about yourself", responseId = "about_" .. tostring(i) },
					{ text = "What do you sell?", responseId = "shop_" .. tostring(i) },
					{ text = "I need a quest", responseId = "quest_" .. tostring(i) },
				},
			}
			entity.inventory = {}
			for j = 1, 5 + (i % 10) do
				entity.inventory[j] = {
					id = j * 100 + i,
					name = "Item_" .. tostring(j * 100 + i),
					value = j * 10 + (i % 20),
					weight = j * 0.5,
					rarity = (j % 5) + 1,
				}
			end
		elseif entityType == 1 then -- Monster
			entity.type = "monster"
			entity.name = "Monster_" .. tostring(i)
			entity.health = 100 + (i % 200)
			entity.damage = 5 + (i % 30)
			entity.attackSpeed = 0.5 + (i % 10) * 0.1
			entity.aggroRange = 50 + (i % 10) * 10
			entity.loot = {}
			for j = 1, 3 + (i % 5) do
				entity.loot[j] = {
					itemId = j * 100 + i,
					dropChance = (j * 10) / 100,
					minQuantity = 1,
					maxQuantity = 1 + (j % 5),
				}
			end
			entity.abilities = {}
			local numAbilities = 1 + (i % 3)
			for j = 1, numAbilities do
				entity.abilities[j] = {
					id = j * 10 + (i % 10),
					name = "Ability_" .. tostring(j * 10 + (i % 10)),
					damage = 10 + (j * 5) + (i % 15),
					cooldown = 5 + (j * 2),
					range = 10 + (j * 5),
					effectType = ({ "Fire", "Ice", "Lightning", "Poison", "Physical" })[(j % 5) + 1],
				}
			end
		elseif entityType == 2 then -- Item
			entity.type = "item"
			entity.name = "DroppedItem_" .. tostring(i)
			entity.itemId = 1000 + i
			entity.quantity = 1 + (i % 99)
			entity.despawnTime = 300 + (i % 300)
			entity.rarity = (i % 5) + 1
			entity.glow = (i % 4 == 0)
		elseif entityType == 3 then -- Structure
			entity.type = "structure"
			entity.name = "Building_" .. tostring(i)
			entity.buildingType = ({ "House", "Shop", "Temple", "Tower", "Fortress", "Ruin" })[(i % 6) + 1]
			entity.health = 500 + (i % 500)
			entity.destructible = (i % 3 == 0)
			entity.interactable = (i % 2 == 0)
			entity.boundingBox = {
				min = { x = entity.position.x - 10, y = entity.position.y, z = entity.position.z - 10 },
				max = { x = entity.position.x + 10, y = entity.position.y + 15 + (i % 10), z = entity.position.z + 10 },
			}
			entity.doors = {}
			local numDoors = 1 + (i % 4)
			for j = 1, numDoors do
				entity.doors[j] = {
					position = {
						x = entity.position.x + (j % 3) * 5 - 5,
						y = entity.position.y,
						z = entity.position.z + (j % 2) * 20 - 10,
					},
					rotation = (j % 2) * 90,
					locked = (j % 3 == 0),
					keyId = (j % 3 == 0) and (1000 + i * 10 + j) or nil,
				}
			end
		elseif entityType == 4 then -- Vehicle
			entity.type = "vehicle"
			entity.name = "Vehicle_" .. tostring(i)
			entity.vehicleType = ({ "Car", "Boat", "Aircraft", "Mount", "Mech" })[(i % 5) + 1]
			entity.maxSpeed = 10 + (i % 50)
			entity.acceleration = 2 + (i % 10) * 0.5
			entity.handling = 3 + (i % 10) * 0.2
			entity.durability = 100 + (i % 100)
			entity.fuel = {
				current = 50 + (i % 50),
				max = 100 + (i % 100),
				consumption = 0.5 + (i % 10) * 0.1,
			}
			entity.seats = {}
			local numSeats = 1 + (i % 6)
			for j = 1, numSeats do
				entity.seats[j] = {
					position = {
						x = entity.position.x + (j % 3) - 1,
						y = entity.position.y + 1,
						z = entity.position.z + math.floor(j / 3) - 1,
					},
					isDriver = (j == 1),
					occupied = false,
					occupantId = nil,
				}
			end
		else -- Environment
			entity.type = "environment"
			entity.name = "EnvObject_" .. tostring(i)
			entity.envType = ({ "Tree", "Rock", "Bush", "Crystal", "Mushroom", "Flower" })[(i % 6) + 1]
			entity.harvestable = (i % 2 == 0)
			entity.respawnTime = (i % 2 == 0) and (300 + (i % 300)) or nil
			entity.resources = {}
			if i % 2 == 0 then
				local numResources = 1 + (i % 3)
				for j = 1, numResources do
					entity.resources[j] = {
						resourceType = ({ "Wood", "Stone", "Herb", "Metal", "Gem", "Fiber" })[(j % 6) + 1],
						quantity = 1 + (j + i) % 10,
						toolRequired = (j % 3 == 0) and ({ "Axe", "Pickaxe", "Scythe", "Hammer" })[(j % 4) + 1] or nil,
						skillRequired = (j % 4 == 0)
								and ({ "Woodcutting", "Mining", "Herbalism", "Stonecutting" })[(j % 4) + 1]
							or nil,
						skillLevel = (j % 4 == 0) and (1 + (i % 10)) or nil,
					}
				end
			end
		end

		gameWorld.entities[i] = entity
	end

	-- Add 100 inventory items for player
	for i = 1, 100 do
		local itemType = i % 8
		local item = {
			id = i,
			slot = i,
			count = 1 + (i % 99),
			name = "Item_" .. tostring(i),
		}

		if itemType == 0 then -- Weapon
			item.type = "weapon"
			item.weaponType = ({ "Sword", "Axe", "Bow", "Staff", "Dagger", "Hammer", "Spear" })[(i % 7) + 1]
			item.damage = 10 + (i % 50)
			item.attackSpeed = 0.8 + (i % 10) * 0.1
			item.durability = { current = 90 + (i % 10), max = 100 }
			item.level = 1 + (i % 10)
			item.effects = {}
			local numEffects = (i % 3) + 1
			for j = 1, numEffects do
				item.effects[j] = {
					type = ({ "Fire", "Ice", "Lightning", "Poison", "Bleed", "Stun" })[(j % 6) + 1],
					chance = 0.05 + (j * 0.05),
					potency = 1 + (j + i) % 5,
				}
			end
		elseif itemType == 1 then -- Armor
			item.type = "armor"
			item.armorType = ({ "Helmet", "Chestplate", "Leggings", "Boots", "Gloves", "Shield" })[(i % 6) + 1]
			item.defense = 5 + (i % 20)
			item.durability = { current = 85 + (i % 15), max = 100 }
			item.level = 1 + (i % 10)
			item.resistances = {}
			local resistanceTypes = { "Fire", "Ice", "Lightning", "Poison", "Physical" }
			for j = 1, #resistanceTypes do
				item.resistances[resistanceTypes[j]] = (i + j) % 10 * 0.05
			end
		elseif itemType == 2 then -- Consumable
			item.type = "consumable"
			item.consumableType = ({ "Potion", "Food", "Scroll", "Elixir" })[(i % 4) + 1]
			item.effects = {}
			local numEffects = (i % 3) + 1
			for j = 1, numEffects do
				item.effects[j] = {
					stat = ({ "Health", "Mana", "Stamina", "Strength", "Dexterity", "Intelligence" })[(j % 6) + 1],
					amount = 10 + (i + j) % 50,
					duration = (j % 3 == 0) and (30 + (i % 60)) or nil,
					isPercentage = (j % 4 == 0),
				}
			end
			item.cooldown = 10 + (i % 50)
		elseif itemType == 3 then -- Material
			item.type = "material"
			item.materialType = ({ "Ore", "Wood", "Leather", "Cloth", "Stone", "Gem", "Herb" })[(i % 7) + 1]
			item.quality = (i % 5) + 1
			item.usedIn = {}
			local numRecipes = (i % 5) + 1
			for j = 1, numRecipes do
				item.usedIn[j] = "Recipe_" .. tostring(i * 10 + j)
			end
		elseif itemType == 4 then -- Quest Item
			item.type = "questItem"
			item.questId = "Quest_" .. tostring(100 + (i % 50))
			item.description = "A special item needed for quest " .. tostring(100 + (i % 50))
			item.glows = (i % 2 == 0)
		elseif itemType == 5 then -- Accessory
			item.type = "accessory"
			item.accessoryType = ({ "Ring", "Amulet", "Earring", "Belt", "Bracelet" })[(i % 5) + 1]
			item.effects = {}
			local statTypes = { "Strength", "Dexterity", "Intelligence", "Vitality", "Wisdom", "Luck", "Speed" }
			local numEffects = (i % 4) + 1
			for j = 1, numEffects do
				local stat = statTypes[(j % #statTypes) + 1]
				item.effects[stat] = 1 + (i + j) % 10
			end
			item.setId = (i % 3 == 0) and ("Set_" .. tostring(i % 10)) or nil
		elseif itemType == 6 then -- Tool
			item.type = "tool"
			item.toolType = ({ "Pickaxe", "Axe", "Fishing Rod", "Hoe", "Hammer", "Shovel" })[(i % 6) + 1]
			item.efficiency = 1 + (i % 10)
			item.durability = { current = 80 + (i % 20), max = 100 }
			item.level = 1 + (i % 5)
		else -- Miscellaneous
			item.type = "misc"
			item.value = 1 + (i % 1000)
			item.description = "A miscellaneous item with ID " .. tostring(i)
			item.tags = {}
			local numTags = (i % 5) + 1
			for j = 1, numTags do
				item.tags[j] = "Tag_" .. tostring((j + i) % 20)
			end
		end

		gameWorld.playerData.inventory[i] = item
	end

	-- Add 50 quests
	for i = 1, 50 do
		local questType = i % 5
		local quest = {
			id = "Quest_" .. tostring(100 + i),
			name = "Quest Title " .. tostring(i),
			description = "This is the description for quest "
				.. tostring(i)
				.. ". It contains details about what needs to be done.",
			level = 1 + (i % 20),
			isMainQuest = (i % 10 == 0),
			status = ({ "Not Started", "In Progress", "Completed", "Failed" })[(i % 4) + 1],
			giver = "NPC_" .. tostring(1 + (i % 500)),
			location = {
				x = (i % 40) * 100,
				y = 0,
				z = math.floor(i / 40) * 100,
			},
		}

		if questType == 0 then -- Kill Quest
			quest.type = "kill"
			quest.target = {
				type = "Monster_" .. tostring(20 + (i % 30)),
				count = 5 + (i % 20),
				current = 0,
			}
		elseif questType == 1 then -- Gather Quest
			quest.type = "gather"
			quest.items = {}
			local numItems = (i % 3) + 1
			for j = 1, numItems do
				quest.items[j] = {
					id = j * 100 + i,
					name = "Item_" .. tostring(j * 100 + i),
					count = 2 + (j % 10),
					current = 0,
				}
			end
		elseif questType == 2 then -- Delivery Quest
			quest.type = "delivery"
			quest.item = {
				id = 1000 + i,
				name = "Delivery Item " .. tostring(i),
			}
			quest.recipient = "NPC_" .. tostring(100 + (i % 400))
			quest.timeLimit = (i % 2 == 0) and (300 + (i % 600)) or nil
		elseif questType == 3 then -- Escort Quest
			quest.type = "escort"
			quest.npc = {
				id = "EscortNPC_" .. tostring(i),
				name = "Person to Escort " .. tostring(i),
			}
			-- Set a default position for the escort NPC (using the quest location)
			quest.npc.position = {
				x = quest.location.x,
				y = quest.location.y,
				z = quest.location.z,
			}
			quest.destination = {
				x = ((i + 20) % 40) * 100,
				y = 0,
				z = math.floor((i + 20) / 40) * 100,
			}
			quest.enemies = {}
			local numEnemies = (i % 4) + 1
			for j = 1, numEnemies do
				quest.enemies[j] = {
					type = "Monster_" .. tostring(j * 10 + (i % 30)),
					count = 2 + (j % 5),
					spawnPoints = {},
				}
				for k = 1, quest.enemies[j].count do
					quest.enemies[j].spawnPoints[k] = {
						x = quest.npc.position.x + (k * 50) * (k % 2 == 0 and 1 or -1),
						y = 0,
						z = quest.npc.position.z + (k * 40) * (k % 2 == 0 and 1 or -1),
					}
				end
			end
		else -- Exploration Quest
			quest.type = "exploration"
			quest.locations = {}
			local numLocations = (i % 5) + 1
			for j = 1, numLocations do
				quest.locations[j] = {
					name = "Location " .. tostring(i) .. "-" .. tostring(j),
					position = {
						x = ((i * j) % 40) * 100,
						y = 0,
						z = math.floor((i * j) / 40) * 100,
					},
					radius = 10 + (j % 10),
					discovered = false,
				}
			end
		end

		quest.rewards = {
			experience = 100 * (1 + (i % 10)),
			gold = 50 * (1 + (i % 20)),
			reputation = {
				faction = "Faction_" .. tostring(1 + (i % 5)),
				amount = 5 + (i % 20),
			},
			items = {},
		}

		local numRewardItems = (i % 3) + 1
		for j = 1, numRewardItems do
			quest.rewards.items[j] = {
				id = 2000 + i * 10 + j,
				name = "Reward Item " .. tostring(i) .. "-" .. tostring(j),
				count = 1 + (j % 3),
			}
		end

		gameWorld.playerData.quests[i] = quest
	end

	-- Add 50 achievements
	for i = 1, 50 do
		local achievement = {
			id = "Achievement_" .. tostring(i),
			name = "Achievement Title " .. tostring(i),
			description = "This is the description for achievement " .. tostring(i),
			category = ({ "Combat", "Exploration", "Crafting", "Social", "Collection" })[(i % 5) + 1],
			icon = "icon_achievement_" .. tostring(i),
			points = 5 + (i % 45),
			unlocked = (i % 3 == 0),
			dateUnlocked = (i % 3 == 0) and (os.time() - (i % 10000)) or nil,
			progress = {
				current = (i % 3 == 0) and 100 or (i % 100),
				max = 100,
			},
			rewards = {},
		}

		if i % 2 == 0 then achievement.rewards.title = "Title_" .. tostring(i) end

		if i % 3 == 0 then
			achievement.rewards.item = {
				id = 3000 + i,
				name = "Achievement Reward " .. tostring(i),
			}
		end

		if i % 5 == 0 then
			achievement.rewards.cosmetic = {
				id = 4000 + i,
				name = "Cosmetic Item " .. tostring(i),
				slot = ({ "Head", "Body", "Back", "Pet", "Effect" })[(i % 5) + 1],
			}
		end

		gameWorld.playerData.achievements[i] = achievement
	end

	-- Add 30 skills
	for i = 1, 30 do
		local skill = {
			id = "Skill_" .. tostring(i),
			name = "Skill " .. tostring(i),
			level = 1 + (i % 100),
			experience = {
				current = (i * 1000) % 10000,
				nextLevel = 10000,
			},
			category = ({ "Combat", "Crafting", "Gathering", "Social", "Movement" })[(i % 5) + 1],
			abilities = {},
		}

		local numAbilities = (i % 10) + 1
		for j = 1, numAbilities do
			skill.abilities[j] = {
				id = i * 100 + j,
				name = "Ability " .. tostring(i) .. "-" .. tostring(j),
				level = 1 + (j % 5),
				cooldown = 10 + (j * 5),
				cost = {
					type = ({ "Mana", "Stamina", "Health", "Focus" })[(j % 4) + 1],
					amount = 5 + (j * 3),
				},
				effects = {},
			}

			local numEffects = (j % 3) + 1
			for k = 1, numEffects do
				skill.abilities[j].effects[k] = {
					type = ({ "Damage", "Heal", "Buff", "Debuff", "Utility" })[(k % 5) + 1],
					potency = 10 + (k * j),
					duration = (k % 2 == 0) and (5 + k * 2) or nil,
					radius = (k % 3 == 0) and (3 + k) or nil,
				}
			end
		end

		gameWorld.playerData.skills[i] = skill
	end

	-- Add 200 world chunks
	for x = 1, 20 do
		for z = 1, 10 do
			local chunkIndex = (x - 1) * 10 + z
			local chunk = {
				position = { x = (x - 1) * 200, z = (z - 1) * 200 },
				biome = ({ "Forest", "Desert", "Plains", "Mountains", "Tundra", "Swamp" })[(chunkIndex % 6) + 1],
				discovered = (chunkIndex % 3 == 0),
				fogOfWar = (chunkIndex % 3 ~= 0),
				weather = ({ "Clear", "Rain", "Snow", "Fog", "Storm" })[(chunkIndex % 5) + 1],
				resources = {},
				danger = 1 + (chunkIndex % 5),
				landmarks = {},
			}

			local numResources = (chunkIndex % 6) + 2
			for i = 1, numResources do
				chunk.resources[i] = {
					type = ({ "Ore", "Wood", "Herb", "Animal", "Fish", "Crystal" })[(i % 6) + 1],
					abundance = ({ "Low", "Medium", "High" })[(i % 3) + 1],
				}
			end

			local numLandmarks = (chunkIndex % 3) + 1
			for i = 1, numLandmarks do
				chunk.landmarks[i] = {
					name = "Landmark " .. tostring(chunkIndex) .. "-" .. tostring(i),
					position = {
						x = chunk.position.x + (i * 50),
						z = chunk.position.z + (i * 40),
					},
					type = ({ "Ruin", "Camp", "Monument", "Cave", "Shrine", "Settlement" })[(i % 6) + 1],
					discovered = (i % 2 == 0),
				}
			end

			gameWorld.chunks[chunkIndex] = chunk
		end
	end

	largeData.gameWorld = gameWorld

	return largeData
end

-- Test cases for different data types
local testCases = {
	booleans = {
		name = "Boolean values",
		values = {
			{ value = true, desc = "true" },
			{ value = false, desc = "false" },
		},
	},

	strings = {
		name = "String values",
		values = {
			{ value = "", desc = "empty string" },
			{ value = "hello", desc = "short string" },
			{ value = string.rep("a", 100), desc = "medium string" },
			{ value = string.rep("Lorem ipsum ", 100), desc = "long string" },
			{ value = string.rep("Lorem ipsum ", 2000), desc = "very long string" },
			{ value = "特殊字符和Unicode", desc = "unicode string" },
		},
	},

	numbers = {
		name = "Number values",
		values = {
			{ value = 0, desc = "zero" },
			{ value = 1, desc = "small positive integer" },
			{ value = 127, desc = "u8 boundary" },
			{ value = 128, desc = "u8 boundary+1" },
			{ value = 255, desc = "u8 max" },
			{ value = 256, desc = "u16 smallest" },
			{ value = 65535, desc = "u16 max" },
			{ value = 65536, desc = "u24 smallest" },
			{ value = 16777215, desc = "u24 max" },
			{ value = 16777216, desc = "u32 smallest" },
			{ value = 4294967295, desc = "u32 max" },
			{ value = 4294967296, desc = "u40 smallest" },
			{ value = 1099511627775, desc = "u40 max" },
			{ value = 1099511627776, desc = "u48 smallest" },
			{ value = 281474976710655, desc = "u48 max" },
			{ value = 281474976710656, desc = "u52 smallest" },
			{ value = 4503599627370495, desc = "u52 max" },
			{ value = -1, desc = "small negative integer" },
			{ value = -128, desc = "n8 boundary" },
			{ value = -129, desc = "n16 smallest" },
			{ value = -32768, desc = "n16 max" },
			{ value = -32769, desc = "n24 smallest" },
			{ value = -8388608, desc = "n24 max" },
			{ value = -8388609, desc = "n32 smallest" },
			{ value = -2147483648, desc = "n32 max" },
			{ value = -2147483649, desc = "n40 smallest" },
			{ value = -549755813888, desc = "n40 max" },
			{ value = -549755813889, desc = "n48 smallest" },
			{ value = -140737488355328, desc = "n48 max" },
			{ value = -140737488355329, desc = "n52 smallest" },
			{ value = -2251799813685248, desc = "n52 max" },
			{ value = 3.14159, desc = "double (pi)" },
			{ value = -3.14159, desc = "negative double" },
			{ value = 1e20, desc = "large exponent" },
		},
	},

	arrays = {
		name = "Array values",
		values = {
			{ value = {}, desc = "empty array" },
			{ value = { 1, 2, 3, 4, 5 }, desc = "small integer array" },
			{ value = { "a", "b", "c" }, desc = "string array" },
			{ value = { true, false, true }, desc = "boolean array" },
			{ value = { 1, "string", true, { nested = "value" } }, desc = "mixed type array" },
		},
	},

	dictionaries = {
		name = "Dictionary values",
		values = {
			{ value = { key = "value" }, desc = "simple dictionary" },
			{ value = { a = 1, b = 2, c = 3 }, desc = "number dictionary" },
			{ value = { ["special key"] = "special value" }, desc = "special key dictionary" },
			{ value = { nested = { further = { evenMore = "deep" } } }, desc = "nested dictionary" },
		},
	},

	complex = {
		name = "Complex structures",
		values = {
			{
				value = {
					user = {
						id = 12345,
						name = "Player1",
						inventory = {
							{ id = 1, name = "Sword", damage = 10, enchanted = true },
							{ id = 2, name = "Shield", defense = 5, enchanted = false },
							{ id = 3, name = "Potion", healing = 20 },
						},
						stats = {
							hp = 100,
							mp = 50,
							level = 10,
							experience = 1234,
						},
						settings = {
							soundEnabled = true,
							musicVolume = 0.7,
							displayName = "SlayerXX",
							friends = { "User123", "GameMaster", "Noobie99" },
						},
					},
					gameState = {
						currentLevel = 5,
						timeElapsed = 345.67,
						checkpoint = { x = 123.45, y = 67.89, z = -12.34 },
						activeBosses = { "Dragon", "Skeleton King" },
					},
				},
				desc = "game save data",
			},
			{
				value = generateLargeTestData(),
				desc = "a really large data",
			},
		},
	},

	buffer = {
		name = "Buffer values",
		values = {
			{ value = buffer.create(0), desc = "simple buffer" },
			{ value = buffer.create(1000), desc = "medium empty buffer" },
			{
				value = (function()
					math.randomseed(0)
					local b = buffer.create(2 ^ 10)
					for i = 0, 2 ^ 10 / 4 - 1 do
						buffer.writeu32(b, i, math.random(0, 31))
					end
					return b
				end)(),
				desc = "medium random buffer",
			},
			{
				value = (function()
					math.randomseed(0)
					local b = buffer.create(2 ^ 28)
					for i = 0, 2 ^ 28 / 4 - 1 do
						buffer.writeu32(b, i, math.random(0, 31))
					end
					return b
				end)(),
				desc = "very large random buffer",
			},
		},
	},

	edgeCases = {
		name = "Edge cases",
		values = {
			{ value = { [1] = "a", [3] = "c", [4] = "d" }, desc = "sparse array" },
			--{ value = {[0] = "zero", [1] = "one"}, desc = "zero-indexed array" },
			--{ value = {["1"] = "string key 1", [1] = "number key 1"}, desc = "mixed string/number keys" },
			{ value = { a = { b = { c = { d = { e = { f = { g = { h = { i = { j = "deep" } } } } } } } } } } },
			desc = "deeply nested",
		},
	},
}

-- Run all tests
local function runTests()
	print("===== Starting Luau Value Compressor Tests =====")

	for categoryName, category in testCases do
		print("\n----- Testing " .. category.name .. " -----")

		for _, testCase in category.values do
			local value = testCase.value
			local desc = testCase.desc or "nil"
			print("\nTesting: " .. desc)

			for level = 1, 3 do
				local success, result = pcall(function()
					local compressed = compress(value, level)
					local decompressed = decompress(compressed)

					local isEqual = deepEquals(value, decompressed)
					local ratio = calcCompressionRatio(compressed, value)
					if not isEqual then
						warn(value)
						warn(decompressed)
					end
					print("  Level " .. level .. ":");
					(isEqual and print or warn :: any)("    Success: " .. tostring(isEqual))
					print("    Original size: " .. #HttpService:JSONEncode(value) .. " bytes")
					print("    Compressed size: " .. #compressed .. " bytes")
					print("    Ratio: " .. string.format("%.2f", ratio * 100) .. "% of JSON size")

					return {
						isEqual = isEqual,
						compressed = compressed,
						compressedSize = #compressed,
						originalSize = #HttpService:JSONEncode(value),
						ratio = ratio,
					}
				end)

				if not success then warn("  Level " .. level .. " ERROR: " .. tostring(result)) end
			end
		end
	end

	print("\n===== Performance Benchmarks =====")

	-- Test with simple, medium, and complex data
	local benchmarkData = {
		{ value = { a = 1, b = "string", c = true }, name = "Simple data" },
		{ value = { array = { 1, 2, 3, 4, 5 }, dict = { a = 1, b = 2, c = { d = 3 } } }, name = "Medium data" },
		{ value = testCases.complex.values[1].value, name = "Complex game data" },
		{ value = testCases.complex.values[2].value, name = "Very large game data" },
	}

	for _, data in benchmarkData do
		print("\nBenchmarking: " .. data.name)
		local results = benchmarkCompression(data.value, 100) -- reduced iterations for quicker tests

		print("  JSON encode time: " .. string.format("%.6f", results.jsonTime) .. " seconds")
		print("  JSON size: " .. results.jsonSize .. " bytes")

		for level = 1, 3 do
			print("  Level " .. level .. ":")
			print("    Compression time: " .. string.format("%.6f", results.compressionTimes[level]) .. " seconds")
			print("    Compressed size: " .. results.compressionSizes[level] .. " bytes")
			print("    Ratio: " .. string.format("%.2f", results.ratios[level] * 100) .. "% of JSON size")
		end

		print("  Decompress time (Level 3): " .. string.format("%.6f", results.decompTime) .. " seconds")
	end

	print("\n===== Tests Completed =====")
end

runTests()

--return {
--	runTests = runTests,
--	testCases = testCases,
--	benchmarkCompression = benchmarkCompression,
--	utilities = {
--		deepEquals = deepEquals,
--		calcCompressionRatio = calcCompressionRatio
--	}
--}
