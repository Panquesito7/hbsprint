-- Vars

local speed = tonumber(minetest.settings:get("sprint_speed")) or 1.3
local jump = tonumber(minetest.settings:get("sprint_jump")) or 1.1
local key = minetest.settings:get("sprint_key") or "Use"
local dir = minetest.settings:get_bool("sprint_forward_only")
local particles = tonumber(minetest.settings:get("sprint_particles")) or 2
local stamina = minetest.settings:get_bool("sprint_stamina")
local stamina_drain = tonumber(minetest.settings:get("sprint_stamina_drain")) or 2
local replenish = tonumber(minetest.settings:get("sprint_stamina_replenish")) or 2
local starve = minetest.settings:get_bool("sprint_starve")
local starve_drain = tonumber(minetest.settings:get("sprint_starve_drain")) or 0.5
local breath = minetest.settings:get_bool("sprint_breath")
local breath_drain = tonumber(minetest.settings:get("sprint_breath_drain")) or 1
local autohide = minetest.settings:get_bool("hudbars_autohide_stamina") ~= false
if dir ~= false then dir = true end
if stamina ~= false then stamina = true end
if starve ~= false then starve = true end
if breath ~= false then breath = true end

local sprint_timer_step = 0.5
local sprint_timer = 0
local player_stamina = 20
local stamina_timer = 0
local breath_timer = 0
local sprinting = false
local hudbars = false
local starve = false
local monoids = false

if minetest.get_modpath("hudbars") ~= nil then hudbars = true else hudbars = false end
if minetest.get_modpath("hbhunger") ~= nil then starve = true else starve = false end
if minetest.get_modpath("player_monoids") ~= nil then monoids = true else monoids = false end

-- Functions

local function start_sprint(player)
	if not sprinting then
		if monoids then
			player_monoids.speed:add_change(player, speed, "hbsprint:speed")
			player_monoids.jump:add_change(player, jump, "hbsprint:jump")
		else
			player:set_physics_override({speed = speed, jump = jump})
		end
	end
end

local function stop_sprint(player)
	if sprinting then
		if monoids then
			player_monoids.speed:del_change(player, "hbsprint:speed")
			player_monoids.jump:del_change(player, "hbsprint:jump")
		else
			player:set_physics_override({speed = 1, jump = 1})
		end
	end
end

local function drain_stamina(player)
	player_stamina = tonumber(player:get_attribute("stamina"))
	if player_stamina > 0 then
		player:set_attribute("stamina", player_stamina - stamina_drain)
	end
	if hudbars then
		if autohide and player_stamina < 20 then hb.unhide_hudbar(player, "stamina") end
		hb.change_hudbar(player, "stamina", player_stamina)
	end
end

local function replenish_stamina(player)
	player_stamina = tonumber(player:get_attribute("stamina"))
	if player_stamina < 20 then
		player:set_attribute("stamina", player_stamina + stamina_drain)
	end
	if hudbars then
		hb.change_hudbar(player, "stamina", player_stamina)
		if autohide and player_stamina == 20 then hb.hide_hudbar(player, "stamina") end
	end
end

local function drain_hunger(player, hunger, name)
	if hunger > 0 then
		hbhunger.hunger[name] = hunger - starve_drain
		hbhunger.set_hunger_raw(player)
	end
end

local function drain_breath(player)
	local player_breath = player:get_breath()
	if player_breath < 11 then
		player_breath = player_breath - breath_drain
		if player_breath > 0 then
			player:set_breath(player_breath)
		end
	end
end

local function create_particles(player, name, pos, ground)
	if ground and ground.name ~= "air" and ground.name ~= "ignore" then
		local def = minetest.registered_nodes[ground.name]
		local tile = def.tiles[1] or def.inventory_image or ""
		if type(tile) == "string" then
			for i = 1, particles do
				minetest.add_particle({
					pos = {x = pos.x + math.random(-1,1) * math.random() / 2, y = pos.y + 0.1, z = pos.z + math.random(-1,1) * math.random() / 2},
					velocity = {x = 0, y = 5, z = 0},
					acceleration = {x = 0, y = -13, z = 0},
					expirationtime = math.random(),
					size = math.random() + 0.5,
					vertical = false,
					texture = tile,
				})
			end
		end
	end
end

-- Registrations

if minetest.get_modpath("hudbars") ~= nil and stamina then
	hb.register_hudbar("stamina",
		0xFFFFFF,
		"Stamina",
		{ bar = "sprint_stamina_bar.png", icon = "sprint_stamina_icon.png", bgicon = "sprint_stamina_bgicon.png" },
		player_stamina, player_stamina,
		false, "%s: %.1f/%.1f")
	hudbars = true
	if autohide then
		hb.hide_hudbar(player, "stamina")
	end
end

minetest.register_on_joinplayer(function(player)
	if hudbars and stamina then hb.init_hudbar(player, "stamina") end
	player:set_attribute("stamina", 20)
end)

minetest.register_globalstep(function(dtime)
	sprint_timer = sprint_timer + dtime
	stamina_timer = stamina_timer + dtime
	breath_timer = breath_timer + dtime
	if sprint_timer >= sprint_timer_step then
		for _,player in ipairs(minetest.get_connected_players()) do
			local ctrl = player:get_player_control()
			local key_press = false
			if key == "Use" and dir then
				key_press = ctrl.aux1 and ctrl.up and not ctrl.left and not ctrl.right
			elseif key == "Use" and not dir then
				key_press = ctrl.aux1
			end

			-- if key == "W" and dir then
			-- 	key_press = ctrl.aux1 and ctrl.up or key_press and ctrl.up
			-- elseif key == "W" then
			-- 	key_press = ctrl.aux1 or key_press and key_tap
			-- end

			if key_press then
				local name = player:get_player_name()
				local hunger = 30
				local pos = player:get_pos()
				local ground = minetest.get_node_or_nil({x=pos.x, y=pos.y-1, z=pos.z})
				local walkable = false
				if starve then
					hunger = tonumber(hbhunger.hunger[name])
				end
				if ground ~= nil then
					walkable = minetest.registered_nodes[ground.name].walkable
				end
				if player_stamina > 0 and hunger > 9 and walkable then
					start_sprint(player)
					sprinting = true
					if stamina then drain_stamina(player) end
					if starve then drain_hunger(player, hunger, name) end
					if breath then
						if breath_timer >= 2 then
							drain_breath(player)
							breath_timer = 0
						end
					end
					if particles then create_particles(player, name, pos, ground) end
				else
					stop_sprint(player)
					sprinting = false
				end
			else
				stop_sprint(player)
				sprinting = false
				if stamina_timer >= replenish then
					if stamina then replenish_stamina(player) end
					stamina_timer = 0
				end
			end
		end
		sprint_timer = 0
	end
end)
