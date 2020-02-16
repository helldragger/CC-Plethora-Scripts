local yieldTime = os.clock()
local function yield()
    coroutine.yield()
    --local YIELD_SPAN = 0.5
    --if os.clock() - yieldTime > YIELD_SPAN then
    --    os.queueEvent("yield")
    --    os.pullEvent("yield")
    --    yieldTime = os.clock()
    --end
end

local DEBUG_LOG_FILE = "fly_debug.log"
if fs.exists(DEBUG_LOG_FILE) then fs.delete(DEBUG_LOG_FILE) end

local function printDebug(msg)
    msg = "["..os.date().."] "..msg.."\n"
    --print(msg)
    local log = fs.open(DEBUG_LOG_FILE, "a")
    log.write(msg)
    log.close()
end

-- NEURAL INTERFACE REQUIRED
local modules = peripheral.find("neuralInterface")
if not modules then error("Must have a neural interface", 0) end

-- MODULES REQUIRED
if not modules.hasModule("plethora:sensor") then error("Must have a sensor", 0) end
if not modules.hasModule("plethora:scanner") then error("Must have a scanner", 0) end
if not modules.hasModule("plethora:introspection") then error("Must have an introspection module", 0) end
if not modules.hasModule("plethora:kinetic", 0) then error("Must have a kinetic agument", 0) end

-- DEBUG CONTROL
local DEBUGCALLS = true
local DEBUGINPUT = false

-- KILL SWITCH CONTROL
local stop = false

-- PLAYER DATA CACHE
local meta = modules.getMetaOwner()

local function refreshMeta()    
    os.pullEvent("refreshMeta")
    if DEBUGCALLS then printDebug("refresh meta") end
    meta = modules.getMetaOwner()
end

-- LOCATION / HEIGHT ABOVE GROUND CACHE
local scanned = modules.scan()
local function refreshScan()    
    os.pullEvent("refreshScan")
    if DEBUGCALLS then printDebug("refresh scan") end
    scanned = modules.scan()
end

-- LOCATION HELPER
local scanner_radius = 8
local scanner_width = scanner_radius*2 + 1

local function scannedAt(x,y,z)
    return scanned[scanner_width ^ 2 * (x + scanner_radius) + scanner_width * (y + scanner_radius) + (z + scanner_radius) + 1]
end


-- CONTROLS

local fly = false
local flyActivatedTime = -1

local upLastPressedTime=-1
local downLastPressedTime=-1
local frontLastPressedTime=-1
local backLastPressedTime=-1
local rightLastPressedTime=-1
local leftLastPressedTime=-1
local KEY_UP_THRESHOLD = 0.3 --sec

local down = false
local up = false
local front = false
local back = false
local right = false
local left = false

local lastSpaceTime = -1
local spacePressed = false

local hover = false

local in_flight = false

local function controls()
    local event, key, held = os.pullEvent("key")
    if DEBUGCALLS then printDebug("controls") end
    down = (downLastPressedTime-os.clock())<KEY_UP_THRESHOLD
    up = (upLastPressedTime-os.clock())<KEY_UP_THRESHOLD
    front = (frontLastPressedTime-os.clock())<KEY_UP_THRESHOLD
    back = (backLastPressedTime-os.clock())<KEY_UP_THRESHOLD
    right = (rightLastPressedTime-os.clock())<KEY_UP_THRESHOLD
    left = (leftLastPressedTime-os.clock())<KEY_UP_THRESHOLD

    if DEBUGINPUT then 
        if held then
            printDebug( "[key   ] " .. key .. "(held)")
        else
            printDebug( "[key   ] " .. key .. "(down)")
        end
    end

    if key == keys.k then
        stop = true
        print("K pressed, stopping program...")
    elseif key == keys.space and not held then    
        local spaceTime = os.clock()
        local diff = spaceTime - lastSpaceTime
        if (diff < 0.5) then
            fly = not fly
            spaceTime = -1
            if fly then 
                print("FLY MODE ENABLED")
                flyActivatedTime = os.clock()
            else 
                print("FLY MODE DISABLED") 
            end                    
        end 
        lastSpaceTime = spaceTime    
    end

    -- FLIGHT RELATED
    -- shift => descente
    if key == keys.shift then
        down = true
        downLastPressedTime = os.clock()
    end
    -- space => montée 
    if key == keys.space then 
        up = true
        upLastPressedTime = os.clock()
    end
    -- W => en avant
    if key == keys.w then
        front = true
        frontLastPressedTime = os.clock()
    end
    -- S => en arrière 
    if key == keys.s then
        back = true
        backLastPressedTime = os.clock()
    end
    -- A => à gauche
    if key == keys.a then
        left = true
        leftLastPressedTime = os.clock()
    end
    -- D => à droite
    if key == keys.d then
        right = true
        rightLastPressedTime = os.clock()
    end
    -- on check le block sous les pieds du joueur
    in_flight = scannedAt(8,0,8).name ~= "minecraft:air"
    if DEBUGINPUT then
        local pressed = ""
        if up then pressed = pressed.."UP " end
        if down then pressed = pressed.."DOWN " end
        if front then pressed = pressed.."FRONT " end
        if back then pressed = pressed.."BACK " end
        if right then pressed = pressed.."RIGHT " end
        if left then pressed = pressed.."LEFT " end
        printDebug(pressed)
    end
    -- on lance une iteration de fly
    if fly then os.queueEvent("fly") end
    -- on refresh nos données
    os.queueEvent("refreshMeta")
    os.queueEvent("refreshScan")
end


-- pitch = vertical
-- yaw = horizontal
-- both use -180 -> 180 degrees
-- lauynche(yaw, pitch, power)
-- i.e.: up = launch(0, -90, power)
-- north: -180|180
-- south: 0|360
-- east : -90|280
-- west : -280|90
--
--  0    --> 360
--  -360 --> 0
--
-- 2.W   3.N
--   \   /
--     X
--   /   \
-- 1.S   4.E     
-- Sens horaire so to the right = theta > 0
-- to the left theta < 0
--

local function addYaw(theta, delta)
    theta = theta + delta
    if theta < -360 then
        theta = theta + 360
    elseif theta > 360 then
        theta = theta - 360
    end
    return theta
end

local function flyMode()
    os.pullEvent("fly")
    if DEBUGCALLS then printDebug("fly") end
    if fly then
        -- si au sol => fly mode desactivé
        
        if not in_flight and not up and (os.clock()-flyActivatedTime) > 0.5 then
            fly = false
            print("Ground reached, fly disabled")
            return
        end

        -- YAW (horizontal)
        local theta = 0
        if left then theta = addYaw(theta, -90) end
        if right then theta = addYaw(theta, 90) end
        if front then theta = addYaw(theta, 0) end
        if back then theta = addYaw(theta, 180) end        
        if DEBUGCALLS then printDebug("fly: current theta = "..meta.yaw) end

        theta = addYaw(meta.yaw, theta)        
        if DEBUGCALLS then printDebug("fly: theta after taking horizontal move = "..theta) end


        -- PITCH (vertical)
        pitch = 0
        if up then pitch = -90 end
        if down then pitch = 90 end
        if left or right or front or back then pitch = pitch / 4 end
        if DEBUGCALLS then printDebug("fly: current pitch = "..meta.pitch) end
        pitch =  meta.pitch + pitch
        if DEBUGCALLS then printDebug("fly: pitch after taking vertical move = "..pitch) end

        -- POWER (speed)
        power = (meta.motionY^2 + meta.motionX^2)^0.5
        if DEBUGCALLS then printDebug("fly: current power = "..power) end

        if left or right or front or back then power = power+0.1 end
        if DEBUGCALLS then printDebug("fly: power after horizontal move = "..power) end
        if up or down then power = power+0.3 end
        if DEBUGCALLS then printDebug("fly: power after vertical move = "..power) end
        local MAXSPEED = 4
        power = math.max(MAXSPEED - power, 0)
        
        -- APPLY
        if DEBUGCALLS then printDebug("fly: launch("..theta..", "..pitch..", "..power..")") end
        modules.launch(theta, pitch, power)
    end
end

local function hoverMode()
    os.pullEvent("hover")
    if DEBUGCALLS then printDebug("hover") end
    if hover then
        local mY = meta.motionY
        mY = (mY - 0.138) / 0.8
        if mY > 0.5 or mY < 0 then
            local sign = 1
            if mY < 0 then sign = -1 end
            modules.launch(meta.yaw, 90 * sign, math.min(4, math.abs(mY)))
        end
    end
end


local function fallCushion()    
    os.pullEvent("fallCushion")
    if DEBUGCALLS then printDebug("fall cushion") end
    if in_flight and not down and not up and meta.motionY < -0.3 then
        for y = 0, -8, -1 do
            local block = scannedAt(8,y,8)
            if block.name ~= "minecraft:air" then
                modules.launch( meta.yaw,
                                -90, 
                                math.min(4, meta.motionY / -0.5))
                break
            end
        end
    end
end

local function untilKill(func, doesYield)
    while not stop do
        if doesYield then yield() end
        func()
    end
end

-- MAIN LOOP
print("FLY program started, press K to stop")

parallel.waitForAny(
    function() 
        untilKill(refreshMeta, false)
    end,
    function() 
        untilKill(refreshScan, false)
    end,
    function() 
        untilKill(controls, false)
    end,
    function() 
        untilKill(flyMode, false)
    end--,
    --function() 
    --    untilKill(hoverMode)
    --end,
    --function() 
    --    untilKill(fallCushion)
    --end
)
