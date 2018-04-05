#!/usr/bin/env tarantool
local mqtt = require 'mqtt'

local config = {}
config.MQTT_WIRENBOARD_HOST = "192.168.1.59"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "tarantool_iot_scada"
config.HTTP_PORT = 8080

io.stdout:setvbuf("no")

local function http_server_action_handler(req)
   local type_param, action_param = req:param("type"), req:param("action")

   if (type_param ~= nil and action_param ~= nil) then
      if (type_param == "mqtt_send") then
         local command = "0"
         if (action_param == "on") then
            command = "1"
         elseif (action_param == "off") then
            command = "0"
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
