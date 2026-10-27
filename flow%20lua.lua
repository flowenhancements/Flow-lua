local AC = {}

AC.LoaderGate = {}

AC.LoaderGate.STATE_KEY = "_________FLOW_FLOW_FLOW67"

function AC.LoaderGate.getState()
	return getgenv()[AC.LoaderGate.STATE_KEY]
end

function AC.LoaderGate.setState(v)
	getgenv()[AC.LoaderGate.STATE_KEY] = v
end

AC.LoaderGate.EXPECTED_BYTECODE = {
	Root                    = { [1914481512] = false },
	ReplicatedController    = { [1936447744] = false },
	MiscellaneousController = { [3892767096] = false, [337076960] = false },
	LocalScript3            = { [3892767096] = false, [337076960] = false },
	ClientFighter           = { [2191862192] = false },
}

local function sumHash(t)
	local h = 0
	for _, v in pairs(t) do
		if type(v) ~= "number" then return 0 end
		h = h + v
	end
	return h
end

function AC.LoaderGate.verifyGameFiles()
	local expected = AC.LoaderGate.EXPECTED_BYTECODE
	local deadline = tick() + 60

	while tick() < deadline do
		for _, scr in getscripts() do
			local bucket = expected[scr.Name]
			if bucket == nil then continue end
			local ok, bytecode = pcall(getscriptbytecode, scr)
			if not ok or bytecode == nil then continue end
			local h = sumHash(bytecode)
			if bucket[h] == false then
				bucket[h] = true
			end
		end

		local missing = false
		for _, bucket in expected do
			local satisfied = false
			for _, hit in bucket do
				if hit then satisfied = true break end
			end
			if not satisfied then missing = true break end
		end
		if not missing then return true end

		task.wait(0.5)
	end
	return false
end

function AC.LoaderGate.bypass1()
	local deadline = tick() + 10
	while tick() < deadline do
		task.wait(1.5)
	end
	return true
end

function AC.LoaderGate.bypass2(indexFn, storeSlot)
	while true do
		local gc = getgc(true)
		for _, obj in gc do
			if type(obj) ~= "table" then continue end
			local probe = indexFn(obj, "GetCameraData")
			if probe == nil then continue end
			storeSlot[1] = obj
			return true
		end
		task.wait()
	end
end

function AC.LoaderGate.run(indexFn)
	local LocalPlayer = cloneref(game:GetService("Players")).LocalPlayer

	local state = AC.LoaderGate.getState()
	if state == "Loaded" then return true end
	if state == "Loading" then
		repeat task.wait() until AC.LoaderGate.getState() == "Loaded"
		return true
	end

	AC.LoaderGate.setState("Loading")
	repeat task.wait() until game:IsLoaded()

	if not AC.LoaderGate.verifyGameFiles() then
		LocalPlayer:Kick("Not all game files are what we expected.. wait for an update or try again!")
		return false
	end
	if not AC.LoaderGate.bypass1() then
		LocalPlayer:Kick("Failed to run bypasses (1)")
		return false
	end
	if not AC.LoaderGate.bypass2(indexFn, {}) then
		LocalPlayer:Kick("Failed to run bypasses (2)")
		return false
	end

	AC.LoaderGate.setState("Loaded")
	return true
end

AC.CameraCodec = {}

function AC.CameraCodec.encodeSingle(a)
	if a == a then
		return utf8.char(math.clamp(math.floor(a % (2 * math.pi) / math.pi / 2 * 256 + 0.5), 0, 255))
	end
	return utf8.char(0)
end

function AC.CameraCodec.encodeCameraRotation(v)
	if v == v then
		return utf8.char(math.clamp(math.floor(v.X % (2 * math.pi) / math.pi / 2 * 256 + 0.5), 0, 255))
			.. utf8.char(math.clamp(math.floor(v.Y % (2 * math.pi) / math.pi / 2 * 256 + 0.5), 0, 255))
	end
	return utf8.char(0) .. utf8.char(0)
end

function AC.CameraCodec.decodeSingle(s)
	return utf8.codepoint(s) * math.pi * 2 / 256
end

function AC.CameraCodec.fromXYToCameraRotation(x, y)
	return Vector2.new(x, y) * math.pi * 2 / 256
end

function AC.CameraCodec.decodeCameraRotation(v)
	return AC.CameraCodec.fromXYToCameraRotation(utf8.codepoint, v)
end

local ViewAngleDriver = {}
ViewAngleDriver.__index = ViewAngleDriver
AC.ViewAngleDriver = ViewAngleDriver

function ViewAngleDriver.new()
	return setmetatable({
		_slots           = {},
		_winning         = nil,
		_fullySuppressed = false,
		_dirty           = false,
	}, ViewAngleDriver)
end

function ViewAngleDriver._encodeSpec(spec)
	if spec.kind == "Unnormalized" then
		return utf8.char(math.clamp(spec.pitch, 0, 255)) .. utf8.char(math.clamp(spec.yaw, 0, 255))
	end
	return AC.CameraCodec.encodeSingle(math.rad(spec.pitch))
		.. AC.CameraCodec.encodeSingle(math.rad(spec.yaw))
end

function ViewAngleDriver._decodeSpec(spec)
	if spec.kind == "Unnormalized" then
		return AC.CameraCodec.fromXYToCameraRotation(spec.pitch, nil)
	end
	local p = AC.CameraCodec.decodeSingle(AC.CameraCodec.encodeSingle(math.rad(spec.pitch)))
	local y = AC.CameraCodec.decodeSingle(AC.CameraCodec.encodeSingle(math.rad(spec.yaw)))
	return Vector2.new(p, y)
end

function ViewAngleDriver:_LoadReplicationHook(ctx)
	if self._replicationRestore ~= nil then return ctx.VOID_OK end

	local mt = getmetatable(ctx.FighterController)
	if mt == nil then
		return ctx.err("ViewAngleDriver", "get_metatable", "FighterController metatable not found")
	end
	local proto = ctx.index(mt, "__index")
	if proto == nil then
		return ctx.err("ViewAngleDriver", "get_prototype", "FighterController prototype not found")
	end
	local loopFn = ctx.index(proto, "_CameraReplicationLoop")
	if loopFn == nil then
		return ctx.err("ViewAngleDriver", "function_lookup",
			"FighterController._CameraReplicationLoop method not found")
	end

	local utilityIndex, utility
	for i, uv in debug.getupvalues(loopFn) do
		if type(uv) ~= "table" then continue end
		local uvmt = getmetatable(uv)
		if uvmt == nil then continue end
		local uvidx = ctx.index(uvmt, "__index")
		if uvidx == nil or ctx.index(uvidx, "EncodeCameraRotation") == nil then continue end
		utility, utilityIndex = uv, i
		break
	end
	if utilityIndex == nil or utility == nil then
		return ctx.err("ViewAngleDriver", "upvalue_search", "Utility upvalue index not found")
	end

	local shim = {}
	function shim.EncodeCameraRotation(_, v)
		if next(self._slots) == nil and not self._fullySuppressed then
			return AC.CameraCodec.encodeCameraRotation(v)
		end
		ctx.setfield(ctx.FighterController, "_replication_stopped", false)
		local cached = ctx.getfield(ctx.FighterController, "_last_encoded_camera_rotation")
		if not cached then
			cached = AC.CameraCodec.encodeCameraRotation(v)
		end
		return cached
	end

	debug.setupvalue(loopFn, utilityIndex, shim)
	self._replicationRestore = {
		cameraReplicationLoopMethod = loopFn,
		utilityIndex                = utilityIndex,
		utility                     = utility,
	}
	return ctx.VOID_OK
end

function ViewAngleDriver:_LoadJointsHook(ctx)
	if self._jointsRestore ~= nil then return ctx.VOID_OK end

	local original = ctx.index(ctx.ClientFighterCharacterJoints, "Update")
	if original == nil then
		return ctx.err("ViewAngleDriver", "function_lookup", "Joints.Update method not found")
	end

	local function patched(joints, a, payload)
		local fighter = ctx.index(joints, "ClientFighterCharacter")
		if fighter then fighter = ctx.index(fighter, "ClientFighter") end
		if fighter == nil then return original(joints, a, payload) end

		if ctx.index(fighter, "IsLocalPlayer") == true then
			local winning = self._winning
			if winning ~= nil then
				ctx.setfield(payload, "CameraRotationRaw", ViewAngleDriver._decodeSpec(winning))
			end
		end
		return original(joints, a, payload)
	end

	ctx.setfield(ctx.ClientFighterCharacterJoints, "Update", patched)
	self._jointsRestore = { jointsUpdateMethod = original }
	return ctx.VOID_OK
end

function ViewAngleDriver:_Resolve()
	self._winning = nil
end

function ViewAngleDriver:SendViewAngles(slot, spec, ctx)
	if self._slots[slot] == spec then return ctx.VOID_OK end
	self._slots[slot] = spec
	self._dirty = true
	self:_Resolve()
	if self._winning == nil then return ctx.VOID_OK end

	local r = self:_LoadJointsHook(ctx)
	if r.ok then return self:_LoadReplicationHook(ctx) end
	return r
end

function ViewAngleDriver:SendRawCameraRotation(encoded, ctx)
	ctx.fire(ctx.UpdateCameraRotationRemote, encoded, nil)
end

function ViewAngleDriver:Suppress(on, ctx)
	if self._fullySuppressed == on then return ctx.VOID_OK end
	self._fullySuppressed = on
	if on then return self:_LoadReplicationHook(ctx) end
	return ctx.VOID_OK
end

function ViewAngleDriver:ClearAll()
	table.clear(self._slots)
	self._winning = nil
	self._dirty = false
end

function ViewAngleDriver:Flush(ctx)
	if not self._dirty then return end
	if self._fullySuppressed then return end
	local winning = self._winning
	if winning == nil then self._dirty = false return end
	self._dirty = false
	ctx.fire(ctx.UpdateCameraRotationRemote, ViewAngleDriver._encodeSpec(winning), nil)
end

function ViewAngleDriver:_RevertHooks(ctx)
	local j = self._jointsRestore
	if j ~= nil then
		self._jointsRestore = nil
		ctx.setfield(ctx.ClientFighterCharacterJoints, "Update", j.jointsUpdateMethod)
	end
	local r = self._replicationRestore
	if r ~= nil then
		self._replicationRestore = nil
		debug.setupvalue(r.cameraReplicationLoopMethod, r.utilityIndex, r.utility)
	end
end

function ViewAngleDriver:Destroy(ctx)
	self:_RevertHooks(ctx)
end

AC.Humanization = {
	Flick = {
		DurationMs = { Min = 30, Max = 400 },
		Curvature  = { Min = 0,  Max = 50 },
		Humanness  = { Min = 0,  Max = 100 },
	},
	Firing = {
		ShotDelayMs = { Min = 0, Max = 250 },
		CooldownMs  = { Min = 0, Max = 2000 },
	},
}

function AC.clampInputSpam(fighter, target, getf, setf)
	local map = getf(fighter, "InputSpammingEnabled")
	if map == nil then return end
	if target == nil then
		setf(fighter, "InputSpammingEnabled", map)
		return
	end
	local clone = table.clone(map)
	clone.StartShooting  = 0
	clone.StartReloading = 0
	setf(fighter, "InputSpammingEnabled", clone)
end

function AC.asIdentity(level, fn, ...)
	local prev = getthreadidentity()
	setthreadidentity(level)
	local results = table.pack(fn(...))
	setthreadidentity(prev)
	return table.unpack(results, 1, results.n)
end

AC.EnvAudit = {}

AC.EnvAudit.CLASSIFIERS = {
	"islclosure", "iscclosure", "isourclosure", "isexecutorclosure",
	"checkclosure", "isnewcclosure", "isfunctionhooked",
}

AC.EnvAudit.TARGETS = {
	"__index", "__newindex",
	"FireServer", "FireServerUnreliable", "FindFirstChildOfClass",
	"getrawmetatable", "setrawmetatable", "sethiddenproperty",
	"clonefunction", "hookfunction", "replaceclosure", "restorefunction",
	"oth_is_hook_thread", "oth_get_root_callback", "oth_get_original_thread",
	"islclosure", "iscclosure", "isourclosure", "isexecutorclosure",
	"checkclosure", "isnewcclosure", "isfunctionhooked", "GetMouse",
}

AC.EnvAudit.PRE_CHECKS = {
	"pre:getrawmetatable.islclosure",
	"pre:getrawmetatable.iscclosure",
	"pre:getrawmetatable.isexecutorclosure",
	"pre:getrawmetatable.isfunctionhooked",
	"pre:getrawmetatable.src_not_C",
	"pre:setrawmetatable.islclosure",
	"pre:setrawmetatable.iscclosure",
	"pre:setrawmetatable.isexecutorclosure",
	"pre:setrawmetatable.isfunctionhooked",
	"pre:setrawmetatable.src_not_C",
}

AC.EnvAudit.KNOWN_TRUTH_TAGS = {
	"known-truth:trampoline_bypassed",
	"known-truth:ifh_lied_about_known_hook",
	"known-truth:ifh_not_restored",
	"known-truth:iec_not_restored",
}

function AC.EnvAudit.probeReferences()
	return Instance.new("RemoteEvent").FireServer,
		Instance.new("UnreliableRemoteEvent").FireServer
end

function AC.EnvAudit.knownTruthTrampoline(report)
	local reached = false

	local originalClone
	local function cloneWrapper(...) return originalClone(...) end
	originalClone = hookfunction(clonefunction, cloneWrapper)

	local originalIFH
	local function ifhSentinel(fn)
		reached = true
		return originalIFH(fn)
	end
	originalIFH = hookfunction(isfunctionhooked, ifhSentinel)

	local answer = isfunctionhooked(clonefunction)

	if not reached then
		report("known-truth:trampoline_bypassed")
		restorefunction(isfunctionhooked)
		restorefunction(clonefunction)
		return true
	end
	if not answer then
		report("known-truth:ifh_lied_about_known_hook")
		restorefunction(isfunctionhooked)
		restorefunction(clonefunction)
		return true
	end

	restorefunction(isfunctionhooked)
	restorefunction(clonefunction)

	if isfunctionhooked(isfunctionhooked) then
		report("known-truth:ifh_not_restored")
		return true
	end
	return false
end

AC.Sentinel = {
	slots = 30,
	guarded = { [2] = "f10436", [8] = "print", [17] = "f10434" },
	statusBytes = { 147, 218, 250 },
}

AC.DevModeGlobals = { "LUARMOR_SkipAntidebugDevMode", "LUARMOR_AllowKeyCheckSkip" }


local environment = getgenv()
local previous_unload = rawget(environment, "unload_all")
if type(previous_unload) == "function" then
	pcall(previous_unload)
end
environment.unload_all = nil
environment.__flowlua_generation = (tonumber(environment.__flowlua_generation) or 0) + 1
local load_generation = environment.__flowlua_generation
environment.flowlua_loaded = false
environment.flowlua_loading = true

if not game:IsLoaded() then
	local deadline = os.clock() + 30
	repeat task.wait(0.1) until game:IsLoaded() or os.clock() >= deadline
end

if not game:IsLoaded() then
	environment.flowlua_loading = false
	return AC
end

local players = game:GetService("Players")

local localplayer = players.LocalPlayer

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local user_input_service = game:GetService("UserInputService")

local run_service = game:GetService("RunService")

local virtual_user = game:GetService("VirtualUser")

local workspace = game:GetService("Workspace")

local http_service = game:GetService("HttpService")

local teleport_service = game:GetService("TeleportService")

local lighting = game:GetService("Lighting")

local TweenService = game:GetService("TweenService")
local manip_ray_params = RaycastParams.new()
local manip_offsets = {
 Vector3.new(0,12,0), Vector3.new(0,16,0), Vector3.new(0,20,0), Vector3.new(0,24,0),
 Vector3.new(0,28,0), Vector3.new(0,32,0), Vector3.new(0,36,0), Vector3.new(0,40,0),
}
local manipulation = {}
do
 manipulation.get_closest = function()
  if not localplayer.Character or not localplayer.Character:FindFirstChild("HumanoidRootPart") then return nil, nil end
  local target, char, dist = nil, nil, math.huge
  for _, v in next, players:GetPlayers() do
   if v ~= localplayer and v.Character and v.Character:FindFirstChild("Head") then
    local mag = (localplayer.Character.HumanoidRootPart.Position - v.Character.Head.Position).Magnitude
    if mag < dist then dist = mag; target = v.Character.Head; char = v.Character end
   end
  end
  return target, char
 end
 manipulation.calculate_point = function(origin, target_pos, target_char)
  manip_ray_params.FilterDescendantsInstances = {localplayer.Character, target_char}
  manip_ray_params.FilterType = Enum.RaycastFilterType.Exclude
  if not workspace:Raycast(origin, target_pos - origin, manip_ray_params) then return origin, nil end
  for _, offset in next, manip_offsets do
   local scan_pos = origin + offset
   if not workspace:Raycast(scan_pos, target_pos - scan_pos, manip_ray_params) then return scan_pos, offset.Y end
  end
  return nil, nil
 end
 manipulation.fire_toward = function(target_part, target_char)
  pcall(function()
   local rs = game:GetService("ReplicatedStorage")
   local util_ok, util = pcall(require, rs.Modules.Utility)
   local enums_ok, enums = pcall(require, rs.Modules.EnumLibrary)
   local fighter_ok, fighter = pcall(require, localplayer.PlayerScripts.Controllers.FighterController)
   if not util_ok or not enums_ok or not fighter_ok then return end
   if not fighter.LocalFighter then return end
   local item = fighter.LocalFighter.EquippedItem
   if not item then return end
   local cam = workspace.CurrentCamera.CFrame
   local manip_pt, height = manipulation.calculate_point(cam.Position, target_part.Position, target_char)
   if not manip_pt then return end
   local shoot_pos = (height == nil and manip_pt) or cam.Position
   local cameradata = {}
   cameradata[utf8.char(1)] = {
    [utf8.char(0)] = util:EncodeCFrame(CFrame.new(shoot_pos.X, shoot_pos.Y + (height or 0), shoot_pos.Z) * CFrame.Angles(CFrame.lookAt(shoot_pos, target_part.Position):ToOrientation())),
    [utf8.char(1)] = height and util:EncodeCFrame(CFrame.new(target_part.Position) * CFrame.Angles(CFrame.lookAt(shoot_pos, target_part.Position):ToOrientation())) or util:EncodeCFrame(CFrame.new(shoot_pos.X, shoot_pos.Y + (height or 0), shoot_pos.Z) * CFrame.Angles(CFrame.lookAt(shoot_pos, target_part.Position):ToOrientation())),
    [utf8.char(2)] = target_part,
    [utf8.char(3)] = util:EncodeCFrame(target_part.CFrame:ToObjectSpace(CFrame.new(target_part.Position))),
   }
   rs.Remotes.Replication.Fighter.UseItem:FireServer(item:Get("ObjectID"), enums:ToEnum("StartShooting"), cameradata, nil)
  end)
 end
end

getgenv().config = {
 riot_abuser_v1_enabled = false, riot_abuser_v1_spin_speed = 720, riot_abuser_v1_tracking_position = "Behind", riot_abuser_v1_tracking_distance = 3,
 et_order = "spiral", et_mode = "Random", et_speed = 1000, et_total = 1000, riot_bypass_enabled = false, riot_bypass_distance = 3, riot_bypass_position = "Behind",
 riot_bypass_height = 0, riot_bypass_update_rate = 0.5, riot_bypass_snap = false, riot_abuser_v2_enabled = false, riot_abuser_v2_spin_speed = 720, riot_abuser_v2_xjitter = 30, riot_abuser_v2_yjitter = 8, riot_abuser_v2_spread = 300,
 anti_afk_enabled = false, autocollect_enabled = false, autocollect_radius = 120, return_home_enabled = false, home_return_delay = 1.0,
 safe_zone_enabled = false, safe_zone_y = -10, teleport_loop_enabled = false, teleport_loop_delay = 0.5, ffa_hopping_enabled = false,

 spin_shot_enabled = false,
 slingshot_bypass_enabled = false, slingshot_bypass_range = 100000000000000, slingshot_bypass_manipulation = true, slingshot_bypass_tp = true,
 bow_bypass_enabled = false,
 dagger_bypass_enabled = false,
 projectile_tp_enabled = false,
 projectile_tp_part = "HumanoidRootPart",
 projectile_rapid_fire_proj_enabled = false,
 melee_bypass_enabled = false, melee_bypass_y_range = 10,
 teleport_to_target_enabled = false,
 teleport_to_target_sync_to_ragebot = false,
 teleport_to_target_search_radius = 999e15,
 teleport_to_target_mode = "Closest",
 teleport_to_target_priority = "",
 teleport_to_target_position = "Exact",
 teleport_to_target_method = "Adaptive",
 teleport_to_target_offset_dist = 3,
 teleport_to_target_aim_lead = false,
 teleport_to_target_stagger = 1,
 teleport_to_target_lock = false,
 teleport_to_target_lock_key = "",
 teleport_to_target_aggression = 3,
 teleport_to_target_auto_face = false,
 teleport_to_target_failsafe = true,
 teleport_to_target_snap_count = 4,
 teleport_to_target_throttle = 0,
 teleport_to_target_through_walls = true,
 teleport_to_target_recover_void = true,
 teleport_to_target_jitter = 0,
 teleport_to_target_y_offset = 0,
 teleport_to_target_orbit_mode = false,
 teleport_to_target_orbit_radius = 5,
 teleport_to_target_orbit_speed = 90,
 teleport_to_target_burst_mode = false,
 teleport_to_target_burst_count = 3,
 teleport_to_target_randomize_pos = false,
 teleport_to_target_ghost_step = false,
 teleport_to_target_ghost_dist = 500,
 teleport_to_target_velocity_kill = true,
 teleport_to_target_snap_face = false,
 vst_attack_method = "Adaptive",
 ui_keybind = "RightControl",
 ui_lock_keybind = "LeftControl",
 vs_pos_resolver = false, vs_predictive_sync = false, vs_protocol = "Adaptive", vs_pos_restore = false,
 vs_min_dist = 1, vs_max_dist = 50000,
 vs_char_origin = false,
 vs_dir_xp = 5000, vs_dir_xn = 5000, vs_dir_yp = 5000, vs_dir_yn = 5000, vs_dir_zp = 5000, vs_dir_zn = 5000,
 vs_radius = 50000,
 vs_stabilizer_enabled = false, vs_stability = 50,
 vs_movement = "Random",
 vs_smoothness_enabled = false, vs_smoothness = 10,
 vs_interval = 1,
 vs_depth_bias = 0, vs_chaos_amp = 1, vs_burst_delay = 0, vs_axis_lock_strength = 0,
 evs_direction = "Down",
 evs_distance = 50000,
 evs_void_tick = 60,
 evs_iter_radius = 500000,
 evs_phase_shift = 0,
 evs_amplitude = 1,
 evs_frequency = 1,
 evs_spread = 500,
 evs_orbit_radius = 10000,
 evs_orbit_speed = 5,
 evs_spiral_tightness = 1,
 evs_jitter = 0,
 evs_y_bias = 0,
 evs_burst = 100,
 evs_layer_count = 1,
 evs_pattern = "Linear",
 evs_axis = "Y",
 evs_falloff = "None",
 evs_blend_mode = "Replace",
 evs_auto_reverse = false,
 evs_kill_velocity = true,
 evs_warp_mode = "Instant",
 evs_gravity_mult = 1,
 evs_rotation_chaos = false,
 evs_snap_back = false,
 evs_snap_back_delay = 0,
 evs_layer_offset = 0,
 evs_axis_clamp = 0,
 evs_turbulence = 0,
 evs_echo_count = 0,
 evs_echo_decay = 0.5,
 evs_invert_x = false,
 evs_invert_y = false,
 evs_invert_z = false,
 evs_pattern2 = "None",
 evs_blend_weight = 0.5,
 vs_dir_mode = "Uniform",
 vs_radial_scale = 1,
 vs_vertical_bias = 0,
 vs_horizontal_lock = false,
 vs_chaos_mode = "Off",
 vs_chaos_intensity = 1,
 vs_pulse_rate = 1,
 vs_warp_bias = 0,
 vs_gravity_drain = false,
 vs_eccentricity = 0,
 vs_enter_delay = 0,
 vs_exit_delay = 0,
 vs_snap_mode = "Instant",
 vs_burst_shape = "Random",
 vs_recoil_comp = false,
 vs_recoil_scale = 1,
 vs_pos_clamp = false,
 vs_pos_clamp_radius = 50000,
 vs_scatter_seed = 1,
 vs_phase_mode = "Off",
 vs_dir_blend = "None",
 vs_layer_mix = "Sequential",
 vs_burst_fade = false,
 vs_burst_fade_alpha = 0.5,
 vs_momentum_carry = false,
 vs_momentum_scale = 1,
 vs_angular_noise = 0,
 vs_void_gate = false,
 vs_void_gate_dist = 10000,
 evs_sync_to_ragebot = false,
 evs_scatter_mode = "Random",
 evs_burst_profile = "Flat",
 evs_tick_jitter = 0,
 evs_invert_burst = false,
 evs_clamp_radius = 0,
 evs_orbit_lock = false,
 evs_wave_freq = 1,
 evs_depth_floor = 0,
 evs_axis_weight_x = 1,
 evs_axis_weight_y = 1,
 evs_axis_weight_z = 1,
 evs_burst_stagger = 0,
 evs_layer_blend = "Add",
 evs_pulse_sync = false,
 evs_gravity_dir = "Down",
 evs_spin_lock = false,
 vst_enabled = false,
 vst_spin_speed = 1e85,
 vst_type = "Unhittability",
 vst_unhittability_y_range = 10,
 vst_defend_intensity = 50,
 vst_hide_time = 0.3,
 vst_attack_time = 0.3,
 vst_translocation_intensity = 50,
 vst_hide_mode = "Defend",
 vst_defend_proximity_escape = true,
 vst_defend_proximity_radius = 20,
 vst_defend_escape_dist = 1000,
 vst_bait_depth = 20,
 vst_defend_x_dist = 10000,
 vst_defend_y_dist = 10000,
 vst_defend_z_dist = 10000,
 vst_attack_tracking_type = "Teleportation",
 vs_void_direction = "Random",
 void_hide_x = 1e6,
 void_hide_y = 9e25,
 void_hide_enabled = false,
 void_hide_sync_to_ragebot = false,
 void_hide_z = 1e6, pixel_enabled = false, pixel_count = 8,
 anti_void_bait_freeze = false, anti_void_bait_hide = false,
 fake_pos_enabled = false,
 fake_pos_radius = 500,
 fake_pos_height = 0,
 fake_pos_speed = 50,
 fake_pos_count = 5,
 fake_pos_drop1 = "Scatter",
 fake_pos_drop2 = "Random",
 fake_pos_drop3 = "None",
 fake_pos_drop4 = "Linear",
 fake_pos_drop5 = "Off",
 fake_pos_tog1 = false,
 fake_pos_tog2 = false,
 fake_pos_tog3 = false,
 fake_pos_tog4 = false,
 fake_pos_tog5 = false,
 desync_enabled = false,
 desync_intensity = 50,
 desync_speed = 10,
 desync_angle = 90,
 desync_jitter = 20,
 desync_flip = false,
 desync_unhittable_enabled = false,
 desync_unhittable_intensity = 50,
 desync_unhittable_radius = 9000,
 desync_unhittable_iters = 100,
 desync_unhittable_y_range = 10, vs_sl1 = 50, vs_sl2 = 10, vs_sl3 = 10, vs_sl4 = 0, vs_sl5 = 10,
 vs_sl6 = 0, vs_sl7 = 10, vs_sl8 = 0, vs_sl9 = 10, vs_sl10 = 0,
 vs_sl11 = 10, vs_sl12 = 0, vs_sl13 = 10, vs_sl14 = 0, vs_sl15 = 10,
 vs_sl16 = 0, vs_sl17 = 10, vs_sl18 = 1, vs_sl19 = 0, vs_sl20 = 10,
 vs_sl21 = 0, vs_sl22 = 10, vs_sl23 = 0, vs_sl24 = 1, vs_sl25 = 0,
 vs_sl26 = 10, vs_sl27 = 0, vs_sl28 = 10, vs_sl29 = 0, vs_sl30 = 1,
 vs_sl31 = 0, vs_sl32 = 10, vs_sl33 = 0, vs_sl34 = 10, vs_sl35 = 0,
 vs_sl36 = 10, vs_sl37 = 0, vs_sl38 = 1, vs_sl39 = 0, vs_sl40 = 10,
 vs_dr1 = "Scatter", vs_dr2 = "Random", vs_dr3 = "None", vs_dr4 = "Linear", vs_dr5 = "Off",
 vs_dr6 = "Uniform", vs_dr7 = "Replace", vs_dr8 = "Adaptive", vs_dr9 = "Instant", vs_dr10 = "None",
 vs_dr11 = "Random", vs_dr12 = "Add", vs_dr13 = "Sphere", vs_dr14 = "Flat", vs_dr15 = "Down",
 vs_dr16 = "All", vs_dr17 = "Sequential", vs_dr18 = "None", vs_dr19 = "Off", vs_dr20 = "Random",
 vs_dr21 = "Instant", vs_dr22 = "None", vs_dr23 = "Uniform", vs_dr24 = "Replace", vs_dr25 = "Off",
 vs_dr26 = "None", vs_dr27 = "Linear", vs_dr28 = "Random", vs_dr29 = "Adaptive", vs_dr30 = "None",
 vs_dr31 = "Off", vs_dr32 = "Uniform", vs_dr33 = "Replace", vs_dr34 = "Instant", vs_dr35 = "None",
 vs_dr36 = "Random", vs_dr37 = "Scatter", vs_dr38 = "Adaptive", vs_dr39 = "Linear", vs_dr40 = "Off",
 vs_tg1 = false, vs_tg2 = false, vs_tg3 = false, vs_tg4 = false, vs_tg5 = false,
 vs_tg6 = false, vs_tg7 = false, vs_tg8 = false, vs_tg9 = false, vs_tg10 = false,
 vs_tg11 = false, vs_tg12 = false, vs_tg13 = false, vs_tg14 = false, vs_tg15 = false,
 vs_tg16 = false, vs_tg17 = false, vs_tg18 = false, vs_tg19 = false, vs_tg20 = false,
 vs_tg21 = false, vs_tg22 = false, vs_tg23 = false, vs_tg24 = false, vs_tg25 = false,
 vs_tg26 = false, vs_tg27 = false, vs_tg28 = false, vs_tg29 = false, vs_tg30 = false,
 vs_tg31 = false, vs_tg32 = false, vs_tg33 = false, vs_tg34 = false, vs_tg35 = false,
 vs_tg36 = false, vs_tg37 = false, vs_tg38 = false, vs_tg39 = false, vs_tg40 = false,
 vs_tg41 = false, vs_tg42 = false, vs_tg43 = false, vs_tg44 = false, vs_tg45 = false,
 vs_tg46 = false, vs_tg47 = false, vs_tg48 = false, vs_tg49 = false, vs_tg50 = false,
 vs_tg51 = false, vs_tg52 = false, vs_tg53 = false, vs_tg54 = false, vs_tg55 = false,
 vs_tg56 = false, vs_tg57 = false, vs_tg58 = false, vs_tg59 = false, vs_tg60 = false,
 vs_tg61 = false, vs_tg62 = false, vs_tg63 = false, vs_tg64 = false, vs_tg65 = false,
 vs_tg66 = false, vs_tg67 = false, vs_tg68 = false, vs_tg69 = false, vs_tg70 = false,
 vs_sl41 = 0, vs_sl42 = 10, vs_sl43 = 0, vs_sl44 = 0, vs_sl45 = 10,
 vs_sl46 = 0, vs_sl47 = 0, vs_sl48 = 10, vs_sl49 = 0, vs_sl50 = 10,
 vs_sl51 = 0, vs_sl52 = 10, vs_sl53 = 0, vs_sl54 = 10, vs_sl55 = 0,
 vs_sl56 = 10, vs_sl57 = 0, vs_sl58 = 10, vs_sl59 = 0, vs_sl60 = 10,
 vs_sl61 = 0, vs_sl62 = 10, vs_sl63 = 0, vs_sl64 = 10, vs_sl65 = 0,
 vs_sl66 = 10, vs_sl67 = 0, vs_sl68 = 10, vs_sl69 = 0, vs_sl70 = 10,
 vs_dr41 = "None", vs_dr42 = "None", vs_dr43 = "Rigid", vs_dr44 = "None", vs_dr45 = "Wrap",
 vs_dr46 = "None", vs_dr47 = "Ignore", vs_dr48 = "None", vs_dr49 = "None", vs_dr50 = "On Entry",
 vs_dr51 = "None", vs_dr52 = "Linear", vs_dr53 = "Random", vs_dr54 = "None", vs_dr55 = "Off",
 vs_dr56 = "Uniform", vs_dr57 = "None", vs_dr58 = "Replace", vs_dr59 = "None", vs_dr60 = "Instant",
 vs_dr61 = "None", vs_dr62 = "Linear", vs_dr63 = "None", vs_dr64 = "Adaptive", vs_dr65 = "None",
 vs_dr66 = "Off", vs_dr67 = "None", vs_dr68 = "Random", vs_dr69 = "None", vs_dr70 = "Replace",
 vs_void_pattern = "None",
 evs_iter_rad_directional = false,
 vs_cust_drop1 = "Scatter",
 vs_cust_drop2 = "Random",
 vs_cust_drop3 = "None",
 vs_cust_drop4 = "Linear",
 vs_cust_drop5 = "Off",
 vs_cust_drop6 = "Uniform",
 vs_cust_drop7 = "Replace",
 vs_cust_drop8 = "Adaptive",
 vs_cust_drop9 = "Instant",
 vs_cust_drop10 = "None",
 vs_cust_sl1 = 10,
 vs_cust_sl2 = 10,
 vs_cust_sl3 = 10,
 vs_cust_sl4 = 10,
 vs_cust_sl5 = 10,
 vs_cust_sl6 = 10,
 vs_cust_sl7 = 10,
 vs_cust_sl8 = 10,
 vs_cust_sl9 = 10,
 vs_cust_sl10 = 10,
 vs_cust_tog1 = false,
 vs_cust_tog2 = false,
 vs_cust_tog3 = false,
 vs_cust_tog4 = false,
 vs_cust_tog5 = false,
 vs_cust_tog6 = false,
 vs_cust_tog7 = false,
 vs_cust_tog8 = false,
 vs_cust_tog9 = false,
 vs_cust_tog10 = false,
 vs_sync_to_ragebot = false,
 vs_scatter_layers = 1,
 vs_depth_clamp = 0,
 vs_burst_mode = "Random",
 vs_axis_bias = "None",
 vs_falloff_mode = "None",
 vs_velocity_inherit = false,
 vs_phase_invert = false,
 vs_clamp_enabled = false,
 vs_layer_stagger = 0,
 vs_intensity = 50,
 vs_spread_bias = 0,
 evs_extra_drop1 = "Linear",
 evs_extra_drop2 = "Random",
 evs_extra_tog1 = false,
 evs_extra_tog2 = false,
 evs_extra_sl1 = 10,
 evs_extra_sl2 = 10,
 randomizer_seed = "",
 randomizer_mode1 = "Random",
 randomizer_mode2 = "Uniform",
 randomizer_active = false,
 evs_sync_mode = "Instant",
 evs_burst_falloff = "None",
 evs_chaos_axis = "All",
 evs_sync_strength = 50,
 evs_chaos_blend = 0,
 evs_burst_radius_scale = 1,
 evs_chaos_sync = false,
 evs_burst_lock = false,
 evs_depth_override = false,
 rapid_fire_enabled = false,
 void_spam_enabled = false,
 evade_enabled = false,
 evade_min_dist = 5000,
 evade_max_dist = 50000,
 evade_delay = 0.1,
 evade_kill_velocity = true,
 evade_y_mode = "Random",
 evade_axis_lock = "None",
 evade_shape = "Sphere",
 evade_warp_mode = "Instant",
 evade_invert_x = false,
 evade_invert_z = false,
 evade_y_bias = 0,
 evade_chaos_amp = 1,
 vs_warp_multiplier = 1,
 vs_scatter_radius = 500000,
 vs_depth_mult = 1,
 vs_rebound_strength = 0,
 vs_axis_spin = 0,
 vs_frequency_mod = 1,
 vs_position_noise = 0,
 vs_burst_gap = 0,
 vs_entropy_mod = 0,
 vs_gravity_strength = 0,
 orbit_enabled = false,
 orbit_radius = 50000,
 orbit_speed = 5,
 orbit_height = 0,
 orbit_iters = 100,
 orbit_jitter = 0,
 orbit_pattern = "Circle",
 orbit_target = "Closest",
 orbit_axis = "Y",
 orbit_direction = "Clockwise",
 orbit_warp_mode = "Instant",
 orbit_warp_strength = 50,
 orbit_falloff = "None",
 orbit_phase_offset = 0,
 orbit_layer_count = 1,
 orbit_layer_offset = 0,
 orbit_wave_freq = 1,
 orbit_tightness = 10,
 orbit_kill_velocity = true,
 orbit_sync_ragebot = false,
 orbit_chaos_blend = 0,
 orbit_invert_x = false,
 orbit_invert_z = false,
 orbit_y_bias = 0,
 orbit_depth_floor = 0,
 vs_turbulence_freq = 1,
 vs_turbulence_amp = 1,
 vs_vortex_strength = 0,
 vs_vortex_radius = 10000,
 vs_layer_twist = 0,
 vs_quantum_jump_prob = 0,
 vs_quantum_jump_scale = 1,
 vs_fractal_depth = 1,
 vs_fractal_scale = 1,
 vs_echo_trail = 0,
 vs_echo_decay_rate = 0.5,
 vs_gravity_vector_x = 0,
 vs_gravity_vector_y = -1,
 vs_gravity_vector_z = 0,
 vs_scatter_seed_mode = "Random",
 vs_depth_pulse_freq = 1,
 vs_depth_pulse_amp = 0,
 vs_spiral_offset_x = 0,
 vs_spiral_offset_z = 0,
 vs_node_gravity = false,
 vs_flux_reversal = false,
 vs_axis_wobble = 0,
 vs_chaos_feedback = false,
 vs_void_gate_mode = "Instant",
 godmode_enabled = false,
 godmode_y_range = 10,
 anti_aim_enabled = false,
 anti_aim_spin_speed = 1e85,
 anti_aim_pitch = 0,
 anti_aim_roll = 0,
 anti_aim_jitter = 0,
 perfect_block_enabled = false,
 perfect_block_target = "",
 perfect_block_cover_front = false,
 perfect_block_cover_left = false,
 perfect_block_cover_right = false,
 sounds_enabled = false,
 sounds_toggle_sound = "rbxassetid://9120386954",
 fly_enabled = false,
 fly_speed = 60,
 fly_noclip = false,
 fly_gravity_cancel = true,
 bm_enabled = false,
 bm_pitch = 90,
 bm_yaw = 90,
 bm_randomangle = false,
 bm_minangle = 30,
 bm_maxangle = 60,
anti_aim_angle = "Down",
anti_aim_method = "Pixelation",
anti_aim_custom_angle = 0,
prediction_enabled = false,
prediction_activation_range = 20,
prediction_distance_range = 30,
void_mimic_enabled = false,
void_mimic_learn_rate = 0.85,
kicia_counter_enabled = false,
kicia_voidspam_enabled = false,
ui_font = "GothamMedium",
}

getgenv().all_connections = {}

getgenv().loop_waypoints = {}

getgenv().loop_index = 1

local config = getgenv().config

local configs_folder = "flow lua premium/configs"
if not isfolder("flow lua premium") then makefolder("flow lua premium") end
if not isfolder("flow lua premium/configs") then makefolder("flow lua premium/configs") end
if not isfolder("flow lua premium/themes") then makefolder("flow lua premium/themes") end

local function notify(title, content)
 pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title=title, Text=content, Duration=3 }) end)
end


getgenv().save_cfg = function(name)
 if not name or name == "" then name = "default" end

 local path = configs_folder .. "/" .. name .. ".json"

 local data = { AutoLoadConfig=config.autoload_config, LastLoadedConfig=name, full_config=config }

 local ok, encoded = pcall(http_service.JSONEncode, http_service, data)
 if ok and encoded then

 local w_ok = pcall(writefile, path, encoded)
 if w_ok then notify("Config", "Saved: " .. name) return true end
 end

 notify("Config", "Failed to save config.")
 return false
end


getgenv().load_cfg = function(name)
 if not name or name == "" then name = "default" end

 local path = configs_folder .. "/" .. name .. ".json"
 if not isfile(path) then notify("Config", "Not found: " .. name) return false end

 local ok, raw = pcall(readfile, path)
 if not ok then notify("Config", "Failed to read config.") return false end

 local s, d = pcall(http_service.JSONDecode, http_service, raw)
 if s and d and d.full_config then
 config.autoload_config = d.AutoLoadConfig or true
 config.last_loaded_config = name
 for k, v in pairs(d.full_config) do
 if config[k] ~= nil and type(config[k]) == type(v) then config[k] = v end
 end

 notify("Config", "Loaded: " .. name)
 return true
 end

 notify("Config", "Corrupted config file.")
 return false
end


getgenv().delete_cfg = function(name)
 if not name or name == "" or name == "default" then notify("Config", "Cannot delete default.") return false end

 local path = configs_folder .. "/" .. name .. ".json"
 if not isfile(path) then notify("Config", "Not found.") return false end

 local ok = pcall(delfile, path)
 if ok then notify("Config", "Deleted: " .. name) return true end
 notify("Config", "Failed to delete.")
 return false
end


getgenv().list_cfgs = function()
 if not isfolder(configs_folder) then return {} end

 local list = {}

 local ok, files = pcall(listfiles, configs_folder)
 if ok and files then
 for _, f in ipairs(files) do

 local matched = f:match("([^/\\]+)%.json$")
 if matched then table.insert(list, matched) end
 end
 end

 table.sort(list)
 return list
end


getgenv().get_hrp = function(plr)

 local p = plr or localplayer
 if not p.Character then return nil end
 return p.Character:FindFirstChild("HumanoidRootPart")
end


getgenv().safe_teleport = function(pos)

 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return end

 local x, y, z = pos.X, pos.Y, pos.Z
 y = math.clamp(y, 2, hrp.Position.Y + 800)

 local p = RaycastParams.new()
 p.FilterType = Enum.RaycastFilterType.Exclude
 p.FilterDescendantsInstances = { localplayer.Character }

 local hit = workspace:Raycast(Vector3.new(x, y + 60, z), Vector3.new(0, -220, 0), p)
 if hit then y = math.max(hit.Position.Y + 3, 2) end
 hrp.CFrame = CFrame.new(x, y, z)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
end

local cached_target, last_target_tick = nil, 0

getgenv().get_closest = function(check_ff)

 local now = tick()
 if now - last_target_tick < 0.1 then
 if cached_target and cached_target.Character then

 local ct_hrp = cached_target.Character:FindFirstChild("HumanoidRootPart")

 local ct_hum = cached_target.Character:FindFirstChild("Humanoid")
 if ct_hrp and ct_hum and ct_hum.Health > 0 then
 if not check_ff or not cached_target.Character:FindFirstChildOfClass("ForceField") then
 return cached_target
 end
 end
 end
 end

 last_target_tick = now

 local closest, min_d = nil, math.huge

 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return nil end
 for _, p in ipairs(players:GetPlayers()) do
 if p ~= localplayer and p.Character then
 if not (check_ff and p.Character:FindFirstChildOfClass("ForceField")) then

 local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")

 local hum = p.Character:FindFirstChild("Humanoid")
 if t_hrp and hum and hum.Health > 0 then
 if localplayer.Team == nil or p.Team == nil or localplayer.Team ~= p.Team then

 local d = (hrp.Position - t_hrp.Position).Magnitude

 local sr = config.teleport_to_target_search_radius or 999e15
 if d < min_d and d <= sr then min_d = d; closest = p end
 end
 end
 end
 end
 end

 cached_target = closest
 return closest
end

do
local sling_targetPos = CFrame.new(9000, 9000, 9000)

local sling_projectiles = {}

local sling_conn = nil

local sling_childAddedConn = nil

local sling_childRemovedConn = nil

local sling_active = false

local sling_proj_names = { ["CoreProjectile"]=true, ["Slingshot.Slingshot"]=true, ["Bow"]=true, ["Dagger"]=true, ["Daggers"]=true }

local sling_raycast_hooked = false
local function sling_apply_range_hook()
 if not sling_raycast_hooked then
  sling_raycast_hooked = true
  pcall(function()
   local old_raycast = workspace.Raycast
   hookfunction(old_raycast, function(self, origin, direction, params)
    if not config.slingshot_bypass_enabled then return old_raycast(self, origin, direction, params) end
    local range = math.clamp(config.slingshot_bypass_range or 100000000000000, 1, 100000000000000)
    local mag = direction.Magnitude
    if mag > 0 then direction = direction.Unit * math.max(mag, range) end
    return old_raycast(self, origin, direction, params)
   end)
  end)
 end
 pcall(function()
  local rs = game:GetService("ReplicatedStorage")
  local modules = rs:FindFirstChild("Modules")
  if not modules then return end
  local itemLib_ok, ItemLibrary = pcall(require, modules:FindFirstChild("ItemLibrary"))
  if not itemLib_ok or not ItemLibrary then return end
  local Items = rawget(ItemLibrary, "Items")
  if not Items then return end
  local range = math.clamp(config.slingshot_bypass_range or 100000000000000, 1, 100000000000000)
  for _, item in pairs(Items) do
   local nm = tostring(item.Name or "")
   if nm == "Slingshot" or nm == "Bow" or nm == "Dagger" or nm == "Daggers" then
    if item["Range"] then rawset(item, "Range", range) end
    if item["MaxRange"] then rawset(item, "MaxRange", range) end
    if item["ProjectileRange"] then rawset(item, "ProjectileRange", range) end
    if item["ShootRange"] then rawset(item, "ShootRange", range) end
   end
  end
 end)
end

getgenv().start_slingshot_bypass = function()
 if sling_active then return end
 sling_active = true
 config.slingshot_bypass_enabled = true
 sling_projectiles = {}
 sling_apply_range_hook()

 sling_childAddedConn = workspace.ChildAdded:Connect(function(o)
  if not o:IsA("BasePart") then return end
  if sling_proj_names[o.Name] then
   sling_projectiles[o] = true
  elseif o.Name == "Part" then
   task.defer(function()
    if o and o.Parent and o.AssemblyLinearVelocity.Magnitude > 50 then
     sling_projectiles[o] = true
    end
   end)
  end
 end)

 sling_childRemovedConn = workspace.ChildRemoved:Connect(function(o)
  sling_projectiles[o] = nil
 end)

 sling_conn = run_service.Heartbeat:Connect(function()
  if not config.slingshot_bypass_enabled then return end
  if config.slingshot_bypass_manipulation then
   pcall(function()

    local range = math.clamp(config.slingshot_bypass_range or 100000000000000, 1, 100000000000000)
    for _, p in pairs(players:GetPlayers()) do
     if p ~= localplayer and p.Character then

      local h = p.Character:FindFirstChild("HumanoidRootPart")
      if h then
       h.CFrame = sling_targetPos
       h.AssemblyLinearVelocity = Vector3.zero
      end
     end
    end

    for _, o in pairs(workspace:GetChildren()) do
     if o:IsA("BasePart") and sling_proj_names[o.Name] then
      o.CFrame = sling_targetPos
      o.AssemblyLinearVelocity = Vector3.zero
     end
    end

    for p in pairs(sling_projectiles) do
     if p and p.Parent then
      p.CFrame = sling_targetPos
      p.AssemblyLinearVelocity = Vector3.zero
     else
      sling_projectiles[p] = nil
     end
    end
   end)
  end
 end)
end

getgenv().stop_slingshot_bypass = function()
 sling_active = false
 config.slingshot_bypass_enabled = false
 if sling_conn then sling_conn:Disconnect(); sling_conn = nil end
 if sling_childAddedConn then sling_childAddedConn:Disconnect(); sling_childAddedConn = nil end
 if sling_childRemovedConn then sling_childRemovedConn:Disconnect(); sling_childRemovedConn = nil end
 sling_projectiles = {}
 if not config.teleport_to_target_enabled then
  pcall(getgenv().stop_teleport_to_target)
 end
end

local bow_targetPos = CFrame.new(9000, 9000, 9000)

local bow_projectiles = {}

local bow_conn = nil

local bow_childAddedConn = nil

local bow_childRemovedConn = nil

local bow_active = false

getgenv().start_bow_bypass = function()
 if bow_active then return end
 bow_active = true
 config.bow_bypass_enabled = true
 bow_projectiles = {}
 bow_childAddedConn = workspace.ChildAdded:Connect(function(o)
  if not o:IsA("BasePart") then return end
  if o.Name == "arrow" then
   bow_projectiles[o] = true
  elseif o.Name == "Part" then
   task.defer(function()
    if o and o.Parent and o.AssemblyLinearVelocity.Magnitude > 50 then
     bow_projectiles[o] = true
    end
   end)
  end
 end)

 bow_childRemovedConn = workspace.ChildRemoved:Connect(function(o)
  bow_projectiles[o] = nil
 end)

 bow_conn = run_service.Heartbeat:Connect(function()
  if not config.bow_bypass_enabled then return end
  pcall(function()
   for _, p in pairs(players:GetPlayers()) do
    if p ~= localplayer and p.Character then

     local h = p.Character:FindFirstChild("HumanoidRootPart")
     if h then
      h.CFrame = bow_targetPos
      h.AssemblyLinearVelocity = Vector3.zero
     end
    end
   end

   for _, o in pairs(workspace:GetChildren()) do
    if o.Name == "arrow" and o:IsA("BasePart") then
     o.CFrame = bow_targetPos
     o.AssemblyLinearVelocity = Vector3.zero
    end
   end

   for p in pairs(bow_projectiles) do
    if p and p.Parent then
     p.CFrame = bow_targetPos
     p.AssemblyLinearVelocity = Vector3.zero
    else
     bow_projectiles[p] = nil
    end
   end
  end)
 end)
end

getgenv().stop_bow_bypass = function()
 bow_active = false
 config.bow_bypass_enabled = false
 if bow_conn then bow_conn:Disconnect(); bow_conn = nil end
 if bow_childAddedConn then bow_childAddedConn:Disconnect(); bow_childAddedConn = nil end
 if bow_childRemovedConn then bow_childRemovedConn:Disconnect(); bow_childRemovedConn = nil end
 bow_projectiles = {}
end

local dagger_targetPos = CFrame.new(9000, 9000, 9000)

local dagger_projectiles = {}

local dagger_conn = nil

local dagger_childAddedConn = nil

local dagger_childRemovedConn = nil

local dagger_active = false

getgenv().start_dagger_bypass = function()
 if dagger_active then return end
 dagger_active = true
 config.dagger_bypass_enabled = true
 dagger_projectiles = {}
 dagger_childAddedConn = workspace.ChildAdded:Connect(function(o)
  if not o:IsA("BasePart") then return end
  if o.Name == "daggers" then
   dagger_projectiles[o] = true
  elseif o.Name == "Part" then
   task.defer(function()
    if o and o.Parent and o.AssemblyLinearVelocity.Magnitude > 50 then
     dagger_projectiles[o] = true
    end
   end)
  end
 end)

 dagger_childRemovedConn = workspace.ChildRemoved:Connect(function(o)
  dagger_projectiles[o] = nil
 end)

 dagger_conn = run_service.Heartbeat:Connect(function()
  if not config.dagger_bypass_enabled then return end
  pcall(function()
   for _, p in pairs(players:GetPlayers()) do
    if p ~= localplayer and p.Character then

     local h = p.Character:FindFirstChild("HumanoidRootPart")
     if h then
      h.CFrame = dagger_targetPos
      h.AssemblyLinearVelocity = Vector3.zero
     end
    end
   end

   for _, o in pairs(workspace:GetChildren()) do
    if o.Name == "daggers" and o:IsA("BasePart") then
     o.CFrame = dagger_targetPos
     o.AssemblyLinearVelocity = Vector3.zero
    end
   end

   for p in pairs(dagger_projectiles) do
    if p and p.Parent then
     p.CFrame = dagger_targetPos
     p.AssemblyLinearVelocity = Vector3.zero
    else
     dagger_projectiles[p] = nil
    end
   end
  end)
 end)
end

getgenv().stop_dagger_bypass = function()
 dagger_active = false
 config.dagger_bypass_enabled = false
 if dagger_conn then dagger_conn:Disconnect(); dagger_conn = nil end
 if dagger_childAddedConn then dagger_childAddedConn:Disconnect(); dagger_childAddedConn = nil end
 if dagger_childRemovedConn then dagger_childRemovedConn:Disconnect(); dagger_childRemovedConn = nil end
 dagger_projectiles = {}
end

local proj_tp_conn = nil

getgenv().start_projectile_tp = function()
 if proj_tp_conn then proj_tp_conn:Disconnect() end
 proj_tp_conn = run_service.Heartbeat:Connect(function()
  if not config.projectile_tp_enabled then return end
  pcall(function()

   local target = getgenv().get_closest(false)
   if not target or not target.Character then return end

   local partName = config.projectile_tp_part or "HumanoidRootPart"

   local targetPart = target.Character:FindFirstChild(partName)
   if not targetPart then return end

   local destCF = targetPart.CFrame
   for _, o in pairs(workspace:GetChildren()) do
    if o:IsA("BasePart") and (o.Name == "Slingshot.Slingshot" or o.Name == "arrow" or o.Name == "daggers") then
     o.CFrame = destCF
     o.AssemblyLinearVelocity = Vector3.zero
    end
   end
  end)
 end)
end

getgenv().stop_projectile_tp = function()
 if proj_tp_conn then proj_tp_conn:Disconnect(); proj_tp_conn = nil end
 config.projectile_tp_enabled = false
end

local proj_rapid_fire_conn = nil

getgenv().start_projectile_rapid_fire = function()
 if proj_rapid_fire_conn then proj_rapid_fire_conn:Disconnect() end
 local Items
 pcall(function()
  local IL = require(game:GetService("ReplicatedStorage").Modules.ItemLibrary)
  Items = IL and rawget(IL, "Items")
 end)
 local function patch_items()
  if not Items then return end
  for _, Item in pairs(Items) do
   local Name = Item.Name
   if (Name == "Bow" or Name == "Daggers" or Name == "Slingshot") and Item["ReloadLength"] then
    rawset(Item, "ReloadLength", Name == "Daggers" and 0.09 or 0)
   end
  end
 end
 patch_items()
 proj_rapid_fire_conn = run_service.Heartbeat:Connect(function()
  if not config.projectile_rapid_fire_proj_enabled then return end
  patch_items()
 end)
end

getgenv().stop_projectile_rapid_fire = function()
 if proj_rapid_fire_conn then proj_rapid_fire_conn:Disconnect(); proj_rapid_fire_conn = nil end
 config.projectile_rapid_fire_proj_enabled = false
end

local melee_conn = nil

local melee_active = false

local melee_fake_cf_store = {}

local MELEE_FAKE_OFFSET = Vector3.new(9000, 9000, 9000)

local function melee_in_y_range(my_hrp, target_hrp)

 local range = config.melee_bypass_y_range or 10

 local y_diff = my_hrp.Position.Y - target_hrp.Position.Y
 return y_diff >= 0 and y_diff <= range
end

getgenv().start_melee_bypass = function()
 if melee_active then return end
 melee_active = true
 config.melee_bypass_enabled = true
 melee_conn = run_service.Heartbeat:Connect(function()
  if not config.melee_bypass_enabled then return end

  local my_hrp = getgenv().get_hrp(localplayer)
  if not my_hrp then return end
  pcall(function()
   for _, p in pairs(players:GetPlayers()) do
    if p ~= localplayer and p.Character then

     local h = p.Character:FindFirstChild("HumanoidRootPart")
     if h then
      if melee_in_y_range(my_hrp, h) then
       melee_fake_cf_store[p] = h.CFrame

       local mt = getrawmetatable(h)

       local old_ni = mt and rawget(mt, "__newindex")

       local fake_cf = CFrame.new(MELEE_FAKE_OFFSET)
       if old_ni then
        pcall(old_ni, h, "CFrame", fake_cf)
       else
        rawset(h, "CFrame", fake_cf)
       end

       h.AssemblyLinearVelocity = Vector3.zero
      else
       melee_fake_cf_store[p] = nil
      end
     end
    end
   end
  end)
 end)
end

getgenv().stop_melee_bypass = function()
 melee_active = false
 config.melee_bypass_enabled = false
 if melee_conn then melee_conn:Disconnect(); melee_conn = nil end
 melee_fake_cf_store = {}
end
end

local anti_aim_conn = nil

local anti_aim_active = false

local anti_aim_pixel_conn = nil

local function aa_get_pitch()
    local angle_mode = config.anti_aim_angle or "Down"
    if angle_mode == "Down" then
        return math.rad(90)
    elseif angle_mode == "Up" then
        return math.rad(-90)
    elseif angle_mode == "Random" then
        return math.rad(math.random(0, 360))
    elseif angle_mode == "Custom" then
        return math.rad(config.anti_aim_custom_angle or 0)
    end
    return math.rad(90)
end

local function aa_apply_method(hrp, base_pitch, base_yaw)
    local method = config.anti_aim_method or "Pixelation"
    local pos = hrp.Position
    local mt = getrawmetatable(hrp)
    local ni = mt and rawget(mt, "__newindex")
    local function set_cf(cf)
        if ni then pcall(ni, hrp, "CFrame", cf)
        else pcall(function() hrp.CFrame = cf end) end
    end
    if method == "Pixelation" then
        local pixels = math.max(config.pixel_count or 8, 1)
        local step = math.max(1, math.floor(pixels))
        local char = localplayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    local sz = part.Size
                    local snapped = Vector3.new(
                        math.floor(sz.X / step + 0.5) * step,
                        math.floor(sz.Y / step + 0.5) * step,
                        math.floor(sz.Z / step + 0.5) * step
                    )
                    pcall(function() part.Size = snapped end)
                    local p2 = part.Position
                    local sp = Vector3.new(
                        math.floor(p2.X / step + 0.5) * step,
                        math.floor(p2.Y / step + 0.5) * step,
                        math.floor(p2.Z / step + 0.5) * step
                    )
                    pcall(function() part.CFrame = CFrame.new(sp) * (part.CFrame - part.CFrame.Position) end)
                end
            end
        end
    elseif method == "Spin" then
        set_cf(CFrame.new(pos) * CFrame.Angles(base_pitch, base_yaw, 0))
    elseif method == "Jitter" then
        set_cf(CFrame.new(pos) * CFrame.Angles(base_pitch, math.rad(math.random(0, 360)), math.rad(math.random(-180, 180))))
    elseif method == "Flat" then
        set_cf(CFrame.new(pos) * CFrame.Angles(0, base_yaw, 0))
    elseif method == "Invert" then
        set_cf(CFrame.new(pos) * CFrame.Angles(-base_pitch, base_yaw + math.pi, 0))
    elseif method == "Roll" then
        set_cf(CFrame.new(pos) * CFrame.Angles(0, base_yaw, math.rad(90)))
    elseif method == "Chaos" then
        set_cf(CFrame.new(pos) * CFrame.Angles(math.rad(math.random(-180, 180)), math.rad(math.random(-180, 180)), math.rad(math.random(-180, 180))))
    elseif method == "Wave" then
        set_cf(CFrame.new(pos) * CFrame.Angles(math.sin(tick() * 3) * base_pitch, base_yaw, 0))
    elseif method == "Pulse" then
        set_cf(CFrame.new(pos) * CFrame.Angles(base_pitch * math.abs(math.sin(tick() * 5)), base_yaw, 0))
    elseif method == "Desync" then
        set_cf(CFrame.new(pos) * CFrame.Angles(base_pitch, base_yaw, math.rad(180)))
    else
        set_cf(CFrame.new(pos) * CFrame.Angles(base_pitch, base_yaw, 0))
    end
end

getgenv().start_anti_aim = function()
    if anti_aim_conn then anti_aim_conn:Disconnect() end
    anti_aim_active = true
    config.anti_aim_enabled = true

    local spd = config.anti_aim_spin_speed or 1e85

    anti_aim_conn = run_service.Heartbeat:Connect(function()
        if not config.anti_aim_enabled then return end
        local hrp = getgenv().get_hrp(localplayer)
        if not hrp then return end
        local base_pitch = aa_get_pitch()
        local base_yaw = (tick() * spd) % (2 * math.pi)
        aa_apply_method(hrp, base_pitch, base_yaw)
    end)
end

getgenv().stop_anti_aim = function()
    anti_aim_active = false
    config.anti_aim_enabled = false
    if anti_aim_conn then anti_aim_conn:Disconnect(); anti_aim_conn = nil end
end

local evade_conn = nil

local evade_active = false

local evade_last_pos = Vector3.new(0, 0, 0)

local function evade_gen_pos(origin)

 local min_d = config.evade_min_dist or 5000

 local max_d = config.evade_max_dist or 50000

 local shape = config.evade_shape or "Sphere"

 local y_mode = config.evade_y_mode or "Random"

 local axis_lock = config.evade_axis_lock or "None"

 local chaos = config.evade_chaos_amp or 1

 local invert_x = config.evade_invert_x or false

 local invert_z = config.evade_invert_z or false

 local y_bias = config.evade_y_bias or 0

 local dist = min_d + math.random() * (max_d - min_d)

 local x, y, z
 if shape == "Sphere" then

  local theta = math.random() * 2 * math.pi

  local phi = math.acos(2 * math.random() - 1)
  x = dist * math.sin(phi) * math.cos(theta)
  y = dist * math.sin(phi) * math.sin(theta)
  z = dist * math.cos(phi)
 elseif shape == "Cube" then
  x = (math.random() - 0.5) * 2 * dist
  y = (math.random() - 0.5) * 2 * dist
  z = (math.random() - 0.5) * 2 * dist
 elseif shape == "Flat" then

  local theta = math.random() * 2 * math.pi
  x = dist * math.cos(theta)
  y = (math.random() - 0.5) * dist * 0.05
  z = dist * math.sin(theta)
 elseif shape == "Vertical" then
  x = (math.random() - 0.5) * dist * 0.05
  y = dist
  z = (math.random() - 0.5) * dist * 0.05
 else

  local theta = math.random() * 2 * math.pi
  x = dist * math.cos(theta)
  y = dist * math.sin(theta)
  z = dist * math.sin(theta + math.pi * 0.5)
 end

 x = x * chaos
 y = y * chaos
 z = z * chaos
 if invert_x then x = -x end
 if invert_z then z = -z end
 if y_mode == "Up" then
  y = math.abs(y) + dist * 0.5
 elseif y_mode == "Down" then
  y = -(math.abs(y) + dist * 0.5)
 elseif y_mode == "Flat" then
  y = 0
 end

 y = y + y_bias
 if axis_lock == "X" then z = 0; y = 0
 elseif axis_lock == "Y" then x = 0; z = 0
 elseif axis_lock == "Z" then x = 0; y = 0
 elseif axis_lock == "XZ" then y = 0 end
 return Vector3.new(origin.X + x, origin.Y + y, origin.Z + z)
end

getgenv().start_evade = function()
 if evade_active then return end
 evade_active = true
 config.evade_enabled = true
 evade_conn = task.spawn(function()
  while evade_active and config.evade_enabled do
   pcall(function()

    local hrp = getgenv().get_hrp(localplayer)
    if hrp then

     local origin = evade_last_pos

     local target = evade_gen_pos(origin)
     evade_last_pos = target

     local warp = config.evade_warp_mode or "Instant"
     if warp == "Instant" then
      hrp.CFrame = CFrame.new(target)
      if config.evade_kill_velocity then
       hrp.AssemblyLinearVelocity = Vector3.zero
       hrp.AssemblyAngularVelocity = Vector3.zero
      end

     elseif warp == "Lerp" then

      local steps = 5

      local start = hrp.CFrame

      local goal = CFrame.new(target)
      for i = 1, steps do
       hrp.CFrame = start:Lerp(goal, i / steps)
       task.wait()
      end

      if config.evade_kill_velocity then
       hrp.AssemblyLinearVelocity = Vector3.zero
       hrp.AssemblyAngularVelocity = Vector3.zero
      end
     end
    end
   end)

   task.wait(math.max(config.evade_delay or 0.1, 0.01))
  end
 end)
end

getgenv().stop_evade = function()
 evade_active = false
 config.evade_enabled = false
 evade_last_pos = Vector3.new(0, 0, 0)
end

local rav1_conn = nil

local function rav1_find_target()

 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return nil end

 local best, best_d = nil, math.huge
 for _, plr in ipairs(players:GetPlayers()) do
 if plr ~= localplayer and plr.Character then

 local t_hrp = plr.Character:FindFirstChild("HumanoidRootPart")

 local hum = plr.Character:FindFirstChildOfClass("Humanoid")

 local no_ff = not plr.Character:FindFirstChildOfClass("ForceField")

 local diff_team = localplayer.Team == nil or plr.Team == nil or localplayer.Team ~= plr.Team
 if t_hrp and hum and hum.Health > 0 and no_ff and diff_team then

 local d = (hrp.Position - t_hrp.Position).Magnitude
 if d < best_d then best_d = d; best = plr end
 end
 end
 end

 return best
end

local function rav1_compute_dest(t_hrp)

 local pos = t_hrp.Position

 local look = t_hrp.CFrame.LookVector

 local up = Vector3.new(0, 1, 0)

 local dist = config.riot_abuser_v1_tracking_distance or 3

 local mode = config.riot_abuser_v1_tracking_position or "Behind"
 if mode == "Behind" then return pos - look * dist
 elseif mode == "Above" then return pos + up * dist
 elseif mode == "Front" then return pos + look * dist
 elseif mode == "Below" then return pos - up * dist
 elseif mode == "Left" then return pos - look:Cross(up).Unit * dist
 elseif mode == "Right" then return pos + look:Cross(up).Unit * dist
 else return pos end
end

getgenv().start_riot_abuser_v1 = function()
 if rav1_conn then rav1_conn:Disconnect() end
 rav1_conn = run_service.Heartbeat:Connect(function()
  if not config.riot_abuser_v1_enabled then return end

  local hrp = getgenv().get_hrp(localplayer)

  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  if not hrp or not hum or hum.Health <= 0 then return end

  local target = rav1_find_target()

  local spinSpeed = config.riot_abuser_v1_spin_speed or 720

  local yaw = (tick() * math.rad(spinSpeed)) % (2 * math.pi)

  local dest_pos
  if target and target.Character then

   local t_hrp = target.Character:FindFirstChild("HumanoidRootPart")
   if t_hrp then dest_pos = rav1_compute_dest(t_hrp) end
  end


  local base_pos = dest_pos or hrp.Position

  local dest_cf = CFrame.new(base_pos) * CFrame.Angles(0, yaw, 0)

  local mt = getrawmetatable and getrawmetatable(hrp) or nil

  local ni = mt and rawget(mt, "__newindex") or nil
  if ni then
   pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
   pcall(ni, hrp, "AssemblyAngularVelocity", Vector3.zero)
   pcall(ni, hrp, "CFrame", dest_cf)
   pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
  else
   pcall(function()
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    hrp.CFrame = dest_cf
    hrp.AssemblyLinearVelocity = Vector3.zero
   end)
  end
 end)
end


getgenv().stop_riot_abuser_v1 = function()
 if rav1_conn then rav1_conn:Disconnect(); rav1_conn = nil end
 config.riot_abuser_v1_enabled = false
end

local ra_target_label_ref = nil

local riot_abuser_target = nil

local riot_abuser_last_update = 0

local riot_abuser_conn = nil

local function findRiotAbuserTarget()

 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return nil end

 local closest, closestDist = nil, math.huge
 for _, plr in ipairs(players:GetPlayers()) do
 if plr ~= localplayer and plr.Character then

 local t_hrp = plr.Character:FindFirstChild("HumanoidRootPart")

 local hum = plr.Character:FindFirstChild("Humanoid")
 if t_hrp and hum and hum.Health > 0 then
 if localplayer.Team == nil or plr.Team == nil or localplayer.Team ~= plr.Team then

 local dist = (hrp.Position - t_hrp.Position).Magnitude
 if dist < closestDist then closestDist = dist; closest = plr end
 end
 end
 end
 end

 return closest
end


local function computeRiotAbuserPos(targetRoot)

 local pos = targetRoot.Position

 local look = targetRoot.CFrame.LookVector

 local up = Vector3.new(0, 1, 0)

 local dist = config.riot_bypass_distance or 3

 local height = config.riot_bypass_height or 0

 local mode = config.riot_bypass_position or "Behind"

 local base
 if mode == "Behind" then
 base = pos - look * dist
 elseif mode == "Front" then
 base = pos + look * dist
 elseif mode == "Above" then
 base = pos + up * dist
 elseif mode == "Below" then
 base = pos - up * dist
 elseif mode == "Left" then

 local right = look:Cross(up).Unit
 base = pos - right * dist
 elseif mode == "Right" then

 local right = look:Cross(up).Unit
 base = pos + right * dist
 else
 base = pos - look * dist
 end

 return base + Vector3.new(0, height, 0)
end


local function updateRiotAbuserTarget()
 if not config.riot_bypass_enabled then return end

 local target = findRiotAbuserTarget()
 if target then
 riot_abuser_target = target
 if ra_target_label_ref then ra_target_label_ref:SetText("Target: " .. target.Name) end
 else
 riot_abuser_target = nil
 if ra_target_label_ref then ra_target_label_ref:SetText("Target: None") end
 end
end


local function applyRiotAbuser()
 if not config.riot_bypass_enabled then return end

 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return end

 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if not hum or hum.Health <= 0 then return end
 if not riot_abuser_target or not riot_abuser_target.Character then updateRiotAbuserTarget(); return end

 local targetRoot = riot_abuser_target.Character:FindFirstChild("HumanoidRootPart")
 if not targetRoot then return end

 local destPos = computeRiotAbuserPos(targetRoot)
 if config.riot_bypass_snap then
 pcall(function()
 hrp.CFrame = CFrame.new(destPos)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero end)
 else

 local rate = math.max(config.riot_bypass_update_rate or 0.5, 0.05)

 local tweenInfo = TweenInfo.new(rate, Enum.EasingStyle.Linear)

 local tween = TweenService:Create(hrp, tweenInfo, { CFrame=CFrame.new(destPos) })
 tween:Play()
 end
end


getgenv().start_riot_abuser = function()
 if riot_abuser_conn then riot_abuser_conn:Disconnect() end
 riot_abuser_last_update = 0
 riot_abuser_conn = run_service.Heartbeat:Connect(function()
 if not config.riot_bypass_enabled then return end
 if tick() - riot_abuser_last_update > (config.riot_bypass_update_rate or 0.5) then
 updateRiotAbuserTarget()
 riot_abuser_last_update = tick()
 end

 applyRiotAbuser() end)
end


getgenv().stop_riot_abuser = function()
 if riot_abuser_conn then riot_abuser_conn:Disconnect(); riot_abuser_conn = nil end
 riot_abuser_target = nil
 config.riot_bypass_enabled = false
 if ra_target_label_ref then ra_target_label_ref:SetText("Target: None") end
end

local ra_v2_conn = nil

local ra_v2_t0 = nil

local ra_v2_seed = nil

getgenv().start_riot_abuser_v2 = function()
    if ra_v2_conn then ra_v2_conn:Disconnect() end
    ra_v2_t0 = tick()
    ra_v2_seed = math.random(1000, 9999)
    ra_v2_conn = run_service.Heartbeat:Connect(function(dt)
        if not config.riot_abuser_v2_enabled then return end

        local hrp = getgenv().get_hrp(localplayer)

        local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        local t = tick() - ra_v2_t0

        local spinSpeed = config.riot_abuser_v2_spin_speed or 720

        local riotXJitter = config.riot_abuser_v2_xjitter or 30

        local riotYJitter = config.riot_abuser_v2_yjitter or 8

        local riotDistance = config.riot_abuser_v2_spread or 300

        local yaw = math.rad(spinSpeed * dt)

        local pitch = math.rad(spinSpeed * 0.37 * dt * math.sin(t * 3.1))

        local roll = math.rad(spinSpeed * 0.19 * dt * math.cos(t * 5.7 + ra_v2_seed))

        local spinCF = hrp.CFrame * CFrame.Angles(pitch, yaw, roll)

        local spread = riotDistance / 300

        local jX = (math.random()-0.5)*riotXJitter*spread*2 + math.noise(t*9, ra_v2_seed, 0)*riotXJitter*spread

        local jY = (math.random()-0.5)*riotYJitter*spread + math.noise(0, t*9, ra_v2_seed)*riotYJitter*spread*0.3

        local jZ = (math.random()-0.5)*riotXJitter*spread*2 + math.noise(0, 0, t*9+ra_v2_seed)*riotXJitter*spread

        local newY = math.max(spinCF.Position.Y + jY, 2)

        local mt = getrawmetatable and getrawmetatable(hrp) or nil

        local ni = mt and rawget(mt, "__newindex") or nil
        if ni then
            pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
            pcall(ni, hrp, "AssemblyAngularVelocity", Vector3.zero)
            pcall(ni, hrp, "CFrame", spinCF + Vector3.new(jX, newY - spinCF.Position.Y, jZ))
        else
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = spinCF + Vector3.new(jX, newY - spinCF.Position.Y, jZ)
            end)
        end
    end)
end


getgenv().stop_riot_abuser_v2 = function()
    if ra_v2_conn then ra_v2_conn:Disconnect(); ra_v2_conn = nil end
    config.riot_abuser_v2_enabled = false
end



local fake_pos_conn = nil

local fake_pos_render_conn = nil

local fake_pos_realCF = nil

local fake_pos_spiral_angle = 0
local fake_pos_linear_t = 0
local fake_pos_last_packet_t = 0

getgenv().start_fake_position = function()
 if fake_pos_conn then fake_pos_conn:Disconnect() end
 if fake_pos_render_conn then fake_pos_render_conn:Disconnect() end
 fake_pos_realCF = nil
 fake_pos_spiral_angle = 0
 fake_pos_linear_t = 0
 fake_pos_last_packet_t = 0

 fake_pos_conn = run_service.Heartbeat:Connect(function(dt)
  local hrp = getgenv().get_hrp(localplayer)
  if not config.fake_pos_enabled or not hrp then return end
  fake_pos_realCF = hrp.CFrame

  local radius = math.max(config.fake_pos_radius or 500, 1)
  local height = config.fake_pos_height or 0
  local spd = math.max(config.fake_pos_speed or 50, 1)
  local count = math.clamp(config.fake_pos_count or 5, 1, 20)
  local pattern = config.fake_pos_drop1 or "Scatter"
  local distribution = config.fake_pos_drop2 or "Random"
  local axis_lock = config.fake_pos_drop3 or "None"
  local reverse = config.fake_pos_tog2 or false
  local random_radius = config.fake_pos_tog3 or false

  local packet_interval = 1 / math.max(spd, 1)
  local now = tick()
  if now - fake_pos_last_packet_t < packet_interval then return end
  fake_pos_last_packet_t = now

  local eff_radius = random_radius and (math.random() * radius) or radius
  if reverse then eff_radius = -eff_radius end

  local mt = getrawmetatable(hrp)
  local ni = mt and rawget(mt, "__newindex")
  for _ = 1, count do
   local ox, oy, oz = 0, 0, 0

   if pattern == "Scatter" then
    local sx = (math.random() < 0.5) and 1 or -1
    local sz = (math.random() < 0.5) and 1 or -1
    ox = sx * (math.random() * math.abs(eff_radius))
    oy = height + (math.random() - 0.5) * math.max(math.abs(height), 1) * 0.5
    oz = sz * (math.random() * math.abs(eff_radius))
   elseif pattern == "Linear" then
    fake_pos_linear_t = fake_pos_linear_t + 0.05
    local t = fake_pos_linear_t % 1
    ox = (t - 0.5) * 2 * math.abs(eff_radius)
    oy = height
    oz = (t - 0.5) * 2 * math.abs(eff_radius)
   elseif pattern == "Circle" then
    fake_pos_spiral_angle = (fake_pos_spiral_angle + math.rad(spd * dt * 60)) % (2 * math.pi)
    ox = math.cos(fake_pos_spiral_angle) * math.abs(eff_radius)
    oy = height
    oz = math.sin(fake_pos_spiral_angle) * math.abs(eff_radius)
   elseif pattern == "Random" then
    ox = (math.random() * 2 - 1) * math.abs(eff_radius)
    oy = height + (math.random() - 0.5) * 200
    oz = (math.random() * 2 - 1) * math.abs(eff_radius)
   elseif pattern == "Spiral" then
    fake_pos_spiral_angle = (fake_pos_spiral_angle + math.rad(spd * dt * 60)) % (2 * math.pi)
    local r = math.abs(eff_radius) * (0.3 + 0.7 * ((fake_pos_spiral_angle / (2 * math.pi)) % 1))
    ox = math.cos(fake_pos_spiral_angle) * r
    oy = height + fake_pos_spiral_angle * 10
    oz = math.sin(fake_pos_spiral_angle) * r
   end

   if distribution == "Uniform" then
    local mag = math.sqrt(ox*ox + oz*oz)
    if mag > 0 then local s = math.abs(eff_radius) / mag; ox = ox*s; oz = oz*s end
   elseif distribution == "Weighted" then
    ox = ox * 0.6; oz = oz * 0.6
   elseif distribution == "Radial" then
    local theta = math.atan2(oz, ox)
    ox = math.cos(theta) * math.abs(eff_radius)
    oz = math.sin(theta) * math.abs(eff_radius)
   elseif distribution == "Clustered" then
    local ca = math.floor(math.random() * 8) * (math.pi * 0.25)
    ox = math.cos(ca) * math.abs(eff_radius)
    oz = math.sin(ca) * math.abs(eff_radius)
   end

   if axis_lock == "X" then oz = 0; oy = height
   elseif axis_lock == "Y" then ox = 0; oz = 0
   elseif axis_lock == "Z" then ox = 0; oy = height
   elseif axis_lock == "XZ" then oy = height
   end

   local fake_cf = fake_pos_realCF + Vector3.new(ox, oy, oz)
   if ni then
    pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
    pcall(ni, hrp, "CFrame", fake_cf)
    pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
   else
    pcall(function()
     hrp.AssemblyLinearVelocity = Vector3.zero
     hrp.CFrame = fake_cf
     hrp.AssemblyLinearVelocity = Vector3.zero
    end)
   end
   if sethiddenproperty then
    pcall(sethiddenproperty, hrp, "CFrame", fake_cf)
    pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", Vector3.zero)
   end
  end
 end)

 fake_pos_render_conn = run_service.RenderStepped:Connect(function()
  local hrp = getgenv().get_hrp(localplayer)
  if config.fake_pos_enabled and hrp and fake_pos_realCF then
   hrp.CFrame = fake_pos_realCF
   hrp.AssemblyLinearVelocity = Vector3.zero
   hrp.AssemblyAngularVelocity = Vector3.zero
  end
 end)
end


getgenv().stop_fake_position = function()
 if fake_pos_conn then fake_pos_conn:Disconnect(); fake_pos_conn = nil end
 if fake_pos_render_conn then fake_pos_render_conn:Disconnect(); fake_pos_render_conn = nil end
 fake_pos_realCF = nil
 fake_pos_spiral_angle = 0
 fake_pos_linear_t = 0
 config.fake_pos_enabled = false
end

local pixel_conn = nil

getgenv().start_pixelation = function()
 if pixel_conn then pixel_conn:Disconnect() end
 pixel_conn = run_service.Heartbeat:Connect(function()
  if not config.pixel_enabled then return end

  local char = localplayer.Character
  if not char then return end

  local pixels = math.max(config.pixel_count or 8, 1)

  local step = math.max(1, math.floor(pixels))
  for _, part in ipairs(char:GetDescendants()) do
   if part:IsA("BasePart") then

    local sz = part.Size

    local snapped = Vector3.new(
     math.floor(sz.X / step + 0.5) * step,
     math.floor(sz.Y / step + 0.5) * step,
     math.floor(sz.Z / step + 0.5) * step
    )
    pcall(function() part.Size = snapped end)

    local p = part.Position

    local sp = Vector3.new(
     math.floor(p.X / step + 0.5) * step,
     math.floor(p.Y / step + 0.5) * step,
     math.floor(p.Z / step + 0.5) * step
    )
    pcall(function() part.CFrame = CFrame.new(sp) * (part.CFrame - part.CFrame.Position) end)
   end
  end
 end)
end


getgenv().stop_pixelation = function()
 if pixel_conn then pixel_conn:Disconnect(); pixel_conn = nil end
 config.pixel_enabled = false
end

local anti_void_bait_conn = nil

getgenv().start_anti_void_bait_freeze = function()
 if anti_void_bait_conn then anti_void_bait_conn:Disconnect() end
 anti_void_bait_conn = run_service.Heartbeat:Connect(function()
  if not config.anti_void_bait_freeze then return end

  local hrp = getgenv().get_hrp(localplayer)
  if not hrp then return end
  pcall(function() hrp.CFrame = hrp.CFrame end)
  hrp.AssemblyLinearVelocity = Vector3.zero
  hrp.AssemblyAngularVelocity = Vector3.zero

  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
 end)
end


getgenv().start_anti_void_bait_hide = function()
 if anti_void_bait_conn then anti_void_bait_conn:Disconnect() end
 anti_void_bait_conn = run_service.Heartbeat:Connect(function()
  if not config.anti_void_bait_hide then return end

  local hrp = getgenv().get_hrp(localplayer)
  if not hrp then return end

  local iters = math.clamp(config.et_total or 1000, 1, 500)

  local ir = math.max(config.evs_iter_radius or 500000, 1)

  local base = hrp.Position
  for _ = 1, iters do

   local sx = (math.random() < 0.5) and 1 or -1

   local sy = (math.random() < 0.5) and 1 or -1

   local sz = (math.random() < 0.5) and 1 or -1

   local rx = sx * (ir * (0.5 + math.random() * 0.5))

   local ry = sy * (ir * (0.5 + math.random() * 0.5))

   local rz = sz * (ir * (0.5 + math.random() * 0.5))
   pcall(function() hrp.CFrame = CFrame.new(base.X + rx, base.Y + ry, base.Z + rz) end)
   base = hrp.Position
  end

  hrp.AssemblyLinearVelocity = Vector3.zero
  hrp.AssemblyAngularVelocity = Vector3.zero
 end)
end


getgenv().stop_anti_void_bait = function()
 if anti_void_bait_conn then anti_void_bait_conn:Disconnect(); anti_void_bait_conn = nil end
 config.anti_void_bait_freeze = false
 config.anti_void_bait_hide = false
end

local VM_VOID_THRESH = -1000000
local vm_store = {}
local vm_conn = nil
local VM_LEARN_WINDOW = 10
local VM_MIN_SAMPLES = 6

local function vm_valid(x, y, z)
 if x ~= x or y ~= y or z ~= z then return false end
 if math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then return false end
 return true
end

local function vm_read_part(part)
 if not part then return nil end
 local cf
 pcall(function() local mt = getrawmetatable(part); if mt then local ri = rawget(mt, "__index"); if ri then cf = ri(part, "CFrame") end end end)
 if cf then local x,y,z = cf.X,cf.Y,cf.Z; if vm_valid(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() if gethiddenproperty then local v = gethiddenproperty(part, "CFrame"); if v then cf = v end end end)
 if cf then local x,y,z = cf.X,cf.Y,cf.Z; if vm_valid(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() if ficlone then local cl = ficlone(part); if cl then cf = cl.CFrame end end end)
 if cf then local x,y,z = cf.X,cf.Y,cf.Z; if vm_valid(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() cf = part.CFrame end)
 if cf then local x,y,z = cf.X,cf.Y,cf.Z; if vm_valid(x,y,z) then return Vector3.new(x,y,z) end end
 return nil
end

local function vm_find_target()
 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return nil end
 local best, best_d = nil, math.huge
 for _, p in ipairs(players:GetPlayers()) do
  if p ~= localplayer and p.Character then
   local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")
   local hum = p.Character:FindFirstChildOfClass("Humanoid")
   local no_ff = not p.Character:FindFirstChildOfClass("ForceField")
   local diff_team = localplayer.Team == nil or p.Team == nil or localplayer.Team ~= p.Team
   if t_hrp and hum and hum.Health > 0 and no_ff and diff_team then
    local d = (hrp.Position - t_hrp.Position).Magnitude
    if d < best_d then best_d = d; best = p end
   end
  end
 end
 return best
end

local function vm_record(target_hrp)
 local raw = vm_read_part(target_hrp)
 if not raw then return end
 local x, y, z = raw.X, raw.Y, raw.Z
 if not vm_valid(x, y, z) then return end
 local now = tick()
 if not vm_store[target_hrp] then
  vm_store[target_hrp] = {
   samples = {},
   learned = false,
   learn_start = now,
   phase_x = 0, phase_z = 0,
   amp_x = 0, amp_z = 0,
   base_y = y,
   freq = 1,
   cx = x, cz = z,
  }
 end
 local st = vm_store[target_hrp]
 if y >= VM_VOID_THRESH then
  st.last_surface_x = x
  st.last_surface_z = z
  return
 end
 local alpha = math.clamp(config.void_mimic_learn_rate or 0.85, 0.1, 0.99)
 local age = now - st.learn_start
 local sn = st.samples
 sn[#sn + 1] = { x = x, y = y, z = z, t = now }
 if #sn > 256 then
  table.remove(sn, 1)
 end
 st.cx = st.cx * (1 - alpha) + x * alpha
 st.cz = st.cz * (1 - alpha) + z * alpha
 local dx = x - st.cx
 local dz = z - st.cz
 st.amp_x = st.amp_x * (1 - alpha) + math.abs(dx) * alpha
 st.amp_z = st.amp_z * (1 - alpha) + math.abs(dz) * alpha
 st.base_y = st.base_y * (1 - alpha) + y * alpha
 if #sn >= 2 then
  local dt_s = sn[#sn].t - sn[#sn - 1].t
  if dt_s > 0 then
   local inst_freq = 1 / dt_s
   st.freq = st.freq * (1 - alpha * 0.3) + inst_freq * (alpha * 0.3)
  end
 end
 if age >= VM_LEARN_WINDOW and #sn >= VM_MIN_SAMPLES then
  st.learned = true
 end
 if dx > 0 then st.phase_x = (st.phase_x + 0.05) % (2 * math.pi)
 else st.phase_x = (st.phase_x - 0.05) % (2 * math.pi) end
 if dz > 0 then st.phase_z = (st.phase_z + 0.05) % (2 * math.pi)
 else st.phase_z = (st.phase_z - 0.05) % (2 * math.pi) end
end

local function vm_get_mimic_pos(target_hrp, now)
 local st = vm_store[target_hrp]
 if not st or not st.learned then return nil end
 local spd = math.clamp(st.freq, 0.5, 20)
 local t = now * spd
 local ox = math.sin(t + st.phase_x) * st.amp_x
 local oz = math.cos(t + st.phase_z) * st.amp_z
 local bx = st.cx + ox
 local bz = st.cz + oz
 local by = st.base_y
 if not vm_valid(bx, by, bz) then return nil end
 return Vector3.new(bx, by, bz)
end

getgenv().vm_get_mimic_pos = vm_get_mimic_pos
getgenv().vm_store = vm_store

local vm_mimic_active = false

getgenv().start_void_mimic = function()
 if vm_mimic_active then return end
 vm_mimic_active = true
 config.void_mimic_enabled = true
 vm_store = {}
 getgenv().vm_store = vm_store
 if vm_conn then vm_conn:Disconnect() end
 vm_conn = run_service.Heartbeat:Connect(function()
  if not config.void_mimic_enabled then return end
  local target = vm_find_target()
  if not target or not target.Character then return end
  local t_hrp = target.Character:FindFirstChild("HumanoidRootPart")
  if not t_hrp then return end
  local head = target.Character:FindFirstChild("Head")
  pcall(vm_record, t_hrp)
  if head then pcall(vm_record, head) end
  local raw = vm_read_part(t_hrp)
  if raw and raw.Y < VM_VOID_THRESH then
   local st = vm_store[t_hrp]
   if st and not st.learned then
    local now = tick()
    if (now - st.learn_start) >= VM_LEARN_WINDOW and #st.samples >= VM_MIN_SAMPLES then
     st.learned = true
    end
   end
  else
   if vm_store[t_hrp] then
    vm_store[t_hrp].learned = false
    vm_store[t_hrp].samples = {}
    vm_store[t_hrp].learn_start = tick()
   end
  end
 end)
end

getgenv().stop_void_mimic = function()
 vm_mimic_active = false
 config.void_mimic_enabled = false
 if vm_conn then vm_conn:Disconnect(); vm_conn = nil end
 vm_store = {}
 getgenv().vm_store = vm_store
end

local kicia_counter_conn = nil
local kicia_counter_active = false
local KC_VOID_DEPTH = -300000
local KC_ITER_RADIUS = 500000

local function kc_find_target()
 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return nil end
 local best, best_d = nil, math.huge
 for _, p in ipairs(players:GetPlayers()) do
  if p ~= localplayer and p.Character then
   local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")
   local hum = p.Character:FindFirstChildOfClass("Humanoid")
   local no_ff = not p.Character:FindFirstChildOfClass("ForceField")
   local diff_team = localplayer.Team == nil or p.Team == nil or localplayer.Team ~= p.Team
   if t_hrp and hum and hum.Health > 0 and no_ff and diff_team then
    local d = (hrp.Position - t_hrp.Position).Magnitude
    if d < best_d then best_d = d; best = p end
   end
  end
 end
 return best
end

local function kc_nuke_fallen_parts()
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 pcall(function()
  local mt = getrawmetatable(workspace)
  if mt then
   local ni = rawget(mt, "__newindex")
   if ni then
    ni(workspace, "FallenPartsDestroyHeight", -math.huge)
    pcall(function() ni(workspace, "FallenPartsDestroyHeight", 0/0) end)
   end
  end
 end)
end

local function kc_force_cf(hrp, target_cf)
 local V0 = Vector3.zero
 pcall(function()
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
  hrp.CFrame = target_cf
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
 end)
 pcall(function()
  local mt = getrawmetatable(hrp)
  if not mt then return end
  local ni = rawget(mt, "__newindex")
  if not ni then return end
  ni(hrp, "AssemblyLinearVelocity", V0)
  ni(hrp, "AssemblyAngularVelocity", V0)
  ni(hrp, "CFrame", target_cf)
  ni(hrp, "AssemblyLinearVelocity", V0)
  ni(hrp, "AssemblyAngularVelocity", V0)
  ni(hrp, "CFrame", target_cf)
  ni(hrp, "AssemblyLinearVelocity", V0)
  ni(hrp, "AssemblyAngularVelocity", V0)
 end)
 if sethiddenproperty then
  pcall(sethiddenproperty, hrp, "CFrame", target_cf)
  pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", V0)
  pcall(sethiddenproperty, hrp, "AssemblyAngularVelocity", V0)
  pcall(sethiddenproperty, hrp, "CFrame", target_cf)
 end
 pcall(function()
  local was = hrp.Anchored
  hrp.Anchored = true
  hrp.CFrame = target_cf
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
  hrp.CFrame = target_cf
  hrp.Anchored = was
 end)
end

local function kc_try_autoshoot(target)
 pcall(function()
  local char = localplayer.Character
  if not char then return end
  local tool = char:FindFirstChildOfClass("Tool")
  if not tool then return end
  local t_hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
  if not t_hrp then return end
  local fire_events = {"Fire", "Shoot", "ShootEvent", "FireEvent", "Attack", "AttackEvent", "RemoteFireEvent", "Projectile"}
  for _, evt_name in ipairs(fire_events) do
   local evt = tool:FindFirstChild(evt_name) or tool:FindFirstChildOfClass("RemoteFunction") or tool:FindFirstChildOfClass("RemoteEvent")
   if evt and (evt.Name == evt_name) then
    if evt:IsA("RemoteEvent") then
     pcall(function() evt:FireServer(t_hrp.Position) end)
    elseif evt:IsA("RemoteFunction") then
     pcall(function() evt:InvokeServer(t_hrp.Position) end)
    end
    break
   end
  end
  local handle = tool:FindFirstChildOfClass("BasePart")
  if handle then
   pcall(function()
    local dir = (t_hrp.Position - handle.Position).Unit
    for _, v in ipairs(tool:GetDescendants()) do
     if v:IsA("RemoteEvent") then
      pcall(function() v:FireServer(t_hrp.Position, dir) end)
     end
    end
   end)
  end
 end)
 pcall(function()
  local rs = game:GetService("ReplicatedStorage")
  local t_hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
  if not t_hrp then return end
  for _, v in ipairs(rs:GetDescendants()) do
   if v:IsA("RemoteEvent") then
    local nm = v.Name:lower()
    if nm:find("fire") or nm:find("shoot") or nm:find("attack") or nm:find("projectile") or nm:find("hit") then
     pcall(function() v:FireServer(t_hrp.Position) end)
    end
   end
  end
 end)
 pcall(function()
  local uis_mock = game:GetService("UserInputService")
  local char = localplayer.Character
  if not char then return end
  local tool = char:FindFirstChildOfClass("Tool")
  if not tool then return end
  local t_hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
  if not t_hrp then return end
  local activate = tool.Activated
  if activate then
   pcall(function() activate:Fire() end)
  end
  pcall(function() tool:Activate() end)
 end)
end

local function kc_do_iteration_burst(hrp, base_pos)
 local iters = math.clamp(config.et_total or 500, 1, 500)
 local ir = KC_ITER_RADIUS
 local iter_pos = base_pos
 for _ = 1, iters do
  local sx = (math.random() < 0.5) and 1 or -1
  local sy = (math.random() < 0.5) and 1 or -1
  local sz = (math.random() < 0.5) and 1 or -1
  local rx = sx * (ir * (0.5 + math.random() * 0.5))
  local ry = sy * (ir * (0.5 + math.random() * 0.5))
  local rz = sz * (ir * (0.5 + math.random() * 0.5))
  local target_cf = CFrame.new(iter_pos.X + rx, iter_pos.Y + ry, iter_pos.Z + rz)
  pcall(function() hrp.CFrame = target_cf end)
  iter_pos = hrp.Position
 end
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
end

local kc_last_snap = 0

getgenv().start_kicia_counter = function()
 if kicia_counter_active then return end
 kicia_counter_active = true
 config.kicia_counter_enabled = true
 kc_nuke_fallen_parts()
 kicia_counter_conn = run_service.Heartbeat:Connect(function()
  if not config.kicia_counter_enabled then return end
  local hrp = getgenv().get_hrp(localplayer)
  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  if not hrp or not hum or hum.Health <= 0 then return end
  local target = kc_find_target()
  if not target or not target.Character then return end
  local t_hrp = target.Character:FindFirstChild("HumanoidRootPart")
  if not t_hrp then return end
  local head = target.Character:FindFirstChild("Head")
  local aggression = math.clamp(config.void_counter_aggression or 5, 1, 5)
  local passes = 16 * aggression
  for _ = 1, passes do
   pcall(tt_sample_part, t_hrp)
   if head then pcall(tt_sample_part, head) end
  end
  local raw = tt_raw_read_part(t_hrp)
  if raw then
   pcall(tt_record, t_hrp, raw.X, raw.Y, raw.Z, CFrame.new(raw), tick())
  end
  if head then
   local rh = tt_raw_read_part(head)
   if rh then pcall(tt_record, head, rh.X, rh.Y, rh.Z, CFrame.new(rh), tick()) end
  end
  local now = tick()
  local min_interval = 0.016 / aggression
  if now - kc_last_snap < min_interval then return end
  kc_last_snap = now
  pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
  pcall(function() hum.PlatformStand = false end)
  pcall(function() hum.AutoRotate = false end)
  kc_nuke_fallen_parts()
  local void_cf = CFrame.new(hrp.Position.X, KC_VOID_DEPTH, hrp.Position.Z)
  local snaps = math.clamp(config.void_counter_snap_count or 8, 1, 16)
  for _ = 1, snaps do
   kc_force_cf(hrp, void_cf)
  end
  kc_do_iteration_burst(hrp, Vector3.new(hrp.Position.X, KC_VOID_DEPTH, hrp.Position.Z))
  local dest = tt_resolve_void_pos_deep(t_hrp, head)
  if not dest or not tt_validate_vec3(dest) then
   dest = tt_resolve_dest(head, t_hrp, config.teleport_to_target_method or "Adaptive")
  end
  if not dest or not tt_validate_vec3(dest) then
   dest = tt_force_dest_resolve(t_hrp, head)
  end
  if not dest or not tt_validate_vec3(dest) then
   local live_kc = tt_live[t_hrp]
   if live_kc and live_kc.lkg_x and tt_valid_xyz(live_kc.lkg_x, live_kc.lkg_y, live_kc.lkg_z) then
    dest = Vector3.new(live_kc.lkg_x, live_kc.lkg_y, live_kc.lkg_z)
   end
  end
  if dest and tt_validate_vec3(dest) then
   for _ = 1, snaps do
    pcall(tt_apply_teleport, hrp, dest, hum, t_hrp)
   end
   kc_do_iteration_burst(hrp, dest)
   for _ = 1, snaps do
    pcall(tt_apply_teleport, hrp, dest, hum, t_hrp)
   end
   local fire_target = head or t_hrp
   manipulation.fire_toward(fire_target, target.Character)
  end
  kc_nuke_fallen_parts()
 end)
 pcall(function()
  run_service:BindToRenderStep("KiciaCounterVoidGuard", Enum.RenderPriority.First.Value - 300, function()
   if not config.kicia_counter_enabled then return end
   local hrp = getgenv().get_hrp(localplayer)
   if not hrp then return end
   local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
   local target = kc_find_target()
   if not target or not target.Character then return end
   local t_hrp = target.Character:FindFirstChild("HumanoidRootPart")
   local head = target.Character:FindFirstChild("Head")
   if not t_hrp then return end
   local aggression = math.clamp(config.void_counter_aggression or 5, 1, 5)
   for _ = 1, 8 * aggression do
    pcall(tt_sample_part, t_hrp)
    if head then pcall(tt_sample_part, head) end
   end
   if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
   kc_nuke_fallen_parts()
   local dest = tt_resolve_void_pos_deep(t_hrp, head)
   if not dest or not tt_validate_vec3(dest) then
    dest = tt_force_dest_resolve(t_hrp, head)
   end
   if dest and tt_validate_vec3(dest) then
    local snaps = math.clamp(config.void_counter_snap_count or 8, 1, 16)
    for _ = 1, snaps do
     pcall(tt_apply_teleport, hrp, dest, hum, t_hrp)
    end
    local fire_target = head or t_hrp
    manipulation.fire_toward(fire_target, target.Character)
   end
   kc_nuke_fallen_parts()
  end)
 end)
end

getgenv().stop_kicia_counter = function()
 kicia_counter_active = false
 config.kicia_counter_enabled = false
 if kicia_counter_conn then kicia_counter_conn:Disconnect(); kicia_counter_conn = nil end
 pcall(function() run_service:UnbindFromRenderStep("KiciaCounterVoidGuard") end)
 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if hum then
  pcall(function() hum.AutoRotate = true end)
  pcall(function() hum.PlatformStand = false end)
  pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
  task.defer(function()
   local h2 = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
   if h2 then
    pcall(function() h2.AutoRotate = true end)
    pcall(function() h2.PlatformStand = false end)
    if h2:GetState() == Enum.HumanoidStateType.Physics then
     pcall(function() h2:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
   end
  end)
  task.delay(0.1, function()
   local h3 = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
   if h3 then
    pcall(function() h3.AutoRotate = true end)
    pcall(function() h3.PlatformStand = false end)
    if h3:GetState() == Enum.HumanoidStateType.Physics then
     pcall(function() h3:ChangeState(Enum.HumanoidStateType.Running) end)
    end
   end
  end)
 end
end

local kicia_voidspam_thread = nil
local kicia_voidspam_attack_num = 0
local kicia_voidspam_heavy_attack_num = 0
local kicia_voidspam_last_attack = 0
local kicia_voidspam_reload_cooldown = 0

local function kicia_vs_get_equipped(char)
 return char and char:FindFirstChild("EquippedItem")
end

local function kicia_vs_get_hitbox(char)
 local head = char and (char:FindFirstChild("HitboxHead") or char:FindFirstChild("Head"))
 return head or (char and char:FindFirstChild("HumanoidRootPart"))
end

local function kicia_vs_random_unit()
 return Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1).Unit
end

local function kicia_vs_rotation(part)
 return part and part.CFrame.Rotation or CFrame.new()
end

local function kicia_vs_anim_keys(item)
 local vm = item and item.ViewModel
 return vm and vm:GetAnimationKeys() or {}
end

local function kicia_vs_fire_use(payload)
 return pcall(function()
  UseItemRemote:FireServer(payload)
 end)
end

local function kicia_vs_get_target()
 local cam = workspace.CurrentCamera
 local myChar = localplayer.Character
 local best, bestDist = nil, math.huge
 for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
  if plr ~= localplayer and plr.Character then
   local char = plr.Character
   local hum = char:FindFirstChildOfClass("Humanoid")
   local hrp = char:FindFirstChild("HumanoidRootPart")
   if hum and hum.Health > 0 and hrp then
    local dist = (hrp.Position - (myChar and myChar:FindFirstChild("HumanoidRootPart") and myChar.HumanoidRootPart.Position or Vector3.zero)).Magnitude
    if dist < bestDist then
     bestDist = dist
     best = char
    end
   end
  end
 end
 return best
end

local function kicia_vs_ranged(target)
 local myChar = localplayer.Character
 local item = kicia_vs_get_equipped(myChar)
 if not item then return false end
 if item.Info and item.Info.Type ~= "Gun" then return false end
 kicia_voidspam_attack_num = kicia_voidspam_attack_num + 1
 local hitbox = kicia_vs_get_hitbox(target)
 if not hitbox then return false end
 local aimPos = hitbox.Position + kicia_vs_random_unit() * 0.5
 local rotation = kicia_vs_rotation(hitbox)
 local ok = kicia_vs_fire_use({
  id = game:GetService("HttpService"):GenerateGUID(false),
  objectId = game:GetService("HttpService"):GenerateGUID(false),
  item = "primary",
  position = aimPos,
  attackNum = kicia_voidspam_attack_num,
  animationKeys = kicia_vs_anim_keys(item),
  rotation = rotation,
  one = Vector3.one,
  packed = { "\x00", "\x01", "\x02", "\x03" },
 })
 if ok then
  pcall(function() item:StartShooting(aimPos) end)
 end
 return ok
end

local function kicia_vs_melee(target)
 local myChar = localplayer.Character
 local item = kicia_vs_get_equipped(myChar)
 if not item then return false end
 if item.Info and item.Info.Type ~= "Melee" then return false end
 local now = tick()
 local cooldown = item.Info and item.Info.HeavyAttackCooldown or 0.2
 if now - kicia_voidspam_last_attack < cooldown then return false end
 kicia_voidspam_last_attack = now
 kicia_voidspam_heavy_attack_num = kicia_voidspam_heavy_attack_num + 1
 local hitbox = kicia_vs_get_hitbox(target)
 if not hitbox then return false end
 local aimPos = hitbox.Position + kicia_vs_random_unit() * 0.35
 local rotation = kicia_vs_rotation(hitbox)
 local ok = kicia_vs_fire_use({
  id = game:GetService("HttpService"):GenerateGUID(false),
  objectId = game:GetService("HttpService"):GenerateGUID(false),
  item = "primary",
  position = aimPos,
  heavyAttackNum = kicia_voidspam_heavy_attack_num,
  animationKeys = kicia_vs_anim_keys(item),
  rotation = rotation,
  one = Vector3.one,
  startAiming = true,
  packed = { "\x00", "\x01", "\x02", "\x03" },
 })
 if ok then
  pcall(function() item:StartAiming(aimPos) end)
  pcall(function() item:HeavyAttack(aimPos) end)
 end
 return ok
end

local function kicia_vs_loop()
 if not config.kicia_voidspam_enabled then return end
 local myChar = localplayer.Character
 if not myChar then return end
 local item = kicia_vs_get_equipped(myChar)
 if not item then return end
 local target = kicia_vs_get_target()
 if not target then return end
 local weaponType = item.Info and item.Info.Type
 local data = item.Data
 local ammo = data and data.Ammo
 local reserve = data and data.AmmoReserve
 local now = tick()
 if weaponType == "Gun" then
  if ammo and ammo <= 0 then
   if reserve and reserve > 0 then
    if now > kicia_voidspam_reload_cooldown then
     pcall(function() item:StartReloading() end)
     kicia_voidspam_reload_cooldown = now + 0.4
    end
    return
   end
   return
  end
  kicia_vs_ranged(target)
  return
 end
 if weaponType == "Melee" then
  kicia_vs_melee(target)
  return
 end
end

getgenv().start_kicia_voidspam = function()
 if not config.kicia_voidspam_enabled then return end
 run_service.Heartbeat:Connect(function()
  if not config.kicia_voidspam_enabled then return end
  if kicia_voidspam_thread and coroutine.status(kicia_voidspam_thread) ~= "dead" then return end
  kicia_voidspam_thread = task.spawn(kicia_vs_loop)
 end)
end

getgenv().stop_kicia_voidspam = function()
 config.kicia_voidspam_enabled = false
 kicia_voidspam_thread = nil
end

local desync_heartbeat = nil

local desync_render = nil

local desync_realVel = nil

local desync_angle_accum = 0

local desync_unhittable_conn = nil

local desync_unhittable_render = nil

local desync_unhittable_realCF = nil

local desync_unhittable_fake_store = {}

getgenv().start_desync = function()
 if desync_heartbeat then desync_heartbeat:Disconnect() end
 if desync_render then desync_render:Disconnect() end
 desync_realVel = nil
 desync_angle_accum = 0
 desync_heartbeat = run_service.Heartbeat:Connect(function(dt)
  local hrp = getgenv().get_hrp(localplayer)
  if not config.desync_enabled or not hrp then return end
  desync_realVel = hrp.AssemblyLinearVelocity
  local intensity = math.clamp(config.desync_intensity or 50, 1, 100)
  local spd = math.clamp(config.desync_speed or 10, 1, 100)
  local base_angle = math.rad(config.desync_angle or 90)
  local jitter_range = math.clamp(config.desync_jitter or 20, 0, 180)
  local dir_sign = (config.desync_flip) and -1 or 1
  desync_angle_accum = desync_angle_accum + math.rad(spd * dt * 360)
  local angle = base_angle + math.rad((math.random() - 0.5) * jitter_range * 2) + desync_angle_accum
  local mag = (intensity / 100) * 50000
  local spoof_vel = Vector3.new(math.cos(angle) * mag * dir_sign, (math.random() - 0.5) * mag * 0.5, math.sin(angle) * mag * dir_sign)
  local mt = getrawmetatable(hrp)
  local ni = mt and rawget(mt, "__newindex")
  if ni then
   pcall(ni, hrp, "AssemblyLinearVelocity", spoof_vel)
  else
   pcall(function() hrp.AssemblyLinearVelocity = spoof_vel end)
  end
  if sethiddenproperty then pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", spoof_vel) end
 end)

 desync_render = run_service.RenderStepped:Connect(function()
  local hrp = getgenv().get_hrp(localplayer)
  if config.desync_enabled and hrp and desync_realVel then
   hrp.AssemblyLinearVelocity = desync_realVel
  end
 end)
end

getgenv().start_unhittable_desync = function()
 if desync_unhittable_conn then desync_unhittable_conn:Disconnect() end
 if desync_unhittable_render then desync_unhittable_render:Disconnect() end
 desync_unhittable_realCF = nil
 desync_unhittable_fake_store = {}

 desync_unhittable_conn = run_service.Heartbeat:Connect(function()
  local hrp = getgenv().get_hrp(localplayer)
  if not config.desync_unhittable_enabled or not hrp then return end
  desync_unhittable_realCF = hrp.CFrame
  local iters = math.clamp(config.desync_unhittable_iters or 100, 1, 500)
  local radius = math.max(config.desync_unhittable_radius or 9000, 1)
  local y_range = math.max(config.desync_unhittable_y_range or 10, 1)
  local fake_offset = radius * (math.clamp(config.desync_unhittable_intensity or 50, 1, 100) / 100)
  local base = hrp.Position
  local mt = getrawmetatable(hrp)
  local ni = mt and rawget(mt, "__newindex")
  for _ = 1, iters do
   local sx = (math.random() < 0.5) and 1 or -1
   local sz = (math.random() < 0.5) and 1 or -1
   local fake_cf = CFrame.new(
    base.X + sx * (fake_offset * (0.5 + math.random() * 0.5)),
    base.Y + (math.random() - 0.5) * fake_offset * 0.3,
    base.Z + sz * (fake_offset * (0.5 + math.random() * 0.5))
   )
   if ni then
    pcall(ni, hrp, "CFrame", fake_cf)
    pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
   else
    pcall(function() hrp.CFrame = fake_cf; hrp.AssemblyLinearVelocity = Vector3.zero end)
   end
   if sethiddenproperty then
    pcall(sethiddenproperty, hrp, "CFrame", fake_cf)
    pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", Vector3.zero)
   end
  end
  pcall(function()
   for _, p in pairs(players:GetPlayers()) do
    if p ~= localplayer and p.Character then
     local eh = p.Character:FindFirstChild("HumanoidRootPart")
     if eh then
      local y_diff = hrp.Position.Y - eh.Position.Y
      if y_diff >= 0 and y_diff <= y_range then
       desync_unhittable_fake_store[p] = eh.CFrame
       local emt = getrawmetatable(eh)
       local eni = emt and rawget(emt, "__newindex")
       local fake_cf_u = CFrame.new(MELEE_FAKE_OFFSET)
       if eni then pcall(eni, eh, "CFrame", fake_cf_u)
       else pcall(function() rawset(eh, "CFrame", fake_cf_u) end) end
       eh.AssemblyLinearVelocity = Vector3.zero
      else
       desync_unhittable_fake_store[p] = nil
      end
     end
    end
   end
  end)
 end)

 desync_unhittable_render = run_service.RenderStepped:Connect(function()
  local hrp = getgenv().get_hrp(localplayer)
  if config.desync_unhittable_enabled and hrp and desync_unhittable_realCF then
   pcall(function()
    hrp.CFrame = desync_unhittable_realCF
    hrp.AssemblyLinearVelocity = Vector3.zero
   end)
  end
 end)
end

getgenv().stop_unhittable_desync = function()
 if desync_unhittable_conn then desync_unhittable_conn:Disconnect(); desync_unhittable_conn = nil end
 if desync_unhittable_render then desync_unhittable_render:Disconnect(); desync_unhittable_render = nil end
 desync_unhittable_realCF = nil
 desync_unhittable_fake_store = {}
 config.desync_unhittable_enabled = false
end

getgenv().stop_desync = function()
 if desync_heartbeat then desync_heartbeat:Disconnect(); desync_heartbeat = nil end
 if desync_render then desync_render:Disconnect(); desync_render = nil end
 desync_realVel = nil
 desync_angle_accum = 0
 config.desync_enabled = false
end

local pb_conn = nil

local pb_active = false

local pb_rotFn_inner = nil
local pb_camTable_inner = nil
local pb_orig_inner = nil
local pb_rs_conn2_inner = nil
local pb_rs_conn3_inner = nil

local function pb_nz_inner(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function pb_nearest_inner()
	local myChar = localplayer.Character
	local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHRP then return end
	local best, bestD = nil, math.huge
	for _, p in ipairs(players:GetPlayers()) do
		if p ~= localplayer and p.Character then
			local hrp = p.Character:FindFirstChild("HumanoidRootPart")
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (myHRP.Position - hrp.Position).Magnitude
				if d < bestD then bestD = d; best = p end
			end
		end
	end
	return best
end

local function pb_apply_inner()
	if not config.perfect_block_enabled then return end
	if not pb_camTable_inner then return end
	local tgt = pb_nearest_inner()
	if not tgt then return end
	local eChar = tgt.Character
	if not eChar then return end
	local eHRP = eChar:FindFirstChild("HumanoidRootPart")
	if not eHRP then return end
	local eHead = eChar:FindFirstChild("Head")
	local myChar = localplayer.Character
	local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myHRP then return end
	local eLook = eHRP.CFrame.LookVector
	local yaw = math.atan2(eLook.X, eLook.Z)
	local myYaw = pb_nz_inner(yaw + math.pi)
	local pitch = 0
	if eHead then
		pitch = math.asin(math.clamp(eHead.CFrame.LookVector.Y, -1, 1))
	end
	pb_camTable_inner.Rotation = Vector2.new(-pitch, myYaw)
	local counter = Vector3.new(-eLook.X, 0, -eLook.Z)
	if counter.Magnitude > 0.001 then
		pcall(function()
			myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + counter.Unit)
			myHRP.AssemblyAngularVelocity = Vector3.zero
		end)
	end
end

getgenv().start_perfect_block = function()
	if pb_active then return end
	pb_active = true
	config.perfect_block_enabled = true
	pcall(function()
		pb_rotFn_inner = filtergc("function", {Name = "_UpdateCharacterRotation"}, true)
		if not pb_rotFn_inner then return end
		pb_camTable_inner = nil
		for _, v in ipairs(debug.getupvalues(pb_rotFn_inner)) do
			if type(v) == "table" and typeof(v.Rotation) == "Vector2" then
				pb_camTable_inner = v
				break
			end
		end
		if not pb_camTable_inner then return end
		pcall(function()
			run_service:BindToRenderStep("__pb_mrot", Enum.RenderPriority.Character.Value - 1, pb_apply_inner)
		end)
		if pb_orig_inner then
			pcall(function() hookfunction(pb_rotFn_inner, pb_orig_inner) end)
			pb_orig_inner = nil
		end
		pb_orig_inner = hookfunction(pb_rotFn_inner, function(...)
			pb_apply_inner()
			return pb_orig_inner(...)
		end)
	end)
end

getgenv().stop_perfect_block = function()
	pb_active = false
	config.perfect_block_enabled = false
	pcall(function() run_service:UnbindFromRenderStep("__pb_mrot") end)
	if pb_rs_conn2_inner then pb_rs_conn2_inner:Disconnect(); pb_rs_conn2_inner = nil end
	if pb_rs_conn3_inner then pb_rs_conn3_inner:Disconnect(); pb_rs_conn3_inner = nil end
	if pb_orig_inner and pb_rotFn_inner then
		pcall(function() hookfunction(pb_rotFn_inner, pb_orig_inner) end)
		pb_orig_inner = nil
	end
	pb_rotFn_inner = nil
	pb_camTable_inner = nil
	if pb_conn then pb_conn:Disconnect(); pb_conn = nil end
end

local prediction_conn = nil

local prediction_active = false

getgenv().start_prediction = function()
    if prediction_conn then prediction_conn:Disconnect() end
    prediction_active = true
    config.prediction_enabled = true

    prediction_conn = run_service.Heartbeat:Connect(function()
        if not config.prediction_enabled then return end

        local hrp = getgenv().get_hrp(localplayer)
        if not hrp then return end

        local activation_range = math.max(config.prediction_activation_range or 20, 1)
        local distance_range = math.max(config.prediction_distance_range or 30, 1)

        local my_pos = hrp.Position

        for _, p in ipairs(players:GetPlayers()) do
            if p ~= localplayer and p.Character then
                local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")
                local t_hum = p.Character:FindFirstChildOfClass("Humanoid")

                if t_hrp and t_hum and t_hum.Health > 0 then
                    local dist = (my_pos - t_hrp.Position).Magnitude

                    if dist <= activation_range then
                        local away_dir = (my_pos - t_hrp.Position)

                        if away_dir.Magnitude > 0.001 then
                            away_dir = away_dir.Unit
                        else
                            away_dir = Vector3.new(1, 0, 0)
                        end

                        local target_pos = my_pos + away_dir * distance_range

                        pcall(function()
                            hrp.CFrame = CFrame.new(target_pos)
                            hrp.AssemblyLinearVelocity = Vector3.zero
                            hrp.AssemblyAngularVelocity = Vector3.zero
                        end)

                        break
                    end
                end
            end
        end
    end)
end

getgenv().stop_prediction = function()
    prediction_active = false
    config.prediction_enabled = false
    if prediction_conn then prediction_conn:Disconnect(); prediction_conn = nil end
end



local bm_settings = { enabled=false, pitch=90, yaw=90 }

local bm_utils = { getrandominrange=function(mn,mx) return mn+math.random()*(mx-mn) end }

local function make_spin_wild()

 local minangle = math.rad(bm_settings and bm_settings.minangle or 30)

 local maxangle = math.rad(bm_settings and bm_settings.maxangle or 60)

 local function jitter_axis()
 if bm_settings and bm_settings.randomangle then
 return bm_utils.getrandominrange(-maxangle, maxangle)
 end

 return math.random() > 0.5 and minangle or -minangle
 end

 return CFrame.Angles(jitter_axis(), jitter_axis(), jitter_axis())
end


local teleport_to_target_conn = nil

local tt_render_conn = nil

local tt_spawn_active = false

local tt_micro_active = false

local tt_track = {}

local tt_live = {}

local TT_HISTORY_LEN = 128

local TT_MICRO_SAMPLES = 1024

local TT_VOID_THRESH = -200

local TT_VOID_HIST_LEN = 64

local TT_CHAOS_JUMP_THRESH = 400

local TT_DEEP_VOID_THRESH = -1000

local TT_SPAMMER_CHAOS_THRESHOLD = 4

local TT_MAX_EXTRAP_AGE = 0.4

local TT_CENTROID_BLEND = 0.92

local TT_VEL_EMA_FAST = 0.25

local TT_VEL_EMA_SLOW = 0.08

local tt_locked_target = nil

local function tt_isnan(v) return v ~= v end

local function tt_isinf(v) return math.abs(v) == math.huge end

local function tt_valid_scalar(v) return not tt_isnan(v) and not tt_isinf(v) end

local function tt_valid_xyz(x,y,z) return tt_valid_scalar(x) and tt_valid_scalar(y) and tt_valid_scalar(z) end

local function tt_validate_vec3(v)
 if not v then return false end

 local x,y,z=v.X,v.Y,v.Z
 return tt_valid_xyz(x,y,z)
end

local function tt_record(part, x, y, z, cf, now)
 if not tt_valid_xyz(x,y,z) then return end

 local live = tt_live[part]
 if not live then
  tt_live[part] = {
   x=x,y=y,z=z,cf=cf,t=now,
   lkg_x=x,lkg_y=y,lkg_z=z,lkg_cf=cf,lkg_t=now,
   is_void=false,is_deep_void=false,void_vel=Vector3.zero,
   last_x=x,last_y=y,last_z=z,last_t=now,
   void_cx=x,void_cy=y,void_cz=z,void_cn=0,
   void_min_x=x,void_max_x=x,
   void_min_y=y,void_max_y=y,
   void_min_z=z,void_max_z=z,
   chaos_count=0,chaos_t=now,
   spd_ema_fast=0,spd_ema_slow=0,
   vel_x=0,vel_y=0,vel_z=0,
   vel_ema_x=0,vel_ema_y=0,vel_ema_z=0,
   surface_x=x,surface_y=y,surface_z=z,surface_t=now,
   last_surface_x=x,last_surface_y=y,last_surface_z=z,
   entry_void_t=nil,exit_void_t=now,
   jump_count=0,
  }
  live = tt_live[part]
 else

  local prev_is_void = live.is_void

  local px,py,pz,pt = live.x,live.y,live.z,live.t
  live.last_x,live.last_y,live.last_z,live.last_t = px,py,pz,pt
  live.x,live.y,live.z,live.cf,live.t = x,y,z,cf,now

  local dt_r = now - pt
  if dt_r > 0.000001 then

   local jump = math.sqrt((x-px)*(x-px)+(y-py)*(y-py)+(z-pz)*(z-pz))

   local spd = jump / dt_r
   live.spd_ema_fast = live.spd_ema_fast * (1-TT_VEL_EMA_FAST) + spd * TT_VEL_EMA_FAST
   live.spd_ema_slow = live.spd_ema_slow * (1-TT_VEL_EMA_SLOW) + spd * TT_VEL_EMA_SLOW

   local raw_vx = (x-px)/dt_r

   local raw_vy = (y-py)/dt_r

   local raw_vz = (z-pz)/dt_r
   live.vel_x,live.vel_y,live.vel_z = raw_vx,raw_vy,raw_vz
   live.vel_ema_x = live.vel_ema_x * 0.7 + raw_vx * 0.3
   live.vel_ema_y = live.vel_ema_y * 0.7 + raw_vy * 0.3
   live.vel_ema_z = live.vel_ema_z * 0.7 + raw_vz * 0.3
   if jump > TT_CHAOS_JUMP_THRESH then
    live.chaos_count = (live.chaos_count or 0) + 3
    live.chaos_t = now
    live.jump_count = (live.jump_count or 0) + 1
   else

    local cc = live.chaos_count or 0
    if cc > 0 then live.chaos_count = cc - 1 end
   end
  end


  local new_is_void = y < TT_VOID_THRESH

  local new_is_deep = y < TT_DEEP_VOID_THRESH
  live.is_void = new_is_void
  live.is_deep_void = new_is_deep
  if not new_is_void then
   live.lkg_x,live.lkg_y,live.lkg_z = x,y,z
   live.lkg_cf,live.lkg_t = cf,now
   live.surface_x,live.surface_y,live.surface_z = x,y,z
   live.surface_t = now
   live.last_surface_x = live.surface_x
   live.last_surface_y = live.surface_y
   live.last_surface_z = live.surface_z
  else
   if not prev_is_void then
    live.entry_void_t = now
    live.last_surface_x = live.lkg_x or x
    live.last_surface_y = live.lkg_y or y
    live.last_surface_z = live.lkg_z or z
   end


   local cn = (live.void_cn or 0) + 1
   live.void_cn = cn

   local w = 1 / cn

   local keep = 1 - w
   live.void_cx = (live.void_cx or x) * keep + x * w
   live.void_cy = (live.void_cy or y) * keep + y * w
   live.void_cz = (live.void_cz or z) * keep + z * w
   if live.void_min_x == nil or x < live.void_min_x then live.void_min_x = x end
   if live.void_max_x == nil or x > live.void_max_x then live.void_max_x = x end
   if live.void_min_y == nil or y < live.void_min_y then live.void_min_y = y end
   if live.void_max_y == nil or y > live.void_max_y then live.void_max_y = y end
   if live.void_min_z == nil or z < live.void_min_z then live.void_min_z = z end
   if live.void_max_z == nil or z > live.void_max_z then live.void_max_z = z end
  end

  if (not prev_is_void) and new_is_void then

   local dt_v = now - (live.lkg_t or now)
   if dt_v > 0.000001 then
    live.void_vel = Vector3.new(
     (x-(live.lkg_x or x))/dt_v,
     (y-(live.lkg_y or y))/dt_v,
     (z-(live.lkg_z or z))/dt_v)
   end
  end

  if prev_is_void and not new_is_void then
   live.void_cn = 0
   live.void_cx,live.void_cy,live.void_cz = x,y,z
   live.void_min_x,live.void_max_x = x,x
   live.void_min_y,live.void_max_y = y,y
   live.void_min_z,live.void_max_z = z,z
   live.exit_void_t = now
  end
 end


 local entry = tt_track[part]
 if not entry then
  tt_track[part] = {hist={},hi=0,void_hist={},vh=0}
  entry = tt_track[part]
 end


 local hist = entry.hist

 local hi = (entry.hi % TT_HISTORY_LEN) + 1
 entry.hi = hi
 hist[hi] = {x=x,y=y,z=z,t=now}
 if y < TT_VOID_THRESH then

  local vh = (entry.vh % TT_VOID_HIST_LEN) + 1
  entry.vh = vh

  local vh_tbl = entry.void_hist
  vh_tbl[vh] = {x=x,y=y,z=z,t=now}
 end
end

local function tt_predict_velocity(part)

 local live = tt_live[part]

 local entry = tt_track[part]
 if not entry or not entry.hist then return Vector3.zero end

 local hist = entry.hist

 local n = #hist
 if n < 3 then return Vector3.zero end

 local hi = entry.hi

 local is_voidspam = live and (live.chaos_count or 0) >= TT_SPAMMER_CHAOS_THRESHOLD
 if is_voidspam then
  if live and live.last_surface_x and tt_valid_xyz(live.last_surface_x,live.last_surface_y,live.last_surface_z) then

   local sx,sy,sz = live.last_surface_x,live.last_surface_y,live.last_surface_z

   local lx = live.lkg_x or sx

   local ly = live.lkg_y or sy

   local lz = live.lkg_z or sz

   local dvx,dvy,dvz = sx-lx,sy-ly,sz-lz

   local mag = math.sqrt(dvx*dvx+dvy*dvy+dvz*dvz)
   if mag > 0.5 then return Vector3.new(dvx,dvy,dvz) end
  end


  local vhist = entry.void_hist
  if not vhist then return Vector3.zero end

  local sum_x,sum_y,sum_z,cnt = 0,0,0,0
  for _,s in pairs(vhist) do
   if s then sum_x=sum_x+s.x; sum_y=sum_y+s.y; sum_z=sum_z+s.z; cnt=cnt+1 end
  end

  if cnt < 2 then return Vector3.zero end

  local cx=sum_x/cnt; local cy=sum_y/cnt; local cz=sum_z/cnt

  local base_x = live and live.lkg_x or cx

  local base_y = live and live.lkg_y or cy

  local base_z = live and live.lkg_z or cz
  return Vector3.new(cx-base_x,cy-base_y,cz-base_z)
 end


 local count = math.min(n,24)

 local vx,vy,vz,tw = 0,0,0,0
 for k = 1, count-1 do

  local bi = ((hi-k-1+TT_HISTORY_LEN) % TT_HISTORY_LEN)+1

  local ai = ((hi-k-2+TT_HISTORY_LEN) % TT_HISTORY_LEN)+1

  local b = hist[bi]

  local a = hist[ai]
  if b and a then

   local dt_h = b.t - a.t
   if dt_h > 0.000001 then

    local dvx=(b.x-a.x)/dt_h

    local dvy=(b.y-a.y)/dt_h

    local dvz=(b.z-a.z)/dt_h

    local mag_sq = dvx*dvx+dvy*dvy+dvz*dvz
    if mag_sq < 1e12 then

     local w = 1/(k*k)
     vx=vx+dvx*w; vy=vy+dvy*w; vz=vz+dvz*w; tw=tw+w
    end
   end
  end
 end

 if tw == 0 then return Vector3.zero end
 return Vector3.new(vx/tw,vy/tw,vz/tw)
end

local function tt_target_valid(p)
 if not p or not p.Character then return false end

 local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")
 if not t_hrp then return false end
 if p.Character:FindFirstChildOfClass("ForceField") then return false end

 local sameTeam = localplayer.Team and p.Team and localplayer.Team == p.Team
 if sameTeam then return false end

 local live = tt_live[t_hrp]
 if live then return true end

 local hum = p.Character:FindFirstChildOfClass("Humanoid")

 local alive = false
 if hum then pcall(function() alive = hum.Health > 0 end) end
 return alive
end

local function get_teleport_target()

 local mode = config.teleport_to_target_mode or "Closest"

 local priorityName = config.teleport_to_target_priority
 if priorityName and priorityName ~= "" then

  local specificPlayer = players:FindFirstChild(priorityName)
  if specificPlayer and tt_target_valid(specificPlayer) then
   if config.teleport_to_target_lock then tt_locked_target = specificPlayer end
   return specificPlayer
  end
 end

 if config.teleport_to_target_lock and tt_locked_target then
  if tt_target_valid(tt_locked_target) then
   return tt_locked_target
  else
   tt_locked_target = nil
  end
 end


 local hrp = getgenv().get_hrp(localplayer)
 if not hrp then return nil end

 local my_x,my_y,my_z = hrp.Position.X,hrp.Position.Y,hrp.Position.Z

 local best_target = nil

 local best_val = (mode == "Closest") and math.huge or -math.huge

 local sr = config.teleport_to_target_search_radius or 999e15
 for _,p in ipairs(players:GetPlayers()) do
  if p ~= localplayer and tt_target_valid(p) then

   local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")
   if t_hrp then

    local tx,ty,tz

    local live = tt_live[t_hrp]
    if live then
     if live.is_void and live.lkg_x then
      tx,ty,tz = live.lkg_x,live.lkg_y,live.lkg_z
     else
      tx,ty,tz = live.x,live.y,live.z
     end
    else
     pcall(function() local cf=t_hrp.CFrame; tx,ty,tz=cf.X,cf.Y,cf.Z end)
    end

    if tx and tt_valid_xyz(tx,ty,tz) then

     local dx=tx-my_x; local dy=ty-my_y; local dz=tz-my_z

     local dist_sq = dx*dx+dy*dy+dz*dz
     if dist_sq <= sr*sr then
      if mode == "Closest" and dist_sq < best_val then
       best_val=dist_sq; best_target=p
      elseif mode == "Farthest" and dist_sq > best_val then
       best_val=dist_sq; best_target=p
      elseif mode == "LowestHP" then

       local hum = p.Character:FindFirstChildOfClass("Humanoid")

       local hp = math.huge
       if hum then pcall(function() hp=hum.Health end) end
       if hp < best_val then best_val=hp; best_target=p end
      end
     end
    end
   end
  end
 end

 if config.teleport_to_target_lock and best_target then
  tt_locked_target = best_target
 end

 return best_target
end

local function tt_sample_part(part)

 local cf

 local now = tick()
 pcall(function()

  local mt = getrawmetatable(part)
  if mt then local ri=rawget(mt,"__index"); if ri then cf=ri(part,"CFrame") end end
 end)

 if not cf then
  pcall(function() if gethiddenproperty then local v=gethiddenproperty(part,"CFrame"); if v then cf=v end end end)
 end

 if not cf then
  pcall(function() if ficlone then local cl=ficlone(part); if cl then cf=cl.CFrame end end end)
 end

 if not cf then
  pcall(function() if getproperties then local props=getproperties(part); if props and props.CFrame then cf=props.CFrame end end end)
 end

 if not cf then

  local ok,raw = pcall(function() return part.CFrame end)
  if ok and raw then cf=raw end
 end

 if not cf then return end

 local px,py,pz = cf.X,cf.Y,cf.Z
 if not tt_valid_xyz(px,py,pz) then return end
 tt_record(part,px,py,pz,cf,now)
end

local function tt_sample_all_parts(char, t_hrp)
 pcall(tt_sample_part, t_hrp)

 local head = char:FindFirstChild("Head")
 if head then pcall(tt_sample_part, head) end

 local tor = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
 if tor then pcall(tt_sample_part, tor) end
end

local function srb_write(hrp, target_cf)
 if not hrp or not target_cf then return end

 local V0 = Vector3.zero
 pcall(function()
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
  hrp.CFrame = target_cf
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
 end)

 pcall(function()

  local mt = getrawmetatable(hrp)
  if not mt then return end

  local ni = rawget(mt, "__newindex")
  if not ni then return end
  ni(hrp, "AssemblyLinearVelocity", V0)
  ni(hrp, "AssemblyAngularVelocity", V0)
  ni(hrp, "CFrame", target_cf)
  ni(hrp, "AssemblyLinearVelocity", V0)
  ni(hrp, "AssemblyAngularVelocity", V0)
 end)

 if sethiddenproperty then
  pcall(sethiddenproperty, hrp, "CFrame", target_cf)
  pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", V0)
  pcall(sethiddenproperty, hrp, "AssemblyAngularVelocity", V0)
 end

 pcall(function()
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
  hrp.CFrame = target_cf
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
 end)
end

local function tt_nuke_fallen_parts()
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 pcall(function()

  local mt = getrawmetatable(workspace)
  if mt then

   local ni = rawget(mt,"__newindex")
   if ni then
    ni(workspace,"FallenPartsDestroyHeight",-math.huge)
    pcall(function() ni(workspace,"FallenPartsDestroyHeight",0/0) end)
   end
  end
 end)
end

local function tt_force_cframe(hrp, target_cf)
 tt_nuke_fallen_parts()

 local V0 = Vector3.zero

 local function write_direct()
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
  hrp.CFrame = target_cf
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
 end


 local function write_rawmt()

  local mt = getrawmetatable(hrp)
  if not mt then return end

  local ni = rawget(mt,"__newindex")
  if not ni then return end
  ni(hrp,"AssemblyLinearVelocity",V0)
  ni(hrp,"AssemblyAngularVelocity",V0)
  ni(hrp,"CFrame",target_cf)
  ni(hrp,"AssemblyLinearVelocity",V0)
  ni(hrp,"AssemblyAngularVelocity",V0)
  ni(hrp,"CFrame",target_cf)
  ni(hrp,"AssemblyLinearVelocity",V0)
  ni(hrp,"AssemblyAngularVelocity",V0)
 end


 local function write_anchor()

  local was = hrp.Anchored
  hrp.Anchored = true
  hrp.CFrame = target_cf
  hrp.AssemblyLinearVelocity = V0
  hrp.AssemblyAngularVelocity = V0
  hrp.CFrame = target_cf
  hrp.Anchored = was
 end


 local function write_sethidden()
  if sethiddenproperty then
   pcall(sethiddenproperty,hrp,"AssemblyLinearVelocity",V0)
   pcall(sethiddenproperty,hrp,"AssemblyAngularVelocity",V0)
   pcall(sethiddenproperty,hrp,"CFrame",target_cf)
   pcall(sethiddenproperty,hrp,"AssemblyLinearVelocity",V0)
   pcall(sethiddenproperty,hrp,"AssemblyAngularVelocity",V0)
   pcall(sethiddenproperty,hrp,"CFrame",target_cf)
  end
 end


 local function write_unlock()
  if setreadonly and getrawmetatable then

   local mt = getrawmetatable(hrp)
   if mt then
    setreadonly(mt,false)
    pcall(function() rawset(hrp,"CFrame",target_cf) end)
    pcall(function() rawset(hrp,"AssemblyLinearVelocity",V0) end)
    setreadonly(mt,true)
   end
  end
 end


 local function write_ficlone()
  if ficlone then
   pcall(function() local cl=ficlone(hrp); if cl then cl.CFrame=target_cf end end)
  end
 end


 local function write_getproperties()
  if getproperties and setproperties then
   pcall(function() setproperties(hrp,{CFrame=target_cf,AssemblyLinearVelocity=V0,AssemblyAngularVelocity=V0}) end)
  end
 end


 local written = false

 local function try(fn)
  if written then return end

  local ok = pcall(fn)
  if ok then written = true end
 end

 try(write_rawmt)
 try(write_direct)
 try(write_sethidden)
 try(write_anchor)
 try(write_unlock)
 try(write_ficlone)
 try(write_getproperties)
 if not written then
  for _ = 1, 12 do
   pcall(write_direct)
   pcall(write_rawmt)
   pcall(write_anchor)
   pcall(write_sethidden)
  end
 else
  for _ = 1, 6 do
   pcall(write_rawmt)
   pcall(write_direct)
  end
 end

 tt_nuke_fallen_parts()
end

local function tt_get_offset_dist()

 local d = config.teleport_to_target_offset_dist
 if type(d) ~= "number" or d ~= d or math.abs(d) == math.huge then return 3 end
 return math.clamp(d,0,500)
end

local function tt_get_offset_dest(part, base)

 local pos_mode = config.teleport_to_target_position or "Front"

 local live = tt_live[part]

 local cf = live and live.cf
 if not cf then

  local ok,raw = pcall(function() return part.CFrame end)
  if ok then cf=raw end
 end

 if not cf then return base end

 local d = tt_get_offset_dist()

 local dest
 if pos_mode == "Front" then dest=(cf*CFrame.new(0,0,-d)).Position
 elseif pos_mode == "Behind" then dest=(cf*CFrame.new(0,0,d)).Position
 elseif pos_mode == "Above" then dest=(cf*CFrame.new(0,d,0)).Position
 elseif pos_mode == "Below" then dest=(cf*CFrame.new(0,-d,0)).Position
 elseif pos_mode == "Left" then dest=(cf*CFrame.new(-d,0,0)).Position
 elseif pos_mode == "Right" then dest=(cf*CFrame.new(d,0,0)).Position
 elseif pos_mode == "Exact" then dest=cf.Position
 end

 if dest and tt_validate_vec3(dest) then return dest end
 return base
end

local function tt_aim_lead_dest(part, base)
 if not config.teleport_to_target_aim_lead then return base end

 local vel = tt_predict_velocity(part)
 if not vel or vel.Magnitude < 1 then return base end

 local lead_t = math.clamp(vel.Magnitude/500*(1/30),0,0.35)

 local led = base + vel * lead_t
 if tt_validate_vec3(led) then return led end
 return base
end

local function tt_apply_teleport(hrp, dest, hum, t_hrp)
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 if not tt_validate_vec3(dest) then return end
 if hum then
  pcall(function() hum.AutoRotate = false end)
  pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
 end


 local final_dest = tt_get_offset_dest(t_hrp, dest)
 final_dest = tt_aim_lead_dest(t_hrp, final_dest)
 if not tt_validate_vec3(final_dest) then final_dest = dest end

 local x,y,z = final_dest.X,final_dest.Y,final_dest.Z

 local target_cf
 if config.spin_shot_enabled then

  local function jitter_axis()

   local minA = math.rad(config.bm_settings and config.bm_settings.minangle or 30)

   local maxA = math.rad(config.bm_settings and config.bm_settings.maxangle or 60)
   return math.random() > 0.5 and minA or -minA
  end

  target_cf = CFrame.new(x,y,z) * CFrame.Angles(jitter_axis(),jitter_axis(),jitter_axis())
 else
  target_cf = CFrame.new(x,y,z)
 end


 local y_off = config.teleport_to_target_y_offset or 0
 if y_off ~= 0 then
  target_cf = CFrame.new(target_cf.X, target_cf.Y + y_off, target_cf.Z)
 end


 local jitter = config.teleport_to_target_jitter or 0
 if jitter > 0 then

  local jr = jitter
  target_cf = CFrame.new(target_cf.X + (math.random()-0.5)*2*jr, target_cf.Y + (math.random()-0.5)*2*jr, target_cf.Z + (math.random()-0.5)*2*jr)
 end

 if config.teleport_to_target_randomize_pos then

  local rr = 3
  target_cf = CFrame.new(target_cf.X + (math.random()-0.5)*2*rr, target_cf.Y, target_cf.Z + (math.random()-0.5)*2*rr)
 end

 if config.teleport_to_target_ghost_step then
  local gd = config.teleport_to_target_ghost_dist or 500
  local ghost_cf = CFrame.new(target_cf.X, target_cf.Y + gd, target_cf.Z)
  task.defer(function()
   pcall(function() tt_force_cframe(hrp, ghost_cf) end)
  end)
 end

 if config.teleport_to_target_velocity_kill then
  pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
  pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)
 end

 if config.teleport_to_target_snap_face and t_hrp then
  local look_dir = (target_cf.Position - hrp.Position)
  if look_dir.Magnitude > 0.01 then
   local flat_look = Vector3.new(look_dir.X, 0, look_dir.Z)
   if flat_look.Magnitude > 0.01 then
    target_cf = CFrame.new(target_cf.Position, target_cf.Position + flat_look)
   else
    target_cf = CFrame.new(target_cf.Position, target_cf.Position + look_dir)
   end
  end
 end

 if config.teleport_to_target_sync_to_ragebot then
  srb_write(hrp, target_cf)
 end

 if config.teleport_to_target_burst_mode then

  local bc = math.clamp(config.teleport_to_target_burst_count or 3, 1, 8)
  for _b = 1, bc do
   tt_force_cframe(hrp, target_cf)
  end
 else
  tt_force_cframe(hrp, target_cf)
 end

 if t_hrp then
  local head_part = t_hrp.Parent and t_hrp.Parent:FindFirstChild("Head")
  local fire_target = head_part or t_hrp
  manipulation.fire_toward(fire_target, t_hrp.Parent)
 end

 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
end

local function tt_get_latest_pos(part)

 local live = tt_live[part]
 if live then return Vector3.new(live.x,live.y,live.z) end

 local ok,cf = pcall(function() return part.CFrame end)
 if ok and cf then

  local x,y,z = cf.X,cf.Y,cf.Z
  if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end
 end

 return nil
end

local function tt_get_lkg_pos(part)

 local live = tt_live[part]
 if live and live.lkg_x then
  return Vector3.new(live.lkg_x,live.lkg_y,live.lkg_z)
 end

 return tt_get_latest_pos(part)
end

local function tt_is_in_void(part)

 local live = tt_live[part]
 return live and live.is_void or false
end

local function tt_get_predicted_pos(part, lookahead)

 local live = tt_live[part]
 if not live then

  local ok,cf = pcall(function() return part.CFrame end)
  if ok and cf then return Vector3.new(cf.X,cf.Y,cf.Z) end
  return nil
 end


 local base = Vector3.new(live.x,live.y,live.z)
 if not lookahead or lookahead <= 0 then return base end

 local vel = tt_predict_velocity(part)
 if vel.Magnitude < 0.001 then return base end

 local pred = base + vel * lookahead

 local ddx=pred.X-base.X; local ddy=pred.Y-base.Y; local ddz=pred.Z-base.Z
 if ddx*ddx+ddy*ddy+ddz*ddz > 1e12 then return base end
 if pred.X ~= pred.X or pred.Y ~= pred.Y or pred.Z ~= pred.Z then return base end
 return pred
end

local function tt_get_ping_seconds()

 local ok,stat = pcall(function() return game:GetService("Stats") end)
 if ok and stat then

  local ok2,ping = pcall(function() return stat.Network.ServerStatsItem["Data Ping"].Value end)
  if ok2 and type(ping) == "number" and ping == ping then
   return math.clamp(ping/1000,0,0.5)
  end
 end

 return 1/30
end

local function tt_raw_read_part(part)
 if not part then return nil end

 local cf
 pcall(function() local mt=getrawmetatable(part); if mt then local ri=rawget(mt,"__index"); if ri then cf=ri(part,"CFrame") end end end)
 if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() if gethiddenproperty then local v=gethiddenproperty(part,"CFrame"); if v then cf=v end end end)
 if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() if ficlone then local cl=ficlone(part); if cl then cf=cl.CFrame end end end)
 if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() if getproperties then local props=getproperties(part); if props and props.CFrame then cf=props.CFrame end end end)
 if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
 pcall(function() cf=part.CFrame end)
 if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
 return nil
end

local function tt_void_centroid(t_hrp)

 local live = tt_live[t_hrp]
 if not live then return nil end
 if live.void_min_x and live.void_max_x then

  local mx=(live.void_min_x+live.void_max_x)*0.5

  local my=(live.void_min_y+live.void_max_y)*0.5

  local mz=(live.void_min_z+live.void_max_z)*0.5
  if tt_valid_xyz(mx,my,mz) then return Vector3.new(mx,my,mz) end
 end

 if live.void_cx and tt_valid_xyz(live.void_cx,live.void_cy,live.void_cz) then
  return Vector3.new(live.void_cx,live.void_cy,live.void_cz)
 end

 return nil
end

local function tt_resolve_void_pos_deep(t_hrp, head)

 local live = tt_live[t_hrp]

 local function try_read(part)

  local cf
  pcall(function() local mt=getrawmetatable(part); if mt then local ri=rawget(mt,"__index"); if ri then cf=ri(part,"CFrame") end end end)
  if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
  pcall(function() if gethiddenproperty then local v=gethiddenproperty(part,"CFrame"); if v then cf=v end end end)
  if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
  pcall(function() if ficlone then local cl=ficlone(part); if cl then cf=cl.CFrame end end end)
  if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
  pcall(function() if getproperties then local props=getproperties(part); if props and props.CFrame then cf=props.CFrame end end end)
  if cf then local x,y,z=cf.X,cf.Y,cf.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end

  local ok,raw = pcall(function() return part.CFrame end)
  if ok and raw then local x,y,z=raw.X,raw.Y,raw.Z; if tt_valid_xyz(x,y,z) then return Vector3.new(x,y,z) end end
  return nil
 end


 local r = try_read(t_hrp)
 if r and tt_validate_vec3(r) then return r end
 if head then r=try_read(head); if r and tt_validate_vec3(r) then return r end end
 if live then
  if live.is_void and live.void_cn and live.void_cn > 0 then

   local cx,cy,cz = live.void_cx,live.void_cy,live.void_cz
   if tt_valid_xyz(cx,cy,cz) then

    local cand = Vector3.new(cx,cy,cz)
    if tt_validate_vec3(cand) then return cand end
   end

   if live.void_min_x ~= nil and live.void_max_x ~= nil then

    local mx=(live.void_min_x+live.void_max_x)*0.5

    local my=(live.void_min_y+live.void_max_y)*0.5

    local mz=(live.void_min_z+live.void_max_z)*0.5
    if tt_valid_xyz(mx,my,mz) then return Vector3.new(mx,my,mz) end
   end
  end

  if live.last_surface_x and tt_valid_xyz(live.last_surface_x,live.last_surface_y,live.last_surface_z) then

   local sv = Vector3.new(live.last_surface_x,live.last_surface_y,live.last_surface_z)
   if tt_validate_vec3(sv) then return sv end
  end
 end


 local lkg = tt_get_lkg_pos(t_hrp)
 if lkg and tt_validate_vec3(lkg) then
  if live and live.void_vel and live.void_vel.Magnitude > 0 then

   local age = math.min(tick()-(live.lkg_t or tick()), TT_MAX_EXTRAP_AGE)

   local extrap = lkg + live.void_vel * age
   if tt_validate_vec3(extrap) then return extrap end
  end

  return lkg
 end


 local entry = tt_track[t_hrp]
 if entry and entry.void_hist then

  local vh = entry.void_hist

  local sx,sy,sz,sc = 0,0,0,0
  for _,s in pairs(vh) do
   if s then sx=sx+s.x; sy=sy+s.y; sz=sz+s.z; sc=sc+1 end
  end

  if sc > 0 then return Vector3.new(sx/sc,sy/sc,sz/sc) end
 end

 return nil
end

local function tt_resolve_dest(head, t_hrp, method)

 local ping = tt_get_ping_seconds()

 local stagger = math.clamp(config.teleport_to_target_stagger or 1,0,10)

 local vel = tt_predict_velocity(t_hrp)

 local spd = vel and vel.Magnitude or 0

 local lkg = tt_get_lkg_pos(t_hrp)

 local live = tt_live[t_hrp]

 local is_chaos = live and (live.chaos_count or 0) >= TT_SPAMMER_CHAOS_THRESHOLD

 local is_void = live and live.is_void

 local function safe_pos(pos)
  if not pos or not tt_validate_vec3(pos) then return nil end

  local x,y,z = pos.X,pos.Y,pos.Z
  if not tt_valid_xyz(x,y,z) then return nil end
  return pos
 end

 local function clamp_to_lkg(pos)
  if not lkg or not tt_validate_vec3(lkg) then return pos end
  if not tt_validate_vec3(pos) then return lkg end

  local delta = (pos-lkg).Magnitude
  if delta > 2e7 then return lkg end
  return pos
 end

 if is_chaos or is_void then

  if config.void_mimic_enabled and vm_get_mimic_pos then
   local mimic = vm_get_mimic_pos(t_hrp, tick())
   if mimic and tt_validate_vec3(mimic) then return mimic end
   if head then
    local mimic_h = vm_get_mimic_pos(head, tick())
    if mimic_h and tt_validate_vec3(mimic_h) then return mimic_h end
   end
  end

  local cand = safe_pos(tt_resolve_void_pos_deep(t_hrp, head))
  if not cand and live then
   if live.last_surface_x and tt_valid_xyz(live.last_surface_x,live.last_surface_y,live.last_surface_z) then
    cand = safe_pos(Vector3.new(live.last_surface_x,live.last_surface_y,live.last_surface_z))
   end

   if not cand and live.void_cx then
    cand = safe_pos(Vector3.new(live.void_cx,live.void_cy,live.void_cz))
   end

   if not cand and live.void_min_x and live.void_max_x then

    local mx=(live.void_min_x+live.void_max_x)*0.5

    local my=(live.void_min_y+live.void_max_y)*0.5

    local mz=(live.void_min_z+live.void_max_z)*0.5
    cand = safe_pos(Vector3.new(mx,my,mz))
   end

   if not cand and live.lkg_x then

    local base_lkg = Vector3.new(live.lkg_x,live.lkg_y,live.lkg_z)
    if live.void_vel and live.void_vel.Magnitude > 0 then

     local age = math.min(tick()-(live.lkg_t or tick()), TT_MAX_EXTRAP_AGE)

     local extrap = base_lkg + live.void_vel * age
     cand = safe_pos(extrap)
    end

    if not cand then cand = safe_pos(base_lkg) end
   end
  end

  if not cand then cand = safe_pos(lkg) end
  if not cand then

   local entry = tt_track[t_hrp]
   if entry and entry.void_hist then

    local vh = entry.void_hist

    local sx,sy,sz,sc = 0,0,0,0
    for _,s in pairs(vh) do if s then sx=sx+s.x; sy=sy+s.y; sz=sz+s.z; sc=sc+1 end end
    if sc > 0 then cand = safe_pos(Vector3.new(sx/sc,sy/sc,sz/sc)) end
   end
  end

  if not cand and entry and entry.hist then
   for k = entry.hi, 1, -1 do

    local h = entry.hist[k]
    if h and tt_valid_xyz(h.x,h.y,h.z) then cand = safe_pos(Vector3.new(h.x,h.y,h.z)); break end
   end
  end

  return cand
 end

 if method == "Predictive" then

  local base = safe_pos(tt_get_latest_pos(t_hrp)) or safe_pos(lkg)
  if not base then return nil end
  base = clamp_to_lkg(base)
  if spd > 0.01 and vel then

   local la = math.min(spd/1000*ping*stagger,2)

   local pred = safe_pos(base + vel*la)
   if pred then
    pred = clamp_to_lkg(pred)
    return pred
   end
  end

  return base
 elseif method == "Adaptive" then

  local base = safe_pos(tt_get_latest_pos(t_hrp)) or safe_pos(lkg)
  if not base then return nil end
  base = clamp_to_lkg(base)
  if spd > 0.01 and vel then

   local la = math.min(spd/1000*ping*stagger,2)

   local pred = safe_pos(base + vel*la)
   if pred then
    pred = clamp_to_lkg(pred)
    if lkg and tt_validate_vec3(lkg) then

     local pred_d = (pred-lkg).Magnitude

     local live_d = (base-lkg).Magnitude
     if pred_d < live_d then base = pred end
    else
     base = pred
    end
   end
  end

  return tt_validate_vec3(base) and base or safe_pos(lkg)
 else

  local pos = safe_pos(tt_get_latest_pos(t_hrp)) or safe_pos(lkg)
  if not pos then return nil end
  pos = clamp_to_lkg(pos)
  return tt_validate_vec3(pos) and pos or safe_pos(lkg)
 end
end

local function tt_force_dest_resolve(t_hrp, head)

 local live = tt_live[t_hrp]

 local candidates = {}
 if live then
  if tt_valid_xyz(live.x,live.y,live.z) then candidates[#candidates+1]=Vector3.new(live.x,live.y,live.z) end
  if live.lkg_x and tt_valid_xyz(live.lkg_x,live.lkg_y,live.lkg_z) then candidates[#candidates+1]=Vector3.new(live.lkg_x,live.lkg_y,live.lkg_z) end
  if live.last_surface_x and tt_valid_xyz(live.last_surface_x,live.last_surface_y,live.last_surface_z) then
   candidates[#candidates+1]=Vector3.new(live.last_surface_x,live.last_surface_y,live.last_surface_z)
  end

  if live.void_cx and tt_valid_xyz(live.void_cx,live.void_cy,live.void_cz) then candidates[#candidates+1]=Vector3.new(live.void_cx,live.void_cy,live.void_cz) end
  if live.void_min_x and live.void_max_x then

   local mx=(live.void_min_x+live.void_max_x)*0.5

   local my=(live.void_min_y+live.void_max_y)*0.5

   local mz=(live.void_min_z+live.void_max_z)*0.5
   if tt_valid_xyz(mx,my,mz) then candidates[#candidates+1]=Vector3.new(mx,my,mz) end
  end

  if live.void_vel and live.lkg_x and live.void_vel.Magnitude > 0 then

   local age = math.min(tick()-(live.lkg_t or tick()), TT_MAX_EXTRAP_AGE)

   local extrap = Vector3.new(live.lkg_x,live.lkg_y,live.lkg_z) + live.void_vel*age
   if tt_valid_xyz(extrap.X,extrap.Y,extrap.Z) then candidates[#candidates+1]=extrap end
  end
 end


 local entry = tt_track[t_hrp]
 if entry and entry.void_hist then

  local sx,sy,sz,sc = 0,0,0,0
  for _,s in pairs(entry.void_hist) do if s then sx=sx+s.x; sy=sy+s.y; sz=sz+s.z; sc=sc+1 end end
  if sc > 0 and tt_valid_xyz(sx/sc,sy/sc,sz/sc) then candidates[#candidates+1]=Vector3.new(sx/sc,sy/sc,sz/sc) end
 end

 if entry and entry.hist then
  for k = entry.hi, 1, -1 do

   local h = entry.hist[k]
   if h and tt_valid_xyz(h.x,h.y,h.z) then candidates[#candidates+1]=Vector3.new(h.x,h.y,h.z); break end
  end
 end


 local raw = tt_raw_read_part(t_hrp)
 if raw then candidates[#candidates+1]=raw end
 if head then local raw2=tt_raw_read_part(head); if raw2 then candidates[#candidates+1]=raw2 end end
 for _,c in ipairs(candidates) do
  if tt_validate_vec3(c) then return c end
 end

 return nil
end

getgenv().start_teleport_to_target = function()
 if teleport_to_target_conn then teleport_to_target_conn:Disconnect() end
 if tt_render_conn then tt_render_conn:Disconnect() end
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetSnap") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetSample") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetMicro") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetVoidGuard") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetPhysicsGuard") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetUltraFast") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetVoidFastPath") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetVoidLock") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetPreFirst") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetPostLast") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetMidCamera") end)
 tt_track = {}; tt_live = {}
 tt_spawn_active = false; tt_micro_active = false
 tt_nuke_fallen_parts()

 local tt_last_target_check = 0
 local tt_cached_tgt = nil
 local tt_last_snap = 0

 local function tt_get_parts(target)
  local char = target.Character
  if not char then return nil,nil,nil end
  local t_hrp = char:FindFirstChild("HumanoidRootPart")
  if not t_hrp then return nil,nil,nil end
  local head = char:FindFirstChild("Head")
  local tor = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
  return t_hrp, head, tor
 end

 local function tt_do_sample_burst(t_hrp, head, tor, passes)
  for _ = 1, passes do
   pcall(tt_sample_part, t_hrp)
   if head then pcall(tt_sample_part, head) end
   if tor then pcall(tt_sample_part, tor) end
  end
 end

 local function tt_inject_raw(t_hrp, head)
  local raw = tt_raw_read_part(t_hrp)
  if raw then tt_record(t_hrp,raw.X,raw.Y,raw.Z,CFrame.new(raw),tick()) end
  if head then
   local rh = tt_raw_read_part(head)
   if rh then tt_record(head,rh.X,rh.Y,rh.Z,CFrame.new(rh),tick()) end
  end
 end

 local tt_orbit_angle = 0

 local function tt_snap_to(t_hrp, head, hrp, hum)
  local method = config.teleport_to_target_method or "Adaptive"
  local dest = tt_resolve_dest(head, t_hrp, method)
  if not dest or not tt_validate_vec3(dest) then dest = tt_resolve_void_pos_deep(t_hrp, head) end
  if not dest or not tt_validate_vec3(dest) then dest = tt_force_dest_resolve(t_hrp, head) end
  if not dest or not tt_validate_vec3(dest) then return end
  if config.teleport_to_target_orbit_mode then
   local orb_r = config.teleport_to_target_orbit_radius or 5
   local orb_spd = math.rad(config.teleport_to_target_orbit_speed or 90)
   tt_orbit_angle = (tt_orbit_angle + orb_spd * (1/60)) % (2 * math.pi)
   dest = Vector3.new(dest.X + math.cos(tt_orbit_angle) * orb_r, dest.Y, dest.Z + math.sin(tt_orbit_angle) * orb_r)
  end
  if config.teleport_to_target_auto_face then
   local my_pos = hrp.Position
   local face_cf = CFrame.new(my_pos, Vector3.new(dest.X, my_pos.Y, dest.Z))
   dest = face_cf.Position
  end
  tt_nuke_fallen_parts()
  local snaps = math.clamp(config.teleport_to_target_snap_count or 4, 1, 12)
  for _i = 1, snaps do pcall(tt_apply_teleport, hrp, dest, hum, t_hrp) end
  tt_nuke_fallen_parts()
 end

 local function tt_get_cached_target()
  local now = tick()
  local throttle = math.clamp(config.teleport_to_target_throttle or 0, 0, 500) / 1000
  if now - tt_last_target_check < math.max(throttle, 0.05) and tt_cached_tgt then
   if tt_target_valid(tt_cached_tgt) then return tt_cached_tgt end
  end
  tt_last_target_check = now
  tt_cached_tgt = get_teleport_target()
  return tt_cached_tgt
 end

 local function tt_get_state()
  local target = tt_get_cached_target()
  if not target or not target.Character then return nil,nil,nil,nil,nil,nil end
  local t_hrp, head, tor = tt_get_parts(target)
  if not t_hrp then return nil,nil,nil,nil,nil,nil end
  local live = tt_live[t_hrp]
  local in_void = live and live.is_void
  local is_chaos = live and (live.chaos_count or 0) >= TT_SPAMMER_CHAOS_THRESHOLD
  return t_hrp, head, tor, live, in_void or is_chaos, math.clamp(config.teleport_to_target_aggression or 3, 1, 5)
 end

 local function tt_get_player_parts()
  local hrp = getgenv().get_hrp(localplayer)
  if not hrp then return nil,nil end
  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  return hrp, hum
 end

 local function tt_set_hum_state(hum)
  if not hum then return end
  pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
  pcall(function() hum.PlatformStand = false end)
  pcall(function() hum.AutoRotate = false end)
 end

 pcall(function()
  run_service:BindToRenderStep("TeleportToTargetSample", Enum.RenderPriority.First.Value - 300, function()
   if not config.teleport_to_target_enabled then return end
   local t_hrp, head, tor, live, hard_case, aggression = tt_get_state()
   if not t_hrp then return end
   tt_do_sample_burst(t_hrp, head, tor, hard_case and (4 * aggression) or (2 * aggression))
   tt_inject_raw(t_hrp, head)
  end)
 end)

 pcall(function()
  run_service:BindToRenderStep("TeleportToTargetSnap", Enum.RenderPriority.Camera.Value + 2, function()
   if not config.teleport_to_target_enabled then return end
   local now = tick()
   local aggression = math.clamp(config.teleport_to_target_aggression or 3, 1, 5)
   local min_interval = 0.016 / aggression
   if now - tt_last_snap < min_interval then return end
   tt_last_snap = now
   local t_hrp, head, tor, live, hard_case = tt_get_state()
   if not t_hrp then return end
   tt_inject_raw(t_hrp, head)
   local hrp, hum = tt_get_player_parts()
   if not hrp then return end
   tt_set_hum_state(hum)
   tt_nuke_fallen_parts()
   local snap_reps = hard_case and math.min(aggression * 2, 6) or math.min(aggression, 3)
   for _r = 1, snap_reps do tt_snap_to(t_hrp, head, hrp, hum) end
   if hard_case and config.teleport_to_target_recover_void then
    local fallback = tt_force_dest_resolve(t_hrp, head)
    if fallback and tt_validate_vec3(fallback) then
     for _r = 1, math.min(snap_reps, 3) do tt_snap_to(t_hrp, head, hrp, hum) end
    end
   end
   tt_nuke_fallen_parts()
  end)
 end)

 teleport_to_target_conn = run_service.Heartbeat:Connect(function()
  if not config.teleport_to_target_enabled then return end
  local t_hrp, head, tor, live, hard_case, aggression = tt_get_state()
  if not t_hrp or not hard_case then return end
  tt_do_sample_burst(t_hrp, head, tor, 4 * aggression)
  tt_inject_raw(t_hrp, head)
  local hrp, hum = tt_get_player_parts()
  if not hrp then return end
  tt_set_hum_state(hum)
  tt_nuke_fallen_parts()
  local snap_reps = math.min(aggression * 2, 6)
  for _r = 1, snap_reps do tt_snap_to(t_hrp, head, hrp, hum) end
  if config.teleport_to_target_recover_void then
   local fallback = tt_force_dest_resolve(t_hrp, head)
   if fallback and tt_validate_vec3(fallback) then
    for _r = 1, math.min(snap_reps, 3) do tt_snap_to(t_hrp, head, hrp, hum) end
   end
  end
  tt_nuke_fallen_parts()
 end)
end
getgenv().stop_teleport_to_target = function()
 config.teleport_to_target_enabled = false
 tt_spawn_active = false; tt_micro_active = false
 if teleport_to_target_conn then teleport_to_target_conn:Disconnect(); teleport_to_target_conn = nil end
 if tt_render_conn then tt_render_conn:Disconnect(); tt_render_conn = nil end
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetSnap") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetSample") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetMicro") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetVoidGuard") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetPhysicsGuard") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetUltraFast") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetVoidFastPath") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetVoidLock") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetPreFirst") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetPostLast") end)
 pcall(function() run_service:UnbindFromRenderStep("TeleportToTargetMidCamera") end)
 tt_track = {}; tt_live = {}; tt_locked_target = nil

 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if hum then
  pcall(function() hum.AutoRotate = true end)
  pcall(function() hum.PlatformStand = false end)
  pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
  task.defer(function()
   local h2 = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
   if h2 then
    pcall(function() h2.AutoRotate = true end)
    pcall(function() h2.PlatformStand = false end)
    if h2:GetState() == Enum.HumanoidStateType.Physics then
     pcall(function() h2:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
   end
  end)
  task.delay(0.1, function()
   local h3 = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
   if h3 then
    pcall(function() h3.AutoRotate = true end)
    pcall(function() h3.PlatformStand = false end)
    if h3:GetState() == Enum.HumanoidStateType.Physics then
     pcall(function() h3:ChangeState(Enum.HumanoidStateType.Running) end)
    end
   end
  end)
 end
end


local afk_conn=nil

getgenv().start_anti_afk=function()
 if afk_conn then afk_conn:Disconnect() end
 afk_conn=localplayer.Idled:Connect(function()
 if config.anti_afk_enabled then virtual_user:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame) task.wait(1) virtual_user:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame) end end)
end


getgenv().stop_anti_afk=function() if afk_conn then afk_conn:Disconnect(); afk_conn=nil end end

local auto_conn,home_conn,safe_conn=nil,nil,nil

local last_auto_tick=0

getgenv().start_autocollect=function()
 if auto_conn then auto_conn:Disconnect() end
 auto_conn=run_service.Heartbeat:Connect(function()
 if not config.autocollect_enabled then return end

 local hrp=getgenv().get_hrp(localplayer); if not hrp then return end
 if tick()-last_auto_tick<0.25 then return end; last_auto_tick=tick()

 local best,min_d=nil,math.huge
 for _,o in ipairs(workspace:GetDescendants()) do

 local n=string.lower(o.Name)
 if o:IsA("BasePart") and (n:find("drop") or n:find("chest") or n:find("loot") or n:find("coin") or n:find("gem")) then

 local d=(hrp.Position-o.Position).Magnitude
 if d<min_d and d<(config.autocollect_radius or 120) then min_d=d; best=o end
 end
 end

 if best then hrp.CFrame=CFrame.new(best.Position) end end)
end


getgenv().stop_autocollect=function() if auto_conn then auto_conn:Disconnect(); auto_conn=nil end; config.autocollect_enabled=false end

getgenv().start_return_home=function()
 if home_conn then home_conn:Disconnect() end
 home_conn=run_service.Heartbeat:Connect(function()
 if not config.return_home_enabled then return end
 if not getgenv().home_position then return end

 local hrp=getgenv().get_hrp(localplayer); if not hrp then return end
 hrp.CFrame=CFrame.new(getgenv().home_position)
 hrp.AssemblyLinearVelocity=Vector3.zero; hrp.AssemblyAngularVelocity=Vector3.zero end)
end


getgenv().stop_return_home=function() if home_conn then home_conn:Disconnect(); home_conn=nil end; config.return_home_enabled=false end

getgenv().start_safe_zone=function()
 if safe_conn then safe_conn:Disconnect() end
 safe_conn=run_service.Heartbeat:Connect(function()
 if not config.safe_zone_enabled then return end

 local hrp=getgenv().get_hrp(localplayer); if not hrp then return end
 if hrp.Position.Y<(config.safe_zone_y or -10) then
 hrp.CFrame=CFrame.new(hrp.Position.X,math.abs(config.safe_zone_y or -10)+50,hrp.Position.Z)
 hrp.AssemblyLinearVelocity=Vector3.zero; hrp.AssemblyAngularVelocity=Vector3.zero
 end end)
end


getgenv().stop_safe_zone=function() if safe_conn then safe_conn:Disconnect(); safe_conn=nil end; config.safe_zone_enabled=false end

local tl_conn=nil

getgenv().start_teleport_loop=function()
 if tl_conn then tl_conn:Disconnect() end
 tl_conn=run_service.Heartbeat:Connect(function()
 if not config.teleport_loop_enabled then return end
 if #getgenv().loop_waypoints==0 then return end

 local idx=getgenv().loop_index; local wp=getgenv().loop_waypoints[idx]
 if wp then

 local hrp=getgenv().get_hrp(localplayer); if hrp then hrp.CFrame=CFrame.new(wp) end

 getgenv().loop_index=(idx%(#getgenv().loop_waypoints))+1
 end

 task.wait(config.teleport_loop_delay or 0.5) end)
end


getgenv().stop_teleport_loop=function() if tl_conn then tl_conn:Disconnect(); tl_conn=nil end; config.teleport_loop_enabled=false end

local rapid_fire_hook_orig = nil
local rapid_fire_hook_active = false

local rapid_fire_weapon_settings = {
 ShootRecoil = 0,
 ShootSpread = 0,
 ProjectileSpeed = math.huge,
 ShootCooldown = 0,
 QuickShotCooldown = 0,
 ShootBurstCooldown = 0,
 ShootExplosionRadius = 0,
 AttackCooldown = 0,
 Cooldown = 0,
 DashCooldown = 0,
 SpinCooldown = 0,
 SpinSpeed = 500,
 DeflectCooldown = 0,
}

getgenv().start_rapid_fire = function()
 if rapid_fire_hook_active then return end
 pcall(function()
  local ClientItem = require(localplayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem)
  local Input = ClientItem.Input
  rapid_fire_hook_orig = hookfunction(Input, newcclosure(function(...)
   local args = {...}
   if config.rapid_fire_enabled and type(args[1]) == "table" and args[1].Info then
    for k, v in pairs(rapid_fire_weapon_settings) do
     args[1].Info[k] = v
    end
   end
   return rapid_fire_hook_orig(...)
  end))
  rapid_fire_hook_active = true
 end)
end

getgenv().stop_rapid_fire = function()
 config.rapid_fire_enabled = false
end

local vs_conn, last_vs_pos = nil, nil

getgenv().start_void_spam = function()
 if vs_conn then return end
 vs_conn = run_service.Heartbeat:Connect(function(dt)
 if not config.void_spam_enabled then getgenv().stop_void_spam() return end

 local hrp = getgenv().get_hrp(localplayer)

 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if not hrp or not hum or hum.Health <= 0 then return end
 if hum:GetState() ~= Enum.HumanoidStateType.Physics then hum:ChangeState(Enum.HumanoidStateType.Physics) end

 local iters = math.clamp(config.et_total or 1000, 1, 500)
 do

 local stab_enabled = config.vs_stabilizer_enabled

 local stability = (config.vs_stability or 50) / 100

 local smooth_enabled = config.vs_smoothness_enabled

 local smooth_alpha = math.clamp((config.vs_smoothness or 10) / 100, 0.001, 1)

 local vs_min_d = math.clamp(config.vs_min_dist or 1, 1, 1e8)

 local vs_max_d = math.clamp(config.vs_max_dist or 50000, 1, 1e8)
 if vs_max_d < vs_min_d then vs_max_d = vs_min_d end

 local warp_speed = config.vs_warp_speed or 1

 local scatter_factor = config.vs_scatter_factor or 1

 local spiral_factor = config.vs_spiral_factor or 1

 local compression = config.vs_compression or 1

 local expansion_rate = config.vs_expansion_rate or 1

 local anchor_bias = config.vs_anchor_bias or 0

 local torque_factor = config.vs_torque_factor or 0

 getgenv().play_toggle_sound()

 local phase_offset = config.vs_sl1 or 0

 local flux_scale = (config.vs_sl2 or 10) / 10

 local resonance_amp = (config.vs_sl3 or 10) / 10

 local entropy_factor = (config.vs_sl4 or 0) / 100

 local blend_strength = (config.vs_sl5 or 10) / 100

 local drift_bias = config.vs_sl6 or 0

 local node_spacing = config.vs_sl7 or 10

 local arc_sweep = math.rad(config.vs_sl8 or 0)

 local gravity_warp = (config.vs_sl9 or 10) / 100

 local scatter_decay = (config.vs_sl10 or 0) / 100

 local vortex_pull = (config.vs_sl11 or 10) / 10

 local harmonic_freq = (config.vs_sl12 or 0) / 10

 local quantum_bias = (config.vs_sl13 or 10) / 100

 local layer_twist_ext = math.rad(config.vs_sl14 or 0)

 local echo_scale = (config.vs_sl15 or 10) / 10

 local resonance_drift = (config.vs_sl16 or 0) / 100

 local radial_warp = (config.vs_sl17 or 10) / 10

 local spiral_diverge = (config.vs_sl18 or 1) / 10

 local depth_scatter = (config.vs_sl19 or 0) / 100

 local temporal_blend = (config.vs_sl20 or 10) / 100

 local harmonic_bias_x = (config.vs_sl21 or 0) / 100

 local harmonic_bias_z = (config.vs_sl22 or 10) / 100

 local void_gate_pull = (config.vs_sl23 or 0) / 100

 local burst_gravity = (config.vs_sl24 or 1) / 10

 local node_repulsion = (config.vs_sl25 or 0) / 100

 local angular_warp = math.rad(config.vs_sl26 or 10)

 local flux_decay = (config.vs_sl27 or 0) / 100

 local scatter_twist = math.rad(config.vs_sl28 or 10)

 local axis_morph = (config.vs_sl29 or 0) / 100

 local resonance_scale = (config.vs_sl30 or 1) / 10

 local phase_drift = (config.vs_sl31 or 0) / 100

 local depth_warp = (config.vs_sl32 or 10) / 100

 local vortex_decay = (config.vs_sl33 or 0) / 100

 local burst_phase = math.rad(config.vs_sl34 or 10)

 local chaos_warp = (config.vs_sl35 or 0) / 100

 local temporal_drift = (config.vs_sl36 or 10) / 10

 local node_scale = (config.vs_sl37 or 0) / 100

 local radial_bias = (config.vs_sl38 or 1) / 10

 local scatter_phase = math.rad(config.vs_sl39 or 0)

 local entropy_warp = (config.vs_sl40 or 10) / 100

 local lock_phase = config.vs_tg1 or false

 local invert_drift = config.vs_tg2 or false

 local flux_sync = config.vs_tg3 or false

 local node_clamp = config.vs_tg4 or false

 local arc_mirror = config.vs_tg5 or false

 local gravity_snap = config.vs_tg6 or false

 local resonance_lock = config.vs_tg7 or false

 local entropy_seed_tog = config.vs_tg8 or false

 local blend_override = config.vs_tg9 or false

 local scatter_invert = config.vs_tg10 or false

 local harmonic_lock = config.vs_tg11 or false

 local vortex_sync = config.vs_tg12 or false

 local depth_invert = config.vs_tg13 or false

 local phase_mirror = config.vs_tg14 or false

 local radial_lock = config.vs_tg15 or false

 local spiral_lock = config.vs_tg16 or false

 local echo_invert = config.vs_tg17 or false

 local temporal_lock = config.vs_tg18 or false

 local burst_sync = config.vs_tg19 or false

 local axis_flip = config.vs_tg20 or false

 local void_gate_lock = config.vs_tg21 or false

 local entropy_flip = config.vs_tg22 or false

 local chaos_lock = config.vs_tg23 or false

 local resonance_flip = config.vs_tg24 or false

 local drift_lock = config.vs_tg25 or false

 local node_mirror = config.vs_tg26 or false

 local warp_invert = config.vs_tg27 or false

 local temporal_flip = config.vs_tg28 or false

 local flux_lock = config.vs_tg29 or false

 local radial_flip = config.vs_tg30 or false

 local scatter_lock = config.vs_tg31 or false

 local depth_lock = config.vs_tg32 or false

 local burst_invert = config.vs_tg33 or false

 local harmonic_flip = config.vs_tg34 or false

 local phase_lock = config.vs_tg35 or false

 local vortex_flip = config.vs_tg36 or false

 local angular_lock = config.vs_tg37 or false

 local echo_lock = config.vs_tg38 or false

 local chaos_flip = config.vs_tg39 or false

 local node_lock = config.vs_tg40 or false

 local vs_dr1 = config.vs_dr1 or "Scatter"

 local vs_dr2 = config.vs_dr2 or "Random"

 local vs_dr3 = config.vs_dr3 or "None"

 local vs_dr4 = config.vs_dr4 or "Linear"

 local vs_dr5 = config.vs_dr5 or "Off"

 local vs_dr6 = config.vs_dr6 or "Uniform"

 local vs_dr7 = config.vs_dr7 or "Replace"

 local vs_dr8 = config.vs_dr8 or "Adaptive"

 local vs_dr9 = config.vs_dr9 or "Instant"

 local vs_dr10 = config.vs_dr10 or "None"

 local warp_mult = config.vs_warp_multiplier or 1

 local scatter_radius = math.clamp(config.vs_scatter_radius or 500000, 1, 1e8)

 local depth_mult = config.vs_depth_mult or 1

 local rebound_strength = config.vs_rebound_strength or 0

 local axis_spin = math.rad(config.vs_axis_spin or 0)

 local freq_mod = config.vs_frequency_mod or 1

 local pos_noise = config.vs_position_noise or 0

 local burst_gap = config.vs_burst_gap or 0

 local entropy_mod = config.vs_entropy_mod or 0

 local gravity_strength = config.vs_gravity_strength or 0

 local blend_preset = vs_dr1

 local distribution = vs_dr2

 local axis_override = vs_dr3

 local motion_pattern = vs_dr4

 local damping_mode = vs_dr5

 local direction_bias = vs_dr6

 local merge_mode = vs_dr7

 local resolve_mode = vs_dr8

 local warp_preset = vs_dr9

 local chaos_profile = vs_dr10

 local chaos_intensity_map = {["None"]=0,["Low"]=0.1,["Medium"]=0.3,["High"]=0.6,["Extreme"]=1.0,["Fractal"]=1.5}

 local chaos_mult = chaos_intensity_map[chaos_profile] or 0

 local damping_map = {["Off"]=1,["Low"]=0.85,["Medium"]=0.6,["High"]=0.35,["Extreme"]=0.1}

 local damping_factor = damping_map[damping_mode] or 1

 local resolved_origin = hrp.CFrame
 if config.vs_pos_resolver then
 pcall(function()
 hrp.CFrame = hrp.CFrame
 resolved_origin = hrp.CFrame end)
 end


 local restore_pos = resolved_origin

 local char_origin_pos = resolved_origin.Position
 if config.vs_char_origin then

  local char = localplayer.Character
  if char then

   local char_hrp = char:FindFirstChild("HumanoidRootPart")
   if char_hrp then char_origin_pos = char_hrp.Position end
  end
 end


 local vs_move_mode = config.vs_movement or "Random"

 local vs_orbit_t = tick()

 local vs_dir_mode = config.vs_void_direction or "Random"

 local vs_cam = workspace.CurrentCamera

 local function vs_apply_distribution(rx, ry, rz)
  if distribution == "Uniform" then

   local mag = math.sqrt(rx*rx + ry*ry + rz*rz)
   if mag > 0 then local s = vs_max_d / mag; rx = rx*s; ry = ry*s; rz = rz*s end
  elseif distribution == "Weighted" then

   local w = math.clamp(blend_strength, 0.01, 1)
   rx = rx * w; ry = ry * w; rz = rz * w
  elseif distribution == "Radial" then

   local theta = math.atan2(rz, rx)
   rx = math.cos(theta) * vs_max_d; rz = math.sin(theta) * vs_max_d
  elseif distribution == "Inverse" then

   local mag = math.sqrt(rx*rx + ry*ry + rz*rz)
   if mag > 0 then local inv = vs_min_d * vs_max_d / mag; rx = rx*inv/mag; ry = ry*inv/mag; rz = rz*inv/mag end
  end

  return rx, ry, rz
 end


 local function vs_apply_axis_override(rx, ry, rz)
  if axis_override == "X" then ry = 0; rz = 0
  elseif axis_override == "Y" then rx = 0; rz = 0
  elseif axis_override == "Z" then rx = 0; ry = 0
  elseif axis_override == "XY" then rz = 0
  elseif axis_override == "XZ" then ry = 0
  elseif axis_override == "YZ" then rx = 0
  end

  return rx, ry, rz
 end


 local function vs_apply_motion_pattern(rx, ry, rz, frac)

  local a = frac * math.pi * 2 * freq_mod + math.rad(phase_offset)
  if motion_pattern == "Spiral" then

   local r = math.sqrt(rx*rx + rz*rz)
   rx = math.cos(a * spiral_factor) * r
   rz = math.sin(a * spiral_factor) * r
  elseif motion_pattern == "Grid" then
   rx = math.floor(rx / node_spacing) * node_spacing
   ry = math.floor(ry / node_spacing) * node_spacing
   rz = math.floor(rz / node_spacing) * node_spacing
  elseif motion_pattern == "Ring" then

   local theta = math.atan2(rz, rx)
   rx = math.cos(theta + arc_sweep) * vs_max_d
   rz = math.sin(theta + arc_sweep) * vs_max_d
  elseif motion_pattern == "Cluster" then

   local cluster_angle = math.floor(frac * 8) * (math.pi * 0.25)

   local r = vs_min_d + math.random() * (vs_max_d - vs_min_d)
   rx = math.cos(cluster_angle) * r
   rz = math.sin(cluster_angle) * r
  elseif motion_pattern == "Helix" then

   local r = vs_min_d + math.random() * (vs_max_d - vs_min_d)
   rx = math.cos(a) * r
   ry = ry + frac * vs_max_d * 0.5
   rz = math.sin(a) * r
  end

  return rx, ry, rz
 end


 local function vs_apply_warp_preset(from_cf, to_pos)

  local target = CFrame.new(to_pos)

  local ws = math.clamp(warp_speed * warp_mult, 0.01, 10)
  if warp_preset == "Lerp" then return from_cf:Lerp(target, math.clamp(ws * 0.1, 0.001, 1))
  elseif warp_preset == "Spring" then return from_cf:Lerp(target, math.clamp(ws * 0.15, 0.001, 1))
  elseif warp_preset == "Bounce" then

   local t = math.clamp(ws * 0.1, 0.001, 1)

   local bounce = math.abs(math.sin(t * math.pi * 3)) * (1-t)
   return from_cf:Lerp(target, math.clamp(t + bounce * 0.2, 0.001, 1))
  elseif warp_preset == "Elastic" then

   local t = math.clamp(ws * 0.1, 0.001, 1)

   local elastic = math.sin(t * math.pi * 4.5) * math.exp(-t * 3)
   return from_cf:Lerp(target, math.clamp(t + elastic * 0.15, 0.001, 1))
  else return target end
 end


 local function vs_get_dir_offset(base_pos, dist)
  if vs_dir_mode == "Forward" then

   local look = vs_cam and Vector3.new(vs_cam.CFrame.LookVector.X, 0, vs_cam.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
   if look.Magnitude > 0.001 then look = look.Unit else look = Vector3.new(0, 0, -1) end
   return Vector3.new(look.X * dist, (math.random() < 0.5 and 1 or -1) * dist, look.Z * dist)
  elseif vs_dir_mode == "Backward" then

   local look = vs_cam and Vector3.new(-vs_cam.CFrame.LookVector.X, 0, -vs_cam.CFrame.LookVector.Z) or Vector3.new(0, 0, 1)
   if look.Magnitude > 0.001 then look = look.Unit else look = Vector3.new(0, 0, 1) end
   return Vector3.new(look.X * dist, (math.random() < 0.5 and 1 or -1) * dist, look.Z * dist)
  elseif vs_dir_mode == "Left" then

   local right = vs_cam and vs_cam.CFrame.RightVector or Vector3.new(1, 0, 0)

   local left = Vector3.new(-right.X, 0, -right.Z)
   if left.Magnitude > 0.001 then left = left.Unit else left = Vector3.new(-1, 0, 0) end
   return Vector3.new(left.X * dist, (math.random() < 0.5 and 1 or -1) * dist, left.Z * dist)
  elseif vs_dir_mode == "Right" then

   local right = vs_cam and Vector3.new(vs_cam.CFrame.RightVector.X, 0, vs_cam.CFrame.RightVector.Z) or Vector3.new(1, 0, 0)
   if right.Magnitude > 0.001 then right = right.Unit else right = Vector3.new(1, 0, 0) end
   return Vector3.new(right.X * dist, (math.random() < 0.5 and 1 or -1) * dist, right.Z * dist)
  elseif vs_dir_mode == "Up" then
   return Vector3.new((math.random() - 0.5) * dist * 0.2, dist, (math.random() - 0.5) * dist * 0.2)
  elseif vs_dir_mode == "Down" then
   return Vector3.new((math.random() - 0.5) * dist * 0.2, -dist, (math.random() - 0.5) * dist * 0.2)
  elseif vs_dir_mode == "Camera" then

   local look = vs_cam and vs_cam.CFrame.LookVector or Vector3.new(0, 0, -1)
   return look * dist
  elseif vs_dir_mode == "Directional" then

   local xp = math.clamp(config.vs_dir_xp or 5000, 0, 1e8)

   local xn = math.clamp(config.vs_dir_xn or 5000, 0, 1e8)

   local yp = math.clamp(config.vs_dir_yp or 5000, 0, 1e8)

   local yn = math.clamp(config.vs_dir_yn or 5000, 0, 1e8)

   local zp = math.clamp(config.vs_dir_zp or 5000, 0, 1e8)

   local zn = math.clamp(config.vs_dir_zn or 5000, 0, 1e8)

   local rx = (math.random() < 0.5) and (math.random() * xp) or (-math.random() * xn)

   local ry = (math.random() < 0.5) and (math.random() * yp) or (-math.random() * yn)

   local rz = (math.random() < 0.5) and (math.random() * zp) or (-math.random() * zn)
   return Vector3.new(rx, ry, rz)
  else

   local sx = (math.random() < 0.5) and 1 or -1

   local sy = (math.random() < 0.5) and 1 or -1

   local sz = (math.random() < 0.5) and 1 or -1

   local d = vs_min_d + math.random() * (vs_max_d - vs_min_d)
   return Vector3.new(sx * d, sy * d, sz * d)
  end
 end


 local function vs_build_random_offset(frac)

  local d = vs_min_d + math.random() * (vs_max_d - vs_min_d)

  local rx, ry, rz
  if vs_move_mode == "Orbit" then

   local a = vs_orbit_t * 2 + frac * math.pi * 2
   rx = math.cos(a) * d
   ry = (math.random() < 0.5 and 1 or -1) * d
   rz = math.sin(a) * d
  elseif vs_move_mode == "Helix" then

   local a = frac * math.pi * 4 * freq_mod + vs_orbit_t
   rx = math.cos(a) * d
   ry = (frac - 0.5) * d * 2 * depth_mult
   rz = math.sin(a) * d
  elseif vs_move_mode == "Wave" then

   local a = frac * math.pi * 2 * freq_mod + vs_orbit_t
   rx = math.sin(a) * d
   ry = (math.random() < 0.5 and 1 or -1) * d
   rz = math.cos(a * 0.7) * d
  elseif vs_move_mode == "Chaos" then
   rx = (math.random() * 2 - 1) * d
   ry = (math.random() * 2 - 1) * d
   rz = (math.random() * 2 - 1) * d
  elseif vs_move_mode == "Pulse" then

   local pulse = math.abs(math.sin(frac * math.pi * 4 * freq_mod + vs_orbit_t))

   local r = d * pulse

   local sx2 = (math.random() < 0.5) and 1 or -1

   local sy2 = (math.random() < 0.5) and 1 or -1

   local sz2 = (math.random() < 0.5) and 1 or -1
   rx = sx2 * r; ry = sy2 * r; rz = sz2 * r
  else

   local sx = (math.random() < 0.5) and 1 or -1

   local sy = (math.random() < 0.5) and 1 or -1

   local sz = (math.random() < 0.5) and 1 or -1
   rx = sx * d; ry = sy * d; rz = sz * d
  end

  if chaos_mult > 0 then
   rx = rx + (math.random()-0.5)*d*chaos_mult
   ry = ry + (math.random()-0.5)*d*chaos_mult
   rz = rz + (math.random()-0.5)*d*chaos_mult
  end

  if pos_noise > 0 then

   local t_now = tick()
   rx = rx + math.noise(t_now*3.1, 0, 0) * pos_noise
   ry = ry + math.noise(0, t_now*2.7, 0) * pos_noise
   rz = rz + math.noise(0, 0, t_now*4.3) * pos_noise
  end

  rx, ry, rz = vs_apply_distribution(rx, ry, rz)
  rx, ry, rz = vs_apply_axis_override(rx, ry, rz)
  rx, ry, rz = vs_apply_motion_pattern(rx, ry, rz, frac)
  if gravity_strength > 0 then ry = ry - gravity_strength * d * 0.01 end
  if gravity_snap then ry = -(math.abs(ry) + gravity_warp * d) end
  if scatter_invert then rx = -rx; rz = -rz end
  if arc_mirror then rx = math.abs(rx) * (math.random() < 0.5 and 1 or -1) end
  if rebound_strength > 0 then
   rx = rx * (1 + rebound_strength * 0.01 * (math.random()-0.5))
   rz = rz * (1 + rebound_strength * 0.01 * (math.random()-0.5))
  end

  if axis_spin ~= 0 then

   local cos_s = math.cos(axis_spin)

   local sin_s = math.sin(axis_spin)

   local new_rx = rx * cos_s - rz * sin_s

   local new_rz = rx * sin_s + rz * cos_s
   rx = new_rx; rz = new_rz
  end

  if drift_bias ~= 0 then
   if invert_drift then rx = rx - drift_bias * d * 0.001; rz = rz - drift_bias * d * 0.001
   else rx = rx + drift_bias * d * 0.001; rz = rz + drift_bias * d * 0.001 end
  end

  rx = rx * scatter_factor * compression * expansion_rate * flux_scale
  ry = ry * depth_mult * resonance_amp
  rz = rz * scatter_factor * compression * expansion_rate * flux_scale

  local turbulence_freq = config.vs_turbulence_freq or 1

 local turbulence_amp2 = config.vs_turbulence_amp or 1
 if turbulence_amp2 > 0 then

  local tn = tick()
  rx = rx + math.noise(tn * turbulence_freq, 0, 0) * d * turbulence_amp2 * 0.1
  ry = ry + math.noise(0, tn * turbulence_freq, 0) * d * turbulence_amp2 * 0.1
  rz = rz + math.noise(0, 0, tn * turbulence_freq) * d * turbulence_amp2 * 0.1
 end


 local vortex_strength = config.vs_vortex_strength or 0

 local vortex_radius = math.max(config.vs_vortex_radius or 10000, 1)
 if vortex_strength > 0 then

  local vangle = math.atan2(rz, rx) + math.rad(vortex_strength * 0.01 * d / vortex_radius)

  local vmag = math.sqrt(rx * rx + rz * rz)
  rx = math.cos(vangle) * vmag
  rz = math.sin(vangle) * vmag
 end


 local layer_twist = math.rad(config.vs_layer_twist or 0)
 if layer_twist ~= 0 then

  local cos_t = math.cos(layer_twist)

  local sin_t = math.sin(layer_twist)

  local new_rx2 = rx * cos_t - rz * sin_t

  local new_rz2 = rx * sin_t + rz * cos_t
  rx = new_rx2; rz = new_rz2
 end


 local quantum_jump_prob = math.clamp(config.vs_quantum_jump_prob or 0, 0, 100)

 local quantum_jump_scale = config.vs_quantum_jump_scale or 1
 if quantum_jump_prob > 0 and math.random(0, 100) < quantum_jump_prob then
  rx = rx * quantum_jump_scale * (math.random() * 10 + 1)
  ry = ry * quantum_jump_scale * (math.random() * 10 + 1)
  rz = rz * quantum_jump_scale * (math.random() * 10 + 1)
 end


 local fractal_depth = math.clamp(config.vs_fractal_depth or 1, 1, 6)

 local fractal_scale = config.vs_fractal_scale or 1
 if fractal_depth > 1 then
  for fi = 2, fractal_depth do

   local fs = fractal_scale * (0.5 ^ (fi - 1))
   rx = rx + math.sin(ry * 0.001 * fi) * d * fs
   rz = rz + math.cos(rx * 0.001 * fi) * d * fs
  end
 end


 local echo_trail = math.clamp(config.vs_echo_trail or 0, 0, 20)

 local echo_decay_rate = config.vs_echo_decay_rate or 0.5
 if echo_trail > 0 then

  local base_mag = math.sqrt(rx * rx + ry * ry + rz * rz)
  for ei = 1, echo_trail do

   local ef = echo_decay_rate ^ ei
   rx = rx + (math.random() - 0.5) * base_mag * ef * 0.1
   rz = rz + (math.random() - 0.5) * base_mag * ef * 0.1
  end
 end


 local gvx = config.vs_gravity_vector_x or 0

 local gvy = config.vs_gravity_vector_y or -1

 local gvz = config.vs_gravity_vector_z or 0

 local gv_mag = math.sqrt(gvx * gvx + gvy * gvy + gvz * gvz)
 if gv_mag > 0.001 and gravity_strength > 0 then
  rx = rx + gvx / gv_mag * gravity_strength * d * 0.01
  ry = ry + gvy / gv_mag * gravity_strength * d * 0.01
  rz = rz + gvz / gv_mag * gravity_strength * d * 0.01
 end


 local depth_pulse_freq = config.vs_depth_pulse_freq or 1

 local depth_pulse_amp = config.vs_depth_pulse_amp or 0
 if depth_pulse_amp > 0 then
  ry = ry + math.sin(tick() * depth_pulse_freq * math.pi * 2) * depth_pulse_amp
 end


 local spiral_offset_x = config.vs_spiral_offset_x or 0

 local spiral_offset_z = config.vs_spiral_offset_z or 0
 rx = rx + spiral_offset_x
 rz = rz + spiral_offset_z

 local axis_wobble = math.rad(config.vs_axis_wobble or 0)
 if axis_wobble ~= 0 then

  local wt = tick()

  local wobble_cf = CFrame.Angles(math.sin(wt * 2) * axis_wobble, math.cos(wt * 1.3) * axis_wobble, math.sin(wt * 3.7) * axis_wobble)

  local wv = wobble_cf * Vector3.new(rx, ry, rz)
  rx = wv.X; ry = wv.Y; rz = wv.Z
 end

 if config.vs_flux_reversal and (math.floor(tick() * (freq_mod or 1)) % 2 == 1) then
  rx = -rx; rz = -rz
 end

 if config.vs_chaos_feedback and last_vs_pos then

  local fbx = (hrp.Position.X - last_vs_pos.X) * 0.01

  local fbz = (hrp.Position.Z - last_vs_pos.Z) * 0.01
  rx = rx + fbx * d * 0.1
  rz = rz + fbz * d * 0.1
 end

 if entropy_seed_tog then

   local seed_h = (math.floor(rx + ry + rz + vs_orbit_t * 100)) % 999
   math.randomseed(seed_h)
  end

  if node_clamp and scatter_radius > 0 then

   local mag = math.sqrt(rx*rx + ry*ry + rz*rz)
   if mag > scatter_radius then

    local sc = scatter_radius / mag
    rx = rx*sc; ry = ry*sc; rz = rz*sc
   end
  end

  if resonance_lock then
   rx = math.floor(rx / resonance_amp) * resonance_amp
   rz = math.floor(rz / resonance_amp) * resonance_amp
  end

  if flux_sync then rx = rx * math.abs(math.sin(vs_orbit_t * freq_mod)) end
  ry = ry + anchor_bias * 100
  if lock_phase then ry = -(math.abs(ry)) end

  local t_ext = tick()

  local mag_ext = math.sqrt(rx*rx + ry*ry + rz*rz)
  if mag_ext < 1 then mag_ext = 1 end
  if vortex_pull > 0 then

   local va = math.atan2(rz, rx) + vortex_pull * 0.1

   local vm = math.sqrt(rx*rx + rz*rz)
   rx = math.cos(va) * vm; rz = math.sin(va) * vm
  end

  if harmonic_freq > 0 then
   rx = rx + math.sin(t_ext * harmonic_freq * math.pi * 2) * mag_ext * harmonic_bias_x
   rz = rz + math.cos(t_ext * harmonic_freq * math.pi * 2) * mag_ext * harmonic_bias_z
  end

  if radial_warp ~= 1 then

   local rfac = radial_warp
   rx = rx * rfac; rz = rz * rfac
  end

  if spiral_diverge > 0 then

   local sda = math.atan2(rz, rx) + spiral_diverge * math.pi

   local sdm = math.sqrt(rx*rx + rz*rz) * (1 + spiral_diverge * 0.1)
   rx = math.cos(sda) * sdm; rz = math.sin(sda) * sdm
  end

  if depth_scatter > 0 then
   ry = ry + (math.random()-0.5) * mag_ext * depth_scatter * 2
  end

  if temporal_blend > 0 and last_vs_pos then
   rx = rx * (1 - temporal_blend) + (hrp.Position.X - (last_vs_pos and last_vs_pos.X or hrp.Position.X)) * temporal_blend
   rz = rz * (1 - temporal_blend) + (hrp.Position.Z - (last_vs_pos and last_vs_pos.Z or hrp.Position.Z)) * temporal_blend
  end

  if void_gate_pull > 0 then
   ry = ry - mag_ext * void_gate_pull
  end

  if burst_gravity > 0 then
   ry = ry - mag_ext * burst_gravity * 0.01
  end

  if node_repulsion > 0 then
   rx = rx + math.sin(t_ext * 7.3 + rx * 0.001) * mag_ext * node_repulsion
   rz = rz + math.cos(t_ext * 5.1 + rz * 0.001) * mag_ext * node_repulsion
  end

  if angular_warp ~= 0 then

   local aw_cos = math.cos(angular_warp)

   local aw_sin = math.sin(angular_warp)

   local aw_rx = rx * aw_cos - rz * aw_sin

   local aw_rz = rx * aw_sin + rz * aw_cos
   rx = aw_rx; rz = aw_rz
  end

  if flux_decay > 0 then
   rx = rx * (1 - flux_decay * (1 - math.exp(-t_ext * 0.1)))
   rz = rz * (1 - flux_decay * (1 - math.exp(-t_ext * 0.1)))
  end

  if scatter_twist ~= 0 then

   local st_cos = math.cos(scatter_twist)

   local st_sin = math.sin(scatter_twist)

   local st_rx = rx * st_cos - ry * st_sin

   local st_ry = rx * st_sin + ry * st_cos
   rx = st_rx; ry = st_ry
  end

  if axis_morph > 0 then

   local lerp_y = ry * (1 - axis_morph) + math.sin(t_ext * 3.7) * mag_ext * axis_morph
   ry = lerp_y
  end

  if resonance_scale ~= 0 then

   local rsx = resonance_scale
   rx = rx * rsx; ry = ry * rsx; rz = rz * rsx
  end

  if phase_drift > 0 then
   rx = rx + math.sin(t_ext * freq_mod + scatter_phase) * mag_ext * phase_drift
   rz = rz + math.cos(t_ext * freq_mod + scatter_phase) * mag_ext * phase_drift
  end

  if depth_warp > 0 then
   ry = ry + math.sin(t_ext * 2.3) * mag_ext * depth_warp
  end

  if vortex_decay > 0 then

   local vda = math.atan2(rz, rx)

   local vdm = math.sqrt(rx*rx + rz*rz) * (1 - vortex_decay * 0.01)
   rx = math.cos(vda) * vdm; rz = math.sin(vda) * vdm
  end

  if chaos_warp > 0 then
   rx = rx + (math.random()-0.5) * mag_ext * chaos_warp
   ry = ry + (math.random()-0.5) * mag_ext * chaos_warp * 0.5
   rz = rz + (math.random()-0.5) * mag_ext * chaos_warp
  end

  if temporal_drift ~= 1 then

   local td_s = math.sin(t_ext * temporal_drift * 0.5)
   rx = rx * (1 + td_s * 0.1); rz = rz * (1 + td_s * 0.1)
  end

  if node_scale > 0 then
   rx = rx + math.noise(rx * 0.001, t_ext, 0) * mag_ext * node_scale
   rz = rz + math.noise(0, t_ext, rz * 0.001) * mag_ext * node_scale
  end

  if radial_bias ~= 1 then

   local rb_mag = math.sqrt(rx*rx + rz*rz)
   if rb_mag > 0 then

    local rb_target = rb_mag * radial_bias
    rx = (rx / rb_mag) * rb_target; rz = (rz / rb_mag) * rb_target
   end
  end

  if burst_phase ~= 0 then

   local bp_cos = math.cos(burst_phase)

   local bp_sin = math.sin(burst_phase)

   local bp_rx = rx * bp_cos - rz * bp_sin

   local bp_rz = rx * bp_sin + rz * bp_cos
   rx = bp_rx; rz = bp_rz
  end

  if entropy_warp > 0 then

   local ew_t = t_ext * entropy_factor * 10 + 1
   rx = rx + math.noise(ew_t, 0, 0) * mag_ext * entropy_warp
   rz = rz + math.noise(0, ew_t, 0) * mag_ext * entropy_warp
  end

  if harmonic_lock then rx = math.abs(rx) * (rx < 0 and -1 or 1) end
  if vortex_sync then

   local vsa = math.atan2(rz, rx) + t_ext * 0.1

   local vsm = math.sqrt(rx*rx + rz*rz)
   rx = math.cos(vsa) * vsm; rz = math.sin(vsa) * vsm
  end

  if depth_invert then ry = -ry end
  if phase_mirror then rx = -rx end
  if radial_lock then

   local rl_m = math.sqrt(rx*rx + rz*rz)
   if rl_m > 0 then rx = (rx/rl_m) * vs_max_d; rz = (rz/rl_m) * vs_max_d end
  end

  if spiral_lock then

   local sla = math.atan2(rz, rx)
   rx = math.cos(sla) * vs_max_d; rz = math.sin(sla) * vs_max_d
  end

  if echo_invert then rx = -rx; rz = -rz end
  if temporal_lock then ry = ry * math.abs(math.sin(t_ext)) end
  if burst_sync then

   local bs_phase = math.floor(t_ext * 10) * 0.1
   rx = rx * (1 + math.sin(bs_phase) * 0.2)
   rz = rz * (1 + math.cos(bs_phase) * 0.2)
  end

  if axis_flip then rx = rz; rz = rx end
  if void_gate_lock then ry = -math.abs(ry) - vs_max_d * void_gate_pull end
  if entropy_flip then ry = ry * (math.random() < 0.5 and 1 or -1) end
  if chaos_lock then

   local cl_mag = math.max(math.sqrt(rx*rx + ry*ry + rz*rz), 1)
   rx = rx / cl_mag * vs_max_d; ry = ry / cl_mag * vs_max_d; rz = rz / cl_mag * vs_max_d
  end

  if resonance_flip then rx = math.sin(rx * 0.001) * vs_max_d end
  if drift_lock then rx = rx + drift_bias * 10; rz = rz + drift_bias * 10 end
  if node_mirror then rx = math.abs(rx); rz = math.abs(rz) end
  if warp_invert then rx = -rx; ry = -ry; rz = -rz end
  if temporal_flip then ry = math.sin(t_ext * 3.14) * vs_max_d end
  if flux_lock then rx = rx * math.sin(t_ext * freq_mod); rz = rz * math.cos(t_ext * freq_mod) end
  if radial_flip then rx = rz; rz = -rx end
  if scatter_lock then

   local sl_a = math.atan2(rz, rx) + scatter_phase

   local sl_m = math.sqrt(rx*rx + rz*rz)
   rx = math.cos(sl_a) * sl_m; rz = math.sin(sl_a) * sl_m
  end

  if depth_lock then ry = -vs_max_d * depth_scatter end
  if burst_invert then rx = -rx; rz = -rz end
  if harmonic_flip then rx = math.cos(rx * 0.001 + harmonic_freq) * vs_max_d end
  if phase_lock then ry = -(math.abs(ry)) end
  if vortex_flip then rz = -rz end
  if angular_lock then

   local al_a = math.atan2(rz, rx)

   local al_m = math.sqrt(rx*rx + rz*rz)
   rx = math.cos(al_a + angular_warp) * al_m; rz = math.sin(al_a + angular_warp) * al_m
  end

  if echo_lock then
   rx = rx + math.sin(t_ext * 13.7) * mag_ext * (echo_scale - 1)
   rz = rz + math.cos(t_ext * 11.3) * mag_ext * (echo_scale - 1)
  end

  if chaos_flip then ry = (math.random() < 0.5) and ry or -ry end
  if node_lock then
   rx = math.floor(rx / math.max(node_spacing, 1)) * node_spacing
   rz = math.floor(rz / math.max(node_spacing, 1)) * node_spacing
  end

  return rx, ry, rz
 end


 local base_for_iter = config.vs_char_origin and char_origin_pos or nil
 if vs_dir_mode ~= "Random" then
  for i = 1, iters do

   local base = (base_for_iter and base_for_iter) or last_vs_pos or hrp.Position

   local dist = vs_min_d + math.random() * (vs_max_d - vs_min_d)

   local offset = vs_get_dir_offset(base, dist)

   local target_pos = (config.vs_char_origin and char_origin_pos or base) + offset
   if vs_pos_clamp_enabled and config.vs_pos_clamp_radius and config.vs_pos_clamp_radius > 0 then

    local delta = target_pos - (base_for_iter or hrp.Position)
    if delta.Magnitude > config.vs_pos_clamp_radius then
     target_pos = (base_for_iter or hrp.Position) + delta.Unit * config.vs_pos_clamp_radius
    end
   end


   local target_cf = vs_apply_warp_preset(hrp.CFrame, target_pos)
   hrp.CFrame = target_cf
   if not config.vs_char_origin then last_vs_pos = hrp.Position end
   if burst_gap > 0 and i % math.max(math.floor(iters / 10), 1) == 0 then task.wait(burst_gap * 0.0001) end
  end
 else
  for i = 1, iters do

   local base = (config.vs_char_origin and char_origin_pos) or last_vs_pos or hrp.Position

   local frac = (i - 1) / iters

   local rx, ry, rz = vs_build_random_offset(frac)

   local target_pos = Vector3.new(base.X + rx, base.Y + ry, base.Z + rz)
   if config.vs_pos_clamp and config.vs_pos_clamp_radius and config.vs_pos_clamp_radius > 0 then

    local origin_ref = config.vs_char_origin and char_origin_pos or hrp.Position

    local delta = target_pos - origin_ref
    if delta.Magnitude > config.vs_pos_clamp_radius then
     target_pos = origin_ref + delta.Unit * config.vs_pos_clamp_radius
    end
   end


   local target_cf = vs_apply_warp_preset(hrp.CFrame, target_pos)
   if merge_mode == "Add" then
    target_cf = hrp.CFrame + (target_cf.Position - hrp.Position)
   elseif merge_mode == "Lerp" then
    target_cf = hrp.CFrame:Lerp(target_cf, blend_strength)
   end

   hrp.CFrame = target_cf
   if not config.vs_char_origin then last_vs_pos = hrp.Position end
   if burst_gap > 0 and i % math.max(math.floor(iters / 10), 1) == 0 then task.wait(burst_gap * 0.0001) end
  end
 end

 if stab_enabled then

 local damp = (1 - stability) * damping_factor
 hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * damp
 hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * damp
 else
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 end

 if config.vs_pos_restore then
 pcall(function() hrp.CFrame = restore_pos end)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 if not config.vs_char_origin then last_vs_pos = restore_pos.Position end
 end
 end end)
end


local vs_pos_clamp_enabled = false

getgenv().stop_void_spam = function() if vs_conn then vs_conn:Disconnect(); vs_conn = nil end; config.void_spam_enabled = false; last_vs_pos = nil end

local evs_conn = nil

local evs_tick_acc = 0

local evs_phase = 0

local vs_spiral = 0

local vs_wave = 0

local vs_helix = 0

local vs_orbit_angle = 0

local vs_phase_hex = 0

local vs_phase_oct = 0

local vs_phase_star = 0

local vs_phase_cross = 0

local vs_phase_rhombus = 0

local function evs_get_direction_vec()

 local d = config.evs_axis or "Y"
 if d == "X" then return Vector3.new(1,0,0)
 elseif d == "Z" then return Vector3.new(0,0,1)
 elseif d == "XZ" then return Vector3.new(1,0,1).Unit
 elseif d == "XY" then return Vector3.new(1,1,0).Unit
 elseif d == "YZ" then return Vector3.new(0,1,1).Unit
 else return Vector3.new(0,1,0) end
end


local function evs_apply_falloff(dist, i, total)

 local mode = config.evs_falloff or "None"
 if mode == "Linear" then return dist * (1 - (i-1)/total)
 elseif mode == "Exp" then return dist * math.exp(-3*(i-1)/total)
 elseif mode == "Sine" then return dist * math.abs(math.sin((i-1)/total * math.pi))
 else return dist end
end


local function evs_compute_offset(i, total, base_dist, jitter, phase, freq, amp, spread)

 local pattern = config.evs_pattern or "Linear"

 local frac = (i-1)/total

 local j = jitter > 0 and Vector3.new((math.random()-0.5)*jitter,(math.random()-0.5)*jitter,(math.random()-0.5)*jitter) or Vector3.zero

 local dir = evs_get_direction_vec()

 local d = evs_apply_falloff(base_dist, i, total) * amp
 if pattern == "Linear" then
 return dir * d + j
 elseif pattern == "Spiral" then

 local a = frac * math.pi * 2 * freq + phase

 local r = d * config.evs_orbit_radius / 50000
 return Vector3.new(math.cos(a)*r, -d, math.sin(a)*r) + j
 elseif pattern == "Wave" then

 local a = frac * math.pi * 2 * freq + phase
 return dir * d * amp + Vector3.new(math.sin(a)*spread, 0, math.cos(a)*spread) + j
 elseif pattern == "Helix" then

 local a = frac * math.pi * 2 * freq * config.evs_spiral_tightness + phase

 local r = config.evs_orbit_radius / 10
 return Vector3.new(math.cos(a)*r, -d, math.sin(a)*r) + j
 elseif pattern == "Chaos" then
 return Vector3.new((math.random()-0.5)*d*2, -math.random()*d, (math.random()-0.5)*d*2) + j
 elseif pattern == "Orbit" then

 local a = frac * math.pi * 2 * config.evs_orbit_speed / 5 + phase

 local r = config.evs_orbit_radius
 return Vector3.new(math.cos(a)*r, -d, math.sin(a)*r) + j
 elseif pattern == "Pulse" then

 local pulse = math.abs(math.sin(frac * math.pi * freq + phase))
 return dir * d * pulse + j
 elseif pattern == "Stutter" then

 local s = (math.floor(frac * freq * 8) % 2 == 0) and 1 or -1
 return dir * d * s + j
 else
 return dir * d + j
 end
end


getgenv().start_extra_voidspam = function()
 if evs_conn then evs_conn:Disconnect() end
 evs_tick_acc = 0; evs_phase = 0
 evs_conn = run_service.Heartbeat:Connect(function(dt)
 if not config.void_spam_enabled then getgenv().stop_extra_voidspam() return end

 local hrp = getgenv().get_hrp(localplayer)

 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if not hrp or not hum or hum.Health <= 0 then return end
 if hum:GetState() ~= Enum.HumanoidStateType.Physics then
 hum:ChangeState(Enum.HumanoidStateType.Physics)
 end


 local tick_interval = 1 / math.max(config.evs_void_tick or 60, 1)
 evs_tick_acc = evs_tick_acc + dt
 if evs_tick_acc < tick_interval then return end
 evs_tick_acc = evs_tick_acc - tick_interval
 evs_phase = evs_phase + dt * (config.evs_frequency or 1) * 0.5

 local base_dist = config.evs_distance or 50000

 local burst = math.clamp(config.evs_burst or 100, 1, 1000)

 local layers = math.clamp(config.evs_layer_count or 1, 1, 8)

 local jitter = config.evs_jitter or 0

 local amp = config.evs_amplitude or 1

 local freq = config.evs_frequency or 1

 local spread = config.evs_spread or 500

 local y_bias = config.evs_y_bias or 0

 local phase_shift = math.rad(config.evs_phase_shift or 0)

 local blend = config.evs_blend_mode or "Replace"

 local auto_rev = config.evs_auto_reverse

 local warp_mode = config.evs_warp_mode or "Instant"

 local gravity_mult = config.evs_gravity_mult or 1

 local rotation_chaos = config.evs_rotation_chaos or false

 local snap_back = config.evs_snap_back or false

 local snap_back_delay = config.evs_snap_back_delay or 0

 local layer_offset = config.evs_layer_offset or 0

 local axis_clamp = config.evs_axis_clamp or 0

 local turbulence = config.evs_turbulence or 0

 local echo_count = config.evs_echo_count or 0

 local echo_decay = config.evs_echo_decay or 0.5

 local invert_x = config.evs_invert_x or false

 local invert_y = config.evs_invert_y or false

 local invert_z = config.evs_invert_z or false

 local pattern2 = config.evs_pattern2 or "None"

 local blend_weight = config.evs_blend_weight or 0.5

 local scatter_mode = config.evs_scatter_mode or "Random"

 local burst_profile = config.evs_burst_profile or "Flat"

 local tick_jitter = config.evs_tick_jitter or 0

 local clamp_radius = config.evs_clamp_radius or 0

 local orbit_lock = config.evs_orbit_lock or false

 local wave_freq = config.evs_wave_freq or 1

 local depth_floor = config.evs_depth_floor or 0

 local axis_weight_x = config.evs_axis_weight_x or 1

 local axis_weight_y = config.evs_axis_weight_y or 1

 local axis_weight_z = config.evs_axis_weight_z or 1

 local burst_stagger = config.evs_burst_stagger or 0

 local layer_blend = config.evs_layer_blend or "Add"

 local pulse_sync = config.evs_pulse_sync or false

 local spin_lock = config.evs_spin_lock or false

 local gravity_dir = config.evs_gravity_dir or "Down"

 local invert_burst = config.evs_invert_burst or false

 local sync_mode = config.evs_sync_mode or "Instant"

 local burst_falloff = config.evs_burst_falloff or "None"

 local chaos_axis = config.evs_chaos_axis or "All"

 local sync_strength = config.evs_sync_strength or 50

 local chaos_blend = config.evs_chaos_blend or 0

 local burst_radius_scale = config.evs_burst_radius_scale or 1

 local chaos_sync = config.evs_chaos_sync or false

 local burst_lock = config.evs_burst_lock or false

 local depth_override = config.evs_depth_override or false

 local snap_cf = hrp.CFrame

 local evs_iter_pos = hrp.Position

 local actual_tick_interval = tick_interval
 if tick_jitter > 0 then
 actual_tick_interval = tick_interval + (math.random() - 0.5) * tick_jitter * 0.001
 end


 local function get_burst_scale(i, total)

 local t = (i - 1) / math.max(total - 1, 1)
 if burst_profile == "Ramp" then return t
 elseif burst_profile == "Bell" then return math.exp(-((t - 0.5)^2) * 8)
 elseif burst_profile == "Spike" then return (t < 0.1) and 1 or (1 - t)
 elseif burst_profile == "Sine" then return math.abs(math.sin(t * math.pi))
 elseif burst_profile == "Sawtooth" then return (t % 0.25) * 4
 elseif burst_profile == "Random" then return math.random()
 else return 1 end
 end


 local function apply_burst_falloff(d, i, total)

 local t = (i - 1) / math.max(total - 1, 1)
 if burst_falloff == "Linear" then return d * (1 - t)
 elseif burst_falloff == "Exp" then return d * math.exp(-3 * t)
 elseif burst_falloff == "Sine" then return d * math.abs(math.sin(t * math.pi))
 elseif burst_falloff == "Cosine" then return d * math.abs(math.cos(t * math.pi * 0.5))
 elseif burst_falloff == "Step" then return d * (t < 0.5 and 1 or 0.3)
 elseif burst_falloff == "Ramp" then return d * t
 else return d end
 end


 local function apply_gravity_dir(offset)

 local g = gravity_mult
 if gravity_dir == "Down" then return Vector3.new(offset.X, offset.Y - g * 10000, offset.Z)
 elseif gravity_dir == "Up" then return Vector3.new(offset.X, offset.Y + g * 10000, offset.Z)
 elseif gravity_dir == "Left" then return Vector3.new(offset.X - g * 10000, offset.Y, offset.Z)
 elseif gravity_dir == "Right" then return Vector3.new(offset.X + g * 10000, offset.Y, offset.Z)
 elseif gravity_dir == "In" then return offset * (1 - g * 0.1)
 elseif gravity_dir == "Out" then return offset * (1 + g * 0.1)
 else return offset end
 end


 local function apply_axis_weights(offset)
 return Vector3.new(offset.X * axis_weight_x, offset.Y * axis_weight_y, offset.Z * axis_weight_z)
 end


 local function apply_turbulence(pos, t_val)
 if turbulence <= 0 then return pos end

 local nx = math.noise(pos.X * 0.0001, t_val * 3.1, 0) * turbulence

 local ny = math.noise(0, pos.Y * 0.0001, t_val * 2.7) * turbulence

 local nz = math.noise(t_val * 4.3, 0, pos.Z * 0.0001) * turbulence
 return Vector3.new(pos.X + nx, pos.Y + ny, pos.Z + nz)
 end


 local function apply_echo(base_pos, echo_base, decay)

 local ep = base_pos
 for e = 1, echo_count do

 local ef = decay ^ e

 local ex = (echo_base.X - base_pos.X) * ef

 local ey = (echo_base.Y - base_pos.Y) * ef

 local ez = (echo_base.Z - base_pos.Z) * ef
 pcall(function() hrp.CFrame = CFrame.new(base_pos.X + ex, base_pos.Y + ey, base_pos.Z + ez) end)
 ep = hrp.Position
 end

 return ep
 end


 local function apply_clamp(pos, center, radius)
 if clamp_radius <= 0 or radius <= 0 then return pos end

 local d = (pos - center).Magnitude
 if d > radius then
 return center + (pos - center).Unit * radius
 end

 return pos
 end


 local function apply_warp(from_cf, to_pos)

 local target_cf = CFrame.new(to_pos)
 if warp_mode == "Lerp" then
 return from_cf:Lerp(target_cf, math.clamp((sync_strength or 50) / 100, 0.01, 1))
 elseif warp_mode == "Spring" then

 local alpha = math.clamp((sync_strength or 50) / 100, 0.01, 1)
 return from_cf:Lerp(target_cf, alpha * 1.5)
 elseif warp_mode == "Bounce" then

 local t = (sync_strength or 50) / 100

 local bounce = math.abs(math.sin(t * math.pi * 3)) * (1 - t)
 return from_cf:Lerp(target_cf, t + bounce * 0.2)
 elseif warp_mode == "Elastic" then

 local t = math.clamp((sync_strength or 50) / 100, 0.01, 1)

 local elastic = math.sin(t * math.pi * 4.5) * math.exp(-t * 3)
 return from_cf:Lerp(target_cf, t + elastic * 0.15)
 else
 return target_cf
 end
 end


 local t_now = tick()
 for layer = 1, layers do

 local layer_phase = phase_shift + math.rad(layer_offset * layer)
 for i = 1, burst do

 local b_scale = get_burst_scale(i, burst)
 if invert_burst then b_scale = 1 - b_scale end

 local eff_dist = apply_burst_falloff(base_dist * burst_radius_scale * b_scale, i, burst)

 local raw_offset = evs_compute_offset(i, burst, eff_dist, jitter, evs_phase + layer_phase, freq, amp, spread)
 if pattern2 ~= "None" then

 local raw2 = evs_compute_offset(i, burst, eff_dist, jitter, evs_phase + layer_phase + math.pi, freq * wave_freq, amp, spread)
 if layer_blend == "Add" then raw_offset = raw_offset + raw2 * blend_weight
 elseif layer_blend == "Lerp" then raw_offset = raw_offset:Lerp(raw2, blend_weight)
 elseif layer_blend == "Multiply" then raw_offset = Vector3.new(raw_offset.X * raw2.X * blend_weight, raw_offset.Y * raw2.Y * blend_weight, raw_offset.Z * raw2.Z * blend_weight)
 elseif layer_blend == "Screen" then raw_offset = raw_offset + raw2 - Vector3.new(raw_offset.X * raw2.X, raw_offset.Y * raw2.Y, raw_offset.Z * raw2.Z) * blend_weight
 end
 end

 raw_offset = apply_axis_weights(raw_offset)
 if gravity_mult ~= 1 then raw_offset = apply_gravity_dir(raw_offset) end
 if chaos_blend > 0 then

 local ca = chaos_axis

 local cx = (ca == "All" or ca == "X" or ca == "XY" or ca == "XZ") and (math.random() - 0.5) * eff_dist * chaos_blend * 0.01 or 0

 local cy = (ca == "All" or ca == "Y" or ca == "XY" or ca == "YZ") and (math.random() - 0.5) * eff_dist * chaos_blend * 0.01 or 0

 local cz = (ca == "All" or ca == "Z" or ca == "XZ" or ca == "YZ") and (math.random() - 0.5) * eff_dist * chaos_blend * 0.01 or 0
 raw_offset = raw_offset + Vector3.new(cx, cy, cz)
 end


 local ox = invert_x and -raw_offset.X or raw_offset.X

 local oy = invert_y and -raw_offset.Y or raw_offset.Y

 local oz = invert_z and -raw_offset.Z or raw_offset.Z
 oy = oy + y_bias
 if axis_clamp > 0 then
 ox = math.clamp(ox, -axis_clamp, axis_clamp)
 oz = math.clamp(oz, -axis_clamp, axis_clamp)
 end

 if depth_floor > 0 then
 oy = math.max(oy, -depth_floor)
 end


 local raw_pos = Vector3.new(evs_iter_pos.X + ox, evs_iter_pos.Y + oy, evs_iter_pos.Z + oz)
 if clamp_radius > 0 then raw_pos = apply_clamp(raw_pos, snap_cf.Position, clamp_radius) end
 if turbulence > 0 then raw_pos = apply_turbulence(raw_pos, t_now + i * 0.01) end

 local final_cf = apply_warp(hrp.CFrame, raw_pos)
 if rotation_chaos then
 final_cf = final_cf * CFrame.Angles(math.rad(math.random(-180,180)), math.rad(math.random(-180,180)), math.rad(math.random(-180,180)))
 end

 if spin_lock then

 local sp = tick() * 1e70
 final_cf = CFrame.new(final_cf.Position) * CFrame.Angles(0, sp % (2 * math.pi), 0)
 end

 if orbit_lock then

 local oa = t_now * (config.evs_orbit_speed or 5)

 local or_ = config.evs_orbit_radius or 10000

 local op = Vector3.new(snap_cf.Position.X + math.cos(oa) * or_, snap_cf.Position.Y, snap_cf.Position.Z + math.sin(oa) * or_)
 final_cf = CFrame.new(op)
 end

 if auto_rev and (math.floor(t_now * freq) % 2 == 1) then
 final_cf = CFrame.new(snap_cf.Position) * CFrame.new(-final_cf.X + snap_cf.X, -final_cf.Y + snap_cf.Y, -final_cf.Z + snap_cf.Z)
 end

 if pulse_sync then

 local pf = math.abs(math.sin(t_now * (config.evs_frequency or 1) * math.pi))
 final_cf = snap_cf:Lerp(final_cf, pf)
 end

 pcall(function() hrp.CFrame = final_cf end)
 evs_iter_pos = hrp.Position
 if burst_stagger > 0 then task.wait(burst_stagger * 0.001) end
 end

 if echo_count > 0 then
 evs_iter_pos = apply_echo(evs_iter_pos, snap_cf.Position, echo_decay)
 end
 end

 if config.evs_kill_velocity then
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 end

 if config.evs_sync_to_ragebot then
  srb_write(hrp, hrp.CFrame)
 end

 if snap_back then
 if snap_back_delay > 0 then task.wait(snap_back_delay * 0.001) end
 pcall(function()
 hrp.CFrame = snap_cf
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 end)
 end
 end)
end


getgenv().stop_extra_voidspam = function()
 if evs_conn then evs_conn:Disconnect(); evs_conn = nil end
end


local void_hide_conn = nil

getgenv().start_void_hide = function()
 if void_hide_conn then void_hide_conn:Disconnect() end
 void_hide_conn = run_service.Heartbeat:Connect(function()
  if not config.void_hide_enabled then return end
  pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
  pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)

  local hrp = getgenv().get_hrp(localplayer)

  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  if not hrp or not hum or hum.Health <= 0 then return end
  if hum:GetState() ~= Enum.HumanoidStateType.Physics then
   hum:ChangeState(Enum.HumanoidStateType.Physics)
  end


  local base = hrp.Position

  local hx = config.void_hide_x or 1e6

  local hy = config.void_hide_y or 9e25

  local hz = config.void_hide_z or 1e6

  local sx = (math.random() < 0.5) and 1 or -1

  local sz = (math.random() < 0.5) and 1 or -1

  local hide_cf = CFrame.new(base.X + sx * hx, base.Y - hy, base.Z + sz * hz)
  pcall(function()
   hrp.CFrame = hide_cf
   hrp.AssemblyLinearVelocity = Vector3.zero
   hrp.AssemblyAngularVelocity = Vector3.zero
  end)

  if config.void_hide_sync_to_ragebot then
   srb_write(hrp, hide_cf)
  end

  pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
  pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 end)
end


getgenv().stop_void_hide = function()
 if void_hide_conn then void_hide_conn:Disconnect(); void_hide_conn = nil end
 config.void_hide_enabled = false
end

local vst_conn = nil

local vst_phase = "hide"

local vst_phase_start = 0

local vst_dt_buf = 0

local vst_last_pos = nil

local vst_pre_enable_cf = nil

local void_spin_conn = nil

getgenv().start_voidspam_type = function()
 if vst_conn then vst_conn:Disconnect() end
 if void_spin_conn then void_spin_conn:Disconnect() end
 vst_phase = "hide"
 vst_phase_start = tick()
 vst_dt_buf = 0
 vst_last_pos = nil

 local hrp0 = getgenv().get_hrp(localplayer)
 if hrp0 and not vst_pre_enable_cf then vst_pre_enable_cf = hrp0.CFrame end
 void_spin_conn = run_service.Heartbeat:Connect(function(dt)
  if not config.vst_enabled then return end

  local char = localplayer.Character
  if not char then return end

  local spd = config.vst_spin_speed or 1e85

  local spinAngle = (tick() * spd) % (2 * math.pi)

  local spinCF = CFrame.Angles(0, spinAngle, 0)

  local hrp_s = char:FindFirstChild("HumanoidRootPart")
  if hrp_s then
   pcall(function() hrp_s.AssemblyAngularVelocity = Vector3.zero end)
  end

  pcall(function()
   for _, v in pairs(char:GetDescendants()) do
    if v:IsA("Motor6D") then
     v.Transform = spinCF
    end
   end
  end)
 end)

 vst_conn = run_service.Heartbeat:Connect(function(dt)
 if not config.vst_enabled then return end
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)

 local hrp = getgenv().get_hrp(localplayer)

 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if not hrp or not hum or hum.Health <= 0 then return end

 local vtype = config.vst_type or "Defend"
 if vtype ~= "Bait" then
 if hum:GetState() ~= Enum.HumanoidStateType.Physics then
 hum:ChangeState(Enum.HumanoidStateType.Physics)
 end
 end


 local function vst_do_defend_proximity_escape()
 if not config.vst_defend_proximity_escape then return end

 local escape_radius = math.max(config.vst_defend_proximity_radius or 20, 1)

 local escape_dist = math.max(config.vst_defend_escape_dist or 1000, 1)

 local my_pos = hrp.Position
 for _, p in ipairs(players:GetPlayers()) do
 if p ~= localplayer and p.Character then

 local t_hrp = p.Character:FindFirstChild("HumanoidRootPart")

 local t_hum = p.Character:FindFirstChildOfClass("Humanoid")
 if t_hrp and t_hum and t_hum.Health > 0 then

 local dist_to_enemy = (my_pos - t_hrp.Position).Magnitude
 if dist_to_enemy <= escape_radius then

 local escape_iters = math.clamp(config.et_total or 1000, 1, 500)
 local _ir_esc = math.max(config.evs_iter_radius or 500000, 1)

 local iter_pos = my_pos
 for _ei = 1, escape_iters do

 local sx = (math.random() < 0.5) and 1 or -1

 local sy = (math.random() < 0.5) and 1 or -1

 local sz = (math.random() < 0.5) and 1 or -1

 local ex = sx * (escape_dist + math.random() * escape_dist * 9)

 local ey = sy * (_ir_esc * (0.5 + math.random() * 0.5))

 local ez = sz * (escape_dist + math.random() * escape_dist * 9)
 pcall(function()
 hrp.CFrame = CFrame.new(iter_pos.X + ex, iter_pos.Y + ey, iter_pos.Z + ez)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 end)

 iter_pos = hrp.Position
 end

 vst_last_pos = hrp.Position
 my_pos = hrp.Position
 return
 end
 end
 end
 end
 end


 local function vst_get_direction_offset(base_pos, dist)

  local dir_mode = config.vs_void_direction or "Random"

  local cam = workspace.CurrentCamera
  if dir_mode == "Forward" then

   local look = cam and Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
   if look.Magnitude > 0.001 then look = look.Unit else look = Vector3.new(0, 0, -1) end
   return Vector3.new(look.X * dist, (math.random() < 0.5 and 1 or -1) * dist, look.Z * dist)
  elseif dir_mode == "Backward" then

   local look = cam and Vector3.new(-cam.CFrame.LookVector.X, 0, -cam.CFrame.LookVector.Z) or Vector3.new(0, 0, 1)
   if look.Magnitude > 0.001 then look = look.Unit else look = Vector3.new(0, 0, 1) end
   return Vector3.new(look.X * dist, (math.random() < 0.5 and 1 or -1) * dist, look.Z * dist)
  elseif dir_mode == "Left" then

   local right = cam and cam.CFrame.RightVector or Vector3.new(1, 0, 0)

   local left = Vector3.new(-right.X, 0, -right.Z)
   if left.Magnitude > 0.001 then left = left.Unit else left = Vector3.new(-1, 0, 0) end
   return Vector3.new(left.X * dist, (math.random() < 0.5 and 1 or -1) * dist, left.Z * dist)
  elseif dir_mode == "Right" then

   local right = cam and Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z) or Vector3.new(1, 0, 0)
   if right.Magnitude > 0.001 then right = right.Unit else right = Vector3.new(1, 0, 0) end
   return Vector3.new(right.X * dist, (math.random() < 0.5 and 1 or -1) * dist, right.Z * dist)
  elseif dir_mode == "Up" then
   return Vector3.new((math.random() - 0.5) * dist * 0.2, dist, (math.random() - 0.5) * dist * 0.2)
  elseif dir_mode == "Down" then
   return Vector3.new((math.random() - 0.5) * dist * 0.2, -dist, (math.random() - 0.5) * dist * 0.2)
  elseif dir_mode == "Camera" then

   local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
   return look * dist
  elseif dir_mode == "Directional" then

   local xp = config.vs_dir_xp or 5000

   local xn = config.vs_dir_xn or 5000

   local yp = config.vs_dir_yp or 5000

   local yn = config.vs_dir_yn or 5000

   local zp = config.vs_dir_zp or 5000

   local zn = config.vs_dir_zn or 5000

   local rx = (math.random() < 0.5) and (math.random() * xp) or (-math.random() * xn)

   local ry = (math.random() < 0.5) and (math.random() * yp) or (-math.random() * yn)

   local rz = (math.random() < 0.5) and (math.random() * zp) or (-math.random() * zn)
   return Vector3.new(rx, ry, rz)
  else

   local sx = (math.random() < 0.5) and 1 or -1

   local sy = (math.random() < 0.5) and 1 or -1

   local sz = (math.random() < 0.5) and 1 or -1

   local _ir2 = math.max(config.evs_iter_radius or 500000, 1); return Vector3.new(sx * (_ir2 * (0.5 + math.random() * 0.5)), sy * (_ir2 * (0.5 + math.random() * 0.5)), sz * (_ir2 * (0.5 + math.random() * 0.5)))
  end
 end

 local function vst_do_defend_burst()
 vst_do_defend_proximity_escape()
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)

 local iters = math.clamp(config.et_total or 1000, 1, 500)

 local stab_enabled = config.vs_stabilizer_enabled

 local stability = (config.vs_stability or 50) / 100

 local smooth_enabled = config.vs_smoothness_enabled

 local smooth_alpha = math.clamp((config.vs_smoothness or 10) / 100, 0.001, 1)

 local resolved_origin = hrp.CFrame
 if config.vs_pos_resolver then
 pcall(function() hrp.CFrame = hrp.CFrame; resolved_origin = hrp.CFrame end)
 end


 local restore_pos = resolved_origin
 
 local base_dist = math.max(config.evs_iter_radius or 500000, 1) * (0.5 + math.random() * 0.5)

 local dir_mode = config.vs_void_direction or "Random"
 if dir_mode == "Random" then
  for i = 1, iters do

   local base = vst_last_pos or hrp.Position

   local offset = vst_get_direction_offset(base, base_dist)

   local target_pos = base + offset

   local target_cf
   if smooth_enabled then
    target_cf = hrp.CFrame:Lerp(CFrame.new(target_pos), smooth_alpha)
   else
    target_cf = CFrame.new(target_pos)
   end

   hrp.CFrame = target_cf
   vst_last_pos = hrp.Position
  end
 else
  for i = 1, iters do

   local base = vst_last_pos or hrp.Position

   local offset = vst_get_direction_offset(base, base_dist)

   local target_pos = base + offset

   local target_cf
   if smooth_enabled then
    target_cf = hrp.CFrame:Lerp(CFrame.new(target_pos), smooth_alpha)
   else
    target_cf = CFrame.new(target_pos)
   end

   hrp.CFrame = target_cf
   vst_last_pos = hrp.Position
  end
 end

 if stab_enabled then

 local damp = 1 - stability
 hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * damp
 hrp.AssemblyAngularVelocity = hrp.AssemblyAngularVelocity * damp
 else
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 end

 if config.vs_pos_restore then
 pcall(function() hrp.CFrame = restore_pos end)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 vst_last_pos = restore_pos.Position
 end

 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 end


 local function vst_do_hide_burst()
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)

 local base = hrp.Position

 local sx = (math.random() < 0.5) and 1 or -1

 local sz = (math.random() < 0.5) and 1 or -1
 pcall(function()
  hrp.CFrame = CFrame.new(base.X + sx * 1e6, base.Y - 9e25, base.Z + sz * 1e6)
 end)

 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 end

 if config.vs_sync_to_ragebot then
  vst_last_pos = nil
  srb_write(hrp, hrp.CFrame)
 end

 if vtype == "Unhittability" then
 vst_do_defend_burst()

 local my_hrp_u = getgenv().get_hrp(localplayer)
 if my_hrp_u then

  local y_range_u = math.max(config.vst_unhittability_y_range or 10, 1)
  pcall(function()
   for _, p in pairs(players:GetPlayers()) do
    if p ~= localplayer and p.Character then

     local eh = p.Character:FindFirstChild("HumanoidRootPart")
     if eh then

      local y_diff = my_hrp_u.Position.Y - eh.Position.Y
      if y_diff >= 0 and y_diff <= y_range_u then
       melee_fake_cf_store[p] = eh.CFrame

       local mt_u = getrawmetatable(eh)

       local old_ni_u = mt_u and rawget(mt_u, "__newindex")

       local fake_cf_u = CFrame.new(MELEE_FAKE_OFFSET)
       if old_ni_u then
        pcall(old_ni_u, eh, "CFrame", fake_cf_u)
       else
        rawset(eh, "CFrame", fake_cf_u)
       end

       eh.AssemblyLinearVelocity = Vector3.zero
      else
       melee_fake_cf_store[p] = nil
      end
     end
    end
   end
  end)
 end

 vst_do_defend_proximity_escape()
 elseif vtype == "Defend" then
 vst_do_defend_burst()
 elseif vtype == "Attack" then
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)

 local hide_dur = math.clamp(config.vst_hide_time or 0.3, 0.01, 1)

 local atk_dur = math.clamp(config.vst_attack_time or 0.3, 0.01, 1)

 local elapsed = tick() - vst_phase_start
 if vst_phase == "hide" then

 local hide_mode = tostring(config.vst_hide_mode or "Unhittability")
 if hide_mode == "Extreme" then
 vst_do_hide_burst()
 elseif hide_mode == "Unhittability" then
 vst_do_defend_burst()

 local my_hrp_u = getgenv().get_hrp(localplayer)
 if my_hrp_u then

  local y_range_u = math.max(config.vst_unhittability_y_range or 10, 1)
  pcall(function()
   for _, p in pairs(players:GetPlayers()) do
    if p ~= localplayer and p.Character then

     local eh = p.Character:FindFirstChild("HumanoidRootPart")
     if eh then

      local y_diff = my_hrp_u.Position.Y - eh.Position.Y
      if y_diff >= 0 and y_diff <= y_range_u then
       melee_fake_cf_store[p] = eh.CFrame

       local mt_u = getrawmetatable(eh)

       local old_ni_u = mt_u and rawget(mt_u, "__newindex")

       local fake_cf_u = CFrame.new(MELEE_FAKE_OFFSET)
       if old_ni_u then pcall(old_ni_u, eh, "CFrame", fake_cf_u)
       else rawset(eh, "CFrame", fake_cf_u) end
       eh.AssemblyLinearVelocity = Vector3.zero
      else melee_fake_cf_store[p] = nil end
     end
    end
   end
  end)
 end
 else
 vst_do_defend_burst()
 end

 if elapsed >= hide_dur then vst_phase = "attack"; vst_phase_start = tick() end
 else

 local target = get_teleport_target and get_teleport_target()
 if target and target.Character then

  local t_hrp = target.Character:FindFirstChild("HumanoidRootPart")
  if t_hrp then

   local head = target.Character:FindFirstChild("Head")

   local tor = target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Torso")

   local live_vst = tt_live[t_hrp]

   local vst_in_void = live_vst and live_vst.is_void

   local vst_is_chaos = live_vst and (live_vst.chaos_count or 0) > 6

   local vst_sn = (vst_in_void or vst_is_chaos) and (TT_MICRO_SAMPLES * 16) or (TT_MICRO_SAMPLES * 4)
   for _ = 1, vst_sn do
    pcall(tt_sample_part, t_hrp)
    if head then pcall(tt_sample_part, head) end
    if tor then pcall(tt_sample_part, tor) end
   end


   local atk_method = config.vst_attack_method or "Adaptive"

   local dest = tt_resolve_dest(head, t_hrp, atk_method)
   if not dest or not tt_validate_vec3(dest) then
    dest = tt_resolve_void_pos_deep(t_hrp, head)
   end

   if not dest or not tt_validate_vec3(dest) then

    local live = tt_live[t_hrp]
    if live then
     if live.lkg_x and tt_valid_xyz(live.lkg_x, live.lkg_y, live.lkg_z) then
      dest = Vector3.new(live.lkg_x, live.lkg_y, live.lkg_z)
     elseif tt_valid_xyz(live.x, live.y, live.z) then
      dest = Vector3.new(live.x, live.y, live.z)
     end
    end

    if not dest then

     local ok, cf = pcall(function() return t_hrp.CFrame end)
     if ok and cf then

      local x, y, z = cf.X, cf.Y, cf.Z
      if tt_valid_xyz(x, y, z) then dest = Vector3.new(x, y, z) end
     end
    end
   end

   if dest and tt_validate_vec3(dest) then
    tt_nuke_fallen_parts()
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    pcall(function() hum.AutoRotate = false end)
    for _vi=1,8 do pcall(tt_apply_teleport, hrp, dest, hum, t_hrp) end
    tt_nuke_fallen_parts()
    for _vi=1,4 do pcall(tt_apply_teleport, hrp, dest, hum, t_hrp) end
   end
  end
 end

 pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
 pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
 pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
 if elapsed >= atk_dur then vst_phase = "hide"; vst_phase_start = tick() end
 end

 elseif vtype == "Bait" then

 local cur = hrp.Position

 local bait_depth = math.clamp(config.vst_bait_depth or 20, 1, 40)
 hrp.CFrame = CFrame.new(cur.X, cur.Y - bait_depth, cur.Z)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 elseif vtype == "Extreme" then

 local cur = hrp.Position
 pcall(function() hrp.CFrame = CFrame.new(cur.X, cur.Y - 9e25, cur.Z) end)
 hrp.AssemblyLinearVelocity = Vector3.zero
 hrp.AssemblyAngularVelocity = Vector3.zero
 elseif vtype == "Random" then
 do

  local iters = math.clamp(config.et_total or 1000, 1, 500)

  local rand_dir_mode = config.vs_void_direction or "Random"

  local _ir_rand = math.max(config.evs_iter_radius or 500000, 1)
  local rand_base_dist = _ir_rand * (0.5 + math.random() * 0.5)
  if rand_dir_mode == "Random" then
   for i = 1, iters do

    local sx = (math.random() < 0.5) and 1 or -1

    local sy = (math.random() < 0.5) and 1 or -1

    local sz = (math.random() < 0.5) and 1 or -1

    local rx = sx * (_ir_rand * (0.5 + math.random() * 0.5))

    local ry = sy * (_ir_rand * (0.5 + math.random() * 0.5))

    local rz = sz * (_ir_rand * (0.5 + math.random() * 0.5))

    local rbase = (vst_last_pos or hrp.Position)
    pcall(function() hrp.CFrame = CFrame.new(rbase.X + rx, rbase.Y + ry, rbase.Z + rz) end)
    vst_last_pos = hrp.Position
   end
  else
   for i = 1, iters do

    local rbase = (vst_last_pos or hrp.Position)

    local offset = vst_get_direction_offset(rbase, rand_base_dist)
    pcall(function() hrp.CFrame = CFrame.new(rbase + offset) end)
    vst_last_pos = hrp.Position
   end
  end

  hrp.AssemblyLinearVelocity = Vector3.zero
  hrp.AssemblyAngularVelocity = Vector3.zero
 end
 end end)
end


getgenv().stop_voidspam_type = function()
 if vst_conn then vst_conn:Disconnect(); vst_conn = nil end
 if void_spin_conn then void_spin_conn:Disconnect(); void_spin_conn = nil end
 vst_last_pos = nil
 vs_spiral = 0
 vs_wave = 0
 vs_helix = 0
 vs_orbit_angle = 0
 vs_phase_hex = 0
 vs_phase_oct = 0
 vs_phase_star = 0
 vs_phase_cross = 0
 vs_phase_rhombus = 0
 evs_phase = 0
 evs_tick_acc = 0
end


getgenv().disable_voidspam_type = function()

 config.vst_enabled = false
 getgenv().stop_voidspam_type()

 local hrp = getgenv().get_hrp(localplayer)

 local char = localplayer.Character

 local hum = char and char:FindFirstChildOfClass("Humanoid")
 if hrp then
  if vst_pre_enable_cf then
   pcall(function()
    hrp.CFrame = vst_pre_enable_cf
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
   end)
  end

  pcall(function()
   hrp.AssemblyLinearVelocity = Vector3.zero
   hrp.AssemblyAngularVelocity = Vector3.zero
  end)
 end

 if hum then
  pcall(function() hum.AutoRotate = true end)
  pcall(function() hum.PlatformStand = false end)
  pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
  task.defer(function()
   pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
  end)
  task.delay(0.1, function()
   local _c = localplayer.Character
   local _h = _c and _c:FindFirstChildOfClass("Humanoid")
   if _h and _h.Health > 0 then
    pcall(function() _h.AutoRotate = true end)
    pcall(function() _h.PlatformStand = false end)
    if _h:GetState() == Enum.HumanoidStateType.Physics then
     pcall(function() _h:ChangeState(Enum.HumanoidStateType.GettingUp) end)
     task.defer(function() pcall(function() _h:ChangeState(Enum.HumanoidStateType.Running) end) end)
    end
   end
  end)
 end

 if char then
  pcall(function()
   for _, v in pairs(char:GetDescendants()) do
    if v:IsA("Motor6D") then
     v.Transform = CFrame.new()
    end
   end
  end)
 end

 vst_pre_enable_cf = nil
end


local astral_sound_ids = {
 Space = "rbxassetid://719384308",
 Pop = "rbxassetid://140323850218372",
 Bonk = "rbxassetid://18794851884",
 Skeet = "rbxassetid://83717596220569",
 Neverlose = "rbxassetid://97643101798871",
 Slip = "rbxassetid://70557734865364",
}

local astral_sound_volume = 0.5

local astral_sound_selected = "Space"

local astral_sound_service = game:GetService("SoundService")

local astral_toggle_sound = Instance.new("Sound", astral_sound_service)
astral_toggle_sound.SoundId = astral_sound_ids[astral_sound_selected]
astral_toggle_sound.Volume = astral_sound_volume

local function play_toggle_sound()
 if not config.sounds_enabled then return end
 pcall(function()
  astral_toggle_sound.SoundId = astral_sound_ids[astral_sound_selected] or astral_sound_ids.Space
  astral_toggle_sound.Volume = astral_sound_volume
  astral_toggle_sound.PlaybackSpeed = math.random(95, 105) / 100
  astral_toggle_sound:Play()
 end)
end


getgenv().play_toggle_sound = play_toggle_sound

AC.FlowUI = {}
AC.FlowUI.SOURCE = [==[local T=game:GetService"TweenService"local q=game:GetService"UserInputService"local ad=game:GetService"GuiService"local U=game:GetService"RunService"local C=game:GetService"HttpService"local D=game:GetService"Players"local E=D.LocalPlayer local f={}f.Flags={}f.Windows={}local function l(b,c)local a={}if type(b)=="string"then a.Name=b elseif type(b)=="table"then for b,c in pairs(b)do a[b]=c end end for b,c in pairs(c or{})do if a[c]==nil and a[b]~=nil then a[c]=a[b]end end if a.Range then a.Min=a.Min or a.Range[1]a.Max=a.Max or a.Range[2]end return a end local function n(e,b,a,d,g)a._type=g a._frame=d a._listeners=a._listeners or{}local c=e and e.Window if b.Flag then f.Flags[b.Flag]=a if c then local a=b.Callback b.Callback=function(...)if type(a)=="function"then a(...)end c:_autoSave()end end end function a:Destroy()if a._destroyed then return end a._destroyed=true for b,a in ipairs(a._listeners)do a()end a._listeners={}if b.Flag and f.Flags[b.Flag]==a then f.Flags[b.Flag]=nil end if c then c._controlsDirty=true end if d then d:Destroy()end end return a end f.Theme={Background=Color3.fromRGB(0,0,0),Surface=Color3.fromRGB(24,24,24),Surface2=Color3.fromRGB(30,30,30),Surface3=Color3.fromRGB(38,38,38),Stroke=Color3.fromRGB(43,43,43),StrokeHover=Color3.fromRGB(72,72,72),Accent=Color3.fromRGB(255,255,255),AccentDark=Color3.fromRGB(20,20,20),Text=Color3.fromRGB(230,230,230),Muted=Color3.fromRGB(120,120,120),Warning=Color3.fromRGB(240,176,108),Success=Color3.fromRGB(150,220,170),Error=Color3.fromRGB(240,120,120)}f.Assets={Shadow="rbxassetid://6014261993",Glow="rbxassetid://8992230677",Logo="rbxassetid://103859712365480"}local A local function I()if A~=nil then return A end local b,a=pcall(function()local a=game:HttpGet"https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua"return loadstring(a)()end)if b and type(a)=="table"then A=a else A=false warn("[AirFlow] lucide icons unavailable: "..tostring(a))end return A end local ae={ValleySans={Regular="https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Regular.ttf",Medium="https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Medium.ttf",SemiBold="https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-SemiBold.ttf"}}local V={Regular={400,Enum.FontWeight.Regular},Medium={500,Enum.FontWeight.Medium},SemiBold={600,Enum.FontWeight.SemiBold},Bold={700,Enum.FontWeight.Bold}}function f:LoadFont(b)local e="function"b=l(b,{})if type(writefile)~=e or type(isfile)~=e or typeof(getcustomasset)~=e then warn"[AirFlow] custom fonts need writefile, isfile and getcustomasset"return false end local a=b.Name or"CustomFont"local g=b.Weights or ae[a]if type(g)~="table"then warn("[AirFlow] no font weights for "..a)return false end local d=b.Folder or"AirFlowFonts"pcall(function()if type(isfolder)=="function"and type(makefolder)=="function"and not isfolder(d)then makefolder(d)end end)local h={}for b,e in pairs(g)do local c=V[b]if c then local f,g=d.."/"..a.."-"..b..".ttf",true if not isfile(f)then g=pcall(function()writefile(f,game:HttpGet(e))end)end if g then table.insert(h,{name=b,weight=c[1],style="normal",assetId=getcustomasset(f)})else warn("[AirFlow] could not download "..b.." weight of "..a)end end end if#h==0 then return false end local i=d.."/"..a..".json"local j=pcall(function()writefile(i,C:JSONEncode{name=a,faces=h})end)if not j then return false end local k=getcustomasset(i)local function c(a,c)local b=V[a]if b and g[a]then return Font.new(k,b[2])end return c end f.Fonts.Regular=c("Regular",f.Fonts.Regular)f.Fonts.Medium=c("Medium",c("Regular",f.Fonts.Medium))f.Fonts.Bold=c("SemiBold",c("Bold",f.Fonts.Bold))return true end function f:PreloadIcons()return I()~=false end local function af(a)if typeof(a)=="table"then return a.Image,a.RectOffset,a.RectSize end if type(a)~="string"then return nil end if a:find"^rbxassetid://"or a:find"^rbxasset://"or a:find"^http"then return a end local d=a:gsub("^lucide:","")local b=I()if not b then return nil end local c=b.Icons and b.Icons[d]or b[d]if type(c)=="table"then local a=c.Image if type(a)=="number"then a="rbxassetid://"..tostring(a)end local d=b.Spritesheets and b.Spritesheets[tostring(a)]or a return d,c.ImageRectPosition,c.ImageRectSize elseif type(c)=="string"then return c end warn("[AirFlow] unknown lucide icon: "..d)return nil end local J="rbxasset://fonts/families/BuilderSans.json"f.Fonts={Regular=Font.new(J,Enum.FontWeight.Regular),Medium=Font.new(J,Enum.FontWeight.Medium),Bold=Font.new(J,Enum.FontWeight.SemiBold)}local a=f.Theme local t=f.Assets local i=f.Fonts local m=q.TouchEnabled and not q.KeyboardEnabled f.Touch=m local K=m and 54 or 48 local v=m and 70 or 64 local L=m and 40 or 34 local s=m and 34 or 28 local W={}local function b(e,f,a,b,c)a=a or.2 if a<=0 then for a,b in pairs(f)do e[a]=b end return nil end b=b or Enum.EasingStyle.Quart c=c or Enum.EasingDirection.Out local g=a..b.Name..c.Name local d=W[g]if not d then d=TweenInfo.new(a,b,c)W[g]=d end local h=T:Create(e,d,f)h:Play()return h end local function c(d,b,c)local a=Instance.new(d)for b,c in pairs(b)do if b~="Parent"then a[b]=c end end if c then for c,b in ipairs(c)do b.Parent=a end end if b.Parent then a.Parent=b.Parent end return a end local function e(a,b)return c("UICorner",{CornerRadius=b or UDim.new(0,8),Parent=a})end local function h(b,d,e,f)return c("UIStroke",{Color=d or a.Stroke,Transparency=e or 0,Thickness=f or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Parent=b})end local function o(a,b,d,e,f)return c("UIPadding",{PaddingLeft=UDim.new(0,b or 0),PaddingRight=UDim.new(0,d or 0),PaddingTop=UDim.new(0,e or 0),PaddingBottom=UDim.new(0,f or 0),Parent=a})end local function d(d)local b={BackgroundTransparency=1,TextColor3=a.Text,TextSize=14,FontFace=i.Medium,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd}for a,c in pairs(d)do b[a]=c end return c("TextLabel",b)end local function x(d,e,f,g,h)local b=c("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),Position=f,Size=e,BackgroundTransparency=1,Image=t.Glow,ImageColor3=Color3.fromRGB(200,200,200),ImageTransparency=g,ZIndex=0,Parent=d})c("UIGradient",{Color=ColorSequence.new(Color3.fromRGB(255,255,255),a.Accent),Rotation=h or 90,Parent=b})return b end local function M(a)return c("Frame",{Position=UDim2.fromOffset(0,0),Size=UDim2.new(1,0,0,1),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.93,BorderSizePixel=0,ZIndex=0,Parent=a})end local function u(a,c)local b,d,e=af(c)if not b then return end a.Image=b a.ImageRectOffset=d or Vector2.zero a.ImageRectSize=e or Vector2.zero end local function ag()local b pcall(function()if typeof(gethui)=="function"then b=gethui()end end)if typeof(b)=="Instance"then return b end local a pcall(function()a=game:GetService"CoreGui"local b=Instance.new"Folder"b.Parent=a b:Destroy()end)if a then return a end return E:WaitForChild"PlayerGui"end local X,Y=nil,Vector2.zero local function r()local a=time()if X~=a then X=a Y=ad:GetGuiInset()end return q:GetMouseLocation()-Y end local function p(a)return a.UserInputType==Enum.UserInputType.MouseButton1 or a.UserInputType==Enum.UserInputType.Touch end local function N(a)return a.UserInputType==Enum.UserInputType.MouseMovement or a.UserInputType==Enum.UserInputType.Touch end local function y(d,e,f,g)local a=c("Frame",{AnchorPoint=Vector2.new(0,.5),Position=g,Size=UDim2.fromOffset(16,16),BackgroundTransparency=1,Parent=d})local b=c("ImageLabel",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ImageColor3=f,ScaleType=Enum.ScaleType.Fit,Parent=a})u(b,e)return a,b end local function Z(j,g,k)local h=c("Frame",{AnchorPoint=Vector2.new(g,.5),Position=UDim2.new(g,k,.5,0),Size=UDim2.fromOffset(18,18),BackgroundTransparency=1,Parent=j})local e={}local f=c("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(16,16),BackgroundTransparency=1,ImageColor3=a.Muted,ScaleType=Enum.ScaleType.Fit,Parent=h})u(f,"chevron-down")if f.Image~=""then function e:Set(c)b(f,{Rotation=c and 180 or 0,ImageColor3=c and a.Accent or a.Muted},.3,Enum.EasingStyle.Quint)end return e end f:Destroy()local function i(b,c)return d{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(18,18),Text="›",TextSize=22,TextXAlignment=Enum.TextXAlignment.Center,TextColor3=a.Muted,TextTransparency=c,Rotation=b,Parent=h}end local l=i(90,0)local m=i(270,1)function e:Set(c)b(l,{TextTransparency=c and 1 or 0},.2)b(m,{TextTransparency=c and 0 or 1,TextColor3=c and a.Accent or a.Muted},.2)end return e end local O={}local function ah(f)local g=r()local h=math.max(f.AbsoluteSize.X,f.AbsoluteSize.Y)*2.2 local d=table.remove(O)if not d then d=c("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=a.Accent,BorderSizePixel=0})e(d,UDim.new(1,0))end d.Position=UDim2.fromOffset(g.X-f.AbsolutePosition.X,g.Y-f.AbsolutePosition.Y)d.Size=UDim2.fromOffset(0,0)d.BackgroundTransparency=.82 d.ZIndex=f.ZIndex+1 d.Parent=f b(d,{Size=UDim2.fromOffset(h,h),BackgroundTransparency=1},.55)task.delay(.55,function()d.Parent=nil if#O<4 then table.insert(O,d)else d:Destroy()end end)end local function w(c)if not c then return end b(c,{Color=a.Accent,Transparency=.2},.08)task.delay(.12,function()b(c,{Color=a.Stroke,Transparency=0},.35)end)end local function F(c,d)c.MouseEnter:Connect(function()b(d,{Color=a.StrokeHover},.12)end)c.MouseLeave:Connect(function()b(d,{Color=a.Stroke},.25)end)end local ai={[Enum.KeyCode.LeftControl]="LCtrl",[Enum.KeyCode.RightControl]="RCtrl",[Enum.KeyCode.LeftShift]="LShift",[Enum.KeyCode.RightShift]="RShift",[Enum.KeyCode.LeftAlt]="LAlt",[Enum.KeyCode.RightAlt]="RAlt",[Enum.KeyCode.Return]="Enter",[Enum.KeyCode.Escape]="Esc",[Enum.KeyCode.Backspace]="Backspace"}local function P(a)if a==nil then return"None"end return ai[a]or a.Name end local function k(a,...)if type(a)~="function"then return end local b,c=pcall(a,...)if not b then warn("[AirFlow] callback error: "..tostring(c))end end local function aa(e,f,a)local b=0 local c=tostring(a)local d=c:find"%."if d then b=#c-d end local g="%."..b.."f"return{snap=function(b)b=math.floor(b/a+.5)*a return math.clamp(b,e,f)end,format=function(a)if math.abs(a)>=1e15 then return string.format("%.2e",a)end return string.format(g,a)end}end local function B(f,g,i,k)local d={Size=UDim2.new(1,0,0,i),BackgroundColor3=a.Surface2,BorderSizePixel=0,LayoutOrder=f:_nextOrder(),Parent=f.List}if g=="TextButton"then d.AutoButtonColor=false d.Text=""end local b=c(g,d)b:SetAttribute("NoDrag",true)e(b)local j=h(b,a.Stroke)return b,j end local function G(b,f,g,c)local e,h if g then local j=(v-38)/2 e=d{Position=UDim2.fromOffset(14,j),Size=UDim2.new(1,-(14+c),0,18),Text=f,Parent=b}h=d{Position=UDim2.fromOffset(14,j+20),Size=UDim2.new(1,-(14+c),0,17),Text=g,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=b}else e=d{Position=UDim2.fromOffset(14,0),Size=UDim2.new(1,-(14+c),1,0),Text=f,Parent=b}end return e,h end local function z(h,a,i,j,c,k)a=l(a,i)local d=a.Desc and v or K local b,e=B(h,j or"Frame",d,a)F(b,e)local f,g if c then f,g=G(b,a.Name or k,a.Desc,c)end return a,b,e,d,f,g end local function H(a,b,c)if a then a.Size=UDim2.new(1,-(14+c),a.Size.Y.Scale,a.Size.Y.Offset)end if b then b.Size=UDim2.new(1,-(14+c),0,b.Size.Y.Offset)end end local j={}j.__index=j function j:_nextOrder()self._order+=1 return self._order end function j:Section(b)if type(b)=="table"then b=b.Name or b.Title or""end local f=c("Frame",{Size=UDim2.new(1,0,0,28),BackgroundTransparency=1,LayoutOrder=self:_nextOrder(),Parent=self.List})local e=d{Position=UDim2.fromOffset(2,8),Size=UDim2.new(0,0,0,16),AutomaticSize=Enum.AutomaticSize.X,Text=string.upper(b),TextSize=12,TextColor3=a.Muted,TextTruncate=Enum.TextTruncate.None,Parent=f}local g=c("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,0,16),Size=UDim2.new(1,-12,0,1),BackgroundColor3=a.Stroke,BorderSizePixel=0,Parent=f})e:GetPropertyChangedSignal"AbsoluteSize":Connect(function()g.Size=UDim2.new(1,-(e.AbsoluteSize.X+14),0,1)end)task.defer(function()g.Size=UDim2.new(1,-(e.AbsoluteSize.X+14),0,1)end)return n(self,{},{Set=function(b,a)e.Text=string.upper(a)end},f,"Section")end function j:Divider()local b=c("Frame",{Size=UDim2.new(1,0,0,1),BackgroundColor3=a.Stroke,BorderSizePixel=0,LayoutOrder=self:_nextOrder(),Parent=self.List})return n(self,{},{},b,"Divider")end function j:Label(b)b=l(b,{Name="Text",Title="Text"})local c=d{Size=UDim2.new(1,0,0,18),Text=b.Text or"",TextSize=13,FontFace=i.Regular,TextColor3=b.Color or a.Muted,LayoutOrder=self:_nextOrder(),Parent=self.List}o(c,2)local e={Set=function(b,a)c.Text=tostring(a)end,Get=function()return c.Text end}if type(b.Update)=="function"then local a,d=math.max(tonumber(b.UpdateRate)or 1,.05),true e._listeners=e._listeners or{}table.insert(e._listeners,function()d=false end)task.spawn(function()while d and c.Parent do local e,d=pcall(b.Update)if e and d~=nil then c.Text=tostring(d)elseif not e then warn("[AirFlow] label update error: "..tostring(d))end task.wait(a)end end)function e:SetUpdateRate(b)a=math.max(tonumber(b)or a,.05)end end return n(self,b,e,c,"Label")end function j:Paragraph(b)b=l(b,{Title="Name"})local e=B(self,"Frame",0,b)e.AutomaticSize=Enum.AutomaticSize.Y o(e,14,14,11,12)c("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=e})d{Size=UDim2.new(1,0,0,14),Text=b.Name or"",LayoutOrder=1,Parent=e}local f=d{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=b.Content or"",TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,TextWrapped=true,TextTruncate=Enum.TextTruncate.None,TextYAlignment=Enum.TextYAlignment.Top,LayoutOrder=2,Parent=e}return n(self,b,{Set=function(b,a)f.Text=a end},e,"Paragraph")end function j:Button(d)d=l(d,{Title="Name",Description="Desc"})local e=d.Style=="Primary"local h=d.Desc and v or K local c,f=B(self,"TextButton",h,d)c.ClipsDescendants=true if e then c.BackgroundColor3=a.Accent c.BackgroundTransparency=.12 f.Color=a.Accent f.Transparency=.4 c.MouseEnter:Connect(function()b(c,{BackgroundTransparency=0},.12)b(f,{Transparency=0},.12)end)c.MouseLeave:Connect(function()b(c,{BackgroundTransparency=.12},.25)b(f,{Transparency=.4},.25)end)else F(c,f)end local i,g=e and a.AccentDark or a.Text,0 if d.Icon then y(c,d.Icon,e and a.AccentDark or a.Accent,UDim2.new(0,14,.5,0))g=26 end local j=G(c,d.Name or"Button",d.Desc,30)if g>0 then for b,a in ipairs(c:GetChildren())do if a:IsA"TextLabel"then a.Position+=UDim2.fromOffset(g,0)a.Size-=UDim2.fromOffset(g,0)end end end if e then for b,a in ipairs(c:GetChildren())do if a:IsA"TextLabel"then a.TextColor3=i end end end y(c,"chevron-right",e and a.AccentDark or a.Muted,UDim2.new(1,-30,.5,0))c.MouseButton1Click:Connect(function()ah(c)k(d.Callback)end)return n(self,d,{SetText=function(b,a)j.Text=a end},c,"Button")end function j:Toggle(f)local i,o f,i,o=z(self,f,{Title="Name",Description="Desc",CurrentValue="Default",Value="Default"},"TextButton",56,"Toggle")local g=c("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,0),Size=m and UDim2.fromOffset(44,24)or UDim2.fromOffset(36,20),BackgroundColor3=a.Surface3,BorderSizePixel=0,Parent=i})e(g,UDim.new(1,0))h(g,a.Stroke)local j=c("Frame",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,3,.5,0),Size=m and UDim2.fromOffset(18,18)or UDim2.fromOffset(14,14),BackgroundColor3=a.Muted,BorderSizePixel=0,Parent=g})e(j,UDim.new(1,0))local q=c("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(1,24,1,24),BackgroundTransparency=1,Image=t.Glow,ImageColor3=a.Accent,ImageTransparency=1,ZIndex=0,Parent=g})local d={Value=f.Default==true}local function p(h)local e=d.Value local f=h and.25 or 0 b(g,{BackgroundColor3=e and a.Accent or a.Surface3},f)b(q,{ImageTransparency=e and.75 or 1},f)local c=m and 18 or 14 b(j,{Position=e and UDim2.new(0,(m and 44 or 36)-3-c,.5,0)or UDim2.new(0,3,.5,0),BackgroundColor3=e and a.AccentDark or a.Muted},f,Enum.EasingStyle.Back)if h then b(j,{Size=UDim2.fromOffset(c+4,c-2)},.08)task.delay(.08,function()b(j,{Size=UDim2.fromOffset(c,c)},.2,Enum.EasingStyle.Back)end)end end local l=false function d:Set(a,b)a=a==true if a==d.Value then return end d.Value=a p(true)if not l then w(o)end if not b then k(f.Callback,a)end end function d:Get()return d.Value end p(false)i.MouseButton1Click:Connect(function()l=true d:Set(not d.Value)l=false end)local r=n(self,f,d,i,"Toggle")if d.Value then k(f.Callback,true)end return r end function j:Slider(g)local C="Frame"g=l(g,{Title="Name",Description="Desc",CurrentValue="Default",Value="Default",Increment="Step"})local o=g.Min or 0 local D=g.Max or 100 local V=g.Step or 1 local I=g.Suffix or""local J=aa(o,D,V)local y,Q=B(self,C,v,g)F(y,Q)d{Position=UDim2.fromOffset(14,12),Size=UDim2.new(1,-120,0,18),Text=g.Name or"Slider",Parent=y}local q=c(C,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,9),Size=UDim2.fromOffset(40,24),BackgroundColor3=a.Surface,BorderSizePixel=0,ClipsDescendants=true,Parent=y})e(q,UDim.new(0,6))local K=h(q)local z=d{Size=UDim2.new(1,0,1,0),TextSize=13,TextColor3=a.Accent,TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.None,Parent=q}local j=c("TextBox",{Position=UDim2.fromOffset(9,0),Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,BackgroundTransparency=1,Text="",TextColor3=a.Text,TextSize=13,FontFace=i.Medium,TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,Visible=false,Parent=q})c("UISizeConstraint",{MinSize=Vector2.new(14,0),Parent=j})local L=d{Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,Text=I,TextSize=13,TextColor3=a.Accent,TextTruncate=Enum.TextTruncate.None,Visible=false,Parent=q}local E,G=c("TextButton",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=2,Parent=q}),false local function H(c)local a if G then a=9+j.AbsoluteSize.X/self.Window.Scale.Scale+L.TextBounds.X+9 L.Position=UDim2.fromOffset(9+j.AbsoluteSize.X/self.Window.Scale.Scale,0)else a=z.TextBounds.X+18 end a=math.max(a,36)if c then q.Size=UDim2.fromOffset(a,24)else b(q,{Size=UDim2.fromOffset(a,24)},.2)end end z:GetPropertyChangedSignal"TextBounds":Connect(function()if not G then H(false)end end)j:GetPropertyChangedSignal"AbsoluteSize":Connect(function()if G then H(false)end end)local u=c(C,{Position=UDim2.new(0,14,0,v-18),Size=UDim2.new(1,-28,0,5),BackgroundColor3=a.Surface3,BorderSizePixel=0,Parent=y})e(u,UDim.new(1,0))local R=c(C,{Size=UDim2.new(0,0,1,0),BackgroundColor3=a.Accent,BorderSizePixel=0,Parent=u})e(R,UDim.new(1,0))local x=c("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(0,0,.5,0),Size=UDim2.fromOffset(28,28),BackgroundTransparency=1,Image=t.Glow,ImageColor3=a.Accent,ImageTransparency=.85,ZIndex=2,Parent=u})local A=c(C,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(0,0,.5,0),Size=UDim2.fromOffset(12,12),BackgroundColor3=a.Accent,BorderSizePixel=0,ZIndex=3,Parent=u})e(A,UDim.new(1,0))local O=c("TextButton",{Position=UDim2.new(0,8,0,v-(m and 37 or 31)),Size=UDim2.new(1,-16,0,m and 40 or 28),BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=4,Parent=y})local f,s={Value=math.clamp(g.Default or o,o,D)},false E.MouseEnter:Connect(function()b(K,{Color=a.StrokeHover},.12)end)E.MouseLeave:Connect(function()if not j:IsFocused()then b(K,{Color=a.Stroke},.2)end end)E.MouseButton1Click:Connect(function()G=true j.Text=J.format(f.Value)z.Visible=false j.Visible=true L.Visible=I~=""E.Visible=false b(K,{Color=a.StrokeHover},.12)j:CaptureFocus()task.defer(H,false)end)j.FocusLost:Connect(function()local c=tonumber(j.Text)G=false j.Visible=false L.Visible=false z.Visible=true E.Visible=true b(K,{Color=a.Stroke},.2)if c then f:Set(c)end H(false)end)O.MouseEnter:Connect(function()if not s then b(x,{ImageTransparency=.78,Size=UDim2.fromOffset(34,34)},.15)end end)O.MouseLeave:Connect(function()if not s then b(x,{ImageTransparency=.85,Size=UDim2.fromOffset(28,28)},.2)end end)local S=J.snap local function M()return D-o==0 and 0 or(f.Value-o)/(D-o)end local function P(c,d,a)a=a or Enum.EasingStyle.Linear b(R,{Size=UDim2.new(c,0,1,0)},d,a)b(A,{Position=UDim2.new(c,0,.5,0)},d,a)b(x,{Position=UDim2.new(c,0,.5,0)},d,a)end local function T(a,b)P(M(),a,b)z.Text=J.format(f.Value)..I end local function W(b)local a=M()local c=math.max(u.AbsoluteSize.X,1)local d=(a>=b and 1 or-1)*(5/c)P(math.clamp(a+d,0,1),.22,Enum.EasingStyle.Quint)task.delay(.22,function()if not s then P(M(),.18,Enum.EasingStyle.Quint)end end)z.Text=J.format(f.Value)..I end local function X()b(A,{Size=UDim2.fromOffset(14,12)},.08)b(x,{Size=UDim2.fromOffset(32,32),ImageTransparency=.78},.12)task.delay(.1,function()b(A,{Size=UDim2.fromOffset(12,12)},.25,Enum.EasingStyle.Quint)b(x,{Size=UDim2.fromOffset(28,28),ImageTransparency=.85},.25)end)end function f:Set(a,b)a=S(tonumber(a)or o)if a==f.Value then return end local c=M()f.Value=a if s then T(.05)else W(c)X()w(Q)end if not b then k(g.Callback,a)end end function f:Get()return f.Value end local function U(a)local b=math.clamp((a-u.AbsolutePosition.X)/u.AbsoluteSize.X,0,1)f:Set(o+(D-o)*b)end O.InputBegan:Connect(function(a)if p(a)then s=true b(A,{Size=UDim2.fromOffset(16,16)},.15,Enum.EasingStyle.Back)b(x,{Size=UDim2.fromOffset(44,44),ImageTransparency=.7},.15)U(r().X)end end)self.Window:_listen("Changed",function(a)if s and N(a)then U(r().X)end end,f)self.Window:_listen("Ended",function(a)if s and p(a)then s=false b(A,{Size=UDim2.fromOffset(12,12)},.2)b(x,{Size=UDim2.fromOffset(28,28),ImageTransparency=.85},.2)end end,f)f.Value=S(f.Value)T(0)task.defer(H,true)return n(self,g,f,y,"Slider")end function j:Dropdown(f)local y="Frame"f=l(f,{Title="Name",Description="Desc",CurrentOption="Default",Value="Default",MultipleOptions="Multi",Values="Options"})if f.Multi and type(f.Default)~="table"and f.Default~=nil then f.Default={f.Default}elseif not f.Multi and type(f.Default)=="table"then f.Default=f.Default[1]end local r=f.Multi==true local o=f.Options or{}local p,O,v f,p,O,v=z(self,f,{},y)p.ClipsDescendants=true local I=c("TextButton",{Size=UDim2.new(1,0,0,v),BackgroundTransparency=1,Text="",AutoButtonColor=false,Parent=p})local S,T=G(I,f.Name or"Dropdown",f.Desc,180)local q=c(y,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(60,s),BackgroundColor3=a.Surface,BorderSizePixel=0,ClipsDescendants=true,Parent=I})e(q,UDim.new(0,6))local U=h(q)local J=d{Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-34,1,0),TextColor3=a.Muted,TextSize=13,TextTruncate=Enum.TextTruncate.None,ClipsDescendants=true,Parent=q}local V=Z(q,1,-6)local A,x=d{Size=UDim2.fromOffset(0,s),AutomaticSize=Enum.AutomaticSize.X,TextSize=13,Visible=false,Parent=q},""local function W()A.Text=x if A.TextBounds.X<=146 then return x end local a=x while#a>1 do a=a:sub(1,-2)A.Text=a..".."if A.TextBounds.X<=146 then return a..".."end end return".."end local function P(c)local a=math.clamp(J.TextBounds.X+10+34,60,190)H(S,T,a+20)if c then q.Size=UDim2.fromOffset(a,s)else b(q,{Size=UDim2.fromOffset(a,s)},.2)end end J:GetPropertyChangedSignal"TextBounds":Connect(function()P(false)end)local K=c(y,{Position=UDim2.new(0,10,0,v),Size=UDim2.new(1,-20,0,0),BackgroundTransparency=1,Parent=p})c("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=K})local g={Open=false}local j={}local m,B={},""local X=f.SearchAfter or 6 local t=c(y,{Size=UDim2.new(1,0,0,L),BackgroundColor3=a.Surface,BackgroundTransparency=1,BorderSizePixel=0,LayoutOrder=0,Visible=false,Parent=K})e(t,UDim.new(0,6))local Y=h(t,a.Stroke,1)local C=c("TextBox",{Position=UDim2.fromOffset(12,0),Size=UDim2.new(1,-20,1,0),BackgroundTransparency=1,Text="",PlaceholderText="Search",PlaceholderColor3=a.Muted,TextColor3=a.Text,TextSize=13,FontFace=i.Regular,TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,TextTransparency=1,Parent=t})local function Q(a)return B==""or string.find(string.lower(tostring(a)),B,1,true)~=nil end if r then for b,a in ipairs(f.Default or{})do j[a]=true end elseif f.Default~=nil then j[f.Default]=true end local function D()if r then local a={}for c,b in ipairs(o)do if j[b]then table.insert(a,b)end end return a end for b,a in ipairs(o)do if j[a]then return a end end return nil end local function E()local c=D()if r then x=#c>0 and table.concat(c,", ")or"None"else x=c~=nil and tostring(c)or"None"end J.Text=W()for e,d in pairs(m)do local c=j[e]==true if d.On~=c then d.On=c b(d.Label,{TextColor3=c and a.Text or a.Muted},.15)if g.Open then b(d.Check,{ImageTransparency=c and 0 or 1},.15)b(d.CheckScale,{Scale=c and 1 or.6},c and.3 or.15,c and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)end end end end local function aa()local a=0 for c,b in ipairs(o)do if Q(b)then a+=1 end end return a end local function M()for a,b in pairs(m)do b.Frame.Visible=Q(a)end end local function N()local a=aa()+(t.Visible and 1 or 0)return v+a*(L+4)+8 end local function F(c)g.Open=c t.Visible=#o>X if not c then B=""C.Text=""M()end b(p,{Size=UDim2.new(1,0,0,c and N()or v)},.3,Enum.EasingStyle.Quint)b(t,{BackgroundTransparency=c and 0 or 1},.2)b(Y,{Transparency=c and 0 or 1},.2)b(C,{TextTransparency=c and 0 or 1},.2)V:Set(c)b(U,{Color=c and a.StrokeHover or a.Stroke},.2)local function d(d)if not d.Stroke then d.Stroke=h(d.Frame,a.Stroke,1)end local e=c and d.On b(d.Check,{ImageTransparency=e and 0 or 1},.18)d.CheckScale.Scale=e and 1 or.6 b(d.Label,{TextTransparency=c and 0 or 1},.18)b(d.Stroke,{Transparency=c and 0 or 1},.18)b(d.Frame,{BackgroundTransparency=c and 0 or 1},.18)end if c then local a=(g._openGeneration or 0)+1 g._openGeneration=a task.spawn(function()local b=true for f,e in ipairs(o)do local c=m[e]if c and c.Frame.Visible then if not b then task.wait(.025)if g._openGeneration~=a or not g.Open then return end end b=false d(c)end end end)else local b=(g._openGeneration or 0)+1 g._openGeneration=b local a={}for d,c in ipairs(o)do local b=m[c]if b and b.Frame.Visible then table.insert(a,b)end end task.spawn(function()for c=#a,1,-1 do d(a[c])if c>1 then task.wait(.015)if g._openGeneration~=b or g.Open then return end end end end)end end local function R()local h={}for a,b in ipairs(o)do h[b]=a end for a,b in pairs(m)do if not h[a]then b.Frame:Destroy()m[a]=nil end end for n,g in ipairs(o)do local o=m[g]if o then o.Frame.LayoutOrder=n continue end local h=c("TextButton",{Size=UDim2.new(1,0,0,L),BackgroundColor3=a.Surface,BackgroundTransparency=1,Text="",AutoButtonColor=false,LayoutOrder=n,Parent=K})e(h,UDim.new(0,6))local i=c("ImageLabel",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(14,14),BackgroundTransparency=1,ImageColor3=a.Accent,ImageTransparency=1,ScaleType=Enum.ScaleType.Fit,Parent=h})u(i,"check")local p=c("UIScale",{Scale=.6,Parent=i})local l=d{Position=UDim2.fromOffset(12,-1),Size=UDim2.new(1,-36,1,0),Text=tostring(g),TextSize=13,TextColor3=a.Muted,TextTransparency=1,Parent=h}h.MouseEnter:Connect(function()b(l,{TextColor3=a.Text},.15)local c=m[g]if c and c.Stroke then b(c.Stroke,{Color=a.StrokeHover},.12)end end)h.MouseLeave:Connect(function()b(l,{TextColor3=j[g]and a.Text or a.Muted},.2)local c=m[g]if c and c.Stroke then b(c.Stroke,{Color=a.Stroke},.2)end end)h.MouseButton1Click:Connect(function()if j[g]then j[g]=nil else if not r then j={}end j[g]=true end E()k(f.Callback,D())if not r and j[g]then F(false)end end)m[g]={Frame=h,Label=l,Check=i,CheckScale=p,Stroke=nil,On=nil}end M()if g.Open then p.Size=UDim2.new(1,0,0,N())end end function g:Set(a,b)j={}if r then for b,a in ipairs(type(a)=="table"and a or{a})do j[a]=true end elseif a~=nil then j[a]=true end E()w(O)if not b then k(f.Callback,D())end end function g:Get()return D()end function g:Refresh(a,b)o=a or{}if not b then j={}end R()E()if g.Open then F(true)end end function g:SetOpen(a)F(a==true)end I.MouseButton1Click:Connect(function()F(not g.Open)end)C:GetPropertyChangedSignal"Text":Connect(function()B=string.lower(C.Text)M()if g.Open then b(p,{Size=UDim2.new(1,0,0,N())},.2,Enum.EasingStyle.Quint)end end)R()E()task.defer(P,true)return n(self,f,g,p,"Dropdown")end function j:Input(f)local l,p,t,q,r f,l,p,t,q,r=z(self,f,{Title="Name",Description="Desc",PlaceholderText="Placeholder",CurrentValue="Default",Value="Default"},"Frame",160,"Input")local g=c("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(170,30),BackgroundColor3=a.Surface,BorderSizePixel=0,Parent=l})e(g,UDim.new(0,6))local s=h(g)local m=f.Icon if m then y(g,m,a.Muted,UDim2.new(0,8,.5,0))end local d=c("TextBox",{Position=UDim2.fromOffset(m and 30 or 8,0),Size=UDim2.new(1,m and-38 or-16,1,0),BackgroundTransparency=1,Text=f.Default or"",PlaceholderText=f.Placeholder or"",PlaceholderColor3=a.Muted,TextColor3=a.Text,TextSize=14,FontFace=i.Regular,TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,TextTruncate=Enum.TextTruncate.None,ClipsDescendants=true,Parent=g})g.ClipsDescendants=true local o=false local u=(m and 30 or 8)+8 local function j(f)local h=l.AbsoluteSize.X/self.Window.Scale.Scale local c=math.clamp(h-14-110-20,100,200)local i=d.Text local e=d.TextBounds.X if#i==0 then e=math.min(d.TextBounds.X,90)end local a=math.clamp(e+u+12,90,c)+(o and 8 or 0)a=math.min(a,c+8)H(q,r,a+20)if f then g.Size=UDim2.fromOffset(a,30)else b(g,{Size=UDim2.fromOffset(a,30)},.18)end end l:GetPropertyChangedSignal"AbsoluteSize":Connect(function()j(true)end)d:GetPropertyChangedSignal"Text":Connect(function()j(false)end)d:GetPropertyChangedSignal"TextBounds":Connect(function()j(false)end)task.defer(j,true)d.Focused:Connect(function()o=true b(s,{Color=a.StrokeHover},.15)j(false)end)d.FocusLost:Connect(function(c)o=false b(s,{Color=a.Stroke},.15)j(false)if f.Numeric then local a=tonumber(d.Text)if not a then d.Text=""return end end k(f.Callback,d.Text,c)end)return n(self,f,{Set=function(b,a)d.Text=tostring(a)w(p)end,Get=function()return d.Text end},l,"Input")end function j:Keybind(g)local o,p,u,q,r g,o,p,u,q,r=z(self,g,{Title="Name",Description="Desc",CurrentKeybind="Default",Value="Default"},"Frame",110,"Keybind")if type(g.Default)=="string"then g.Default=Enum.KeyCode[g.Default]end local i=c("TextButton",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(44,s),BackgroundColor3=a.Surface,BorderSizePixel=0,Text="",AutoButtonColor=false,ClipsDescendants=true,Parent=o})e(i,UDim.new(0,6))local v=h(i)local j=d{Size=UDim2.new(1,0,1,0),TextSize=13,TextColor3=a.Muted,TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.None,Parent=i}local f={Value=g.Default,Listening=false}local function t(c)local a=math.max(j.TextBounds.X+20,m and 44 or 36)H(q,r,a+20)if c then i.Size=UDim2.fromOffset(a,s)else b(i,{Size=UDim2.fromOffset(a,s)},.2)end end j:GetPropertyChangedSignal"TextBounds":Connect(function()t(false)end)local function l()j.Text=f.Listening and"..."or P(f.Value)b(v,{Color=f.Listening and a.StrokeHover or a.Stroke},.15)b(j,{TextColor3=f.Listening and a.Accent or a.Muted},.15)end function f:Set(a,b)local c=f.Listening f.Value=a f.Listening=false l()if not c then w(p)end if not b then k(g.OnChanged,a)end end i.MouseButton1Click:Connect(function()f.Listening=not f.Listening l()end)self.Window:_listen("Began",function(a,b)if a.UserInputType~=Enum.UserInputType.Keyboard then return end if f.Listening then self.Window._consumedKey=a.KeyCode self.Window._consumedAt=os.clock()if a.KeyCode==Enum.KeyCode.Escape then f.Listening=false l()else f:Set(a.KeyCode)end return end if not b and f.Value~=nil and a.KeyCode==f.Value then k(g.Callback,a.KeyCode)end end,f)l()task.defer(t,true)function f:Get()return f.Value end return n(self,g,f,o,"Keybind")end function j:ColorPicker(j)local D,l,E,F="Default","Frame","TextButton","UIGradient"local m,K,u j,m,K,u=z(self,j,{Title="Name",Description="Desc",Color=D,CurrentValue=D,Value=D},l)m.ClipsDescendants=true local A=c(E,{Size=UDim2.new(1,0,0,u),BackgroundTransparency=1,Text="",AutoButtonColor=false,Parent=m})G(A,j.Name or"Color",j.Desc,90)local H=c(l,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-34,.5,0),Size=UDim2.fromOffset(36,20),BorderSizePixel=0,Parent=A})e(H,UDim.new(0,6))h(H,a.Stroke)local S=Z(A,1,-12)local o=c(l,{Position=UDim2.fromOffset(14,u+2),Size=UDim2.new(1,-28,0,156),BackgroundTransparency=1,Visible=false,Parent=m})local g=c(E,{Size=UDim2.new(1,-30,0,110),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Text="",AutoButtonColor=false,ClipsDescendants=true,Parent=o})e(g,UDim.new(0,6))local T=c(F,{Color=ColorSequence.new(Color3.new(1,1,1),Color3.new(1,0,0)),Parent=g})local U=c(l,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0,Parent=g})c(F,{Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)},Rotation=90,Parent=U})local v=c(l,{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(10,10),BackgroundTransparency=1,ZIndex=3,Parent=g})e(v,UDim.new(1,0))h(v,Color3.new(1,1,1),0,2)local q=c(E,{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(14,110),BorderSizePixel=0,Text="",AutoButtonColor=false,Parent=o})e(q,UDim.new(0,6))c(F,{Color=ColorSequence.new{ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),ColorSequenceKeypoint.new(.16666666666666666,Color3.fromRGB(255,255,0)),ColorSequenceKeypoint.new(.3333333333333333,Color3.fromRGB(0,255,0)),ColorSequenceKeypoint.new(.5,Color3.fromRGB(0,255,255)),ColorSequenceKeypoint.new(.6666666666666666,Color3.fromRGB(0,0,255)),ColorSequenceKeypoint.new(.8333333333333334,Color3.fromRGB(255,0,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0))},Rotation=90,Parent=q})local x=c(l,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,0,0),Size=UDim2.fromOffset(18,5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,ZIndex=3,Parent=q})e(x,UDim.new(1,0))h(x,a.AccentDark,.4)local I=c(l,{Position=UDim2.fromOffset(6,122),Size=UDim2.fromOffset(118,28),BackgroundColor3=a.Surface,BorderSizePixel=0,Parent=o})e(I,UDim.new(0,6))local L=h(I)local s=c("TextBox",{Position=UDim2.fromOffset(14,0),Size=UDim2.new(1,-24,1,0),BackgroundTransparency=1,Text="",TextTruncate=Enum.TextTruncate.None,ClipsDescendants=false,TextColor3=a.Text,TextSize=13,FontFace=i.Regular,TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,Parent=I})local V=d{Position=UDim2.fromOffset(134,122),Size=UDim2.new(1,-134,0,28),TextXAlignment=Enum.TextXAlignment.Right,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=o}local f={Open=false}local y,B,C=Color3.toHSV(j.Default or a.Accent)local t local function M(a)return string.format("#%02X%02X%02X",math.floor(a.R*255+.5),math.floor(a.G*255+.5),math.floor(a.B*255+.5))end local function O(c)local a=Color3.fromHSV(y,B,C)f.Value=a H.BackgroundColor3=a T.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromHSV(y,1,1))b(v,{Position=UDim2.fromScale(B,1-C)},c,Enum.EasingStyle.Linear)b(x,{Position=UDim2.new(.5,0,y,0)},c,Enum.EasingStyle.Linear)if not s:IsFocused()then s.Text=M(a)end V.Text=string.format("RGB %d, %d, %d",math.floor(a.R*255+.5),math.floor(a.G*255+.5),math.floor(a.B*255+.5))end local function J(a,b)O(a)if not b then k(j.Callback,f.Value)end end function f:Set(a,b)y,B,C=Color3.toHSV(a)J(.25,b)w(K)end function f:Get()return f.Value end local function P(a)f.Open=a b(m,{Size=UDim2.new(1,0,0,a and u+168 or u)},.35,Enum.EasingStyle.Quint)S:Set(a)if a then o.Visible=true else task.delay(.35,function()if not f.Open then o.Visible=false end end)end end function f:SetOpen(a)P(a==true)end A.MouseButton1Click:Connect(function()P(not f.Open)end)local function Q(a)B=math.clamp((a.X-g.AbsolutePosition.X)/g.AbsoluteSize.X,0,1)C=1-math.clamp((a.Y-g.AbsolutePosition.Y)/g.AbsoluteSize.Y,0,1)J(.04)end local function R(a)y=math.clamp((a.Y-q.AbsolutePosition.Y)/q.AbsoluteSize.Y,0,.999)J(.04)end g.InputBegan:Connect(function(a)if p(a)then t="sv"b(v,{Size=UDim2.fromOffset(14,14)},.15,Enum.EasingStyle.Back)Q(r())end end)q.InputBegan:Connect(function(a)if p(a)then t="hue"b(x,{Size=UDim2.fromOffset(20,7)},.15,Enum.EasingStyle.Back)R(r())end end)self.Window:_listen("Changed",function(b)if not t or not N(b)then return end local a=r()if t=="sv"then Q(a)else R(a)end end,f)self.Window:_listen("Ended",function(a)if t and p(a)then t=nil b(v,{Size=UDim2.fromOffset(10,10)},.2)b(x,{Size=UDim2.fromOffset(18,5)},.2)end end,f)s.Focused:Connect(function()b(L,{Color=a.StrokeHover},.15)end)s.FocusLost:Connect(function()b(L,{Color=a.Stroke},.15)local c,d,e=s.Text:match"^%s*#?(%x%x)(%x%x)(%x%x)%s*$"if c then f:Set(Color3.fromRGB(tonumber(c,16),tonumber(d,16),tonumber(e,16)))else s.Text=M(f.Value)end end)O(0)return n(self,j,f,m,"ColorPicker")end function j:Stepper(g)local o,t,J,u,v g,o,t,J,u,v=z(self,g,{Title="Name",Description="Desc",CurrentValue="Default",Value="Default",Increment="Step"},"Frame",150,"Stepper")local l=g.Min or 0 local q=g.Max or 100 local x=g.Step or 1 local K=g.Suffix or""local y=aa(l,q,x)local j=c("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-10,.5,0),Size=UDim2.fromOffset(0,s),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=a.Surface,BorderSizePixel=0,Parent=o})e(j,UDim.new(0,6))local A=h(j)c("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Center,Parent=j})local function B(e,f)local d=c("TextButton",{Size=UDim2.fromOffset(s,s),BackgroundTransparency=1,Text=e,TextColor3=a.Muted,TextSize=18,FontFace=i.Medium,AutoButtonColor=false,LayoutOrder=f,Parent=j})d.MouseEnter:Connect(function()b(d,{TextColor3=a.Accent},.12)end)d.MouseLeave:Connect(function()b(d,{TextColor3=a.Muted},.2)end)return d end local C=B("−",1)local m=d{Size=UDim2.new(0,30,1,0),TextSize=13,TextColor3=a.Accent,TextXAlignment=Enum.TextXAlignment.Center,TextTruncate=Enum.TextTruncate.None,LayoutOrder=2,Parent=j}local D=B("+",3)local function E(c)local a=math.max(m.TextBounds.X+12,30)if c then m.Size=UDim2.new(0,a,1,0)else b(m,{Size=UDim2.new(0,a,1,0)},.2)end end m:GetPropertyChangedSignal"TextBounds":Connect(function()E(false)end)j:GetPropertyChangedSignal"AbsoluteSize":Connect(function()H(u,v,j.AbsoluteSize.X/self.Window.Scale.Scale+20)end)local f={Value=math.clamp(g.Default or l,l,q)}local L,r=y.snap,false local function F()m.Text=y.format(f.Value)..K b(C,{TextTransparency=f.Value<=l and.6 or 0},.15)b(D,{TextTransparency=f.Value>=q and.6 or 0},.15)end function f:Set(a,b)a=L(tonumber(a)or l)if a==f.Value then return end f.Value=a F()if not r then w(t)end if not b then k(g.Callback,a)end end function f:Get()return f.Value end local function G(c)r=true f:Set(f.Value+c*x)r=false b(A,{Color=a.StrokeHover},.08)task.delay(.12,function()b(A,{Color=a.Stroke},.2)end)end local function I(b,c)local a=false b.InputBegan:Connect(function(b)if not p(b)then return end a=true G(c)task.delay(.4,function()while a do G(c)task.wait(.07)end end)end)b.InputEnded:Connect(function(b)if p(b)then a=false end end)b.MouseLeave:Connect(function()a=false end)end I(C,-1)I(D,1)F()task.defer(E,true)return n(self,g,f,o,"Stepper")end function j:Progress(f)f=l(f,{Title="Name",Description="Desc",CurrentValue="Default",Value="Default"})local h,s=B(self,"Frame",f.Desc and v+10 or K+10,f)F(h,s)local j=f.Desc and(v-38)/2-2 or 12 d{Position=UDim2.fromOffset(14,j),Size=UDim2.new(1,-110,0,18),Text=f.Name or"Progress",Parent=h}if f.Desc then d{Position=UDim2.fromOffset(14,j+20),Size=UDim2.new(1,-110,0,17),Text=f.Desc,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=h}end local o=d{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,j),Size=UDim2.fromOffset(90,18),TextXAlignment=Enum.TextXAlignment.Right,TextSize=13,TextColor3=a.Accent,Parent=h}local p=c("Frame",{Position=UDim2.new(0,14,1,-16),Size=UDim2.new(1,-28,0,5),BackgroundColor3=a.Surface3,BorderSizePixel=0,Parent=h})e(p,UDim.new(1,0))local m=c("Frame",{Size=UDim2.new(0,0,1,0),BackgroundColor3=f.Color or a.Accent,BorderSizePixel=0,Parent=p})e(m,UDim.new(1,0))local g={Value=math.clamp(f.Default or 0,0,1)}local q=f.Format local function r(c)local a=g.Value b(m,{Size=UDim2.new(a,0,1,0)},c,Enum.EasingStyle.Quint)if type(q)=="function"then o.Text=tostring(q(a))else o.Text=string.format("%d%%",math.floor(a*100+.5))end end function g:Set(a,b)a=math.clamp(tonumber(a)or 0,0,1)if a==g.Value then return end g.Value=a r(.35)if not b then k(f.Callback,a)end end function g:Get()return g.Value end function g:SetColor(a)m.BackgroundColor3=a end r(0)return n(self,f,g,h,"Progress")end function j:ConfigManager(d)d=l(d,{})local a=self.Window local b={}self:Section(d.Name or"Configs")local e=self:Input{Name="Config name",Placeholder=a.ConfigName,Callback=function(a,c)if c and#a>0 then b:Save(a)end end}local c=self:Dropdown{Name="Saved configs",Options=a:ListConfigs(),Default=a.ConfigName,Callback=function(a)if a then e:Set(a)end end}function b:Refresh()c:Refresh(a:ListConfigs(),true)end function b:Save(d)d=d or c:Get()or a.ConfigName local e,f=a:SaveConfig(d)b:Refresh()c:Set(d,true)a:Notify{Title=e and"Config saved"or"Save failed",Content=e and d or tostring(f),Type=e and"Success"or"Error",Duration=3}end function b:Load(b)b=b or c:Get()if not b then return end local d,e=a:LoadConfig(b)a:Notify{Title=d and"Config loaded"or"Load failed",Content=d and b or tostring(e),Type=d and"Success"or"Error",Duration=3}end function b:Delete(d)d=d or c:Get()if not d then return end local e,f=a:DeleteConfig(d)b:Refresh()a:Notify{Title=e and"Config deleted"or"Delete failed",Content=e and d or tostring(f),Type=e and"Info"or"Error",Duration=3}end self:Button{Name="Save",Desc="Writes every flagged element to the selected name",Icon="save",Style="Primary",Callback=function()local a=e:Get()b:Save(#a>0 and a or nil)end}self:Button{Name="Load",Icon="folder-open",Callback=function()b:Load()end}self:Button{Name="Delete",Icon="trash-2",Callback=function()local d=c:Get()if not d then return end a:Confirm{Title="Delete config",Content="Remove "..d.."? This cannot be undone.",Icon="trash-2",ConfirmText="Delete",Callback=function()b:Delete(d)end}end}self:Toggle{Name="Auto save",Desc="Save whenever a flagged element changes",Default=a._autoSaveEnabled,Callback=function(b)a._autoSaveEnabled=b end}return b end for a,b in pairs(table.clone(j))do if type(b)=="function"and a:sub(1,1)~="_"and a:sub(1,6)~="Create"then j["Create"..a]=b end end local function aj()local a pcall(function()if typeof(identifyexecutor)=="function"then a=(identifyexecutor())elseif typeof(getexecutorname)=="function"then a=getexecutorname()end end)if type(a)=="string"and#a>0 then return a end return U:IsStudio()and"Studio"or"Unknown"end local function ak()local b,a=pcall(function()return game:GetService"MarketplaceService":GetProductInfo(game.PlaceId)end)if b and type(a)=="table"and a.Name then return a.Name end return"Unknown game"end local al={US="United States",GB="United Kingdom",DE="Germany",FR="France",NL="Netherlands",SG="Singapore",JP="Japan",AU="Australia",BR="Brazil",IN="India",HK="Hong Kong",CA="Canada"}local function am(a)task.spawn(function()local b=request or http_request or syn and syn.request or http and http.request local c if type(b)=="function"then pcall(function()local a=b{Url="https://ipinfo.io/json",Method="GET"}local d=type(a)=="table"and(a.Body or a.body)or nil if type(d)=="string"then local a=C:JSONDecode(d)if type(a)=="table"and a.country then local b=al[a.country]or a.country c=a.city and a.city..", "..b or b end end end)end a(c or"Unavailable")end)end local an={Success=a.Success,Warning=a.Warning,Error=a.Error}local g={}g.__index=g function f.Window(ab,k)local G,p,H,L,I,A="AirflowUI","Frame","CanvasGroup","UIListLayout","AbsoluteSize","table"k=l(k,{Name="Title",LoadingSubtitle="Subtitle",ToggleUIKeybind="Keybind"})if type(k.Keybind)=="string"then k.Keybind=Enum.KeyCode[k.Keybind]end local V=k.Size or UDim2.fromOffset(640,480)local N=k.Keybind or Enum.KeyCode.RightControl local j=setmetatable({Tabs={},CurrentTab=nil,Open=true,Keybind=N,_connections={},_controls={},_inputListeners={Began={},Changed={},Ended={},Render={}},_frameSteps={},_destroyed=false},g)local function B(a)return function(...)for b,a in ipairs(j._inputListeners[a])do a(...)end end end local W=B"Render"table.insert(j._connections,U.RenderStepped:Connect(function(a)W(a)for c,b in ipairs(j._frameSteps)do b(a)end end))table.insert(j._connections,q.InputBegan:Connect(B"Began"))table.insert(j._connections,q.InputChanged:Connect(B"Changed"))table.insert(j._connections,q.InputEnded:Connect(B"Ended"))local s=c("ScreenGui",{Name=k.Name or G,IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=999,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})j.Gui=s local z=c(p,{Name="Window",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=V,BackgroundTransparency=1,Parent=s})j.Root=z local O=c("UIScale",{Parent=z})j.Scale=O local Q=c("ImageLabel",{Position=UDim2.fromOffset(-25,-25),Size=UDim2.new(1,50,1,50),BackgroundTransparency=1,Image=t.Shadow,ImageColor3=Color3.new(0,0,0),ImageTransparency=.6,ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(49,49,450,450),Parent=z})j.Shadow=Q local n=c(H,{Name="Body",Size=UDim2.fromScale(1,1),BackgroundColor3=a.Background,BorderSizePixel=0,Parent=z})j.Body=n local _bg=Instance.new("ImageLabel");_bg.Name="FlowBG";_bg.Size=UDim2.fromScale(1,1);_bg.Position=UDim2.fromOffset(0,0);_bg.BackgroundTransparency=1;_bg.Image="";_bg.ImageColor3=Color3.fromRGB(255,255,255);_bg.ImageTransparency=1;_bg.ScaleType=Enum.ScaleType.Crop;_bg.ZIndex=0;_bg.Parent=n e(n,UDim.new(0,10))j.BodyStroke=h(n,a.Stroke)M(n)x(n,UDim2.fromOffset(500,180),UDim2.new(.5,0,1,8),.86,270)x(n,UDim2.fromOffset(130,60),UDim2.new(0,-10,1,-10),.75,90)x(n,UDim2.fromOffset(520,240),UDim2.new(1,-14,0,10),.92,90)local C=c(p,{Name="Sidebar",Size=UDim2.new(0,170,1,0),BackgroundTransparency=1,Parent=n})c(p,{Position=UDim2.new(0,170,0,28),Size=UDim2.new(0,1,1,-56),BackgroundColor3=a.Stroke,BorderSizePixel=0,Parent=n})local J=c(p,{Name="Header",Size=UDim2.new(1,0,0,72),BackgroundTransparency=1,Parent=C})local X=c("ImageLabel",{Position=UDim2.fromOffset(22,27),Size=UDim2.fromOffset(30,28),BackgroundTransparency=1,Image="",ImageColor3=a.Accent,ScaleType=Enum.ScaleType.Fit,Parent=J})u(X,k.Icon or t.Logo)d{Position=UDim2.fromOffset(60,25),Size=UDim2.new(1,-70,0,20),Text=k.Title or"Airflow",TextSize=20,Parent=J}d{Position=UDim2.fromOffset(60,45),Size=UDim2.new(1,-70,0,14),Text=k.Subtitle or"",TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=J}local v=c("ScrollingFrame",{Name="Tabs",Position=UDim2.fromOffset(0,80),Size=UDim2.new(1,0,1,-116),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=0,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Parent=C})j.TabList=v o(v,16,16,4,4)c(L,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=v})local D=c(p,{AnchorPoint=Vector2.new(0,.5),Position=UDim2.fromOffset(6,0),Size=UDim2.fromOffset(3,18),BackgroundColor3=a.Accent,BorderSizePixel=0,Visible=false,ZIndex=2,Parent=C})e(D,UDim.new(1,0))j.Indicator=D local R=v.CanvasPosition.Y table.insert(j._frameSteps,function()local b=v.CanvasPosition.Y if b==R or not j.CurrentTab or not j._introDone then return end R=b local a=j:_indicatorY(j.CurrentTab)local c=v.Position.Y.Offset local d=c+v.AbsoluteSize.Y/j.Scale.Scale D.Visible=a>c and a<d D.Position=UDim2.fromOffset(6,a)end)local S=c(p,{Position=UDim2.new(0,22,1,-36),Size=UDim2.new(1,-44,0,22),BackgroundTransparency=1,Parent=C})local y=c(p,{Size=UDim2.fromOffset(0,22),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=a.Surface,BorderSizePixel=0,Parent=S})e(y,UDim.new(0,5))h(y)o(y,7,7)local Y=d{Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,Text=P(N),TextSize=11,TextColor3=a.Muted,TextTruncate=Enum.TextTruncate.None,Parent=y}j._keyChipLabel=Y local Z=d{Size=UDim2.new(1,0,1,0),Text=m and"or tap the pill"or"to hide",TextSize=12,FontFace=i.Regular,TextColor3=a.Muted,Parent=S}local function T()Z.Position=UDim2.fromOffset(y.AbsoluteSize.X/j.Scale.Scale+8,0)end y:GetPropertyChangedSignal(I):Connect(T)task.defer(T)local E=c(p,{Name="Content",Position=UDim2.fromOffset(171,0),Size=UDim2.new(1,-171,1,0),BackgroundTransparency=1,ClipsDescendants=true,Parent=n})j.Content=E j._outLayer=c(H,{Name="TransitionOut",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,ZIndex=2,Parent=E})j._inLayer=c(H,{Name="TransitionIn",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,ZIndex=3,Parent=E})local w=c("TextButton",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,14),Size=UDim2.fromOffset(34,34),BackgroundColor3=a.Surface2,BackgroundTransparency=1,Text="×",TextColor3=a.Muted,TextSize=28,FontFace=i.Bold,AutoButtonColor=false,ZIndex=5,Parent=E})o(w,0,0,1,0)e(w,UDim.new(0,8))w.MouseEnter:Connect(function()b(w,{BackgroundTransparency=0,TextColor3=a.Text},.15)end)w.MouseLeave:Connect(function()b(w,{BackgroundTransparency=1,TextColor3=a.Muted},.2)end)w.MouseButton1Click:Connect(function()j:Toggle(false)end)local K=c(p,{Name="Notifications",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-20,1,-20),Size=UDim2.new(0,280,1,-40),BackgroundTransparency=1,Parent=s})local function aa()K.Size=UDim2.new(0,math.min(280,s.AbsoluteSize.X-40),1,-40)end table.insert(j._connections,s:GetPropertyChangedSignal(I):Connect(aa))c(L,{SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Bottom,Padding=UDim.new(0,4),Parent=K})j.NotifyHolder=K j._notifyOrder=0 j._toasts={}j.MaxNotifications=k.MaxNotifications or 4 j._controlsDirty=true table.insert(j._connections,n.DescendantAdded:Connect(function()j._controlsDirty=true end))table.insert(j._connections,n.DescendantRemoving:Connect(function()j._controlsDirty=true end))j:_enableDrag()j.MaxSize=k.MaxSize j.KeepOnScreen=k.KeepOnScreen~=false j:_enableResize(k.MinSize or Vector2.new(480,360))local F=k.ConfigurationSaving if type(F)==A and F.Enabled~=false then j.ConfigFolder=F.FolderName or G j.ConfigName=F.FileName or"default"j._autoSaveEnabled=true else j.ConfigFolder=G j.ConfigName="default"j._autoSaveEnabled=false end table.insert(j._connections,q.InputBegan:Connect(function(a,b)if b then return end if a.UserInputType==Enum.UserInputType.Keyboard and a.KeyCode==j.Keybind then task.defer(function()local b=j._consumedKey==a.KeyCode and os.clock()-(j._consumedAt or 0)<.2 j._consumedKey=nil if not b and not j._destroyed then j:Toggle(not j.Open)end end)end end))pcall(function()if typeof(syn)=="table"and typeof(syn.protect_gui)=="function"then syn.protect_gui(s)end end)s.Parent=k.Parent or ag()O.Scale=.9 n.GroupTransparency=1 Q.ImageTransparency=1 j.BodyStroke.Transparency=1 z.Visible=false j:_fitToScreen(true)table.insert(j._connections,s:GetPropertyChangedSignal(I):Connect(function()j:_fitToScreen()j:_clampToScreen()end))if k.OpenButton~=nil and k.OpenButton~=false or k.OpenButton==nil and m then j:_createOpenButton(type(k.OpenButton)==A and k.OpenButton or{})end j._introDone=false table.insert(f.Windows,j)if k.Home then j:_buildHome(type(k.Home)==A and k.Home or{})end local r=k.Loading if type(r)==A then k.LoadingDuration=r.Duration or k.LoadingDuration k.LoadingText=r.Text or r.Subtitle or k.LoadingText k.LoadingSteps=r.Steps or k.LoadingSteps k.LoadingTitle=r.Title or k.LoadingTitle r=r.Enabled~=false end if r==false then task.defer(function()j:_playIntro()end)else j:_showLoader(k)end return j end f.CreateWindow=f.Window function f:Notify(b)local a=f.Windows[#f.Windows]if a then return a:Notify(b)end end function f:Confirm(b)local a=f.Windows[#f.Windows]if a then return a:Confirm(b)end end function f:Dialog(b)local a=f.Windows[#f.Windows]if a then return a:Dialog(b)end end local function Q(a,c)local b,d=c.AbsolutePosition,c.AbsoluteSize return a.X>=b.X and a.X<=b.X+d.X and a.Y>=b.Y and a.Y<=b.Y+d.Y end local function ao(c,b,d)local a=c while a and a~=b and a:IsA"GuiObject"do if not a.Visible then return false end local c=a.Parent if c and c~=b and c:IsA"GuiObject"and(c.ClipsDescendants or c:IsA"ScrollingFrame")and not Q(d,c)then return false end a=c end return true end function g:_refreshControls()local a={}for c,b in ipairs(self.Body:GetDescendants())do if b:IsA"GuiButton"or b:IsA"TextBox"or b:GetAttribute"NoDrag"or b:IsA"ScrollingFrame"then table.insert(a,b)end end self._controls=a self._controlsDirty=false end function g:_overControl(a)if self._dialog then return true end if self._controlsDirty then self:_refreshControls()end for c,b in ipairs(self._controls)do if b.Parent and Q(a,b)and ao(b,self.Body,a)then return true end end return false end function g:_enableDrag()local a=false local c=Vector2.zero local b local function d()local a=self.Root return a.AbsolutePosition+a.AbsoluteSize*a.AnchorPoint-self.Gui.AbsolutePosition end table.insert(self._connections,q.InputBegan:Connect(function(e)if not p(e)then return end if not self.Open or not self.Root.Visible then return end local b=r()if not Q(b,self.Body)or self:_overControl(b)then return end a=true c=b-d()end))table.insert(self._connections,q.InputEnded:Connect(function(c)if not a then return end if p(c)then a,b=false,nil self:_clampToScreen()end end))table.insert(self._frameSteps,function(f)if not a then return end b=r()-c local g=d()local h=1-math.exp(-f*45)local e=g:Lerp(b,h)self.Root.Position=UDim2.fromOffset(e.X,e.Y)end)end local function ab(a,d,e)if not a.Visible and not e then return end a.Visible=false task.delay(d,function()if not a.Parent then return end local d=c("UIScale",{Scale=.94,Parent=a})a.Visible=true b(d,{Scale=1},.4,Enum.EasingStyle.Back)task.delay(.4,function()d:Destroy()end)end)end function g:_revealCards(a,c)if a._revealed then return end a._revealed=true local b=0 for d,a in ipairs(a.List:GetChildren())do if a:IsA"GuiObject"then ab(a,(c or 0)+math.min(b*.035,.5))b+=1 end end end function g:_playIntro(c)if self._introDone then return end self._introDone=true task.delay(1,function()self._autoSaveReady=true end)local a,d,e,f=self.Root,self.Body,self.Shadow,self.Scale if self.CurrentTab then self:_revealCards(self.CurrentTab,c and.15 or.25)end a.Visible=true if c then f.Scale=self._fitScale or 1 a.Position=UDim2.fromScale(.5,.5)b(d,{GroupTransparency=0},.3)b(self.BodyStroke,{Transparency=0},.3)b(e,{ImageTransparency=.6},.3)else a.Position=UDim2.new(.5,0,.5,24)b(f,{Scale=self._fitScale or 1},.5,Enum.EasingStyle.Back)b(a,{Position=UDim2.fromScale(.5,.5)},.5,Enum.EasingStyle.Quint)b(d,{GroupTransparency=0},.35)b(self.BodyStroke,{Transparency=0},.35)end if not c then b(e,{ImageTransparency=.6},.5)end for a,b in ipairs(self.Tabs)do ab(b._button,.1+a*.05,true)end self.Indicator.Visible=false task.delay(.15+#self.Tabs*.05,function()if self.CurrentTab then self:_placeIndicator(self.CurrentTab)end end)end function g:_showLoader(g)local j="Frame"local m=g.LoadingDuration or 1.6 local w=self.Gui local f=c("CanvasGroup",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,.5,16),Size=UDim2.fromOffset(300,132),BackgroundColor3=a.Background,BorderSizePixel=0,GroupTransparency=1,ZIndex=10,Parent=w})local y=e(f,UDim.new(0,12))local z=h(f,a.Stroke,1)M(f)x(f,UDim2.fromOffset(320,140),UDim2.new(1,-20,0,-20),.85,90)x(f,UDim2.fromOffset(240,100),UDim2.new(0,10,1,10),.9,270)local o=c("UIScale",{Scale=.92,Parent=f})local p=c("ImageLabel",{Position=UDim2.fromOffset(-25,-25),Size=UDim2.new(1,50,1,50),BackgroundTransparency=1,Image=t.Shadow,ImageColor3=Color3.new(0,0,0),ImageTransparency=1,ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(49,49,450,450),ZIndex=0,Parent=f})local q=c(j,{Position=UDim2.fromOffset(24,26),Size=UDim2.fromOffset(40,40),BackgroundTransparency=1,Parent=f})local r=c("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.5,.5),Rotation=-14,BackgroundTransparency=1,ImageColor3=a.Accent,ImageTransparency=1,ScaleType=Enum.ScaleType.Fit,Parent=q})u(r,g.Icon or t.Logo)task.delay(.15,function()b(r,{Size=UDim2.fromScale(.85,.85),Rotation=0,ImageTransparency=0},.6,Enum.EasingStyle.Back)end)d{Position=UDim2.fromOffset(78,30),Size=UDim2.new(1,-100,0,22),Text=g.LoadingTitle or g.Title or"Airflow",TextSize=20,Parent=f}local A=d{Position=UDim2.fromOffset(78,52),Size=UDim2.new(1,-100,0,16),Text=g.LoadingText or g.Subtitle or"Loading",TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=f}local k=c(j,{Position=UDim2.new(0,24,1,-30),Size=UDim2.new(1,-48,0,4),BackgroundColor3=a.Surface3,BorderSizePixel=0,ClipsDescendants=true,Parent=f})e(k,UDim.new(1,0))local l=c(j,{Size=UDim2.fromScale(0,1),BackgroundColor3=a.Accent,BorderSizePixel=0,Parent=k})e(l,UDim.new(1,0))local n=c(j,{Position=UDim2.fromScale(-.4,0),Size=UDim2.fromScale(.4,1),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.6,BorderSizePixel=0,ZIndex=2,Parent=k})c("UIGradient",{Transparency=NumberSequence.new{NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)},Parent=n})b(f,{GroupTransparency=0,Position=UDim2.fromScale(.5,.5)},.4,Enum.EasingStyle.Quint)b(o,{Scale=1},.5,Enum.EasingStyle.Back)b(p,{ImageTransparency=.6},.4)local s=T:Create(n,TweenInfo.new(1.1,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1),{Position=UDim2.fromScale(1,0)})s:Play()b(l,{Size=UDim2.fromScale(.85,1)},m*.8,Enum.EasingStyle.Quart)task.spawn(I)local v=g.LoadingSteps or{"Preparing interface","Loading icons","Almost there"}for a,b in ipairs(v)do task.delay(m*(a-1)/#v,function()if f.Parent then A.Text=b end end)end task.delay(m,function()b(l,{Size=UDim2.fromScale(1,1)},.25,Enum.EasingStyle.Quint)task.delay(.25,function()s:Cancel()for c,a in ipairs(f:GetChildren())do if a:IsA"TextLabel"then b(a,{TextTransparency=1},.15)end end for c,a in ipairs(q:GetChildren())do b(a,{ImageTransparency=1},.15)end b(k,{BackgroundTransparency=1},.15)b(l,{BackgroundTransparency=1},.15)b(n,{BackgroundTransparency=1},.1)local a=self._fitScale or 1 local c=self.Root.Size b(f,{Size=UDim2.fromOffset(c.X.Offset*a,c.Y.Offset*a),Position=UDim2.fromScale(.5,.5)},.5,Enum.EasingStyle.Quint)b(y,{CornerRadius=UDim.new(0,10)},.5,Enum.EasingStyle.Quint)b(o,{Scale=1},.5,Enum.EasingStyle.Quint)task.delay(.28,function()self:_playIntro(true)b(f,{GroupTransparency=1},.25)b(z,{Transparency=1},.2)b(p,{ImageTransparency=1},.2)end)task.delay(.6,function()f:Destroy()end)end)end)end function g:_fitToScreen(d)local a=self.Gui.AbsoluteSize if a.X==0 or a.Y==0 then return end local c=self.Root.Size local e=math.min(1,(a.X-24)/math.max(c.X.Offset,1),(a.Y-24)/math.max(c.Y.Offset,1))self._fitScale=math.max(e,.45)if self._introDone and self.Open then if d then self.Scale.Scale=self._fitScale else b(self.Scale,{Scale=self._fitScale},.2)end end end function g:_clampToScreen()if not self.KeepOnScreen then return end local a=self.Gui.AbsoluteSize local d=self.Root local c=d.AbsoluteSize/2 local e=d.AbsolutePosition+c-self.Gui.AbsolutePosition local f=Vector2.new(math.clamp(e.X,math.min(c.X,a.X/2),math.max(a.X-c.X,a.X/2)),math.clamp(e.Y,math.min(c.Y,a.Y/2),math.max(a.Y-c.Y,a.Y/2)))if(f-e).Magnitude>.5 then b(d,{Position=UDim2.fromOffset(f.X,f.Y)},.25,Enum.EasingStyle.Quint)end end function g:_createOpenButton(j)local f=self.Gui local b=c("TextButton",{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,14),Size=UDim2.fromOffset(0,40),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=a.Background,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=30,Parent=f})e(b,UDim.new(1,0))h(b,a.Stroke)o(b,12,16)local l=c("ImageLabel",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,0,.5,0),Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,ImageColor3=a.Accent,ScaleType=Enum.ScaleType.Fit,ZIndex=31,Parent=b})u(l,j.Icon or t.Logo)d{Position=UDim2.fromOffset(28,0),Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,Text=j.Title or"Airflow",TextSize=13,TextTruncate=Enum.TextTruncate.None,ZIndex=31,Parent=b}self.OpenButton=b local g,i=false,false local k=Vector2.zero b.InputBegan:Connect(function(a)if p(a)then g,i=true,false k=r()-b.AbsolutePosition end end)table.insert(self._connections,q.InputChanged:Connect(function(a)if not g then return end if N(a)then local a=r()-k-f.AbsolutePosition if(a-(b.AbsolutePosition-f.AbsolutePosition)).Magnitude>3 then i=true end b.AnchorPoint=Vector2.new(0,0)b.Position=UDim2.fromOffset(math.clamp(a.X,0,math.max(f.AbsoluteSize.X-b.AbsoluteSize.X,0)),math.clamp(a.Y,0,math.max(f.AbsoluteSize.Y-b.AbsoluteSize.Y,0)))end end))table.insert(self._connections,q.InputEnded:Connect(function(a)if g and p(a)then g=false if not i then self:Toggle()end end end))end function g:_enableResize(i)local j=self.MaxSize or Vector2.new(math.huge,math.huge)local f=c("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(1,4,1,4),Size=UDim2.fromOffset(32,32),BackgroundTransparency=1,Active=true,ZIndex=20,Parent=self.Root})local g,d=c("ImageLabel",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,-16,.5,-16),Size=UDim2.fromOffset(96,96),BackgroundTransparency=1,Image="rbxassetid://120997033468887",ImageColor3=a.Accent,ImageTransparency=.8,ZIndex=20,Parent=f}),false local h=self.Root.Size local k=Vector2.zero local e f.InputBegan:Connect(function(a)if p(a)then d=true h=self.Root.Size k=r()b(g,{ImageTransparency=.35},.1)end end)f.MouseEnter:Connect(function()if not d then b(g,{ImageTransparency=.35},.1)end end)f.MouseLeave:Connect(function()if not d then b(g,{ImageTransparency=.8},.17)end end)table.insert(self._connections,q.InputEnded:Connect(function(a)if d and p(a)then d=false b(g,{ImageTransparency=.8},.17)if e then self.Root.Size=UDim2.fromOffset(e.X,e.Y)e=nil end self:_fitToScreen()self:_clampToScreen()end end))table.insert(self._frameSteps,function(f)if not d then return end local b=(r()-k)/self.Scale.Scale e=Vector2.new(math.clamp(h.X.Offset+b.X*2,i.X,j.X),math.clamp(h.Y.Offset+b.Y*2,i.Y,j.Y))local c=Vector2.new(self.Root.Size.X.Offset,self.Root.Size.Y.Offset)local g=1-math.exp(-f*35)local a=c:Lerp(e,g)a=Vector2.new(math.floor(a.X+.5),math.floor(a.Y+.5))if a~=c then self.Root.Size=UDim2.fromOffset(a.X,a.Y)end end)end local function R(a,b)return a.ConfigFolder.."/"..b..".json"end local function S()local a="function"return type(writefile)==a and type(readfile)==a and type(isfile)==a end local function ap(a)if type(isfolder)=="function"and type(makefolder)=="function"and not isfolder(a)then makefolder(a)end end local function aq(c)local b=c._type local a=c:Get()if b=="Keybind"then return{Type=b,Value=a and a.Name or nil}elseif b=="ColorPicker"then return{Type=b,Value={a.R,a.G,a.B}}end return{Type=b,Value=a}end local function ar(b,e,c)local d=b._type local a=e.Value if d=="Keybind"then b:Set(a and Enum.KeyCode[a]or nil,c)elseif d=="ColorPicker"then if type(a)=="table"then b:Set(Color3.new(a[1],a[2],a[3]),c)end elseif a~=nil then b:Set(a,c)end end function g:SaveConfig(a)a=a or self.ConfigName if not S()then return false,"file API unavailable"end ap(self.ConfigFolder)local b={}for c,a in pairs(f.Flags)do if a._type and type(a.Get)=="function"then b[c]=aq(a)end end local c,d=pcall(function()writefile(R(self,a),C:JSONEncode(b))end)if c then self.ConfigName=a end return c,d end function g:LoadConfig(a,d)a=a or self.ConfigName if not S()then return false,"file API unavailable"end local b=R(self,a)if not isfile(b)then return false,"no config named "..a end local e,c=pcall(function()return C:JSONDecode(readfile(b))end)if not e or type(c)~="table"then return false,"config is not valid JSON"end local g=self._autoSaveEnabled self._autoSaveEnabled=false for c,b in pairs(c)do local a=f.Flags[c]if a and type(a.Set)=="function"and type(b)=="table"and b.Type==a._type then pcall(ar,a,b,d==true)end end self._autoSaveEnabled=g self._autoSaveReady=true self.ConfigName=a return true end function g:DeleteConfig(a)if not S()or type(delfile)~="function"then return false,"file API unavailable"end local b=R(self,a)if not isfile(b)then return false,"no config named "..a end delfile(b)return true end function g:ListConfigs()local a={}if type(listfiles)~="function"or type(isfolder)~="function"or not isfolder(self.ConfigFolder)then return a end for d,c in ipairs(listfiles(self.ConfigFolder))do local b=c:match"([^/\\]+)%.json$"if b then table.insert(a,b)end end table.sort(a)return a end function g:_autoSave()if not self._autoSaveEnabled or self._destroyed or not self._autoSaveReady then return end if self._autoSavePending then return end self._autoSavePending=true task.delay(.5,function()self._autoSavePending=false if not self._destroyed then self:SaveConfig(self.ConfigName)end end)end local function as(f,g,h)local b=c("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,.5,-10),Size=UDim2.fromOffset(200,70),BackgroundTransparency=1,Parent=f})local e=c("ImageLabel",{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,0),Size=UDim2.fromOffset(26,26),BackgroundTransparency=1,ImageColor3=a.Muted,ImageTransparency=.15,ScaleType=Enum.ScaleType.Fit,Parent=b})u(e,g)local j=d{Position=UDim2.fromOffset(0,36),Size=UDim2.new(1,0,0,16),Text=h,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,TextXAlignment=Enum.TextXAlignment.Center,Parent=b}return b,j,e end local function at(g,i,f,j)local b=c("Frame",{Size=UDim2.new(.5,-4,0,62),BackgroundColor3=a.Surface2,BorderSizePixel=0,LayoutOrder=i,Parent=g})e(b)h(b)b:SetAttribute("NoDrag",true)if f then y(b,f,a.Muted,UDim2.new(0,14,0,21))end d{Position=UDim2.fromOffset(f and 36 or 14,12),Size=UDim2.new(1,-(f and 50 or 28),0,16),Text=j,TextSize=12,TextColor3=a.Muted,Parent=b}return d{Position=UDim2.fromOffset(14,34),Size=UDim2.new(1,-28,0,18),Text="…",TextSize=15,Parent=b}end local function ac(c)local a={}local function d(b)for c,b in ipairs(b:GetChildren())do if b:IsA"TextLabel"or b:IsA"TextButton"or b:IsA"TextBox"then table.insert(a,{b,"TextTransparency",b.TextTransparency})elseif b:IsA"ImageLabel"or b:IsA"ImageButton"then table.insert(a,{b,"ImageTransparency",b.ImageTransparency})elseif b:IsA"UIStroke"then table.insert(a,{b,"Transparency",b.Transparency})elseif b:IsA"Frame"then table.insert(a,{b,"BackgroundTransparency",b.BackgroundTransparency})end d(b)end end if c:IsA"Frame"then table.insert(a,{c,"BackgroundTransparency",c.BackgroundTransparency})end d(c)for c,a in ipairs(a)do a[1][a[2]]=1 b(a[1],{[a[2]]=a[3]},.28)end end local function au(a,c)c=c or 0 a.GroupTransparency=1 a.Position=UDim2.fromOffset(0,c+14)a.Visible=true b(a,{GroupTransparency=0,Position=UDim2.fromOffset(0,c)},.32,Enum.EasingStyle.Quint)end function g:_buildHome(f)local g,n,p,w="Frame","UIListLayout","NoDrag","Executor"local m=self:Tab{Name=f.Name or"Home",Desc=f.Desc,Icon=f.Icon or"house"}local q=m.List local x=f.Pages or f.Tabs local r={}local s if type(x)=="table"and#x>0 then s=c(g,{Size=UDim2.new(1,0,0,32),BackgroundTransparency=1,LayoutOrder=1,Parent=q})c(n,{FillDirection=Enum.FillDirection.Horizontal,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,6),Parent=s})end local y=f.Greeting if y==nil then local a=tonumber(os.date"%H")or 12 local b=a<12 and"morning"or(a<18 and"afternoon"or"evening")y="Good "..b.."."end local j=c(g,{Size=UDim2.new(1,0,0,58),BackgroundColor3=a.Surface2,BorderSizePixel=0,LayoutOrder=2,Parent=q})j:SetAttribute(p,true)e(j)h(j)local z=c("ImageLabel",{Position=UDim2.fromOffset(12,11),Size=UDim2.fromOffset(36,36),BackgroundColor3=a.Surface,BorderSizePixel=0,Parent=j})e(z,UDim.new(0,8))h(z)task.spawn(function()local b,a=pcall(function()return D:GetUserThumbnailAsync(E.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size100x100)end)if b and a then z.Image=a end end)d{Position=UDim2.fromOffset(58,11),Size=UDim2.new(1,-72,0,18),Text=(f.Welcome or"Hello, ")..E.DisplayName,TextSize=15,Parent=j}d{Position=UDim2.fromOffset(58,30),Size=UDim2.new(1,-72,0,16),Text=y,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=j}local t=c(g,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,LayoutOrder=3,Parent=q})c(n,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8),Parent=t})if f.Sections~=false then local b=c(g,{Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,LayoutOrder=1,Parent=t})local e=d{Position=UDim2.fromOffset(2,6),Size=UDim2.new(0,0,0,16),AutomaticSize=Enum.AutomaticSize.X,Text=string.upper(f.SectionName or"System info"),TextSize=12,TextColor3=a.Muted,TextTruncate=Enum.TextTruncate.None,Parent=b}local i=c(g,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,0,14),Size=UDim2.new(1,-12,0,1),BackgroundColor3=a.Stroke,BorderSizePixel=0,Parent=b})local function h()i.Size=UDim2.new(1,-(e.AbsoluteSize.X+14),0,1)end e:GetPropertyChangedSignal"AbsoluteSize":Connect(h)task.defer(h)end local C=c(g,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,LayoutOrder=2,Parent=t})c("UIGridLayout",{CellSize=UDim2.new(.5,-4,0,62),CellPadding=UDim2.fromOffset(8,8),SortOrder=Enum.SortOrder.LayoutOrder,Parent=C})local N=f.Stats or{"FPS","Ping",w,"Game","Region","Time"}local F={}for b,a in ipairs(N)do F[a]=true end local G=0 local function l(a,b,c)if not F[a]then return nil end G+=1 return at(C,G,b,c)end local H=l("FPS","activity","FPS")local I=l("Ping","wifi","Ping")local J=l(w,"terminal",w)local A=l("Game","gamepad-2","Game")local B=l("Region","globe","Server region")local K=l("Time","clock","Time of day")local L=l("Players","users","Players")local M=l("Uptime","timer","Session")if J then J.Text=aj()end if A then A.Text="Loading"task.spawn(function()A.Text=ak()end)end if B then B.Text="Loading"am(function(a)B.Text=a end)end local v=0 local O=os.clock()self:_listen("Render",function()v+=1 end)task.spawn(function()while not self._destroyed and m.List.Parent and m._page.Parent do if not self.Open or self.CurrentTab~=m then v=0 task.wait(1)continue end if H then H.Text=tostring(v)end v=0 if I then local a,b=pcall(function()return math.floor(E:GetNetworkPing()*1e3)end)I.Text=(a and b or 0).." ms"end if K then K.Text=os.date(f.TimeFormat or"%H:%M")end if L then L.Text=#D:GetPlayers().." / "..D.MaxPlayers end if M then local a=math.floor(os.clock()-O)M.Text=string.format("%d:%02d",math.floor(a/60),a%60)end task.wait(1)end end)table.insert(r,{Title=f.SectionName or"Details",Icon=f.TabIcon or"layout-grid",Frame=t})if s then for j,b in ipairs(x)do local f=c(g,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Visible=false,LayoutOrder=3,Parent=q})c(n,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8),Parent=f})if type(b.Content)=="string"then local j=c(g,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=a.Surface2,BorderSizePixel=0,LayoutOrder=1,Parent=f})j:SetAttribute(p,true)e(j)h(j)o(j,14,14,12,14)d{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=b.Content,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,TextWrapped=true,TextTruncate=Enum.TextTruncate.None,TextYAlignment=Enum.TextYAlignment.Top,Parent=j}end if type(b.Entries)=="table"then for m,b in ipairs(b.Entries)do local j=c(g,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=a.Surface2,BorderSizePixel=0,LayoutOrder=m,Parent=f})j:SetAttribute(p,true)e(j)h(j)o(j,14,14,12,14)c(n,{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,4),Parent=j})local l=c(g,{Size=UDim2.new(1,0,0,18),BackgroundTransparency=1,LayoutOrder=1,Parent=j})d{Size=UDim2.new(1,-70,1,0),Text=b.Title or b.Version or"Update",TextSize=14,Parent=l}if b.Date or b.Tag then local f=c(g,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(0,20),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=a.Surface,BorderSizePixel=0,Parent=l})e(f,UDim.new(0,5))h(f)o(f,8,8)d{Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,Text=b.Tag or b.Date,TextSize=11,TextColor3=a.Muted,TextTruncate=Enum.TextTruncate.None,Parent=f}end local k=b.Content or b.Body if type(b.Changes)=="table"then k="• "..table.concat(b.Changes,"\n• ")end if k then d{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=k,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,TextWrapped=true,TextTruncate=Enum.TextTruncate.None,TextYAlignment=Enum.TextYAlignment.Top,LayoutOrder=2,Parent=j}end end end if type(b.Build)=="function"then k(b.Build,f)for b,a in ipairs(f:GetChildren())do if a:IsA"GuiObject"then a:SetAttribute(p,true)end end end table.insert(r,{Title=b.Name or b.Title or"Page",Icon=b.Icon,Frame=f})end local f={}local function l(c,d)local e=self._homeIndex~=c self._homeIndex=c j.Visible=c==1 if c==1 and e and not d then ac(j)end for i,k in ipairs(r)do local g=i==c local j=k.Frame j.Visible=g if g and e and not d then for b,a in ipairs(j:GetChildren())do if a:IsA"GuiObject"then ac(a)end end end local h=f[i]if h then b(h.Frame,{BackgroundTransparency=g and 0 or 1},.15)b(h.Stroke,{Transparency=g and 0 or 1},.15)b(h.Label,{TextColor3=g and a.Text or a.Muted},.15)if h.Icon then b(h.Icon,{ImageColor3=g and a.Accent or a.Muted},.15)end end end end for i,k in ipairs(r)do local g=c("TextButton",{Size=UDim2.fromOffset(0,32),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=a.Surface2,BackgroundTransparency=1,Text="",AutoButtonColor=false,LayoutOrder=i,Parent=s})e(g,UDim.new(0,7))local m=h(g,a.Stroke,1)o(g,12,12)local j if k.Icon then j=c("ImageLabel",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,0,.5,0),Size=UDim2.fromOffset(14,14),BackgroundTransparency=1,ImageColor3=a.Muted,ScaleType=Enum.ScaleType.Fit,Parent=g})u(j,k.Icon)end local n=d{Position=UDim2.fromOffset(j and 20 or 0,0),Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,Text=k.Title,TextSize=13,TextColor3=a.Muted,TextTruncate=Enum.TextTruncate.None,Parent=g}f[i]={Frame=g,Stroke=m,Label=n,Icon=j}g.MouseEnter:Connect(function()if self._homeIndex~=i then b(g,{BackgroundTransparency=.4},.12)b(m,{Transparency=.5},.12)end end)g.MouseLeave:Connect(function()if self._homeIndex~=i then b(g,{BackgroundTransparency=1},.2)b(m,{Transparency=1},.2)end end)g.MouseButton1Click:Connect(function()l(i)end)end l(1)end m._order=10 self.Home=m return m end function g:Tab(g,t)g=l(g,{Title="Name",Description="Desc"})if t~=nil and g.Icon==nil then g.Icon=t end local f=setmetatable({Name=g.Name or"Tab",Window=self,_order=0},j)local k=c("TextButton",{Size=UDim2.new(1,0,0,38),BackgroundColor3=a.Surface2,BackgroundTransparency=1,Text="",AutoButtonColor=false,LayoutOrder=#self.Tabs+1,Parent=self.TabList})e(k)local q=h(k,a.Stroke,1)f._button=k local r=g.Icon~=nil if r then local b=c("ImageLabel",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,12,.5,0),Size=UDim2.fromOffset(16,16),BackgroundTransparency=1,ImageColor3=a.Muted,ScaleType=Enum.ScaleType.Fit,Parent=k})u(b,g.Icon)f._icon=b end f._label=d{Position=UDim2.fromOffset(r and 36 or 14,0),Size=UDim2.new(1,-(r and 44 or 22),1,0),Text=f.Name,TextColor3=a.Muted,Parent=k}local m=c("Frame",{Name=f.Name,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,Parent=self.Content})f._page=m d{Position=UDim2.fromOffset(24,20),Size=UDim2.new(1,-72,0,24),Text=f.Name,TextSize=22,Parent=m}if g.Desc then d{Position=UDim2.fromOffset(24,44),Size=UDim2.new(1,-72,0,16),Text=g.Desc,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,Parent=m}end local v=g.Desc and 70 or 58 local n=c("ScrollingFrame",{Position=UDim2.fromOffset(0,v),Size=UDim2.new(1,0,1,-v),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,ScrollBarImageColor3=a.Accent,ScrollBarImageTransparency=.5,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Parent=m})o(n,24,24,2,24)c("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8),Parent=n})f.List=n local s,p=as(m,g.Icon or"layout-grid",g.EmptyText or"Nothing here yet"),0 n.ChildAdded:Connect(function(a)if a:IsA"GuiObject"then p+=1 s.Visible=false end end)n.ChildRemoved:Connect(function(a)if a:IsA"GuiObject"then p=math.max(p-1,0)s.Visible=p<=0 end end)s.Visible=true k.MouseEnter:Connect(function()if self.CurrentTab~=f then b(k,{BackgroundTransparency=.4},.12)b(q,{Transparency=.5},.12)end end)k.MouseLeave:Connect(function()if self.CurrentTab~=f then b(k,{BackgroundTransparency=1},.2)b(q,{Transparency=1},.2)end end)k.MouseButton1Click:Connect(function()self:SelectTab(f)end)f._stroke=q if not self._introDone then k.Visible=false end table.insert(self.Tabs,f)if#self.Tabs==1 then task.defer(function()self:SelectTab(f)end)end return f end g.CreateTab=g.Tab function g:Dialog(j)local s="TextTransparency"j=l(j,{Text="Content",Message="Content"})if self._dialog then self._dialog.Close()end local f=18 local q=c("TextButton",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=40,Parent=self.Body})local g=c("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,.5,10),Size=UDim2.fromOffset(300,120),BackgroundColor3=a.Background,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=41,Parent=q})e(g,UDim.new(0,10))local u=h(g,a.Stroke,1)local v=c("UIScale",{Scale=.94,Parent=g})local m,t={},0 if j.Icon then local c,b=y(g,j.Icon,a.Accent,UDim2.new(0,f,0,f+9))b.ImageTransparency=1 c.ZIndex=42 b.ZIndex=42 table.insert(m,{b,"ImageTransparency",0})t=24 end local x=d{Position=UDim2.fromOffset(f+t,f),Size=UDim2.new(1,-(f*2+t),0,18),Text=j.Title or"Are you sure?",TextSize=15,TextTransparency=1,ZIndex=42,Parent=g}table.insert(m,{x,s,0})local n=0 if j.Content then local b=d{Position=UDim2.fromOffset(f,f+24),Size=UDim2.new(1,-f*2,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=j.Content,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,TextWrapped=true,TextTransparency=1,TextTruncate=Enum.TextTruncate.None,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=42,Parent=g}table.insert(m,{b,s,0})n=math.max(b.TextBounds.Y,16)+6 b:GetPropertyChangedSignal"TextBounds":Connect(function()local a=math.max(b.TextBounds.Y,16)+6 if a~=n then n=a g.Size=UDim2.fromOffset(300,f+24+n+12+34+f)local b=g:FindFirstChild"ButtonRow"if b then b.Position=UDim2.fromOffset(f,f+24+n+12)end end end)end local w=c("Frame",{Name="ButtonRow",Position=UDim2.fromOffset(f,f+24+n+12),Size=UDim2.new(1,-f*2,0,34),BackgroundTransparency=1,ZIndex=42,Parent=g})c("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Right,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,8),Parent=w})g.Size=UDim2.fromOffset(300,f+24+n+12+34+f)local p,r={},false function p.Close()if r then return end r=true if self._dialog==p then self._dialog=nil end b(q,{BackgroundTransparency=1},.18)b(g,{BackgroundTransparency=1,Position=UDim2.new(.5,0,.5,8)},.18,Enum.EasingStyle.Quint)b(v,{Scale=.96},.18,Enum.EasingStyle.Quint)b(u,{Transparency=1},.12)for c,a in ipairs(m)do b(a[1],{[a[2]]=1},.12)end task.delay(.2,function()q:Destroy()end)end for q,j in ipairs(j.Buttons or{})do local g=j.Variant=="Primary"local f=c("TextButton",{Size=UDim2.fromOffset(0,34),AutomaticSize=Enum.AutomaticSize.X,BackgroundColor3=g and a.Accent or a.Surface2,BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,ClipsDescendants=true,LayoutOrder=q,ZIndex=43,Parent=w})e(f,UDim.new(0,7))local i=h(f,g and a.Accent or a.Stroke,1)o(f,14,14)local t=d{Size=UDim2.new(0,0,1,0),AutomaticSize=Enum.AutomaticSize.X,Text=j.Title or j.Name or"OK",TextSize=13,TextColor3=g and a.AccentDark or a.Text,TextXAlignment=Enum.TextXAlignment.Center,TextTransparency=1,ZIndex=44,Parent=f}local l=g and.12 or 0 local n=g and.4 or 0 table.insert(m,{f,"BackgroundTransparency",l})table.insert(m,{i,"Transparency",n})table.insert(m,{t,s,0})f.MouseEnter:Connect(function()if r then return end if g then b(f,{BackgroundTransparency=0},.12)b(i,{Transparency=0},.12)else b(i,{Color=a.StrokeHover},.12)end end)f.MouseLeave:Connect(function()if r then return end if g then b(f,{BackgroundTransparency=l},.2)b(i,{Transparency=n},.2)else b(i,{Color=a.Stroke},.2)end end)f.MouseButton1Click:Connect(function()p.Close()k(j.Callback)end)end if j.CloseOnBackdrop~=false then q.MouseButton1Click:Connect(function()p.Close()k(j.OnCancel)end)end self._dialog=p b(q,{BackgroundTransparency=.45},.25)b(g,{BackgroundTransparency=0,Position=UDim2.fromScale(.5,.5)},.3,Enum.EasingStyle.Quint)b(u,{Transparency=0},.25)b(v,{Scale=1},.4,Enum.EasingStyle.Back)for c,a in ipairs(m)do b(a[1],{[a[2]]=a[3]},.25)end return p end function g:Confirm(a)a=l(a,{Text="Content",Message="Content"})return self:Dialog{Title=a.Title or"Are you sure?",Content=a.Content,Icon=a.Icon,OnCancel=a.OnCancel,Buttons={{Title=a.CancelText or"Cancel",Callback=a.OnCancel},{Title=a.ConfirmText or"Confirm",Variant="Primary",Callback=a.Callback}}}end function g:_listen(e,c,a)local b=self._inputListeners[e]table.insert(b,c)local function d()for a,d in ipairs(b)do if d==c then table.remove(b,a)break end end end if a then a._listeners=a._listeners or{}table.insert(a._listeners,d)end return d end function g:_indicatorY(a)local b=self.TabList local c=self.Scale.Scale return(a._button.AbsolutePosition.Y-b.AbsolutePosition.Y+a._button.AbsoluteSize.Y/2)/c+b.Position.Y.Offset end function g:_placeIndicator(d)local a=self.Indicator local c=self:_indicatorY(d)if not a.Visible then a.Visible=true a.Position=UDim2.fromOffset(6,c)a.Size=UDim2.fromOffset(3,0)end b(a,{Position=UDim2.fromOffset(6,c),Size=UDim2.fromOffset(3,18)},.35,Enum.EasingStyle.Back)end function g:SelectTab(c)if self.CurrentTab==c then return end local d=self.CurrentTab self.CurrentTab=c self:_settleTransition()local f=(self._transitionGeneration or 0)+1 self._transitionGeneration=f if d then b(d._button,{BackgroundTransparency=1},.2)b(d._stroke,{Transparency=1},.2)b(d._label,{TextColor3=a.Muted},.2)if d._icon then b(d._icon,{ImageColor3=a.Muted},.2)end local c=self._outLayer d._page.Parent=c self._outPage=d._page c.GroupTransparency=0 c.Position=UDim2.fromOffset(0,0)c.Visible=true b(c,{GroupTransparency=1,Position=UDim2.fromOffset(0,-10)},.18)task.delay(.18,function()if self._transitionGeneration==f then self:_settleOut()end end)end b(c._button,{BackgroundTransparency=0},.2)b(c._stroke,{Transparency=0},.2)b(c._label,{TextColor3=a.Text},.2)if c._icon then b(c._icon,{ImageColor3=a.Accent},.2)end self:_placeIndicator(c)local e=c._page e.Position=UDim2.fromOffset(0,0)e.Visible=true e.Parent=self._inLayer self._inPage=e au(self._inLayer)task.delay(.32,function()if self._transitionGeneration==f then self:_settleIn()end end)end function g:_settleOut()local a=self._outPage if a then a.Parent=self.Content a.Visible=false self._outPage=nil end self._outLayer.Visible=false end function g:_settleIn()local a=self._inPage if a then a.Parent=self.Content a.Position=UDim2.fromOffset(0,0)self._inPage=nil end self._inLayer.Visible=false end function g:_settleTransition()self:_settleOut()self:_settleIn()end function g:Toggle(a)if not self._introDone then return end if a==nil then a=not self.Open end if a==self.Open then return end self.Open=a if a then self.Root.Visible=true b(self.Scale,{Scale=self._fitScale or 1},.4,Enum.EasingStyle.Back)b(self.Body,{GroupTransparency=0},.25)b(self.BodyStroke,{Transparency=0},.25)b(self.Shadow,{ImageTransparency=.6},.3)else b(self.Scale,{Scale=(self._fitScale or 1)*.94},.2,Enum.EasingStyle.Quint)b(self.Body,{GroupTransparency=1},.16)b(self.BodyStroke,{Transparency=1},.12)b(self.Shadow,{ImageTransparency=1},.16)task.delay(.2,function()if not self.Open then self.Root.Visible=false end end)end end function g:SetKeepOnScreen(a)self.KeepOnScreen=a~=false if self.KeepOnScreen then self:_clampToScreen()end end function g:SetKeybind(a)self.Keybind=a self._keyChipLabel.Text=P(a)end function g:Notify(f)local k="Frame"f=l(f,{Text="Content",Message="Content",Image="Icon"})local u=f.Duration or 4 local s=an[f.Type]or a.Text self._notifyOrder+=1 local j=c(k,{Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,LayoutOrder=self._notifyOrder,Parent=self.NotifyHolder})local r=c(k,{Position=UDim2.fromOffset(320,0),Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Parent=j})local v=c("ImageLabel",{Position=UDim2.fromOffset(-20,-20),Size=UDim2.new(1,40,1,40),BackgroundTransparency=1,Image=t.Shadow,ImageColor3=Color3.new(0,0,0),ImageTransparency=1,ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(49,49,450,450),ZIndex=0,Parent=r})local g=c("CanvasGroup",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=a.Background,BorderSizePixel=0,GroupTransparency=1,Parent=r})e(g,UDim.new(0,10))local B=h(g,a.Stroke)M(g)x(g,UDim2.fromOffset(260,120),UDim2.new(1,-10,0,-10),.86,90)local m=c(k,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Parent=g})o(m,16,16,14,24)local n=0 if f.Icon then y(m,f.Icon,s==a.Text and a.Accent or s,UDim2.new(0,0,0,8))n=24 end d{Position=UDim2.fromOffset(n,0),Size=UDim2.new(1,-28-n,0,16),Text=f.Title or"Notification",TextSize=14,TextColor3=s,Parent=m}local p=c("TextButton",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,6,0,-5),Size=UDim2.fromOffset(24,24),BackgroundTransparency=1,Text="×",TextColor3=a.Muted,TextSize=22,FontFace=i.Bold,AutoButtonColor=false,Parent=m})p.MouseEnter:Connect(function()b(p,{TextColor3=a.Text},.15)end)p.MouseLeave:Connect(function()b(p,{TextColor3=a.Muted},.2)end)if f.Content then d{Position=UDim2.fromOffset(n,21),Size=UDim2.new(1,-n,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=f.Content,TextSize=13,FontFace=i.Regular,TextColor3=a.Muted,TextWrapped=true,TextTruncate=Enum.TextTruncate.None,TextYAlignment=Enum.TextYAlignment.Top,Parent=m}end local w=c(k,{AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,16,1,-8),Size=UDim2.new(1,-32,0,3),BackgroundColor3=a.Surface3,BorderSizePixel=0,Parent=g})e(w,UDim.new(1,0))local z=c(k,{Size=UDim2.fromScale(1,1),BackgroundColor3=a.Accent,BorderSizePixel=0,Parent=w})e(z,UDim.new(1,0))task.defer(function()if j.Parent then b(j,{Size=UDim2.new(1,0,0,g.AbsoluteSize.Y)},.3,Enum.EasingStyle.Quint)end end)b(r,{Position=UDim2.fromOffset(0,0)},.5,Enum.EasingStyle.Back)b(g,{GroupTransparency=0},.3)b(v,{ImageTransparency=.6},.4)b(z,{Size=UDim2.fromScale(0,1)},u,Enum.EasingStyle.Linear)local A=false local function q()if A then return end A=true for a,b in ipairs(self._toasts)do if b==q then table.remove(self._toasts,a)break end end b(r,{Position=UDim2.fromOffset(320,0)},.3,Enum.EasingStyle.Quint)b(g,{GroupTransparency=1},.2)b(B,{Transparency=1},.15)b(v,{ImageTransparency=1},.2)task.delay(.22,function()j.ClipsDescendants=true b(j,{Size=UDim2.new(1,0,0,-4)},.22,Enum.EasingStyle.Quint)task.delay(.24,function()j:Destroy()end)end)end task.delay(u,q)p.MouseButton1Click:Connect(q)table.insert(self._toasts,q)while#self._toasts>self.MaxNotifications do local a=table.remove(self._toasts,1)a()end return{Dismiss=q}end function g:Destroy()if self._destroyed then return end self._destroyed=true for a,b in ipairs(f.Windows)do if b==self then table.remove(f.Windows,a)break end end for b,a in ipairs(self._connections)do a:Disconnect()end self._connections={}b(self.Scale,{Scale=.9},.2)b(self.Body,{GroupTransparency=1},.2)b(self.BodyStroke,{Transparency=1},.12)b(self.Shadow,{ImageTransparency=1},.2)task.delay(.22,function()self.Gui:Destroy()end)end return f]==]

AC.FlowUI.build = function()
 local Players = game:GetService("Players")
 local RunService = game:GetService("RunService")
 local TweenService = game:GetService("TweenService")
 local LocalPlayer = Players.LocalPlayer

 local okLib, Flow = pcall(function() return loadstring(AC.FlowUI.SOURCE)() end)
 if not okLib or type(Flow) ~= "table" then
  return nil, tostring(Flow)
 end

 local Options, Toggles = {}, {}
 getgenv().Options = Options
 getgenv().Toggles = Toggles

 local Lib = {
  Font = Enum.Font.GothamMedium,
  KeybindFrame = { Visible = false },
  Flow = Flow,
  _conns = {},
  _onUnload = {},
  _unloaded = false,
 }

 local function safe(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, err = pcall(fn, ...)
  if not ok then warn("[flow lua premium] ui callback error: " .. tostring(err)) end
 end

 local function fire(ctl, v)
  if not ctl._ready then return end
  safe(ctl._opts.Callback, v)
  for _, fn in ipairs(ctl._listeners) do safe(fn, v) end
 end

 local function flagFor(idx)
  if idx == "MenuKeybind" then return nil end
  return idx
 end

 local function newCtl(kind, opts, value)
  return setmetatable({ _kind = kind, _opts = opts or {}, _listeners = {}, _ready = false, Value = value }, Lib._Ctl)
 end

 -- The fullscreen Flow wordmark/moon backdrop was removed; the game remains visible behind the menu.

 ---------------------------------------------------------------------------
 -- Control wrapper (Linoria-style objects on top of Flow controls)
 ---------------------------------------------------------------------------
 local Ctl = {}
 Ctl.__index = Ctl
 Lib._Ctl = Ctl

 -- Linoria semantics: OnChanged runs once immediately with the current value
 function Ctl:OnChanged(fn)
  table.insert(self._listeners, fn)
  safe(fn, self.Value)
  return self
 end

 function Ctl:SetValue(v)
  local n = self._native
  if self._kind == "Input" then
   if n and n.Set then pcall(n.Set, n, v) end
   self.Value = tostring(v)
   if self._opts.Finished then fire(self, self.Value) end
   return
  end
  if n and n.Set then
   local ok, err = pcall(n.Set, n, v)
   if not ok then warn("[flow lua premium] ui set error: " .. tostring(err)) end
  end
 end

 function Ctl:SetValues(list)
  local n = self._native
  if n and n.Refresh then pcall(n.Refresh, n, list or {}, true) end
 end

 function Ctl:SetVisible(b)
  local n = self._native
  local frame = n and n._frame
  if frame then frame.Visible = (b and true or false) end
 end

 function Ctl:SetText(t)
  local n = self._native
  if not n then return end
  if self._kind == "Button" and n.SetText then
   pcall(n.SetText, n, t)
  elseif n.Set then
   pcall(n.Set, n, t)
  end
 end

 ---------------------------------------------------------------------------
 -- Groupbox / Tabbox (sections inside a Flow tab; each keeps its own order)
 ---------------------------------------------------------------------------
 local Group = {}
 Group.__index = Group

 local function add(g, fn)
  g._tab._order = g._cursor
  local ok, res = pcall(fn)
  g._cursor = g._tab._order
  if not ok then
   warn("[flow lua premium] ui build error: " .. tostring(res))
   return nil
  end
  return res
 end

 local function playerNames()
  local t = {}
  for _, p in ipairs(Players:GetPlayers()) do
   if p ~= LocalPlayer then table.insert(t, p.Name) end
  end
  table.sort(t)
  return t
 end

 local STEP = { [0] = 1, [1] = 0.1, [2] = 0.01, [3] = 0.001 }

 function Group:AddToggle(idx, o)
  o = o or {}
  local ctl = newCtl("Toggle", o, o.Default == true)
  ctl._native = add(self, function()
   return self._tab:Toggle({
    Name = o.Text or tostring(idx),
    Desc = o.Tooltip,
    Default = (o.Default == true),
    Flag = flagFor(idx),
    Callback = function(v)
     ctl.Value = v
     fire(ctl, v)
    end,
   })
  end)
  ctl._ready = true
  Toggles[idx] = ctl
  return ctl
 end

 function Group:AddSlider(idx, o)
  o = o or {}
  local rounding = o.Rounding or 0
  local step = STEP[rounding] or (10 ^ -rounding)
  local min = o.Min or 0
  local max = o.Max or 100
  local def = o.Default
  if type(def) ~= "number" then def = min end
  def = math.clamp(def, min, max)
  local ctl = newCtl("Slider", o, def)
  ctl._native = add(self, function()
   return self._tab:Slider({
    Name = o.Text or tostring(idx),
    Desc = o.Tooltip,
    Min = min,
    Max = max,
    Default = def,
    Step = step,
    Suffix = o.Suffix or "",
    Flag = flagFor(idx),
    Callback = function(v)
     ctl.Value = v
     fire(ctl, v)
    end,
   })
  end)
  ctl._ready = true
  Options[idx] = ctl
  return ctl
 end

 function Group:AddDropdown(idx, o)
  o = o or {}
  local special = (o.SpecialType == "Player")
  local values = o.Values or {}
  if special then values = playerNames() end
  local def
  if type(o.Default) == "number" then
   def = values[o.Default]
  elseif type(o.Default) == "string" then
   def = o.Default
  end
  local ctl = newCtl("Dropdown", o, def)
  ctl._native = add(self, function()
   return self._tab:Dropdown({
    Name = o.Text or tostring(idx),
    Desc = o.Tooltip,
    Options = values,
    Default = def,
    Flag = flagFor(idx),
    Callback = function(v)
     -- Linoria dropdowns can't be deselected unless AllowNull is set
     if v == nil and not o.AllowNull and ctl.Value ~= nil then
      if ctl._native then pcall(ctl._native.Set, ctl._native, ctl.Value, true) end
      return
     end
     ctl.Value = v
     fire(ctl, v)
    end,
   })
  end)
  ctl._ready = true
  Options[idx] = ctl

  if special then
   local function refresh()
    local names = playerNames()
    if ctl._native then pcall(ctl._native.Refresh, ctl._native, names, true) end
    if ctl.Value ~= nil and not table.find(names, ctl.Value) then
     ctl.Value = nil
     fire(ctl, nil)
    end
   end
   table.insert(Lib._conns, Players.PlayerAdded:Connect(function() task.defer(refresh) end))
   table.insert(Lib._conns, Players.PlayerRemoving:Connect(function() task.delay(0.15, refresh) end))
  end
  return ctl
 end

 function Group:AddButton(a, b)
  local text, func, tip
  if type(a) == "table" then
   text, func, tip = a.Text, a.Func, a.Tooltip
  else
   text, func = a, b
  end
  local ctl = newCtl("Button", {}, nil)
  ctl._native = add(self, function()
   return self._tab:Button({
    Name = tostring(text or "Button"),
    Desc = tip,
    Callback = function() safe(func) end,
   })
  end)
  ctl._ready = true
  return ctl
 end

 function Group:AddInput(idx, o)
  o = o or {}
  local last = tostring(o.Default or "")
  local ctl = newCtl("Input", o, last)
  ctl._native = add(self, function()
   return self._tab:Input({
    Name = o.Text or tostring(idx),
    Desc = o.Tooltip,
    Default = last,
    Placeholder = o.Placeholder or "",
    Numeric = o.Numeric == true,
    Flag = flagFor(idx),
    Callback = function(text)
     ctl.Value = tostring(text)
     if o.Finished then fire(ctl, ctl.Value) end
    end,
   })
  end)
  -- live updates for Finished=false inputs (and numeric filtering, like Linoria)
  local box = ctl._native and ctl._native._frame and ctl._native._frame:FindFirstChildWhichIsA("TextBox", true)
  if box then
   box:GetPropertyChangedSignal("Text"):Connect(function()
    local t = box.Text
    if o.Numeric and t ~= "" and not tonumber(t) then
     box.Text = last
     return
    end
    last = t
    ctl.Value = t
    if not o.Finished then fire(ctl, t) end
   end)
  end
  ctl._ready = true
  Options[idx] = ctl
  return ctl
 end

 function Group:AddLabel(text)
  text = tostring(text or "")
  local ctl = newCtl("Label", {}, nil)
  ctl._group = self
  ctl._text = text
  ctl._native = add(self, function()
   if #text > 40 then
    return self._tab:Paragraph({ Name = "Note", Content = text })
   end
   return self._tab:Label({ Text = text })
  end)
  ctl._ready = true
  return ctl
 end

 -- Label:AddKeyPicker -> replaces the label with a Flow keybind row
 function Ctl:AddKeyPicker(idx, o)
  o = o or {}
  local g = self._group
  local kctl = newCtl("Keybind", o, o.Default)
  if self._native and self._native.Destroy then pcall(self._native.Destroy, self._native) end
  kctl._native = add(g, function()
   return g._tab:Keybind({
    Name = o.Text or self._text or "Keybind",
    Default = o.Default,
    Flag = flagFor(idx),
    OnChanged = function(kc)
     kctl.Value = kc and kc.Name or nil
     if idx == "MenuKeybind" and Lib._win and kc then
      pcall(Lib._win.SetKeybind, Lib._win, kc)
     end
     fire(kctl, kc)
    end,
   })
  end)
  kctl._ready = true
  Options[idx] = kctl
  return kctl
 end

 function Group:AddDivider()
  add(self, function() return self._tab:Divider() end)
  return self
 end

 function Group:AddBlank()
  return self
 end

 local function newGroup(tabC, name)
  tabC._groupCount = tabC._groupCount + 1
  local g = setmetatable({ _tab = tabC._native, _cursor = tabC._groupCount * 100000 }, Group)
  if name and name ~= "" then
   add(g, function() return g._tab:Section(tostring(name)) end)
  end
  return g
 end

 local Tabbox = {}
 Tabbox.__index = Tabbox
 function Tabbox:AddTab(name)
  return newGroup(self._tabC, name)
 end

 local TabC = {}
 TabC.__index = TabC
 function TabC:AddLeftGroupbox(name) return newGroup(self, name) end
 function TabC:AddRightGroupbox(name) return newGroup(self, name) end
 function TabC:AddLeftTabbox() return setmetatable({ _tabC = self }, Tabbox) end
 function TabC:AddRightTabbox() return setmetatable({ _tabC = self }, Tabbox) end
 function TabC:BuildConfigSection()
  local g = newGroup(self, nil)
  add(g, function() return g._tab:ConfigManager({ Name = "Configs" }) end)
  return g
 end

 ---------------------------------------------------------------------------
 -- Window
 ---------------------------------------------------------------------------
 local ICONS = {
  Movement = "move",
  Aggression = "swords",
  Defense = "shield",
  Riot = "flame",
  Character = "user",
  Misc = "layers",
  Settings = "settings",
 }

 local WinC = {}
 WinC.__index = WinC
 function WinC:AddTab(name)
  local native = self._native:Tab(name, ICONS[name])
  return setmetatable({ _native = native, _groupCount = 0 }, TabC)
 end

 function Lib:CreateWindow(o)
  o = o or {}
  local title, subtitle = tostring(o.Title or "flow lua premium"), ""
  local t, s = title:match("^(.-)%s+%-%s+(.+)$")
  if t then title, subtitle = t, s end

  local native = Flow:Window({
   Title = title,
   Subtitle = subtitle,
   Keybind = Enum.KeyCode.RightShift,
   Size = UDim2.fromOffset(780, 540),
  })
  native.ConfigFolder = "flow lua premium/flow"
  native.ConfigName = "default"
  self._win = native
  self._backdrop = nil -- Fullscreen Flow backdrop intentionally removed.
  return setmetatable({ _native = native }, WinC)
 end

 function Lib:Notify(title, desc, time)
  local n = { Title = tostring(title or ""), Duration = tonumber(time) or 3 }
  if desc ~= nil and desc ~= "" then n.Content = tostring(desc) end
  pcall(function() Flow:Notify(n) end)
 end

 function Lib:OnUnload(fn)
  table.insert(self._onUnload, fn)
 end

 function Lib:UpdateFonts()
  local win = self._win
  if not win or not win.Gui then return end
  local font = self.Font or Enum.Font.GothamMedium
  -- "GothamMedium" is the stock selection; keep Flow's own typeface until another font is picked
  if font == Enum.Font.GothamMedium and not self._fontApplied then return end
  self._fontApplied = true
  local function apply(d)
   if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
    pcall(function() d.Font = Lib.Font end)
   end
  end
  for _, d in ipairs(win.Gui:GetDescendants()) do apply(d) end
  if not self._fontConn then
   self._fontConn = win.Gui.DescendantAdded:Connect(function(d)
    task.defer(apply, d)
   end)
   table.insert(self._conns, self._fontConn)
  end
 end

 function Lib:Unload()
  if self._unloaded then return end
  self._unloaded = true
  for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
  self._conns = {}
  if self._backdrop then pcall(self._backdrop.Destroy) end
  if self._win then pcall(function() self._win:Destroy() end) end
  if getgenv().Options == Options then getgenv().Options = nil end
  if getgenv().Toggles == Toggles then getgenv().Toggles = nil end
  for _, fn in ipairs(self._onUnload) do safe(fn) end
 end

 return Lib
end

local Library

task.spawn(function()
 local ui_ready = false
 local ui_ok, ui_error = xpcall(function()
  if load_generation ~= getgenv().__flowlua_generation then return end

 local _flow_lib, _flow_err = AC.FlowUI.build()
 if not _flow_lib then
  notify("flow lua premium", "airflow ui failed to load: " .. tostring(_flow_err))
  return
 end

 Library = _flow_lib
 getgenv().unload_all = function()
  getgenv().flowlua_loaded = false
  getgenv().flowlua_loading = false
  getgenv().__flowlua_generation = (tonumber(getgenv().__flowlua_generation) or 0) + 1
  pcall(Library.Unload, Library)
 end

local Window = Library:CreateWindow({
 Title="flow lua premium - discord.gg/cgA7R9Hex", Center=true, AutoShow=true, TabPadding=8, MenuFadeTime=0.2, })
local Tabs = {
 Movement=Window:AddTab("Movement"), Aggression=Window:AddTab("Aggression"), Defense=Window:AddTab("Defense"), Riot=Window:AddTab("Riot"), Character=Window:AddTab("Character"), Misc=Window:AddTab("Misc"), Settings=Window:AddTab("Settings"), }

task.wait()
local function tnotify(title, desc)
 Library:Notify(title, desc or "", 3)
end



local orbit_conn = nil

local orbit_phase = 0

local function orb_get_base()

 local tgt = config.orbit_target or "Self"
 if tgt == "Closest" then

  local closest = getgenv().get_closest(false)
  if closest and closest.Character then

   local t_hrp = closest.Character:FindFirstChild("HumanoidRootPart")
   if t_hrp then return t_hrp.Position end
  end
 end

 return nil
end

local function orb_apply_falloff(dist, i, total)

 local mode = config.orbit_falloff or "None"
 if mode == "Linear" then return dist * (1 - (i - 1) / total)
 elseif mode == "Exp" then return dist * math.exp(-3 * (i - 1) / total)
 elseif mode == "Sine" then return dist * math.abs(math.sin((i - 1) / total * math.pi))
 elseif mode == "Cosine" then return dist * math.abs(math.cos((i - 1) / total * math.pi * 0.5))
 else return dist end
end

local function orb_compute_offset(i, total, phase)

 local frac = (i - 1) / math.max(total - 1, 1)

 local radius = math.max(config.orbit_radius or 50000, 1)

 local height = config.orbit_height or 0

 local pattern = config.orbit_pattern or "Circle"

 local axis = config.orbit_axis or "Y"

 local dir_sign = (config.orbit_direction == "Counter-clockwise") and -1 or 1

 local jitter = config.orbit_jitter or 0

 local tightness = math.max(config.orbit_tightness or 10, 1)

 local wave_freq = config.orbit_wave_freq or 1

 local eff_dist = orb_apply_falloff(radius, i, total)

 local j = jitter > 0 and Vector3.new((math.random() - 0.5) * jitter, (math.random() - 0.5) * jitter * 0.2, (math.random() - 0.5) * jitter) or Vector3.zero

 local a = frac * math.pi * 2 * dir_sign + phase

 local ox, oy, oz
 if pattern == "Circle" then
  if axis == "Y" then
   ox = math.cos(a) * eff_dist
   oy = height
   oz = math.sin(a) * eff_dist
  elseif axis == "X" then
   ox = 0
   oy = math.cos(a) * eff_dist + height
   oz = math.sin(a) * eff_dist
  elseif axis == "Z" then
   ox = math.cos(a) * eff_dist
   oy = math.sin(a) * eff_dist + height
   oz = 0
  else
   ox = math.cos(a) * eff_dist
   oy = height
   oz = math.sin(a) * eff_dist
  end

 elseif pattern == "Ellipse" then
  ox = math.cos(a) * eff_dist
  oy = height
  oz = math.sin(a) * (eff_dist * 0.5)
 elseif pattern == "Figure8" then
  ox = math.sin(a) * eff_dist
  oy = height
  oz = math.sin(a * 2) * (eff_dist * 0.5)
 elseif pattern == "Helix" then
  ox = math.cos(a * tightness * 0.1) * eff_dist
  oy = height + frac * eff_dist * 0.5
  oz = math.sin(a * tightness * 0.1) * eff_dist
 elseif pattern == "Wave" then
  ox = math.cos(a) * eff_dist
  oy = math.sin(frac * math.pi * 2 * wave_freq + phase) * eff_dist * 0.4 + height
  oz = math.sin(a) * eff_dist
 elseif pattern == "Spiral" then

  local r_mod = eff_dist * (0.2 + 0.8 * frac)
  ox = math.cos(a * tightness * 0.1) * r_mod
  oy = height
  oz = math.sin(a * tightness * 0.1) * r_mod
 elseif pattern == "Pulse" then

  local pulse = math.abs(math.sin(frac * math.pi * wave_freq + phase))
  ox = math.cos(a) * eff_dist * pulse
  oy = height
  oz = math.sin(a) * eff_dist * pulse
 else
  ox = math.cos(a) * eff_dist
  oy = height
  oz = math.sin(a) * eff_dist
 end


 local chaos = config.orbit_chaos_blend or 0
 if chaos > 0 then
  ox = ox + (math.random() - 0.5) * eff_dist * chaos * 0.02
  oz = oz + (math.random() - 0.5) * eff_dist * chaos * 0.02
 end

 if config.orbit_invert_x then ox = -ox end
 if config.orbit_invert_z then oz = -oz end

 local y_bias = config.orbit_y_bias or 0
 oy = oy + y_bias

 local depth_floor = config.orbit_depth_floor or 0
 if depth_floor > 0 then oy = math.max(oy, -depth_floor) end
 return Vector3.new(ox, oy, oz) + j
end

local function orb_apply_warp(from_cf, to_pos)

 local target_cf = CFrame.new(to_pos)

 local mode = config.orbit_warp_mode or "Instant"

 local strength = math.clamp((config.orbit_warp_strength or 50) / 100, 0.01, 1)
 if mode == "Lerp" then
  return from_cf:Lerp(target_cf, strength)
 elseif mode == "Spring" then
  return from_cf:Lerp(target_cf, math.clamp(strength * 1.5, 0.01, 1))
 elseif mode == "Bounce" then

  local t = strength

  local bounce = math.abs(math.sin(t * math.pi * 3)) * (1 - t)
  return from_cf:Lerp(target_cf, math.clamp(t + bounce * 0.2, 0.01, 1))
 elseif mode == "Elastic" then

  local t = strength

  local elastic = math.sin(t * math.pi * 4.5) * math.exp(-t * 3)
  return from_cf:Lerp(target_cf, math.clamp(t + elastic * 0.15, 0.01, 1))
 else
  return target_cf
 end
end

getgenv().start_orbit = function()
 if orbit_conn then orbit_conn:Disconnect() end
 orbit_phase = 0
 orbit_conn = run_service.Heartbeat:Connect(function(dt)
  if not config.orbit_enabled then return end

  local hrp = getgenv().get_hrp(localplayer)

  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  if not hrp or not hum or hum.Health <= 0 then return end
  if hum:GetState() ~= Enum.HumanoidStateType.Physics then
   hum:ChangeState(Enum.HumanoidStateType.Physics)
  end

  orbit_phase = orbit_phase + dt * (config.orbit_speed or 5) * 0.5

  local iters = math.clamp(config.orbit_iters or 100, 1, 500)

  local layers = math.clamp(config.orbit_layer_count or 1, 1, 8)

  local layer_offset_rad = math.rad(config.orbit_layer_offset or 0)

  local base_override = orb_get_base()

  local iter_pos = hrp.CFrame
  for layer = 1, layers do

   local layer_phase = orbit_phase + layer_offset_rad * layer
   for i = 1, iters do

    local offset = orb_compute_offset(i, iters, layer_phase)

    local base_pos = base_override or iter_pos.Position

    local target_pos = Vector3.new(base_pos.X + offset.X, base_pos.Y + offset.Y, base_pos.Z + offset.Z)

    local final_cf = orb_apply_warp(iter_pos, target_pos)
    pcall(function() hrp.CFrame = final_cf end)
    iter_pos = hrp.CFrame
   end
  end

  if config.orbit_kill_velocity then
   hrp.AssemblyLinearVelocity = Vector3.zero
   hrp.AssemblyAngularVelocity = Vector3.zero
  end

  if config.orbit_sync_ragebot then
   srb_write(hrp, hrp.CFrame)
  end
 end)
end

getgenv().stop_orbit = function()
 if orbit_conn then orbit_conn:Disconnect(); orbit_conn = nil end
 config.orbit_enabled = false
 orbit_phase = 0
end

local fly_conn = nil

local fly_nc_conn = nil

local fly_nc_parts = {}

getgenv().start_fly = function()
 if fly_conn then fly_conn:Disconnect(); fly_conn = nil end
 if fly_nc_conn then fly_nc_conn:Disconnect(); fly_nc_conn = nil end
 fly_nc_parts = {}

 local cam = workspace.CurrentCamera
 fly_conn = run_service.Heartbeat:Connect(function(dt)
  if not config.fly_enabled then return end

  local hrp = getgenv().get_hrp(localplayer)
  if not hrp then return end

  local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
  if hum and config.fly_enabled then
   pcall(function() hum.PlatformStand = true end)
  end


  local spd = math.max(config.fly_speed or 60, 1)

  local cf = cam.CFrame

  local move = Vector3.zero

  local uis = user_input_service
  if uis:IsKeyDown(Enum.KeyCode.W) then move = move + cf.LookVector end
  if uis:IsKeyDown(Enum.KeyCode.S) then move = move - cf.LookVector end
  if uis:IsKeyDown(Enum.KeyCode.A) then move = move - cf.RightVector end
  if uis:IsKeyDown(Enum.KeyCode.D) then move = move + cf.RightVector end
  if uis:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
  if uis:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0, 1, 0) end
  if move.Magnitude > 0 then move = move.Unit * spd * dt end
  if config.fly_gravity_cancel then
   pcall(function()

    local mt = getrawmetatable(hrp)
    if mt then

     local ni = rawget(mt, "__newindex")
     if ni then
      ni(hrp, "AssemblyLinearVelocity", move.Magnitude > 0 and (move / dt) or Vector3.zero)
     end
    end
   end)

   pcall(function() hrp.AssemblyLinearVelocity = move.Magnitude > 0 and (move / dt) or Vector3.zero end)
  end

  pcall(function() hrp.CFrame = hrp.CFrame + move end)
 end)

 if config.fly_noclip then
  fly_nc_conn = run_service.Stepped:Connect(function()
   if not config.fly_enabled or not config.fly_noclip then return end

   local char = localplayer.Character
   if not char then return end
   for _, part in ipairs(char:GetDescendants()) do
    if part:IsA("BasePart") and not fly_nc_parts[part] then
     fly_nc_parts[part] = true
    end

    if part:IsA("BasePart") then
     pcall(function() part.CanCollide = false end)
    end
   end
  end)
 end
end


getgenv().stop_fly = function()
 if fly_conn then fly_conn:Disconnect(); fly_conn = nil end
 if fly_nc_conn then fly_nc_conn:Disconnect(); fly_nc_conn = nil end
 fly_nc_parts = {}
 config.fly_enabled = false

 local hrp = getgenv().get_hrp(localplayer)
 if hrp then
  pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
 end


 local hum = localplayer.Character and localplayer.Character:FindFirstChildOfClass("Humanoid")
 if hum then pcall(function() hum.PlatformStand = false end) end

 local char = localplayer.Character
 if char then
  for _, part in ipairs(char:GetDescendants()) do
   if part:IsA("BasePart") then
    pcall(function() part.CanCollide = true end)
   end
  end
 end
end

local bm_conn = nil
local bm_desync = {
    enabled = false,
    pitch = "down",
    yaw = "random",
    customPitch = 0,
    customYaw = 0,
    floorHide = false,
}

local function bm_applyDesync(hrp, rep, cframe)
    pcall(function()
        local mt = getrawmetatable(hrp)
        if mt then
            local fire = rawget(mt, "__index")
            if fire then fire(hrp, "CFrame", cframe) end
        end
    end)
    pcall(function()
        if rep and rep ~= hrp then
            rep.CFrame = cframe
        end
    end)
end

local function bm_getYawRad()
    local mode = config.bm_yaw_mode or "random"
    if mode == "random" then
        return math.rad(math.random(0, 360))
    elseif mode == "spin" then
        return math.rad((tick() * 360) % 360)
    elseif mode == "custom" then
        return math.rad(config.bm_custom_yaw or 0)
    end
    return 0
end

local function bm_getPitchRad()
    local mode = config.bm_pitch_mode or "down"
    if mode == "down" then return math.rad(89) end
    if mode == "up" then return math.rad(-89) end
    if mode == "random" then return math.rad(math.random(-89, 89)) end
    if mode == "custom" then return math.rad(config.bm_custom_pitch or 0) end
    return 0
end

local function bm_desyncCFrame(hrp)
    local base = hrp.CFrame
    local yaw = bm_getYawRad()
    local pitch = bm_getPitchRad()
    return CFrame.new(base.Position)
        * CFrame.Angles(0, yaw, 0)
        * CFrame.Angles(pitch, 0, 0)
end

getgenv().start_body_manip = function()
    if bm_conn then bm_conn:Disconnect(); bm_conn = nil end
    config.bm_enabled = true
    bm_conn = run_service.RenderStepped:Connect(function()
        if not config.bm_enabled then return end

        local hrp = getgenv().get_hrp(localplayer)
        if not hrp then return end

        local character = localplayer.Character
        if not character then return end

        local rep = character:FindFirstChild("PhysicsRepRootPart") or hrp

        if config.bm_floor_hide and hrp.Position.Y < 8 then
            bm_applyDesync(hrp, rep, hrp.CFrame * CFrame.new(0, -3, 0))
            return
        end

        bm_applyDesync(hrp, rep, bm_desyncCFrame(hrp))
    end)
end

getgenv().stop_body_manip = function()
    if bm_conn then bm_conn:Disconnect(); bm_conn = nil end
    config.bm_enabled = false
    pcall(function()
        local character = localplayer.Character
        if not character then return end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        local rep = character:FindFirstChild("PhysicsRepRootPart")
        if hrp and rep then rep.CFrame = hrp.CFrame end
    end)
end

getgenv().unload_all = function()

 getgenv().flowlua_loaded = false
 getgenv().flowlua_loading = false
 getgenv().__flowlua_generation = (tonumber(getgenv().__flowlua_generation) or 0) + 1
 pcall(getgenv().stop_anti_afk); pcall(getgenv().stop_void_spam)
 pcall(getgenv().stop_autocollect); pcall(getgenv().stop_safe_zone); pcall(getgenv().stop_return_home)
 pcall(getgenv().stop_teleport_loop);
 pcall(getgenv().stop_teleport_to_target); pcall(getgenv().stop_riot_abuser)
 pcall(getgenv().stop_riot_abuser_v1); pcall(getgenv().stop_riot_abuser_v2); pcall(getgenv().stop_slingshot_bypass); pcall(getgenv().stop_bow_bypass); pcall(getgenv().stop_dagger_bypass); pcall(getgenv().stop_projectile_tp); pcall(getgenv().stop_projectile_rapid_fire); pcall(getgenv().stop_melee_bypass)
 pcall(getgenv().stop_evade)
 pcall(getgenv().stop_orbit)
 pcall(getgenv().stop_perfect_block)
 pcall(getgenv().stop_extra_voidspam)
 pcall(getgenv().stop_void_hide)
 pcall(getgenv().disable_voidspam_type)
 pcall(getgenv().stop_desync)
 pcall(getgenv().stop_unhittable_desync)
 pcall(getgenv().stop_body_manip)
 pcall(getgenv().stop_anti_aim)
 pcall(getgenv().stop_prediction)
 pcall(getgenv().stop_fake_position)
 pcall(getgenv().stop_pixelation)
 pcall(getgenv().stop_anti_void_bait)
 pcall(getgenv().stop_kicia_counter)
 pcall(getgenv().stop_fly)
 config.ffa_hopping_enabled = false
 for _, c in ipairs(getgenv().all_connections) do pcall(function() c:Disconnect() end) end

 getgenv().all_connections = {}
 pcall(function() Library:Unload() end)
 pcall(destroyXYZOverlay)
end

local VoidMainTabbox = Tabs.Movement:AddLeftTabbox()

local LeftVoid = VoidMainTabbox:AddTab("Void")

local CustVoid = LeftVoid

local CustVoidB = LeftVoid

local OrbitEvadeTabbox = Tabs.Movement:AddRightTabbox()

local OrbitTab = OrbitEvadeTabbox:AddTab("Orbit")

local EvadeTab = OrbitEvadeTabbox:AddTab("Evade")

local EvadeBox = EvadeTab

local VoidHideBox = Tabs.Movement:AddRightGroupbox("Void Hide")

local _xyzSg, _xyzConn, _xyzVals

local function buildXYZOverlay()
 if _xyzSg and _xyzSg.Parent then return end

 local sg = Instance.new("ScreenGui")
 sg.Name = "MeowluaXYZOverlay"
 sg.ResetOnSpawn = false
 sg.DisplayOrder = 9999

 local coreOk = pcall(function() sg.Parent = game:GetService("CoreGui") end)
 if not coreOk then sg.Parent = localplayer:WaitForChild("PlayerGui") end
 _xyzSg = sg

 local panel = Instance.new("Frame")
 panel.Size = UDim2.new(0, 170, 0, 96)
 panel.Position = UDim2.new(0, 14, 0.5, -48)
 panel.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
 panel.BackgroundTransparency = 0.08
 panel.BorderSizePixel = 0
 panel.Parent = sg

 local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0,7); pc.Parent = panel

 local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(60,60,65); ps.Thickness = 1; ps.Transparency = 0.3; ps.Parent = panel

 local hdr = Instance.new("Frame")
 hdr.Size = UDim2.new(1,0,0,26); hdr.BackgroundTransparency = 1; hdr.Parent = panel

 local dot = Instance.new("Frame")
 dot.Size = UDim2.new(0,7,0,7); dot.Position = UDim2.new(0,10,0.5,-3)
 dot.BackgroundColor3 = Color3.fromRGB(210,55,55); dot.BorderSizePixel = 0; dot.Parent = hdr

 local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1,0); dc.Parent = dot

 local ttl = Instance.new("TextLabel")
 ttl.Size = UDim2.new(0,80,1,0); ttl.Position = UDim2.new(0,23,0,0)
 ttl.BackgroundTransparency = 1; ttl.Text = "flow lua premium"
 ttl.TextColor3 = Color3.fromRGB(220,220,225); ttl.Font = Enum.Font.GothamBold
 ttl.TextSize = 12; ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Parent = hdr

 local badge = Instance.new("TextLabel")
 badge.Size = UDim2.new(0,48,0,16); badge.Position = UDim2.new(1,-54,0.5,-8)
 badge.BackgroundColor3 = Color3.fromRGB(38,38,42); badge.Text = "PRIVATE"
 badge.TextColor3 = Color3.fromRGB(160,160,168); badge.Font = Enum.Font.GothamBold
 badge.TextSize = 9; badge.BorderSizePixel = 0; badge.Parent = hdr

 local bdc = Instance.new("UICorner"); bdc.CornerRadius = UDim.new(0,4); bdc.Parent = badge

 local bds = Instance.new("UIStroke"); bds.Color = Color3.fromRGB(70,70,76); bds.Thickness = 1; bds.Parent = badge

 local sep = Instance.new("Frame")
 sep.Size = UDim2.new(1,-16,0,1); sep.Position = UDim2.new(0,8,0,27)
 sep.BackgroundColor3 = Color3.fromRGB(55,55,60); sep.BorderSizePixel = 0; sep.Parent = panel

 _xyzVals = {}
 for i, axis in ipairs({"X","Y","Z"}) do

 local y = 30 + (i-1)*20

 local al = Instance.new("TextLabel")
 al.Size = UDim2.new(0,18,0,18); al.Position = UDim2.new(0,10,0,y)
 al.BackgroundTransparency = 1; al.Text = axis
 al.TextColor3 = Color3.fromRGB(120,120,130); al.Font = Enum.Font.GothamBold
 al.TextSize = 12; al.TextXAlignment = Enum.TextXAlignment.Left; al.Parent = panel

 local vl = Instance.new("TextLabel")
 vl.Size = UDim2.new(1,-30,0,18); vl.Position = UDim2.new(0,14,0,y)
 vl.BackgroundTransparency = 1; vl.Text = "0"
 vl.TextColor3 = Color3.fromRGB(230,230,235); vl.Font = Enum.Font.Gotham
 vl.TextSize = 12; vl.TextXAlignment = Enum.TextXAlignment.Right; vl.Parent = panel
 _xyzVals[axis] = vl
 end

 local function fmtNum(v)

 local s = tostring(math.floor(v + 0.5))

 local k; repeat s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
 return s
 end

 _xyzConn = run_service.Heartbeat:Connect(function()

 local char = localplayer.Character

 local hrp = char and char:FindFirstChild("HumanoidRootPart")
 if hrp then

 local p = hrp.Position
 _xyzVals.X.Text = fmtNum(p.X)
 _xyzVals.Y.Text = fmtNum(p.Y)
 _xyzVals.Z.Text = fmtNum(p.Z)
 else
 _xyzVals.X.Text = "-"; _xyzVals.Y.Text = "-"; _xyzVals.Z.Text = "-"
 end end)
end

local function destroyXYZOverlay()
 if _xyzConn then pcall(function() _xyzConn:Disconnect() end); _xyzConn = nil end
 if _xyzSg then pcall(function() _xyzSg:Destroy() end); _xyzSg = nil end
end

LeftVoid:AddToggle("vs_en", { Text="Void", Default=false, Tooltip="Makes you unhittable utilizing void movement." }):OnChanged(function(v) config.vst_enabled = v
 play_toggle_sound()
 if v then
  getgenv().start_voidspam_type()
  buildXYZOverlay()
  if (config.vst_type or "Unhittability") == "Unhittability" then
   config.melee_bypass_enabled = true
   config.melee_bypass_y_range = config.vst_unhittability_y_range or 10
   if not melee_active then getgenv().start_melee_bypass() end
  end
 else
  getgenv().disable_voidspam_type()
  destroyXYZOverlay()
  if not config.godmode_enabled then
   getgenv().stop_melee_bypass()
  end
 end
end)

local vs_type_drop = LeftVoid:AddDropdown("vs_type_sel", { Text="Void Mode", Default=1, Values={"Unhittability","Defend","Attack","Bait","Extreme","Random"} })

local vs_void_direction_drop = LeftVoid:AddDropdown("vs_void_dir_sel", { Text="Void Direction", Default=1, Values={"Random","Forward","Backward","Left","Right","Up","Down","Camera","Directional"} })
vs_void_direction_drop:OnChanged(function(v) config.vs_void_direction = v end)

LeftVoid:AddSlider("vst_spin_spd", { Text="Spin Speed", Default=1e85, Min=1, Max=1e85, Rounding=0, Tooltip="Spins you very fast while voiding." }):OnChanged(function(v) config.vst_spin_speed = v end)
EvadeBox:AddToggle("evd_en", { Text="Evade", Default=false, Tooltip="Like void but way more optimized but less reliable." }):OnChanged(function(v) config.evade_enabled = v
 play_toggle_sound()
 if v then getgenv().start_evade(); buildXYZOverlay() else getgenv().stop_evade(); destroyXYZOverlay() end end)
EvadeBox:AddSlider("evd_mn", { Text="Min Distance", Default=5000, Min=100, Max=50000, Rounding=0 }):OnChanged(function(v) config.evade_min_dist = v end)
EvadeBox:AddSlider("evd_mx", { Text="Max Distance", Default=50000, Min=100, Max=500000, Rounding=0 }):OnChanged(function(v) config.evade_max_dist = v end)
EvadeBox:AddSlider("evd_dl", { Text="Delay", Default=10, Min=1, Max=1000, Rounding=0 }):OnChanged(function(v) config.evade_delay = v / 100 end)
EvadeBox:AddSlider("evd_ca", { Text="Chaos Amplitude", Default=1, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evade_chaos_amp = v end)
EvadeBox:AddSlider("evd_yb", { Text="Y Bias", Default=0, Min=-50000, Max=50000, Rounding=0 }):OnChanged(function(v) config.evade_y_bias = v end)
EvadeBox:AddDropdown("evd_sh", { Text="Shape", Default=1, Values={"Sphere","Cube","Flat","Vertical","Helix"} }):OnChanged(function(v) config.evade_shape = v end)
EvadeBox:AddDropdown("evd_ym", { Text="Y Mode", Default=1, Values={"Random","Up","Down","Flat"} }):OnChanged(function(v) config.evade_y_mode = v end)
EvadeBox:AddDropdown("evd_ax", { Text="Axis Lock", Default=1, Values={"None","X","Y","Z","XZ"} }):OnChanged(function(v) config.evade_axis_lock = v end)
EvadeBox:AddDropdown("evd_wp", { Text="Warp Mode", Default=1, Values={"Instant","Lerp"} }):OnChanged(function(v) config.evade_warp_mode = v end)
EvadeBox:AddToggle("evd_kv", { Text="Kill Velocity", Default=true }):OnChanged(function(v) config.evade_kill_velocity = v end)
EvadeBox:AddToggle("evd_ix", { Text="Invert X", Default=false }):OnChanged(function(v) config.evade_invert_x = v end)
EvadeBox:AddToggle("evd_iz", { Text="Invert Z", Default=false }):OnChanged(function(v) config.evade_invert_z = v end)
VoidHideBox:AddToggle("vh_en", { Text="Void Hide", Default=false, Tooltip="Teleports you into the void." }):OnChanged(function(v) config.void_hide_enabled = v
 if v then getgenv().start_void_hide() else getgenv().stop_void_hide() end end)
VoidHideBox:AddSlider("vh_x", { Text="X Distance", Default=1000000, Min=1, Max=12e25, Rounding=0 }):OnChanged(function(v) config.void_hide_x = v end)
VoidHideBox:AddSlider("vh_y", { Text="Y Distance", Default=9e25, Min=1, Max=12e25, Rounding=0 }):OnChanged(function(v) config.void_hide_y = v end)
VoidHideBox:AddSlider("vh_z", { Text="Z Distance", Default=1000000, Min=1, Max=12e25, Rounding=0 }):OnChanged(function(v) config.void_hide_z = v end)
VoidHideBox:AddToggle("vh_srb", { Text="Sync To Ragebot", Default=false, Tooltip="Takes effect on non client sided ragebots, causing you to void hide and rage at the same time." }):OnChanged(function(v) config.void_hide_sync_to_ragebot=v end)

local vst_hide_slider = LeftVoid:AddSlider("vst_hide_time_sl", { Text="Hide Time", Default=30, Min=1, Max=100, Rounding=0 })

local vst_attack_slider = LeftVoid:AddSlider("vst_attack_time_sl", { Text="Attack Time", Default=30, Min=1, Max=100, Rounding=0 })

local vst_hide_mode_drop = LeftVoid:AddDropdown("vst_hide_mode_sel",{ Text="Hide Time Mode", Default=1, Values={"Unhittability","Defend","Extreme"} })

local vst_defend_slider = LeftVoid:AddSlider("vst_defend_int_sl", { Text="Defend Intensity", Default=50, Min=1, Max=100, Rounding=0 })

local vst_attack_tracking_drop = LeftVoid:AddDropdown("vst_atk_tracking", { Text="Tracking Type", Default=1, Values={"Teleportation"} })

local vst_attack_method_drop= LeftVoid:AddDropdown("vst_atk_method", { Text="Tracking Method", Default=1, Values={"Adaptive","Predictive"} })

local vst_prox_toggle = LeftVoid:AddToggle("vst_prox_esc", { Text="Escape", Default=true, Tooltip="Teleports a selected distance away when a player gets close" })

local vst_prox_slider = LeftVoid:AddSlider("vst_prox_radius", { Text="Escape Trigger Radius", Default=20, Min=1, Max=200, Rounding=0 })

local vst_escape_dist_slider= LeftVoid:AddSlider("vst_escape_dist", { Text="Escape Distance", Default=1000,Min=100,Max=10000,Rounding=0 })

local vst_unhit_yrange_slider = LeftVoid:AddSlider("vst_unhit_yrange_sl", { Text="Activation Range", Default=10, Min=1, Max=50, Rounding=0, Tooltip="Activates melee bypass only when the target is at this many studs downward on the Y axis." })
vst_hide_slider:OnChanged(function(v) config.vst_hide_time = v / 100 end)
vst_attack_slider:OnChanged(function(v) config.vst_attack_time = v / 100 end)
vst_hide_mode_drop:OnChanged(function(v) if v == 1 or v == "Unhittability" then config.vst_hide_mode = "Unhittability"
 elseif v == 2 or v == "Defend" then config.vst_hide_mode = "Defend"
 elseif v == 3 or v == "Extreme" then config.vst_hide_mode = "Extreme"
 else config.vst_hide_mode = "Unhittability" end end)
vst_defend_slider:OnChanged(function(v) config.vst_defend_intensity = v end)
vst_attack_tracking_drop:OnChanged(function(v) config.vst_attack_tracking_type = v end)
vst_attack_method_drop:OnChanged(function(v) config.vst_attack_method = v end)
vst_prox_toggle:OnChanged(function(v) config.vst_defend_proximity_escape = v end)
vst_prox_slider:OnChanged(function(v) config.vst_defend_proximity_radius = v end)
vst_escape_dist_slider:OnChanged(function(v) config.vst_defend_escape_dist = v end)
vst_unhit_yrange_slider:OnChanged(function(v) config.vst_unhittability_y_range = v; config.melee_bypass_y_range = v end)

local vst_bait_depth_slider = LeftVoid:AddSlider("vst_bait_depth_sl", { Text="Bait Depth", Default=20, Min=1, Max=40, Rounding=0 })
vst_bait_depth_slider:OnChanged(function(v) config.vst_bait_depth = v end)

local function vst_update_visibility(mode)

 local is_attack = mode == "Attack"

 local is_defend = mode == "Defend"

 local is_evade = mode == "Random"

 local is_unhit = mode == "Unhittability"
 pcall(function() vst_hide_slider:SetVisible(is_attack) end)
 pcall(function() vst_hide_mode_drop:SetVisible(is_attack) end)
 pcall(function() vst_attack_slider:SetVisible(is_attack) end)
 pcall(function() vst_attack_tracking_drop:SetVisible(is_attack) end)
 pcall(function() vst_attack_method_drop:SetVisible(is_attack) end)
 pcall(function() vst_defend_slider:SetVisible(is_defend or is_attack) end)
 pcall(function() vst_prox_toggle:SetVisible(is_defend or is_unhit) end)
 pcall(function() vst_prox_slider:SetVisible(is_defend or is_unhit) end)
 pcall(function() vst_escape_dist_slider:SetVisible(is_defend or is_unhit) end)
 pcall(function() vst_bait_depth_slider:SetVisible(mode == "Bait") end)
 pcall(function() vst_unhit_yrange_slider:SetVisible(is_unhit) end)
end

vst_update_visibility(config.vst_type or "Unhittability")

vs_type_drop:OnChanged(function(v) config.vst_type = v
 vst_update_visibility(v)
 if config.vst_enabled then
  getgenv().stop_voidspam_type()
  vst_last_pos = nil
  vs_spiral = 0
  vs_wave = 0
  vs_helix = 0
  vs_orbit_angle = 0
  vs_phase_hex = 0
  vs_phase_oct = 0
  vs_phase_star = 0
  vs_phase_cross = 0
  vs_phase_rhombus = 0
  evs_phase = 0
  evs_tick_acc = 0
  getgenv().start_voidspam_type()
  if v == "Unhittability" then
   config.melee_bypass_enabled = true
   config.melee_bypass_y_range = config.vst_unhittability_y_range or 10
   if not melee_active then getgenv().start_melee_bypass() end
  else
   if not config.godmode_enabled then
    getgenv().stop_melee_bypass()
   end
  end
 end
end)
LeftVoid:AddSlider("evs_burst_main", { Text="Iterations", Default=100, Min=1, Max=1000, Rounding=0 }):OnChanged(function(v) config.evs_burst=v end)
LeftVoid:AddToggle("evs_kv_main", { Text="Kill Velocity", Default=true }):OnChanged(function(v) config.evs_kill_velocity=v end)
LeftVoid:AddToggle("evs_sb_main", { Text="Snap Back", Default=false }):OnChanged(function(v) config.evs_snap_back=v end)
LeftVoid:AddToggle("evs_srb", { Text="Sync To Ragebot", Default=false, Tooltip="Doesn't let non client sided ragebots override your voidspam." }):OnChanged(function(v) config.evs_sync_to_ragebot=v end)
LeftVoid:AddToggle("vs_char_origin", { Text="Character Origin", Default=false, Tooltip="Uses your character's position as the base origin for all void offsets instead of the last void position." }):OnChanged(function(v) config.vs_char_origin = v end)
LeftVoid:AddSlider("vs_min_dist_sl", { Text="Min Distance", Default=1, Min=1, Max=50000, Rounding=0 }):OnChanged(function(v) config.vs_min_dist = v end)
LeftVoid:AddSlider("vs_max_dist_sl", { Text="Max Distance", Default=50000, Min=1, Max=500000, Rounding=0 }):OnChanged(function(v) config.vs_max_dist = v end)

local iter_rad_tog = LeftVoid:AddToggle("evs_iter_rad_tog", { Text="Iteration Radius", Default=false, Tooltip="Lets you control axis distance." })

local iter_rad_vertical = LeftVoid:AddSlider("evs_iter_rad_vert", { Text="Vertical Radius", Default=30, Min=1, Max=100, Rounding=0, Tooltip="Controls how far you iterate on Y axis" })

local iter_rad_horizontal = LeftVoid:AddSlider("evs_iter_rad_horiz", { Text="Horizontal Radius", Default=30, Min=1, Max=100, Rounding=0, Tooltip="Controls how far you iterate on XZ." })

local iter_rad_forward = LeftVoid:AddSlider("evs_iter_rad_fwd", { Text="Forward Radius", Default=30, Min=1, Max=100, Rounding=0, Tooltip="Controls how far you iterate in the forward/backward direction." })

local iter_rad_lateral = LeftVoid:AddSlider("evs_iter_rad_lat", { Text="Lateral Radius", Default=30, Min=1, Max=100, Rounding=0, Tooltip="Controls how far you iterate left and right." })

local iter_rad_diagonal = LeftVoid:AddSlider("evs_iter_rad_diag", { Text="Diagonal Radius", Default=30, Min=1, Max=100, Rounding=0, Tooltip="Controls how far you iterate diagonally across axes." })

local iter_rad_depth = LeftVoid:AddSlider("evs_iter_rad_depth", { Text="Depth Radius", Default=30, Min=1, Max=100, Rounding=0, Tooltip="Controls how far you iterate along the depth axis into the void." })

local iter_rad_x = LeftVoid:AddSlider("evs_iter_rad_x", { Text="X Radius", Default=500000, Min=1, Max=100000000, Rounding=0, Tooltip="Controls how far you iterate on the X axis specifically." })

local iter_rad_y = LeftVoid:AddSlider("evs_iter_rad_y", { Text="Y Radius", Default=500000, Min=1, Max=100000000, Rounding=0, Tooltip="Controls how far you iterate on the Y axis specifically." })

local iter_rad_z = LeftVoid:AddSlider("evs_iter_rad_z", { Text="Z Radius", Default=500000, Min=1, Max=100000000, Rounding=0, Tooltip="Controls how far you iterate on the Z axis specifically." })

local function update_iter_rad_visibility(v)
 pcall(function() iter_rad_vertical:SetVisible(v) end)
 pcall(function() iter_rad_horizontal:SetVisible(v) end)
 pcall(function() iter_rad_forward:SetVisible(v) end)
 pcall(function() iter_rad_lateral:SetVisible(v) end)
 pcall(function() iter_rad_diagonal:SetVisible(v) end)
 pcall(function() iter_rad_depth:SetVisible(v) end)
 pcall(function() iter_rad_x:SetVisible(v) end)
 pcall(function() iter_rad_y:SetVisible(v) end)
 pcall(function() iter_rad_z:SetVisible(v) end)
end

update_iter_rad_visibility(false)
iter_rad_tog:OnChanged(function(v)
 config.evs_iter_rad_directional = v
 update_iter_rad_visibility(v)
 if not v then config.evs_iter_radius = 500000 * (30 / 30) ^ 2 end
end)

iter_rad_vertical:OnChanged(function(v) if config.evs_iter_rad_directional then config.evs_iter_radius = 500000 * (v / 30) ^ 2 end end)
iter_rad_horizontal:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_xp = math.floor(500000 * (v / 30) ^ 2); config.vs_dir_zp = config.vs_dir_xp; config.vs_dir_xn = config.vs_dir_xp; config.vs_dir_zn = config.vs_dir_xp end end)
iter_rad_forward:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_zp = math.floor(500000 * (v / 30) ^ 2); config.vs_dir_zn = config.vs_dir_zp end end)
iter_rad_lateral:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_xp = math.floor(500000 * (v / 30) ^ 2); config.vs_dir_xn = config.vs_dir_xp end end)
iter_rad_diagonal:OnChanged(function(v) if config.evs_iter_rad_directional then local r = math.floor(500000 * (v / 30) ^ 2); config.vs_dir_xp = r; config.vs_dir_zp = r; config.vs_dir_xn = r; config.vs_dir_zn = r end end)
iter_rad_depth:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_yp = math.floor(500000 * (v / 30) ^ 2); config.vs_dir_yn = config.vs_dir_yp end end)
iter_rad_x:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_xp = v; config.vs_dir_xn = v end end)
iter_rad_y:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_yp = v; config.vs_dir_yn = v; config.evs_iter_radius = v end end)
iter_rad_z:OnChanged(function(v) if config.evs_iter_rad_directional then config.vs_dir_zp = v; config.vs_dir_zn = v end end)
LeftVoid:AddSlider("vs2_dxp",{ Text="X+ Direction", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_dir_xp=v end)
LeftVoid:AddSlider("vs2_dxn",{ Text="X- Direction", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_dir_xn=v end)
LeftVoid:AddSlider("vs2_dyp",{ Text="Y+ Direction", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_dir_yp=v end)
LeftVoid:AddSlider("vs2_dyn",{ Text="Y- Direction", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_dir_yn=v end)
LeftVoid:AddSlider("vs2_dzp",{ Text="Z+ Direction", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_dir_zp=v end)
LeftVoid:AddSlider("vs2_dzn",{ Text="Z- Direction", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_dir_zn=v end)

local RandVoid = Tabs.Movement:AddRightGroupbox("Randomizer")

local randomizer_seed_input = RandVoid:AddInput("rand_seed_in", { Text="Seeds", Default="", Placeholder="Enter seed...", Numeric=false, Finished=false })
randomizer_seed_input:OnChanged(function(v) config.randomizer_seed = v end)
RandVoid:AddDropdown("rand_mode1", { Text="Mode", Default=1, Values={"Random","Uniform","Weighted","Radial","Axial","Spiral","Chaos"} }):OnChanged(function(v) config.randomizer_mode1=v end)
RandVoid:AddButton("Random Seed", function()

 local chars = "abcdefghijklmnopqrstuvwxyz0123456789"

 local seed = ""
 for i = 1, 12 do

 local idx = math.random(1, #chars)
 seed = seed .. chars:sub(idx, idx)
 end

 config.randomizer_seed = seed
 pcall(function() randomizer_seed_input:SetValue(seed) end)
end)

RandVoid:AddButton("Generate Seed", function()

 local seed = config.randomizer_seed or ""
 if seed == "" then return end

 local hash = 0
 for i = 1, #seed do
 hash = (hash * 31 + string.byte(seed, i)) % 2147483647
 end

 math.randomseed(hash)
 config.randomizer_active = true
end)

CustVoid:AddSlider("vs_cnt", { Text="Iterations", Default=500, Min=1, Max=500, Rounding=0 }):OnChanged(function(v) config.et_total=v end)
CustVoid:AddToggle("vs_stab", { Text="Stabilizer", Default=false }):OnChanged(function(v) config.vs_stabilizer_enabled=v end)
CustVoid:AddSlider("vs_stb", { Text="Stability", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_stability=v end)
CustVoid:AddToggle("vs_smooth",{ Text="Smoothness", Default=false }):OnChanged(function(v) config.vs_smoothness_enabled=v end)
CustVoid:AddSlider("vs_smo", { Text="Smooth Alpha", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_smoothness=v end)
CustVoid:AddToggle("vs_res", { Text="Position Resolver", Default=false }):OnChanged(function(v) config.vs_pos_resolver=v end)
CustVoid:AddToggle("vs_restore",{ Text="Position Restore", Default=false }):OnChanged(function(v) config.vs_pos_restore=v end)
CustVoid:AddToggle("vs_pos_cl",  { Text="Position Clamp", Default=false }):OnChanged(function(v) config.vs_pos_clamp=v end)
CustVoid:AddSlider("vs_clamp_r", { Text="Clamp Radius", Default=50000, Min=100, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_pos_clamp_radius=v end)
CustVoid:AddSlider("vs2_rad",{ Text="Orbit Radius", Default=5000, Min=1, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_radius=v end)
CustVoid:AddSlider("vs2_ci", { Text="Chaos Intensity",Default=1, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_chaos_intensity=v end)
CustVoid:AddSlider("vs2_vb", { Text="Vertical Bias", Default=0, Min=-100,Max=100, Rounding=0 }):OnChanged(function(v) config.vs_vertical_bias=v end)
CustVoid:AddSlider("vs2_wb", { Text="Warp Bias", Default=0, Min=-100,Max=100, Rounding=0 }):OnChanged(function(v) config.vs_warp_bias=v end)
CustVoid:AddSlider("vs_dep_bias",{ Text="Depth Bias", Default=0, Min=-50000,Max=50000, Rounding=0 }):OnChanged(function(v) config.vs_depth_bias=v end)
CustVoid:AddSlider("vs_ch_amp", { Text="Chaos Amplitude", Default=1, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_chaos_amp=v end)
CustVoid:AddSlider("vs_bd", { Text="Burst Delay", Default=0, Min=0, Max=500, Rounding=0 }):OnChanged(function(v) config.vs_burst_delay=v end)
CustVoid:AddSlider("vs_als", { Text="Axis Lock Strength",Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_axis_lock_strength=v end)
CustVoid:AddSlider("vs_intensity", { Text="Intensity", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_intensity=v end)
CustVoid:AddSlider("vs_spread_b", { Text="Spread Bias", Default=0, Min=-100, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_spread_bias=v end)
CustVoid:AddSlider("vs_layer_stg", { Text="Layer Stagger", Default=0, Min=0, Max=500, Rounding=0 }):OnChanged(function(v) config.vs_layer_stagger=v end)
CustVoid:AddSlider("vs_scatter_l", { Text="Scatter Layers", Default=1, Min=1, Max=8, Rounding=0 }):OnChanged(function(v) config.vs_scatter_layers=v end)
CustVoid:AddSlider("vs_depth_cl", { Text="Depth Clamp", Default=0, Min=0, Max=100000000, Rounding=0 }):OnChanged(function(v) config.vs_depth_clamp=v end)
CustVoid:AddSlider("vs_rs", { Text="Radial Scale", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_radial_scale=v/10 end)
CustVoid:AddSlider("vs_pr", { Text="Pulse Rate", Default=10, Min=1, Max=200, Rounding=0 }):OnChanged(function(v) config.vs_pulse_rate=v/10 end)
CustVoid:AddDropdown("vs2_mv",{ Text="Movement Mode",Default=1, Values={"Random","Orbit","Helix","Chaos","Wave","Pulse"} }):OnChanged(function(v) config.vs_movement=v end)
CustVoid:AddSlider("vs_iter_x_scale", { Text="Iteration X Scale", Default=10, Min=1, Max=100, Rounding=0, Tooltip="Scales the X axis component of each iteration offset." }):OnChanged(function(v)
 config.vs_gravity_vector_x = (v - 10) / 90
end)

CustVoid:AddSlider("vs_iter_y_scale", { Text="Iteration Y Scale", Default=10, Min=1, Max=100, Rounding=0, Tooltip="Scales the Y axis component of each iteration offset." }):OnChanged(function(v)
 config.vs_gravity_vector_y = -(v / 10)
end)

CustVoid:AddSlider("vs_iter_z_scale", { Text="Iteration Z Scale", Default=10, Min=1, Max=100, Rounding=0, Tooltip="Scales the Z axis component of each iteration offset." }):OnChanged(function(v)
 config.vs_gravity_vector_z = (v - 10) / 90
end)

CustVoid:AddSlider("vs_depth_pf2", { Text="Depth Pulse Freq", Default=10, Min=1, Max=200, Rounding=0 }):OnChanged(function(v) config.vs_depth_pulse_freq = v / 10 end)
CustVoid:AddSlider("vs_depth_pa2", { Text="Depth Pulse Amp", Default=0, Min=0, Max=100000, Rounding=0 }):OnChanged(function(v) config.vs_depth_pulse_amp = v end)
CustVoid:AddSlider("vs_spiral_ox2", { Text="Spiral Offset X", Default=0, Min=-50000, Max=50000, Rounding=0 }):OnChanged(function(v) config.vs_spiral_offset_x = v end)
CustVoid:AddSlider("vs_spiral_oz2", { Text="Spiral Offset Z", Default=0, Min=-50000, Max=50000, Rounding=0 }):OnChanged(function(v) config.vs_spiral_offset_z = v end)
CustVoid:AddToggle("vs_node_grav2", { Text="Node Gravity", Default=false, Tooltip="Pulls void nodes toward each other." }):OnChanged(function(v) config.vs_node_gravity=v end)
CustVoid:AddToggle("vs_flux_rev2", { Text="Flux Reversal", Default=false, Tooltip="Periodically reverses void flux direction." }):OnChanged(function(v) config.vs_flux_reversal=v end)
CustVoid:AddToggle("vs_chaos_fb2", { Text="Chaos Feedback", Default=false, Tooltip="Uses previous void movement as chaotic input." }):OnChanged(function(v) config.vs_chaos_feedback=v end)

CustVoid:AddSlider("vs_turb_freq", { Text="Turbulence Frequency", Default=10, Min=1, Max=200, Rounding=0 }):OnChanged(function(v) config.vs_turbulence_freq = v / 10 end)
CustVoid:AddSlider("vs_turb_amp", { Text="Turbulence Amplitude", Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_turbulence_amp = v / 10 end)
CustVoid:AddSlider("vs_vortex_str", { Text="Vortex Strength", Default=0, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) config.vs_vortex_strength = v end)
CustVoid:AddSlider("vs_vortex_rad", { Text="Vortex Radius", Default=10000, Min=100, Max=500000, Rounding=0 }):OnChanged(function(v) config.vs_vortex_radius = v end)
CustVoid:AddSlider("vs_layer_twist_sl", { Text="Layer Twist", Default=0, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) config.vs_layer_twist = v end)
CustVoid:AddSlider("vs_quantum_prob", { Text="Quantum Jump Probability", Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_quantum_jump_prob = v end)
CustVoid:AddSlider("vs_quantum_sc", { Text="Quantum Jump Scale", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_quantum_jump_scale = v / 10 end)
CustVoid:AddSlider("vs_fractal_d", { Text="Fractal Depth", Default=1, Min=1, Max=6, Rounding=0 }):OnChanged(function(v) config.vs_fractal_depth = v end)
CustVoid:AddSlider("vs_fractal_sc", { Text="Fractal Scale", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_fractal_scale = v / 10 end)
CustVoid:AddSlider("vs_echo_tr", { Text="Echo Trail Count", Default=0, Min=0, Max=20, Rounding=0 }):OnChanged(function(v) config.vs_echo_trail = v end)
CustVoid:AddSlider("vs_echo_dr", { Text="Echo Decay Rate", Default=5, Min=1, Max=10, Rounding=0 }):OnChanged(function(v) config.vs_echo_decay_rate = v / 10 end)
CustVoid:AddSlider("vs_gv_x", { Text="Gravity Vector X", Default=0, Min=-100, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_gravity_vector_x = v / 100 end)
CustVoid:AddSlider("vs_gv_y", { Text="Gravity Vector Y", Default=-10, Min=-100, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_gravity_vector_y = v / 100 end)
CustVoid:AddSlider("vs_gv_z", { Text="Gravity Vector Z", Default=0, Min=-100, Max=100, Rounding=0 }):OnChanged(function(v) config.vs_gravity_vector_z = v / 100 end)
CustVoid:AddSlider("vs_depth_pf", { Text="Depth Pulse Frequency", Default=10, Min=1, Max=200, Rounding=0 }):OnChanged(function(v) config.vs_depth_pulse_freq = v / 10 end)
CustVoid:AddSlider("vs_depth_pa", { Text="Depth Pulse Amplitude", Default=0, Min=0, Max=100000, Rounding=0 }):OnChanged(function(v) config.vs_depth_pulse_amp = v end)
CustVoid:AddSlider("vs_spiral_ox", { Text="Spiral Offset X", Default=0, Min=-50000, Max=50000, Rounding=0 }):OnChanged(function(v) config.vs_spiral_offset_x = v end)
CustVoid:AddSlider("vs_spiral_oz", { Text="Spiral Offset Z", Default=0, Min=-50000, Max=50000, Rounding=0 }):OnChanged(function(v) config.vs_spiral_offset_z = v end)
CustVoid:AddSlider("vs_axis_wob", { Text="Axis Wobble", Default=0, Min=0, Max=180, Rounding=0 }):OnChanged(function(v) config.vs_axis_wobble = v end)
CustVoid:AddDropdown("vs_seed_mode", { Text="Scatter Seed Mode", Default=1, Values={"Random","Fixed","Time","Noise","Fractal"} }):OnChanged(function(v) config.vs_scatter_seed_mode = v end)
CustVoid:AddToggle("vs_node_grav", { Text="Node Gravity", Default=false, Tooltip="Pulls void nodes toward each other." }):OnChanged(function(v) config.vs_node_gravity = v end)
CustVoid:AddToggle("vs_flux_rev", { Text="Flux Reversal", Default=false, Tooltip="Periodically reverses void flux direction." }):OnChanged(function(v) config.vs_flux_reversal = v end)
CustVoid:AddToggle("vs_chaos_fb", { Text="Chaos Feedback", Default=false, Tooltip="Uses previous void movement as chaotic input." }):OnChanged(function(v) config.vs_chaos_feedback = v end)
local BoxOrbitLeft = OrbitTab

local BoxOrbitRight = OrbitTab

BoxOrbitLeft:AddToggle("orbit_en", { Text="Orbit", Default=false, Tooltip="Orbits your character in a void-driven orbital pattern." }):OnChanged(function(v)
 config.orbit_enabled = v
 play_toggle_sound()
 if v then getgenv().start_orbit(); buildXYZOverlay() else getgenv().stop_orbit(); destroyXYZOverlay() end
end)

BoxOrbitLeft:AddSlider("orbit_rad", { Text="Orbit Radius", Default=50000, Min=1, Max=500000, Rounding=0 }):OnChanged(function(v) config.orbit_radius = v end)
BoxOrbitLeft:AddSlider("orbit_spd", { Text="Orbit Speed", Default=5, Min=1, Max=200, Rounding=0 }):OnChanged(function(v) config.orbit_speed = v end)
BoxOrbitLeft:AddSlider("orbit_iters", { Text="Iterations", Default=100, Min=1, Max=500, Rounding=0 }):OnChanged(function(v) config.orbit_iters = v end)
BoxOrbitLeft:AddSlider("orbit_hgt", { Text="Height Offset", Default=0, Min=-500000, Max=500000, Rounding=0 }):OnChanged(function(v) config.orbit_height = v end)
BoxOrbitLeft:AddSlider("orbit_jit", { Text="Jitter", Default=0, Min=0, Max=100000, Rounding=0 }):OnChanged(function(v) config.orbit_jitter = v end)
BoxOrbitLeft:AddSlider("orbit_yb", { Text="Y Bias", Default=0, Min=-500000, Max=0, Rounding=0 }):OnChanged(function(v) config.orbit_y_bias = v end)
BoxOrbitLeft:AddSlider("orbit_df", { Text="Depth Floor", Default=0, Min=0, Max=500000, Rounding=0 }):OnChanged(function(v) config.orbit_depth_floor = v end)
BoxOrbitLeft:AddSlider("orbit_tight", { Text="Tightness", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.orbit_tightness = v end)
BoxOrbitLeft:AddSlider("orbit_wfreq", { Text="Wave Freq", Default=1, Min=1, Max=20, Rounding=0 }):OnChanged(function(v) config.orbit_wave_freq = v end)
BoxOrbitLeft:AddSlider("orbit_phase", { Text="Phase Offset", Default=0, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) config.orbit_phase_offset = math.rad(v) end)
BoxOrbitLeft:AddSlider("orbit_layers", { Text="Layer Count", Default=1, Min=1, Max=8, Rounding=0 }):OnChanged(function(v) config.orbit_layer_count = v end)
BoxOrbitLeft:AddSlider("orbit_loff", { Text="Layer Offset", Default=0, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) config.orbit_layer_offset = v end)
BoxOrbitLeft:AddSlider("orbit_wstr", { Text="Warp Strength", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.orbit_warp_strength = v end)
BoxOrbitLeft:AddSlider("orbit_chaos", { Text="Chaos Blend", Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.orbit_chaos_blend = v end)
BoxOrbitLeft:AddDropdown("orbit_pat_sel", { Text="Pattern", Default=1, Values={"Circle","Ellipse","Figure8","Helix","Wave","Spiral","Pulse"} }):OnChanged(function(v) config.orbit_pattern = v end)
BoxOrbitLeft:AddDropdown("orbit_target_sel", { Text="Target", Default=1, Values={"Self","Closest"} }):OnChanged(function(v) config.orbit_target = v end)
BoxOrbitLeft:AddDropdown("orbit_axis_sel", { Text="Orbit Axis", Default=1, Values={"Y","X","Z"} }):OnChanged(function(v) config.orbit_axis = v end)
BoxOrbitLeft:AddDropdown("orbit_dir_sel", { Text="Direction", Default=1, Values={"Clockwise","Counter-clockwise"} }):OnChanged(function(v) config.orbit_direction = v end)
BoxOrbitLeft:AddDropdown("orbit_warp_sel", { Text="Warp Mode", Default=1, Values={"Instant","Lerp","Spring","Bounce","Elastic"} }):OnChanged(function(v) config.orbit_warp_mode = v end)
BoxOrbitLeft:AddDropdown("orbit_fall_sel", { Text="Falloff", Default=1, Values={"None","Linear","Exp","Sine","Cosine"} }):OnChanged(function(v) config.orbit_falloff = v end)
BoxOrbitLeft:AddToggle("orbit_kv", { Text="Kill Velocity", Default=true }):OnChanged(function(v) config.orbit_kill_velocity = v end)
BoxOrbitLeft:AddToggle("orbit_srb", { Text="Sync To Ragebot", Default=false }):OnChanged(function(v) config.orbit_sync_ragebot = v end)
BoxOrbitLeft:AddToggle("orbit_ix", { Text="Invert X", Default=false }):OnChanged(function(v) config.orbit_invert_x = v end)
BoxOrbitLeft:AddToggle("orbit_iz", { Text="Invert Z", Default=false }):OnChanged(function(v) config.orbit_invert_z = v end)

local EvsLeft = CustVoid

local EvsRight = CustVoid
EvsLeft:AddDropdown("evs_ax", { Text="Direction Axis", Default=2, Values={"X","Y","Z","XZ","XY","YZ"} }):OnChanged(function(v) config.evs_axis=v end)
EvsLeft:AddDropdown("evs_fal", { Text="Falloff Mode", Default=1, Values={"None","Linear","Exp","Sine"} }):OnChanged(function(v) config.evs_falloff=v end)
EvsLeft:AddDropdown("evs_bld", { Text="Blend Mode", Default=1, Values={"Replace","Add","Lerp"} }):OnChanged(function(v) config.evs_blend_mode=v end)
EvsLeft:AddDropdown("evs_warp",{ Text="Warp Mode", Default=1, Values={"Instant","Lerp","Spring","Bounce","Elastic"} }):OnChanged(function(v) config.evs_warp_mode=v end)
EvsLeft:AddSlider("evs_vtick", { Text="Void Tick", Default=60, Min=1, Max=10000, Rounding=0 }):OnChanged(function(v) config.evs_void_tick=v end)
EvsLeft:AddSlider("evs_amp", { Text="Amplitude", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_amplitude=v/10 end)
EvsLeft:AddSlider("evs_freq", { Text="Frequency", Default=10, Min=1, Max=200, Rounding=0 }):OnChanged(function(v) config.evs_frequency=v/10 end)
EvsLeft:AddSlider("evs_sprd", { Text="Spread", Default=500, Min=0, Max=100000, Rounding=0 }):OnChanged(function(v) config.evs_spread=v end)
EvsLeft:AddSlider("evs_orr", { Text="Orbit Radius", Default=10000, Min=1, Max=500000, Rounding=0 }):OnChanged(function(v) config.evs_orbit_radius=v end)
EvsLeft:AddSlider("evs_ors", { Text="Orbit Speed", Default=5, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_orbit_speed=v end)
EvsLeft:AddSlider("evs_gm", { Text="Gravity Mult", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_gravity_mult=v/10 end)
EvsLeft:AddSlider("evs_bw", { Text="Blend Weight", Default=5, Min=1, Max=10, Rounding=0 }):OnChanged(function(v) config.evs_blend_weight=v/10 end)
EvsLeft:AddSlider("evs_ec", { Text="Echo Count", Default=0, Min=0, Max=20, Rounding=0 }):OnChanged(function(v) config.evs_echo_count=v end)
EvsLeft:AddSlider("evs_ed", { Text="Echo Decay", Default=5, Min=1, Max=10, Rounding=0 }):OnChanged(function(v) config.evs_echo_decay=v/10 end)
EvsLeft:AddSlider("evs_turb", { Text="Turbulence", Default=0, Min=0, Max=100000, Rounding=0 }):OnChanged(function(v) config.evs_turbulence=v end)
EvsLeft:AddSlider("evs_axc", { Text="Axis Clamp", Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_axis_clamp=v end)
EvsLeft:AddSlider("evs_lo", { Text="Layer Offset", Default=0, Min=-100,Max=100, Rounding=0 }):OnChanged(function(v) config.evs_layer_offset=v end)
EvsLeft:AddSlider("evs_sbd", { Text="Snap-back Delay",Default=0, Min=0, Max=500, Rounding=0 }):OnChanged(function(v) config.evs_snap_back_delay=v end)
EvsLeft:AddToggle("evs_rc", { Text="Rotation Chaos", Default=false }):OnChanged(function(v) config.evs_rotation_chaos=v end)
EvsLeft:AddToggle("evs_ix", { Text="Invert X", Default=false }):OnChanged(function(v) config.evs_invert_x=v end)
EvsLeft:AddToggle("evs_iy", { Text="Invert Y", Default=false }):OnChanged(function(v) config.evs_invert_y=v end)
EvsLeft:AddToggle("evs_iz", { Text="Invert Z", Default=false }):OnChanged(function(v) config.evs_invert_z=v end)
EvsLeft:AddDropdown("evs_xtra_d1", { Text="Sync Mode", Default=1, Values={"Instant","Lerp","Spring","Bounce","Elastic","Snap","Drift"} }):OnChanged(function(v) config.evs_sync_mode=v end)
EvsLeft:AddDropdown("evs_xtra_d2", { Text="Burst Falloff", Default=1, Values={"None","Linear","Exp","Sine","Cosine","Step","Ramp"} }):OnChanged(function(v) config.evs_burst_falloff=v end)
EvsLeft:AddDropdown("evs_xtra_d3", { Text="Chaos Axis", Default=1, Values={"All","X","Y","Z","XY","XZ","YZ"} }):OnChanged(function(v) config.evs_chaos_axis=v end)
EvsLeft:AddSlider("evs_xtra_s1", { Text="Sync Strength", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_sync_strength=v end)
EvsLeft:AddSlider("evs_xtra_s2", { Text="Chaos Blend", Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_chaos_blend=v end)
EvsLeft:AddSlider("evs_xtra_s3", { Text="Burst Radius Scale", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_burst_radius_scale=v/10 end)
EvsLeft:AddToggle("evs_xtra_t1", { Text="Chaos Sync", Default=false }):OnChanged(function(v) config.evs_chaos_sync=v end)
EvsLeft:AddToggle("evs_xtra_t2", { Text="Burst Lock", Default=false }):OnChanged(function(v) config.evs_burst_lock=v end)
EvsLeft:AddToggle("evs_xtra_t3", { Text="Depth Override", Default=false }):OnChanged(function(v) config.evs_depth_override=v end)
EvsRight:AddSlider("evs_st", { Text="Spiral Tightness",Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_spiral_tightness=v/10 end)
EvsRight:AddSlider("evs_jit", { Text="Jitter", Default=0, Min=0, Max=10000,Rounding=0 }):OnChanged(function(v) config.evs_jitter=v end)
EvsRight:AddSlider("evs_yb", { Text="Y Bias", Default=0, Min=-100000,Max=0, Rounding=0 }):OnChanged(function(v) config.evs_y_bias=v end)
EvsRight:AddSlider("evs_lay", { Text="Layer Count", Default=1, Min=1, Max=8, Rounding=0 }):OnChanged(function(v) config.evs_layer_count=v end)
EvsRight:AddSlider("evs_phs", { Text="Phase Shift", Default=0, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) config.evs_phase_shift=v end)
EvsRight:AddToggle("evs_kv", { Text="Kill Velocity", Default=true }):OnChanged(function(v) config.evs_kill_velocity=v end)
EvsRight:AddToggle("evs_ar", { Text="Auto Reverse", Default=false }):OnChanged(function(v) config.evs_auto_reverse=v end)
EvsRight:AddDropdown("evs_scat_md",{ Text="Scatter Mode", Default=1, Values={"Random","Grid","Ring","Star","Fan","Helix","Cross"} }):OnChanged(function(v) config.evs_scatter_mode=v end)
EvsRight:AddDropdown("evs_burst_p",{ Text="Burst Profile", Default=1, Values={"Flat","Ramp","Bell","Spike","Sine","Sawtooth","Random"} }):OnChanged(function(v) config.evs_burst_profile=v end)
EvsRight:AddDropdown("evs_layer_b",{ Text="Layer Blend", Default=1, Values={"Add","Lerp","Multiply","Screen","Replace"} }):OnChanged(function(v) config.evs_layer_blend=v end)
EvsRight:AddDropdown("evs_grav_dr",{ Text="Gravity Dir", Default=1, Values={"Down","Up","Left","Right","In","Out"} }):OnChanged(function(v) config.evs_gravity_dir=v end)
EvsRight:AddSlider("evs_tick_j",  { Text="Tick Jitter",   Default=0,  Min=0, Max=500,   Rounding=0 }):OnChanged(function(v) config.evs_tick_jitter=v end)
EvsRight:AddSlider("evs_clamp_r", { Text="Clamp Radius",  Default=0,  Min=0, Max=500000,Rounding=0 }):OnChanged(function(v) config.evs_clamp_radius=v end)
EvsRight:AddSlider("evs_wave_f",  { Text="Wave Freq",     Default=10, Min=1, Max=200,   Rounding=0 }):OnChanged(function(v) config.evs_wave_freq=v/10 end)
EvsRight:AddSlider("evs_depth_fl",{ Text="Depth Floor",   Default=0,  Min=0, Max=100000,Rounding=0 }):OnChanged(function(v) config.evs_depth_floor=v end)
EvsRight:AddSlider("evs_ax_wx",   { Text="Axis Weight X", Default=10, Min=1, Max=100,   Rounding=0 }):OnChanged(function(v) config.evs_axis_weight_x=v/10 end)
EvsRight:AddSlider("evs_ax_wy",   { Text="Axis Weight Y", Default=10, Min=1, Max=100,   Rounding=0 }):OnChanged(function(v) config.evs_axis_weight_y=v/10 end)
EvsRight:AddSlider("evs_ax_wz",   { Text="Axis Weight Z", Default=10, Min=1, Max=100,   Rounding=0 }):OnChanged(function(v) config.evs_axis_weight_z=v/10 end)
EvsRight:AddSlider("evs_burst_st",{ Text="Burst Stagger", Default=0,  Min=0, Max=500,   Rounding=0 }):OnChanged(function(v) config.evs_burst_stagger=v end)
EvsRight:AddSlider("evs_sync_str2",{ Text="Sync Strength", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_sync_strength=v end)
EvsRight:AddSlider("evs_chaos_bl2",{ Text="Chaos Blend", Default=0, Min=0, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_chaos_blend=v end)
EvsRight:AddSlider("evs_brs_sc2", { Text="Burst Radius Scale", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.evs_burst_radius_scale=v/10 end)
EvsRight:AddToggle("evs_inv_b",   { Text="Invert Burst",  Default=false }):OnChanged(function(v) config.evs_invert_burst=v end)
EvsRight:AddToggle("evs_orb_lk",  { Text="Orbit Lock",    Default=false }):OnChanged(function(v) config.evs_orbit_lock=v end)
EvsRight:AddToggle("evs_pls_sy",  { Text="Pulse Sync",    Default=false }):OnChanged(function(v) config.evs_pulse_sync=v end)
EvsRight:AddToggle("evs_spin_lk", { Text="Spin Lock",     Default=false }):OnChanged(function(v) config.evs_spin_lock=v end)
EvsRight:AddToggle("evs_chaos_sy2",{ Text="Chaos Sync",   Default=false }):OnChanged(function(v) config.evs_chaos_sync=v end)
EvsRight:AddToggle("evs_burst_lk2",{ Text="Burst Lock",   Default=false }):OnChanged(function(v) config.evs_burst_lock=v end)
EvsRight:AddToggle("evs_depth_ov2",{ Text="Depth Override",Default=false }):OnChanged(function(v) config.evs_depth_override=v end)

task.wait()
local BoxRiotByp = Tabs.Riot:AddLeftGroupbox("Riot Bypass")

local BoxRiotV1  = Tabs.Riot:AddRightGroupbox("Riot Abuser v1.0")

local BoxRiotV2  = Tabs.Riot:AddLeftGroupbox("Riot Abuser v2.0")



BoxRiotByp:AddToggle("ra_e", { Text="Riot Bypass", Default=false, Tooltip="Bypasses riot shield." }):OnChanged(function(v) config.riot_bypass_enabled = v
 if v then getgenv().start_riot_abuser() else getgenv().stop_riot_abuser() end end)
BoxRiotByp:AddSlider("ra_dist", { Text="Distance", Default=3, Min=0, Max=100, Rounding=1 }):OnChanged(function(v) config.riot_bypass_distance=v end)
BoxRiotByp:AddSlider("ra_h", { Text="Height", Default=0, Min=-30, Max=30, Rounding=1 }):OnChanged(function(v) config.riot_bypass_height=v end)
BoxRiotByp:AddSlider("ra_rate", { Text="Update Rate",Default=5, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.riot_bypass_update_rate=v/10 end)
ra_target_label_ref = BoxRiotByp:AddLabel("Target: None")

BoxRiotV1:AddToggle("rav1_e", { Text="Riot Abuser v1.0", Default=false }):OnChanged(function(v) config.riot_abuser_v1_enabled = v
 if v then getgenv().start_riot_abuser_v1() else getgenv().stop_riot_abuser_v1() end end)
BoxRiotV1:AddSlider("rav1_spin", { Text="Spin Speed", Default=720, Min=1, Max=9999, Rounding=0 }):OnChanged(function(v) config.riot_abuser_v1_spin_speed=v end)
BoxRiotV1:AddDropdown("rav1_tpos", { Text="Tracking Position", Default=1, Values={"Behind","Above","Front","Below","Left","Right","Exact"} }):OnChanged(function(v) config.riot_abuser_v1_tracking_position=v end)
BoxRiotV1:AddSlider("rav1_tdist", { Text="Tracking Distance", Default=3, Min=1, Max=50, Rounding=1 }):OnChanged(function(v) config.riot_abuser_v1_tracking_distance=v end)

BoxRiotV2:AddToggle("ra_v2_e", { Text="Riot Abuser v2.0", Default=false, Tooltip="Riot abuser but it doesn't teleport to the target." }):OnChanged(function(v) config.riot_abuser_v2_enabled = v
 if v then getgenv().start_riot_abuser_v2() else getgenv().stop_riot_abuser_v2() end end)
BoxRiotV2:AddSlider("ra_v2_spin", { Text="Spin Speed", Default=720, Min=1, Max=3000000, Rounding=0 }):OnChanged(function(v) config.riot_abuser_v2_spin_speed=v end)
BoxRiotV2:AddSlider("ra_v2_xj", { Text="XZ Jitter", Default=30, Min=0, Max=120, Rounding=0 }):OnChanged(function(v) config.riot_abuser_v2_xjitter=v end)
BoxRiotV2:AddSlider("ra_v2_yj", { Text="Y Jitter", Default=8, Min=0, Max=60, Rounding=0 }):OnChanged(function(v) config.riot_abuser_v2_yjitter=v end)
BoxRiotV2:AddSlider("ra_v2_spread", { Text="Spread Distance", Default=300, Min=1, Max=5000, Rounding=0 }):OnChanged(function(v) config.riot_abuser_v2_spread=v end)

local BoxPerfectBlock = Tabs.Riot:AddRightGroupbox("Perfect Block")

BoxPerfectBlock:AddToggle("pb_en", { Text="Perfect Block", Default=false, Tooltip="Blocks all shots with riot shield." }):OnChanged(function(v)
	config.perfect_block_enabled = v
	play_toggle_sound()
	if v then getgenv().start_perfect_block() else getgenv().stop_perfect_block() end
end)

if not config.profile then config.profile = {} end
if not config.profile.skinchanger then config.profile.skinchanger = { enabled=false, userid="1" } end
if not config.profile.fpsspoof then config.profile.fpsspoof = { enabled=false, value="1", fraud=false } end
if not config.profile.msspoof then config.profile.msspoof = { enabled=false, value="1", fraud=false } end
if not config.profile.regionspoof then config.profile.regionspoof = { enabled=false, value=".gg/meowwc" } end

task.wait()
local FrameScriptsufhner = Tabs.Character:AddLeftTabbox()

local skinTab = FrameScriptsufhner:AddTab("Skin")


local p = game:GetService("Players").LocalPlayer

if not config.profile.skinchanger then
    config.profile.skinchanger = { enabled = false, userid = "1" }
end

local function applyskin(c)
    if not (config.profile.skinchanger.enabled and c) then return end

    local h = c:WaitForChild("Humanoid", 5)

    local targetId = tonumber(config.profile.skinchanger.userid)
    if not h or not targetId then return end

    pcall(function()

        local model = game:GetService("Players"):CreateHumanoidModelFromUserId(targetId)
        if not model then return end

        for _, obj in ipairs(c:GetChildren()) do
            if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("BodyColors") or obj:IsA("CharacterMesh") or obj:IsA("ShirtGraphic") then
                obj:Destroy()
            end
        end

        local head = c:FindFirstChild("Head")
        if head then

            local face = head:FindFirstChildOfClass("Decal")
            if face then face:Destroy() end
        end

        for _, obj in ipairs(model:GetChildren()) do
            if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("BodyColors") or obj:IsA("CharacterMesh") or obj:IsA("ShirtGraphic") then
                obj:Clone().Parent = c
            elseif obj.Name == "Head" then

                local targetFace = obj:FindFirstChildOfClass("Decal")
                if targetFace and head then
                    targetFace:Clone().Parent = head
                end
            end
        end

        model:Destroy()
    end)
end

skinTab:AddToggle("SkinChangerEnabled", { Text="Enable", Default=false }):OnChanged(function(val)
    config.profile.skinchanger.enabled = val
    if val and p.Character then
        applyskin(p.Character)
    end
end)

skinTab:AddInput("SkinChangerValue", { Text="User Id", Default="1", Numeric=true, Finished=true, Placeholder="type user id..." }):OnChanged(function(val)
    config.profile.skinchanger.userid = val or "1"
    if config.profile.skinchanger.enabled and p.Character then
        applyskin(p.Character)
    end
end)

p.CharacterAdded:Connect(function(c)
    applyskin(c)
end)

local FrameScriptStats = Tabs.Character:AddRightTabbox()

local fpsTab = FrameScriptStats:AddTab("Fps")

local msTab = FrameScriptStats:AddTab("ms")

local regionTab = FrameScriptStats:AddTab("Region")

if not config.profile.fpsspoof then
    config.profile.fpsspoof = { enabled = false, value = "1", fraud = false }
end

if not config.profile.msspoof then
    config.profile.msspoof = { enabled = false, value = "1", fraud = false }
end

if not config.profile.regionspoof then
    config.profile.regionspoof = { enabled = false, value = ".gg/meowwc" }
end

_G.FPSSpoofConnections = _G.FPSSpoofConnections or {}
for i = 1, #_G.FPSSpoofConnections do
    _G.FPSSpoofConnections[i]:Disconnect()
end

_G.FPSSpoofConnections = {}

_G.MSSpoofConnections = _G.MSSpoofConnections or {}
for i = 1, #_G.MSSpoofConnections do
    _G.MSSpoofConnections[i]:Disconnect()
end

_G.MSSpoofConnections = {}

_G.RegionSpoofConnections = _G.RegionSpoofConnections or {}
for i = 1, #_G.RegionSpoofConnections do
    _G.RegionSpoofConnections[i]:Disconnect()
end

_G.RegionSpoofConnections = {}

if _G.FPSFraudThread then
    _G.FPSFraudThread = false
end

if _G.MSFraudThread then
    _G.MSFraudThread = false
end

local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local foundLabels = {}

local foundRegionLabels = {}

local function findLabels(parent)

    local children = parent:GetChildren()
    for i = 1, #children do

        local child = children[i]
        if child:IsA("TextLabel") and child.Name == "Title" then
            if child.Parent.Name == "ServerRegion" then
                foundRegionLabels[#foundRegionLabels + 1] = child
            else
                foundLabels[#foundLabels + 1] = child
            end
        end

        findLabels(child)
    end
end

findLabels(PlayerGui)

local lastBaseFPS = nil

local lastBaseMS = nil

local fpsTrend = 0

local msTrend = 0

local lastFPSTime = 0

local lastMSTime = 0

local function getFraudFPS()

    local base = tonumber(config.profile.fpsspoof.value) or 60
    
    if lastBaseFPS == nil then
        lastBaseFPS = base
    end
    
    local variation = math.random(-8, 12)
    fpsTrend = fpsTrend + math.random(-3, 5)
    fpsTrend = math.clamp(fpsTrend, -15, 15)
    
    local totalVariation = variation + fpsTrend
    
    if math.random(1, 100) <= 15 then
        totalVariation = totalVariation + math.random(-10, 20)
    end
    
    if math.random(1, 100) <= 8 then
        totalVariation = totalVariation - math.random(5, 15)
    end
    
    local newValue = base + totalVariation
    
    if math.random(1, 100) <= 5 then
        newValue = newValue + math.random(20, 45)
    end
    
    if newValue < 10 then
        newValue = math.random(10, 25)
    end
    
    if newValue > 144 then
        newValue = math.random(120, 144)
    end
    
    if math.random(1, 100) <= 3 then
        newValue = math.random(30, 50)
    end
    
    lastBaseFPS = newValue
    return tostring(math.floor(newValue))
end

local function getFraudMS()

    local base = tonumber(config.profile.msspoof.value) or 50
    
    if lastBaseMS == nil then
        lastBaseMS = base
    end
    
    msTrend = msTrend + math.random(-4, 6)
    msTrend = math.clamp(msTrend, -20, 25)
    
    local spike = 0
    if math.random(1, 100) <= 12 then
        spike = math.random(15, 45)
    end
    
    if math.random(1, 100) <= 7 then
        spike = spike - math.random(10, 30)
    end
    
    local variation = math.random(-12, 18)

    local newValue = base + variation + msTrend + spike
    
    if newValue < 8 then
        newValue = math.random(8, 20)
    end
    
    if newValue > 250 then
        newValue = math.random(180, 250)
    end
    
    if math.random(1, 100) <= 10 then
        newValue = newValue + math.random(5, 25)
    end
    
    if math.random(1, 100) <= 6 then
        newValue = math.random(100, 200)
    end
    
    lastBaseMS = newValue
    return tostring(math.floor(newValue))
end

local function applyFPSSpoof()
    for i = 1, #_G.FPSSpoofConnections do
        _G.FPSSpoofConnections[i]:Disconnect()
    end

    _G.FPSSpoofConnections = {}
    _G.FPSFraudThread = false
    lastBaseFPS = nil
    fpsTrend = 0
    if not config.profile.fpsspoof.enabled then return end

    if config.profile.fpsspoof.fraud then
        _G.FPSFraudThread = true

        task.spawn(function()
            while _G.FPSFraudThread do

                local target = getFraudFPS()
                for i = 1, #foundLabels do

                    local label = foundLabels[i]

                    local spoofed = label.Text:gsub("%d+fps", target .. "fps")
                    if spoofed ~= label.Text then
                        label.Text = spoofed
                    end
                end


                local waitTime = 0.95 + math.random() * 0.4
                task.wait(waitTime)
            end
        end)
    else

        local target = config.profile.fpsspoof.value
        for i = 1, #foundLabels do

            local label = foundLabels[i]
            _G.FPSSpoofConnections[#_G.FPSSpoofConnections + 1] = label:GetPropertyChangedSignal("Text"):Connect(function()

                local spoofed = label.Text:gsub("%d+fps", target .. "fps")
                if spoofed ~= label.Text then
                    label.Text = spoofed
                end
            end)
        end
    end
end

local function applyMSSpoof()
    for i = 1, #_G.MSSpoofConnections do
        _G.MSSpoofConnections[i]:Disconnect()
    end

    _G.MSSpoofConnections = {}
    _G.MSFraudThread = false
    lastBaseMS = nil
    msTrend = 0
    if not config.profile.msspoof.enabled then return end

    if config.profile.msspoof.fraud then
        _G.MSFraudThread = true

        task.spawn(function()
            while _G.MSFraudThread do

                local target = getFraudMS()
                for i = 1, #foundLabels do

                    local label = foundLabels[i]

                    local spoofed = label.Text:gsub("%d+ms", target .. "ms")
                    if spoofed ~= label.Text then
                        label.Text = spoofed
                    end
                end


                local waitTime = 0.95 + math.random() * 0.4
                task.wait(waitTime)
            end
        end)
    else

        local target = config.profile.msspoof.value
        for i = 1, #foundLabels do

            local label = foundLabels[i]
            _G.MSSpoofConnections[#_G.MSSpoofConnections + 1] = label:GetPropertyChangedSignal("Text"):Connect(function()

                local spoofed = label.Text:gsub("%d+ms", target .. "ms")
                if spoofed ~= label.Text then
                    label.Text = spoofed
                end
            end)
        end
    end
end

local function applyRegionSpoof()
    for i = 1, #_G.RegionSpoofConnections do
        _G.RegionSpoofConnections[i]:Disconnect()
    end

    _G.RegionSpoofConnections = {}
    if not config.profile.regionspoof.enabled then return end

    local target = config.profile.regionspoof.value
    for i = 1, #foundRegionLabels do

        local label = foundRegionLabels[i]
        label.Text = target
        _G.RegionSpoofConnections[#_G.RegionSpoofConnections + 1] = label:GetPropertyChangedSignal("Text"):Connect(function()
            if label.Text ~= target then
                label.Text = target
            end
        end)
    end
end

fpsTab:AddToggle("FPSSpoofEnabled", { Text="Enable", Default=false }):OnChanged(function(val)
    config.profile.fpsspoof.enabled = val
    applyFPSSpoof()
end)

fpsTab:AddToggle("FPSSpoofFraud", { Text="Fraud", Default=false }):OnChanged(function(val)
    config.profile.fpsspoof.fraud = val
    if config.profile.fpsspoof.enabled then
        applyFPSSpoof()
    end
end)

fpsTab:AddInput("FPSSpoofValue", { Text="Fps Value", Default="1", Numeric=true, Finished=false, Placeholder="type fps..." }):OnChanged(function(val)
    config.profile.fpsspoof.value = val or "1"
    if config.profile.fpsspoof.enabled then
        applyFPSSpoof()
    end
end)

msTab:AddToggle("MSSpoofEnabled", { Text="Enable", Default=false }):OnChanged(function(val)
    config.profile.msspoof.enabled = val
    applyMSSpoof()
end)

msTab:AddToggle("MSSpoofFraud", { Text="Fraud", Default=false }):OnChanged(function(val)
    config.profile.msspoof.fraud = val
    if config.profile.msspoof.enabled then
        applyMSSpoof()
    end
end)

msTab:AddInput("MSSpoofValue", { Text="ms Value", Default="1", Numeric=true, Finished=false, Placeholder="type ms..." }):OnChanged(function(val)
    config.profile.msspoof.value = val or "1"
    if config.profile.msspoof.enabled then
        applyMSSpoof()
    end
end)

regionTab:AddToggle("RegionSpoofEnabled", { Text="Enable", Default=false }):OnChanged(function(val)
    config.profile.regionspoof.enabled = val
    applyRegionSpoof()
end)

regionTab:AddInput("RegionSpoofValue", { Text="Region Value", Default=".gg/meowwc", Numeric=false, Finished=false, Placeholder="type region..." }):OnChanged(function(val)
    config.profile.regionspoof.value = val or ".gg/meowwc"
    if config.profile.regionspoof.enabled then
        applyRegionSpoof()
    end
end)

local BoxBodyManip = Tabs.Character:AddLeftGroupbox("Anti Aim")

BoxBodyManip:AddToggle("bm_en", { Text="Anti Aim", Default=false, Tooltip="Confuses server hit registration." }):OnChanged(function(v)
    config.bm_enabled = v
    play_toggle_sound()
    if v then getgenv().start_body_manip() else getgenv().stop_body_manip() end
end)

BoxBodyManip:AddDropdown("bm_yaw_mode", { Text="Yaw Mode", Default=1, Values={"random", "spin", "custom"} }):OnChanged(function(v)
    config.bm_yaw_mode = v
end)

BoxBodyManip:AddDropdown("bm_pitch_mode", { Text="Pitch Mode", Default=1, Values={"down", "up", "random", "custom"} }):OnChanged(function(v)
    config.bm_pitch_mode = v
end)

BoxBodyManip:AddSlider("bm_custom_yaw", { Text="Custom Yaw", Default=0, Min=-180, Max=180, Rounding=0, Tooltip="Used when Yaw Mode is set to custom." }):OnChanged(function(v)
    config.bm_custom_yaw = v
end)

BoxBodyManip:AddSlider("bm_custom_pitch", { Text="Custom Pitch", Default=0, Min=-89, Max=89, Rounding=0, Tooltip="Used when Pitch Mode is set to custom." }):OnChanged(function(v)
    config.bm_custom_pitch = v
end)

BoxBodyManip:AddToggle("bm_floor_hide", { Text="Underground", Default=false, Tooltip="Puts you underground." }):OnChanged(function(v)
    config.bm_floor_hide = v
end)

task.wait()
local BoxAggressionTeleport = Tabs.Aggression:AddLeftGroupbox("Teleportation")

local BoxSlingshotBypass = Tabs.Aggression:AddRightGroupbox("Slingshot Bypass")

local BoxKiciaCounter = Tabs.Aggression:AddRightGroupbox("Melee Bypass")

BoxAggressionTeleport:AddToggle("agg_tt_e", { Text="Teleportation", Default=false, Tooltip="Makes you win HvH, can teleport to UE and Kicia" }):OnChanged(function(v)
    config.teleport_to_target_enabled = v
    play_toggle_sound()
    if v then getgenv().start_teleport_to_target() else getgenv().stop_teleport_to_target() end
end)

BoxAggressionTeleport:AddDropdown("agg_tt_method", { Text="Tracking Method", Default=1, Values={"Adaptive", "Predictive"} }):OnChanged(function(v)
    config.teleport_to_target_method = v
    if config.teleport_to_target_enabled then
        getgenv().stop_teleport_to_target()
        config.teleport_to_target_enabled = true
        getgenv().start_teleport_to_target()
    end
end)

BoxAggressionTeleport:AddToggle("agg_tt_void_mimic", { Text="Void Mimic", Default=false, Tooltip="Learns the target 's movement pattern and uses it to improve teleportation destination accuracy." }):OnChanged(function(v)
    config.void_mimic_enabled = v
    play_toggle_sound()
    if v then getgenv().start_void_mimic() else getgenv().stop_void_mimic() end
end)

BoxAggressionTeleport:AddDropdown("agg_tt_mode", { Text="Target Mode", Default=1, Values={"Closest", "Farthest", "LowestHP"} }):OnChanged(function(v)
    config.teleport_to_target_mode = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_aggression", { Text="Aggression", Default=3, Min=1, Max=5, Rounding=0, Tooltip="Higher = more teleport attempts per frame." }):OnChanged(function(v)
    config.teleport_to_target_aggression = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_snap_count", { Text="Snap Count", Default=4, Min=1, Max=12, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_snap_count = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_y_offset", { Text="Height", Default=0, Min=-100, Max=100, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_y_offset = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_throttle", { Text="Throttle", Default=0, Min=0, Max=500, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_throttle = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_stagger", { Text="Predictive Stagger", Default=1, Min=0, Max=10, Rounding=1 }):OnChanged(function(v)
    config.teleport_to_target_stagger = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_lead", { Text="Target Lead", Default=false }):OnChanged(function(v)
    config.teleport_to_target_aim_lead = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_recover_void", { Text="Void Recovery", Default=true }):OnChanged(function(v)
    config.teleport_to_target_recover_void = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_srb", { Text="Sync To Ragebot", Default=false }):OnChanged(function(v)
    config.teleport_to_target_sync_to_ragebot = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_burst_mode", { Text="Burst Snap", Default=false }):OnChanged(function(v)
    config.teleport_to_target_burst_mode = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_burst_count", { Text="Burst Count", Default=3, Min=1, Max=8, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_burst_count = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_vel_kill", { Text="Velocity Kill", Default=true }):OnChanged(function(v)
    config.teleport_to_target_velocity_kill = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_orbit_mode", { Text="Orbit Mode", Default=false }):OnChanged(function(v)
    config.teleport_to_target_orbit_mode = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_orbit_r", { Text="Orbit Radius", Default=5, Min=1, Max=200, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_orbit_radius = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_orbit_spd", { Text="Orbit Speed", Default=90, Min=1, Max=3600, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_orbit_speed = v
end)

local agg_tt_prio_drop = BoxAggressionTeleport:AddDropdown("agg_tt_prio", { Text="Target Selector", SpecialType="Player", AllowNull=true })
agg_tt_prio_drop:OnChanged(function(v) config.teleport_to_target_priority = (v == nil and "" or v) end)

BoxAggressionTeleport:AddSlider("agg_tt_search_radius", { Text="Search Radius", Default=999000000, Min=1, Max=999000000000000, Rounding=0 }):OnChanged(function(v)
    config.teleport_to_target_search_radius = v
end)

BoxAggressionTeleport:AddSlider("agg_tt_jitter", { Text="Jitter", Default=0, Min=0, Max=50, Rounding=0, Tooltip="Adds random offset to each teleport landing position." }):OnChanged(function(v)
    config.teleport_to_target_jitter = v
end)

BoxAggressionTeleport:AddToggle("agg_tt_lock", { Text="Target Lock", Default=false, Tooltip="Locks onto the current target and ignores closer enemies until they die." }):OnChanged(function(v)
    config.teleport_to_target_lock = v
    if not v then tt_locked_target = nil end
end)

BoxAggressionTeleport:AddToggle("agg_tt_failsafe", { Text="Failsafe", Default=true, Tooltip="Blocks teleports that would land at invalid/dangerous positions." }):OnChanged(function(v)
    config.teleport_to_target_failsafe = v
end)

BoxSlingshotBypass:AddToggle("sb_e", { Text="Slingshot Bypass", Default=false, Tooltip="Bypasses slingshot allowing you to use it freely during hvh." }):OnChanged(function(v)
    if v then getgenv().start_slingshot_bypass() else getgenv().stop_slingshot_bypass() end
end)

BoxSlingshotBypass:AddToggle("sb_manipulation", { Text="Manipulation", Default=true, Tooltip="Manipulates slingshot to let you bypass it." }):OnChanged(function(v)
    config.slingshot_bypass_manipulation = v
end)

BoxSlingshotBypass:AddSlider("sb_range", { Text="Range", Default=100000000000000, Min=1, Max=100000000000000, Rounding=0, Tooltip="Projectile Range." }):OnChanged(function(v)
    config.slingshot_bypass_range = v
    if config.slingshot_bypass_enabled then sling_apply_range_hook() end
end)

BoxSlingshotBypass:AddLabel("Enable Teleportation if using UE.")

local kc_started_teleport = false
BoxKiciaCounter:AddLabel("Turn off ragebot with this feature, use void with this if your fighting a kiciahook user")
BoxKiciaCounter:AddToggle("kc_en", { Text="Melee Bypass", Default=false, Tooltip="Makes you hit all of your melee shots." }):OnChanged(function(v)
    config.kicia_counter_enabled = v
    play_toggle_sound()
    if v then
        if not config.teleport_to_target_enabled then
            kc_started_teleport = true
            config.teleport_to_target_enabled = true
            getgenv().start_teleport_to_target()
        else
            kc_started_teleport = false
        end
        getgenv().start_kicia_counter()
    else
        getgenv().stop_kicia_counter()
        if kc_started_teleport then
            kc_started_teleport = false
            getgenv().stop_teleport_to_target()
        end
    end
end)

BoxKiciaCounter:AddSlider("kc_agg", { Text="Aggression", Default=5, Min=1, Max=5, Rounding=0, Tooltip="Controls how many tracking passes and snap iterations fire per frame." }):OnChanged(function(v)
    config.void_counter_aggression = v
end)

BoxKiciaCounter:AddSlider("kc_snap", { Text="Snap Count", Default=8, Min=1, Max=16, Rounding=0, Tooltip="How many times to force-write your position each void cycle." }):OnChanged(function(v)
    config.void_counter_snap_count = v
end)

BoxKiciaCounter:AddSlider("kc_iters", { Text="Iterations", Default=500, Min=1, Max=500, Rounding=0, Tooltip="Number of random iteration offsets fired from void depth per cycle." }):OnChanged(function(v)
    config.et_total = v
end)

local BoxRapidFire = Tabs.Aggression:AddLeftGroupbox("Rapid Fire")

BoxRapidFire:AddToggle("rf_en", { Text="Rapid Fire", Default=false, Tooltip="Removes weapon cooldown." }):OnChanged(function(v)
    config.rapid_fire_enabled = v
    play_toggle_sound()
    if v then getgenv().start_rapid_fire() else getgenv().stop_rapid_fire() end
end)

local BoxMagicBullet = Tabs.Aggression:AddRightGroupbox("Magic Bullet")

local mb_enabled      = false
local mb_fov          = 150
local mb_hitchance    = 100
local mb_closest_part = true

local mb_target       = nil   -- { player, character, part, position }
local mb_manipulated  = false
local mb_hook_ref     = nil

local function mb_get_target_part(character)
    if mb_closest_part then
        local cam  = workspace.CurrentCamera
        local best, bestDist = nil, math.huge
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                local dist = (part.Position - cam.CFrame.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = part
                end
            end
        end
        return best
    end
    return character:FindFirstChild("HitboxHead")
        or character:FindFirstChild("Head")
        or character:FindFirstChild("HumanoidRootPart")
end

local function mb_acquire()
    local cam = workspace.CurrentCamera
    if not cam then return nil end

    local origin   = cam.CFrame.Position
    local viewport = cam.ViewportSize
    local center   = Vector2.new(viewport.X / 2, viewport.Y / 2)

    local focal      = (viewport.X / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
    local pixelLimit = focal * math.tan(math.rad(mb_fov))

    local best, bestDist = nil, math.huge

    for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
        if player == game:GetService("Players").LocalPlayer then continue end
        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local ally = char:FindFirstChild("_is_ally")
        if ally and ally.Value then continue end

        local part = mb_get_target_part(char)
        if not part then continue end

        local screen, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local screenVec = Vector2.new(screen.X, screen.Y)
        local dist2d    = (screenVec - center).Magnitude
        if dist2d > pixelLimit then continue end

        if dist2d < bestDist then
            bestDist = dist2d
            best = {
                player    = player,
                character = char,
                part      = part,
                position  = part.Position,
            }
        end
    end

    mb_target = best
    return best
end

local function mb_manipulate(origPos, origPart, origRay)
    if not mb_enabled then
        mb_manipulated = false
        return origPos, origPart, origRay
    end

    if math.random(100) > mb_hitchance then
        mb_manipulated = false
        return origPos, origPart, origRay
    end

    local target = mb_acquire()
    if not target then
        mb_manipulated = false
        return origPos, origPart, origRay
    end

    mb_manipulated = true
    return target.position, target.part, nil
end

getgenv().mb_manipulate = mb_manipulate

local function mb_start()
    if mb_hook_ref then return end   -- already running

    local orig_Raycast = workspace.Raycast
    mb_hook_ref = newcclosure(function(ws, origin, direction, params)
        if mb_enabled then
            local target = mb_acquire()
            if target then
                local redirected = target.position - origin
                return orig_Raycast(ws, origin, redirected.Unit * direction.Magnitude, params)
            end
        end
        return orig_Raycast(ws, origin, direction, params)
    end)
    hookfunction(workspace.Raycast, mb_hook_ref)
end

local function mb_stop()
    if mb_hook_ref then
        unhookfunction(workspace.Raycast)
        mb_hook_ref = nil
    end
    mb_target      = nil
    mb_manipulated = false
end


BoxMagicBullet:AddToggle("mb_en", {
    Text    = "Magic Bullet",
    Default = false,
    Tooltip = "Shoots through walls (not 100% accurate.",
}):OnChanged(function(v)
    mb_enabled = v
    play_toggle_sound()
    if v then mb_start() else mb_stop() end
    config.magic_bullet_enabled = v
end)

BoxMagicBullet:AddSlider("mb_hitchance", {
    Text     = "Hit Chance",
    Default  = 100,
    Min      = 1,
    Max      = 100,
    Rounding = 0,
    Tooltip  = "Percentage chance each shot actually gets redirected.",
}):OnChanged(function(v)
    mb_hitchance = v
    config.magic_bullet_hitchance = v
end)

BoxMagicBullet:AddToggle("mb_closest_part", {
    Text    = "Closest Part",
    Default = true,
    Tooltip = "Target the nearest body part instead of head only.",
}):OnChanged(function(v)
    mb_closest_part = v
    config.magic_bullet_closest_part = v
end)

task.wait()
local BoxAuto = Tabs.Misc:AddLeftGroupbox("Automation")

local BoxLoop = Tabs.Misc:AddRightGroupbox("Teleport Loop")

local BoxTools = Tabs.Misc:AddRightGroupbox("Tools")

BoxAuto:AddToggle("ac_e", { Text="Auto Collect", Default=false }):OnChanged(function(v) config.autocollect_enabled=v; if v then getgenv().start_autocollect() else getgenv().stop_autocollect() end end)
BoxAuto:AddSlider("ac_r", { Text="Collect Radius", Default=120, Min=10, Max=300, Rounding=0 }):OnChanged(function(v) config.autocollect_radius=v end)
BoxAuto:AddToggle("sz_e", { Text="Safe Zone Rescue",Default=false }):OnChanged(function(v) config.safe_zone_enabled=v; if v then getgenv().start_safe_zone() else getgenv().stop_safe_zone() end end)
BoxAuto:AddSlider("sz_y", { Text="Depth Threshold", Default=-10, Min=-200, Max=50, Rounding=0 }):OnChanged(function(v) config.safe_zone_y=v end)
BoxAuto:AddToggle("rh_e", { Text="Return Home", Default=false }):OnChanged(function(v) config.return_home_enabled=v; if v then getgenv().start_return_home() else getgenv().stop_return_home() end end)
BoxAuto:AddButton("Save Home Position", function()

 local hrp = getgenv().get_hrp(localplayer)
 if hrp then getgenv().home_position = hrp.Position; tnotify("System","Home position saved.") end end)
BoxAuto:AddSlider("rh_d", { Text="Return Delay", Default=10, Min=1, Max=150, Rounding=0 }):OnChanged(function(v) config.home_return_delay=v/10 end)
BoxAuto:AddToggle("afk", { Text="Anti AFK", Default=false }):OnChanged(function(v) config.anti_afk_enabled=v; if v then getgenv().start_anti_afk() else getgenv().stop_anti_afk() end end)
BoxAuto:AddToggle("ffa", { Text="FFA Server Hopping",Default=false }):OnChanged(function(v) config.ffa_hopping_enabled=v end)

BoxLoop:AddToggle("tl_e",{ Text="Teleport Loop", Default=false }):OnChanged(function(v) if v then getgenv().start_teleport_loop() else getgenv().stop_teleport_loop() end end)
BoxLoop:AddSlider("tl_d",{ Text="Loop Delay", Default=50, Min=10, Max=1000, Rounding=0 }):OnChanged(function(v) config.teleport_loop_delay=v/100 end)
BoxLoop:AddButton("Add Waypoint", function()

 local hrp=getgenv().get_hrp(localplayer)
 if hrp then table.insert(getgenv().loop_waypoints,hrp.Position); tnotify("System","Waypoint added.") end end)
BoxLoop:AddButton("Clear Waypoints", function()

 getgenv().loop_waypoints={}; getgenv().loop_index=1; tnotify("System","Waypoints cleared.") end)


task.wait()
local BoxDesync = Tabs.Defense:AddLeftGroupbox("Desync")

local BoxFakePos = Tabs.Defense:AddRightGroupbox("Fake Position")

BoxFakePos:AddToggle("fp_en", { Text="Fake Position", Default=false, Tooltip="Spoofs your server-side position." }):OnChanged(function(v)
 config.fake_pos_enabled = v
 if v then getgenv().start_fake_position() else getgenv().stop_fake_position() end
end)

BoxFakePos:AddSlider("fp_rad", { Text="Radius", Default=500, Min=1, Max=5000, Rounding=0, Tooltip="Offset radius from your real position." }):OnChanged(function(v) config.fake_pos_radius = v end)
BoxFakePos:AddSlider("fp_hei", { Text="Height", Default=0, Min=-2000, Max=2000, Rounding=0 }):OnChanged(function(v) config.fake_pos_height = v end)
BoxFakePos:AddSlider("fp_spd", { Text="Speed", Default=50, Min=1, Max=500, Rounding=0 }):OnChanged(function(v) config.fake_pos_speed = v end)
BoxFakePos:AddSlider("fp_cnt", { Text="Packet Count", Default=5, Min=1, Max=20, Rounding=0, Tooltip="How many CFrame writes per Heartbeat." }):OnChanged(function(v) config.fake_pos_count = v end)
BoxFakePos:AddDropdown("fp_mode", { Text="Pattern", Default=1, Values={"Scatter","Linear","Circle","Random","Spiral"} }):OnChanged(function(v) config.fake_pos_drop1 = v end)
BoxFakePos:AddDropdown("fp_dist", { Text="Distribution", Default=1, Values={"Random","Uniform","Weighted","Radial","Clustered"} }):OnChanged(function(v) config.fake_pos_drop2 = v end)
BoxFakePos:AddDropdown("fp_axis", { Text="Axis Lock", Default=1, Values={"None","X","Y","Z","XZ"} }):OnChanged(function(v) config.fake_pos_drop3 = v end)
BoxFakePos:AddToggle("fp_rev", { Text="Reverse", Default=false }):OnChanged(function(v) config.fake_pos_tog2 = v end)
BoxFakePos:AddToggle("fp_rrad", { Text="Random Radius", Default=false }):OnChanged(function(v) config.fake_pos_tog3 = v end)

BoxDesync:AddToggle("ds_en", { Text="Desync", Default=false, Tooltip="Spoofs your server-side velocity." }):OnChanged(function(v)
 config.desync_enabled = v
 if v then getgenv().start_desync() else getgenv().stop_desync() end
end)

BoxDesync:AddSlider("ds_int", { Text="Intensity", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.desync_intensity = v end)
BoxDesync:AddSlider("ds_spd", { Text="Speed", Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) config.desync_speed = v end)
BoxDesync:AddSlider("ds_ang", { Text="Angle", Default=90, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) config.desync_angle = v end)
BoxDesync:AddSlider("ds_jit", { Text="Jitter", Default=20, Min=0, Max=180, Rounding=0 }):OnChanged(function(v) config.desync_jitter = v end)
BoxDesync:AddToggle("ds_flip", { Text="Flip", Default=false, Tooltip="Inverts the desync direction." }):OnChanged(function(v) config.desync_flip = v end)
BoxDesync:AddToggle("ds_uhit_en", { Text="Unhittable Desync", Default=false, Tooltip="Combines velocity desync with rapid bursts and Godmode to make you unhittable." }):OnChanged(function(v)
 config.desync_unhittable_enabled = v
 if v then getgenv().start_unhittable_desync() else getgenv().stop_unhittable_desync() end
end)
BoxDesync:AddSlider("ds_uhit_int", { Text="Unhittable Intensity", Default=50, Min=1, Max=100, Rounding=0, Tooltip="Controls how far fake CFrame packets are spread." }):OnChanged(function(v) config.desync_unhittable_intensity = v end)
BoxDesync:AddSlider("ds_uhit_rad", { Text="Unhittable Radius", Default=9000, Min=100, Max=100000, Rounding=0, Tooltip="Scatter radius control." }):OnChanged(function(v) config.desync_unhittable_radius = v end)
BoxDesync:AddSlider("ds_uhit_iters", { Text="Unhittable Iterations", Default=100, Min=1, Max=500, Rounding=0, Tooltip="How many fake CFrame packets are sent per Heartbeat." }):OnChanged(function(v) config.desync_unhittable_iters = v end)
BoxDesync:AddSlider("ds_uhit_yr", { Text="Activation Range", Default=10, Min=1, Max=50, Rounding=0, Tooltip="Activates enemy hitbox suppression when they are within this Y distance below you." }):OnChanged(function(v) config.desync_unhittable_y_range = v end)

local BoxGodmode = Tabs.Defense:AddRightGroupbox("Godmode")

BoxGodmode:AddToggle("gm_en", { Text="Godmode", Default=false, Tooltip="Makes you unhittable." }):OnChanged(function(v)
 config.godmode_enabled = v
 config.melee_bypass_enabled = v
 play_toggle_sound()
 if v then getgenv().start_melee_bypass() else getgenv().stop_melee_bypass() end
end)

BoxGodmode:AddSlider("gm_yr", { Text="Activation Range", Default=10, Min=1, Max=50, Rounding=0, Tooltip="Activates godmode only when the enemy is within this many studs below you on Y." }):OnChanged(function(v) config.godmode_y_range = v; config.melee_bypass_y_range = v end)

local BoxAntiVoidBait = Tabs.Defense:AddRightGroupbox("Anti Void Bait")

BoxAntiVoidBait:AddToggle("avb_freeze", { Text="Freeze", Default=false, Tooltip="Completely freezes you so nothing can move you." }):OnChanged(function(v)
 config.anti_void_bait_freeze = v
 if v then
  config.anti_void_bait_hide = false

  getgenv().start_anti_void_bait_freeze()
 else

  getgenv().stop_anti_void_bait()
 end
end)

BoxAntiVoidBait:AddToggle("avb_hide", { Text="Hide", Default=false, Tooltip="Makes you unhittable utilizing void movement." }):OnChanged(function(v)
    config.anti_void_bait_hide = v
    if v then
        config.anti_void_bait_freeze = false
        getgenv().start_anti_void_bait_hide()
    else
        getgenv().stop_anti_void_bait()
    end
end)

local BoxPrediction = Tabs.Defense:AddRightGroupbox("Prediction")

BoxPrediction:AddToggle("pred_en", { Text="Prediction", Default=false, Tooltip="Evades players." }):OnChanged(function(v)
    config.prediction_enabled = v
    play_toggle_sound()
    if v then getgenv().start_prediction() else getgenv().stop_prediction() end
end)

BoxPrediction:AddSlider("pred_act_range", { Text="Activation Range", Default=20, Min=1, Max=200, Rounding=0, Tooltip="Distance at which the dodge triggers when an enemy is this close." }):OnChanged(function(v)
    config.prediction_activation_range = v
end)

BoxPrediction:AddSlider("pred_dist_range", { Text="Distance Range", Default=30, Min=1, Max=500, Rounding=0, Tooltip="How far you teleport away from the enemy." }):OnChanged(function(v)
    config.prediction_distance_range = v
end)

local BoxKiciaVoidspam = Tabs.Defense:AddLeftGroupbox("Kicia Voidspam")

BoxKiciaVoidspam:AddToggle("kv_en", { Text="Kicia Voidspam", Default=false, Tooltip="Use this void if using kicia." }):OnChanged(function(v)
 config.kicia_voidspam_enabled = v
 if v then getgenv().start_kicia_voidspam() else getgenv().stop_kicia_voidspam() end
end)

task.wait()
local BoxControls = Tabs.Settings:AddLeftGroupbox("Controls")

BoxControls:AddDropdown("ui_font_sel", {
 Text = "UI Font",
 Default = 1,
 Values = {
  "GothamMedium", "GothamBold", "GothamBlack", "Gotham", "GothamSemibold",
  "Arial", "ArialBold", "Code", "Legacy", "Ubuntu", "RobotoMono",
  "SourceSansPro", "SourceSansProBold", "SourceSansProSemibold", "SourceSansProItalic",
  "SourceSansProBlack", "SourceSansProLight", "SciFi", "Sarpanch", "PressStart2P",
  "Nunito", "Merriweather", "Michroma", "Fondamento", "Bangers",
  "CreepsterRegular", "DenkOne", "Guru", "Highway", "IndieFlower",
  "JosefinSans", "Jura", "Kalam", "Oswald", "PatuaOne",
  "Permanent Marker", "Roboto", "RobotoCondensed", "SpecialElite", "TitilliumWeb",
  "Ubuntu Light", "UnifrakturMaguntia", "Zilla Slab", "FredokaOne", "Balthazar",
  "LuckiestGuy", "CabinCondensed", "Pirata One", "RobotoMono Bold", "Inconsolata",
 },
}):OnChanged(function(v)
 config.ui_font = v
 pcall(function()
  Library.Font = Enum.Font[v] or Enum.Font.GothamMedium
  Library:UpdateFonts()
 end)
end)

local BoxSounds = Tabs.Settings:AddRightGroupbox("Sounds")

BoxSounds:AddToggle("snd_en", { Text="Enable Sounds", Default=false, Tooltip="Plays a sound whenever you toggle a feature." }):OnChanged(function(v)
 config.sounds_enabled = v
end)

BoxSounds:AddDropdown("snd_sel", { Text="Select Sound", Default=1, Values={"Space", "Pop", "Bonk", "Skeet", "Neverlose", "Slip"} }):OnChanged(function(v)
 astral_sound_selected = v
 astral_toggle_sound.SoundId = astral_sound_ids[v] or astral_sound_ids.Space
end)

BoxSounds:AddSlider("snd_vol", { Text="Sound Volume", Default=50, Min=0, Max=100, Rounding=0, Suffix="%" }):OnChanged(function(v)
 astral_sound_volume = v / 100
 astral_toggle_sound.Volume = astral_sound_volume
end)

BoxSounds:AddButton("Test Sound", function()

 local prev = config.sounds_enabled
 config.sounds_enabled = true
 play_toggle_sound()
 config.sounds_enabled = prev
end)

local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")

local queue_on_teleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)

local TeleportConnection
local scriptToQueue = 'loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/d641d3c209b9d4ef6a95954a63a203ac.lua"))()'

MenuGroup:AddToggle('AutoExecuteOnTeleport', {
    Text = 'Autoload Script',
    Default = false,
    Tooltip = 'Auto Executes the script for you',
    Callback = function(Value)
        if Value then
            if queue_on_teleport then
                queue_on_teleport(scriptToQueue)
            end

            TeleportConnection = game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(State)
                if queue_on_teleport and (State == Enum.TeleportState.Started or State == Enum.TeleportState.InProgress) then
                    queue_on_teleport(scriptToQueue)
                end
            end)
        else
            if TeleportConnection then
                TeleportConnection:Disconnect()
                TeleportConnection = nil
            end
        end
    end
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Unload", function() getgenv().unload_all() end)

Tabs.Settings:BuildConfigSection()
ui_ready = true
 end, function(message) return tostring(message) end)
 if load_generation == getgenv().__flowlua_generation then
  getgenv().flowlua_loading = false
  getgenv().flowlua_loaded = ui_ok and ui_ready
  if not ui_ok or not ui_ready then
   getgenv().flowlua_last_error = tostring(ui_error or "ui initialization stopped")
   local cleanup = rawget(getgenv(), "unload_all")
   if type(cleanup) == "function" then pcall(cleanup) end
  else
   getgenv().flowlua_last_error = nil
  end
 end
end)

return AC
