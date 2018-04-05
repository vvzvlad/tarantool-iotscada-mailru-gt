#!/usr/bin/env tarantool
local mqtt = require 'mqtt'
local fiber = require 'fiber'

local config = {}
config.MQTT_WIRENBOARD_HOST = "192.168.1.59"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "tarantool_iot_scada"
config.HTTP_PORT = 8080

io.stdout:setvbuf("no")

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

local function http_server_root_handler(req)
   return req:redirect_to('/dashboard')
end

--//-----------------------------------------------------------------------//--

mqtt.wb = mqtt.new(config.MQTT_WIRENBOARD_ID, true)
local mqtt_ok, mqtt_err = mqtt.wb:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
if (mqtt_ok ~= true) then
   print ("Error mqtt: "..(mqtt_err or "No error"))
   os.exit()
end

local http_server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})

http_server:route({ path = '/action' }, http_server_action_handler)
http_server:route({ path = '/' }, http_server_root_handler)
http_server:route({ path = '/dashboard', file = 'dashboard.html' })

http_server:start()
