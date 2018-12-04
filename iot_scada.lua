#!/usr/bin/env tarantool
local mqtt = require 'mqtt'
local fiber = require 'fiber'
local clock = require 'clock'

local config = {}
config.MQTT_WIRENBOARD_HOST = "192.168.1.111"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "tarantool_iot_scada"
config.HTTP_PORT = 8080

io.stdout:setvbuf("no")

local box = box -- Fake define for disabling IDE warnings

local storage

local function play_star_wars()
   local function play()
      local imperial_march = {{392, 350}, {392, 350}, {392, 350}, {311, 250}, {466, 100}, {392, 350}, {311, 250}, {466, 100}, {392, 700}, {392, 350}, {392, 350}, {392, 350}, {311, 250}, {466, 100}, {392, 350}, {311, 250}, {466, 100}, {392, 700}, {784, 350}, {392, 250}, {392, 100}, {784, 350}, {739, 250}, {698, 100}, {659, 100}, {622, 100}, {659, 450}, {415, 150}, {554, 350}, {523, 250}, {493, 100}, {466, 100}, {440, 100}, {466, 450}, {311, 150}, {369, 350}, {311, 250}, {466, 100}, {392, 750}}
      for i = 1, #imperial_march do
         local delay = imperial_march[i][2]
         local freq = imperial_march[i][1]
         mqtt.wb:publish("/devices/buzzer/controls/frequency/on", freq, mqtt.QOS_0, mqtt.NON_RETAIN)
         mqtt.wb:publish("/devices/buzzer/controls/enabled/on", 1, mqtt.QOS_0, mqtt.NON_RETAIN)
         fiber.sleep(delay/1000*2)
         mqtt.wb:publish("/devices/buzzer/controls/enabled/on", 0, mqtt.QOS_0, mqtt.NON_RETAIN)
         fiber.sleep(delay/1000/3)
      end
   end
   fiber.create(play)
end


local function http_server_action_handler(req)
   local type_param, action_param = req:param("type"), req:param("action")

   if (type_param ~= nil and action_param ~= nil) then
      if (type_param == "mqtt_send") then
         local command = "0"
         if (action_param == "on") then
            command = "1"
         elseif (action_param == "off") then
            command = "0"
         elseif (action_param == "sw") then
            play_star_wars()
         end
         local result = mqtt.wb:publish("/devices/buzzer/controls/enabled/on", command, mqtt.QOS_1, mqtt.NON_RETAIN)
         return req:render{ json = { mqtt_result = result } }
      end
   end
end

local function get_values_for_table(serial)
   local temperature_data_object, i = {}, 0
   for _, tuple in storage.index.serial:pairs(serial) do
      i = i + 1
      local time_in_sec = math.ceil(tuple["timestamp"]/10000)
      local absolute_time_text = os.date("%Y-%m-%d, %H:%M:%S", time_in_sec)

      temperature_data_object[i] = {}
      temperature_data_object[i].serial = tuple["serial"]
      temperature_data_object[i].temperature = tuple["value"]
      temperature_data_object[i].time_epoch = tuple["timestamp"]
      temperature_data_object[i].time_text = absolute_time_text
   end
   return temperature_data_object
end

local function get_values_for_graph(serial)
   local temperature_data_object, i = {}, 1
   temperature_data_object[1] = {"Time", "Value"}
   for _, tuple in storage.index.serial:pairs(serial) do
      i = i + 1
      local time_in_sec = math.ceil(tuple["timestamp"]/10000)
      temperature_data_object[i] = {os.date("%H:%M", time_in_sec), tuple["value"]}
   end
   return temperature_data_object
end

local function gen_id()
   local new_id = clock.realtime()*10000
   while storage.index.timestamp:get(new_id) do
      new_id = new_id + 1
   end
   return new_id
end

local function save_value(serial, value)
   value = tonumber(value)
   if (value ~= nil and serial ~= nil) then
      storage:insert({serial, gen_id(), value})
      return true
   end
   return false
end

local function http_server_data_handler(req)
   local params = req:param()

   if (params["data"] == "table") then
      local values = get_values_for_table(params["serial"])
      return req:render{ json = { values } }
   elseif (params["data"] == "graph") then
      local values = get_values_for_graph(params["serial"])
      return req:render{ json = { values } }
   end


   return req:render{ json = { none_data = "true" } }
end

local function http_init()
   local http_server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})
   http_server:route({ path = '/action' }, http_server_action_handler)
   http_server:route({ path = '/data' }, http_server_data_handler)
   http_server:route({ path = '/' }, function(req) return req:redirect_to('/dashboard') end)
   http_server:route({ path = '/dashboard', file = 'dashboard.html' })
   http_server:start()
end

local function mqtt_init()
   local function mqtt_callback(message_id, topic, payload, gos, retain)
      local topic_pattern = "/devices/wb%-w1/controls/(%S+)"
      local _, _, sensor_address = string.find(topic, topic_pattern)
      local result = save_value(sensor_address, payload)
      if (result ~= true) then print("Error save value to DB(address, payload):", sensor_address, payload) end
   end

   mqtt.wb = mqtt.new(config.MQTT_WIRENBOARD_ID, true)
   local mqtt_ok, mqtt_err = mqtt.wb:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
   if (mqtt_ok ~= true) then
      print ("Error mqtt: "..(mqtt_err or "No error"))
      os.exit()
   end

   mqtt.wb:on_message(mqtt_callback)
   mqtt.wb:subscribe('/devices/wb-w1/controls/+', 0)
end

local function database_init()
   box.cfg { log_level = 4 }
   box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})
   local format = {
      {name='serial',      type='string'},   --1
      {name='timestamp',   type='number'},   --2
      {name='value',       type='number'},   --3
   }
   storage = box.schema.space.create('storage', {if_not_exists = true, format = format})
   storage:create_index('timestamp', {parts = {'timestamp'}, if_not_exists = true})
   storage:create_index('serial', {parts = {'serial'}, unique = false, if_not_exists = true})
end


--//-----------------------------------------------------------------------//--

database_init()
mqtt_init()
http_init()

if pcall(require('console').start) then -- Init console
   os.exit(0)
end
