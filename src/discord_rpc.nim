import std/[net, os, endians, strutils, options, tables, httpclient, uri, with]
when defined(posix):
  from posix import Stat, stat, S_ISSOCK
import packedjson, uuids

const
  RPCVersion = 1
  oauthUrl = "https://discord.com/api/oauth2/token"

type
  DiscordRPCError* = object of CatchableError
    code*: int

  DiscordRPC* = ref object
    socket: Socket
    clientId*: int64

  OpCode = enum
    opHandshake, opFrame, opClose, opPing, opPong

  RpcMessage = object
    opCode: OpCode
    payload: string

  ServerConfig* = object
    cdnHost*, apiEndpoint*, environment*: string

  PremiumKind* = enum
    pkNone, pkNitroClassic, pkNitro

  User* = object
    id*: int64
    username*, discriminator*, avatar*: string
    bot*: bool
    premium*: PremiumKind

  VoiceStatus* = object
    mute*, deaf*, selfMute*, selfDeaf*, suppress*: bool

  VoiceState* = object
    nick*: string
    user*: User
    mute*: bool
    volume*: InputVolume
    pan*: Pan
    voiceStatus*: VoiceStatus

  ChannelKind* = enum
    ckGuildText = "GUILD_TEXT"
    ckDM = "DM"
    ckGuildVoice = "GUILD_VOICE"
    ckGroupDM = "GROUP_DM"
    ckGuildCategory = "GUILD_CATEGORY"
    ckGuildNews = "GUILD_NEWS"
    ckGuildStore = "GUILD_STORE"

  Channel* = object
    id*, guildId*: int64
    name*: string
    position*: int
    case kind*: ChannelKind
    of ckGuildVoice:
      bitrate*, userLimit*: int
      voiceStates*: seq[VoiceState]
    else:
      topic*: string

  Guild* = object
    id*: int64
    name*, iconUrl*, vanityUrlCode*: string

  Pan* = object
    left*, right*: 0.0..1.0

  InputVolume* = 0..100
  OutputVolume* = 0..200

  UserVoiceSettings* = object
    id*: int64
    pan*: Pan
    volume*: OutputVolume
    mute*: bool

  UserVoiceSettingsSetter* = object
    id*: int64
    pan*: Option[Pan]
    volume*: Option[OutputVolume]
    mute*: Option[bool]

  AudioDevice* = object
    id*, name*: string

  VoiceSettingsInput* = object
    deviceId*: string
    volume*: InputVolume
    availableDevices*: seq[AudioDevice]

  VoiceSettingsOutput* = object
    deviceId*: string
    volume*: OutputVolume
    availableDevices*: seq[AudioDevice]

  KeyKind* = enum
    kkKeyboardKey, kkMouseButton, kkKeyboardModifierKey, kkGamepadButton

  ShortcutKey* = object
    kind*: KeyKind
    code*: int
    name*: string

  VoiceModeKind* = enum
    vmPushToTalk = "PUSH_TO_TALK", vmVoiceActivity = "VOICE_ACTIVITY"

  VoiceSettingsMode* = object
    kind*: VoiceModeKind
    autoThreshold*: bool
    threshold*: -100.0..0.0
    shortcut*: seq[ShortcutKey]
    delay*: 0.0..20000.0

  VoiceSettings* = object
    input*: VoiceSettingsInput
    output*: VoiceSettingsOutput
    mode*: VoiceSettingsMode
    automaticGainControl*, echoCancellation*, noiseSuppression*,
      qualityOfService*, silenceWarning*, deaf*, mute*: bool

  VoiceSettingsInputSetter* = object
    deviceId*: Option[string]
    volume*: Option[InputVolume]

  VoiceSettingsOutputSetter* = object
    deviceId*: Option[string]
    volume*: Option[OutputVolume]

  VoiceSettingsModeSetter* = object
    kind*: Option[VoiceModeKind]
    autoThreshold*: Option[bool]
    threshold*: Option[-100.0..0.0]
    shortcut*: Option[seq[ShortcutKey]]
    delay*: Option[0.0..20000.0]

  VoiceSettingsSetter* = object
    input*: Option[VoiceSettingsInputSetter]
    output*: Option[VoiceSettingsOutputSetter]
    mode*: Option[VoiceSettingsModeSetter]
    automaticGainControl*, echoCancellation*, noiseSuppression*,
      qualityOfService*, silenceWarning*, deaf*, mute*: Option[bool]

  Vendor* = object
    name*, url*: string

  Model* = object
    name*, url*: string

  DeviceKind* = enum
    dkAudioInput = "audioinput", dkAudioOutput = "audiooutput", dkVideoInput = "videoinput"

  Device* = object
    case kind*: DeviceKind
    of dkAudioInput:
      echoCancellation*, noiseSuppression*, automaticGainControl*, hardwareMute*: bool
    else:
      discard
    id*: string
    vendor*: Vendor
    model*: Model
    related*: seq[string]

  ActivityTimestamps* = object
    start*, finish*: int64

  ActivityAssets* = object
    largeImage*, largeText*, smallImage*, smallText*: string

  PartySize* = object
    currentSize*, maxSize*: int32

  ActivityParty* = object
    id*: string
    size*: PartySize

  ActivitySecrets* = object
    join*, spectate*, match*: string

  Activity* = object
    details*, state*, url*: string
    timestamps*: ActivityTimestamps
    party*: Option[ActivityParty]
    assets*: Option[ActivityAssets] ## images for the presence and their hover texts
    secrets*: Option[ActivitySecrets]
    instance*: Option[bool]

  ActivityKind* = enum
    Playing ## Playing {name}
    Streaming ## Streaming {details}
    Listening ## Listening to {name}
    Custom ## {emoji} {name}

  ActivityJoinRequestReply* = enum
    No, Yes, Ignore

  ActivityActionType* = enum
    Join = 1, Spectate

  Application* = object
    name*, description*, icon*: string
    rpcOrigins*: seq[string]
    id*: int64

  Command = enum
    cmdDispatch = "DISPATCH"
    cmdAuthorize = "AUTHORIZE"
    cmdAuthenticate = "AUTHENTICATE"
    cmdGetGuild = "GET_GUILD"
    cmdGetGuilds = "GET_GUILDS"
    cmdGetChannel = "GET_CHANNEL"
    cmdGetChannels = "GET_CHANNELS"
    cmdSubscribe = "SUBSCRIBE"
    cmdUnsubscribe = "UNSUBSCRIBE"
    cmdSetUserVoiceSettings = "SET_USER_VOICE_SETTINGS"
    cmdSelectVoiceChannel = "SELECT_VOICE_CHANNEL"
    cmdGetSelectedVoiceChannel = "GET_SELECTED_VOICE_CHANNEL"
    cmdSelectTextChannel = "SELECT_TEXT_CHANNEL"
    cmdGetVoiceSettings = "GET_VOICE_SETTINGS"
    cmdSetVoiceSettings = "SET_VOICE_SETTINGS"
    cmdCaptureShortcut = "CAPTURE_SHORTCUT"
    cmdSetCertifiedDevices = "SET_CERTIFIED_DEVICES"
    cmdSetActivity = "SET_ACTIVITY"
    cmdSendActivityJoinInvite = "SEND_ACTIVITY_JOIN_INVITE"
    cmdCloseActivityRequest = "CLOSE_ACTIVITY_REQUEST"

  OAuthScope* = enum
    oasBot = "bot"
    oasConnections = "connections"
    oasEmail = "email"
    oasIdentify = "identify"
    oasGuilds = "guilds"
    oasGuildsJoin = "guilds.join"
    oasGdmJoin = "gdm.join"
    oasMessagesRead = "messages.read"
    oasRpc = "rpc"
    oasRpcApi = "rpc.api"
    oasRpcNotificationsRead = "rpc.notifications.read"
    oasWebhookIncoming = "webhook.incoming"
    oasApplicationsBuildsUpload = "applications.builds.upload"
    oasApplicationsBuildsRead = "applications.builds.read"
    oasApplicationsStoreUpdate = "applications.store.update"
    oasApplicationsEntitlements = "applications.entitlements"
    oasRelationshipsRead = "relationships.read"
    oasActivitiesRead = "activities.read"
    oasActivitiesWrite = "activities.write"

template assertResult(value, body): untyped =
  when compileOption "assertions":
    assert body == value
  else:
    discard body

proc existsSocket(s: string): bool =
  var res: Stat
  return stat(s, res) >= 0 and S_ISSOCK(res.st_mode)

proc getSocketDir(): string =
  when defined(windows):
    "\\\\?\\pipe"
  else:
    if existsEnv "XDG_RUNTIME_DIR":
      getEnv "XDG_RUNTIME_DIR"
    elif existsEnv "TMPDIR":
      getEnv "TMPDIR"
    elif existsEnv "TMP":
      getEnv "TMP"
    elif existsEnv "TEMP":
      getEnv "TEMP"
    else:
      "/tmp/"

proc getSocketPath(): string =
  let dir = getSocketDir()
  for i in 0..9:
    result = dir / "discord-ipc-" & $i
    if existsSocket result: return
  raise newException(CatchableError, "No RPC socket found.")

func parseOpCode(u: uint32): OpCode =
  if u <= OpCode.high.ord:
    result = OpCode u
  else:
    raise newException(CatchableError, "Invalid opcode: " & $u)

proc readUint32(s: Socket): uint32 =
  assertResult sizeof uint32, s.recv(addr result, sizeof uint32)
  littleEndian32 addr result, addr result

proc readOpCode(s: Socket): OpCode =
  s.readUint32.parseOpCode

proc readMessage(s: Socket): RpcMessage =
  result.opCode = s.readOpCode
  let len = int s.readUint32
  result.payload = s.recv len

func toString(u: uint32): string =
  result = newString(4)
  littleEndian32 addr result[0], unsafeAddr u

proc write(s: Socket, m: RpcMessage) =
  var payload = newStringOfCap(m.payload.len + 8)
  payload.add m.opCode.uint32.toString
  payload.add m.payload.len.uint32.toString
  payload.add m.payload
  assertResult payload.len, s.send(unsafeAddr payload[0], payload.len)

func composeHandshake(id: int64, version: int): string =
  result = newStringOfCap(85)
  with result:
    add "{\"client_id\":\""
    add $id
    add "\",\"v\":"
    add $RPCVersion
    add "}"

func composeCommand(cmd: Command, args = "", nonce = $genUUID()): string =
  let cmd = $cmd
  result = newStringOfCap(cmd.len + args.len + 67)
  with result:
    add "{\"cmd\":\""
    add cmd
    add "\",\"args\":{"
    add args
    add "},\"nonce\":\""
    add nonce
    add "\"}"

func composeAuthorize(id: int64, scopes: openArray[OAuthScope]): string =
  result.add "\"client_id\":\""
  result.add $id
  result.add "\",\"scopes\":["
  if scopes.len > 0:
    result.add "\""
    result.add $scopes[0]
    result.add "\""
    for i in 1..scopes.high:
      result.add ",\""
      result.add $scopes[i]
      result.add "\""
  result.add "]"

func composeAuthenticate(token: string): string =
  result = newStringOfCap(token.len + 17)
  result.add "\"access_token\":\""
  result.add token
  result.add '"'

func composeGetGuild(id: int64): string =
  result.add "\"guild_id\":\""
  result.add $id
  result.add '"'

func composeGetChannels(id: int64): string =
  composeGetGuild id

func composeGetChannel(id: int64): string =
  result.add "\"channel_id\":\""
  result.add $id
  result.add '"'

func composeSetUserVoiceSettings(settings: UserVoiceSettings): string =
  with result:
    add "\"pan\":{\"left\":"
    add $settings.pan.left
    add ",\"right\":"
    add $settings.pan.right
    add "},"
    add "\"volume\":"
    add $settings.volume
    add ','
    add "\"mute\":"
    add $settings.mute
    add ','
    add "\"user_id\":\""
    add $settings.id
    add '"'

func composeSetUserVoiceSettings(settings: UserVoiceSettingsSetter): string =
  if settings.pan.isSome:
    result.add "\"pan\":{\"left\":"
    result.add $settings.pan.get.left
    result.add ",\"right\":"
    result.add $settings.pan.get.right
    result.add "},"
  if settings.volume.isSome:
    result.add "\"volume\":"
    result.add $settings.volume.get
    result.add ','
  if settings.mute.isSome:
    result.add "\"mute\":"
    result.add $settings.mute.get
    result.add ','
  result.add "\"user_id\":\""
  result.add $settings.id
  result.add '"'

func composeSetUserVoiceSettings(id: int64, pan: Option[Pan],
    volume: Option[OutputVolume], mute: Option[bool]): string =
  if pan.isSome:
    result.add "\"pan\":{\"left\":"
    result.add $pan.get.left
    result.add ",\"right\":"
    result.add $pan.get.right
    result.add "},"
  if volume.isSome:
    result.add "\"volume\":"
    result.add $volume.get
    result.add ','
  if mute.isSome:
    result.add "\"mute\":"
    result.add $mute.get
    result.add ','
  result.add "\"user_id\":\""
  result.add $id
  result.add '"'

func composeSelectVoiceChannel(id: Option[int64], force: bool): string =
  result.add "\"channel_id\":"
  if id.isSome:
    result.add '"'
    result.add $id.get
    result.add '"'
  else:
    result.add "null"
  if force:
    result.add ",\"force\":true"

func composeSelectTextChannel(id: Option[int64]): string =
  result.add "\"channel_id\":"
  if id.isSome:
    result.add '"'
    result.add $id.get
    result.add '"'
  else:
    result.add "null"

func compose(result: var string, settings: VoiceSettingsInput | VoiceSettingsOutput) =
  with result:
    add "\"device_id\":\""
    add settings.deviceId
    add "\",\"volume\":"
    add $settings.volume

func compose(result: var string, mode: VoiceSettingsMode) =
  with result:
    add "\"type\":\""
    add $mode.kind
    add "\",\"auto_threshold\":\""
    add $mode.autoThreshold
    add "\",\"threshold\":\""
    add $mode.threshold
    add "\",\"delay\":\""
    add $mode.delay
    add "\","

func composeSetVoiceSettings(settings: VoiceSettings): string =
  with result:
    add "\"input\":{"
    compose settings.input
    add "},\"output\":{"
    compose settings.output
    add "},\"mode\":{"
    compose settings.mode
    add "},\"automaticGainControl\":"
    add $settings.automaticGainControl
    add ",\"echoCancellation\":"
    add $settings.echoCancellation
    add ",\"noiseSuppression\":"
    add $settings.noiseSuppression
    add ",\"qualityOfService\":"
    add $settings.qualityOfService
    add ",\"silenceWarning\":"
    add $settings.silenceWarning
    add ",\"deaf\":"
    add $settings.deaf
    add ",\"mute\":"
    add $settings.mute

func compose(result: var string, settings: VoiceSettingsInputSetter | VoiceSettingsOutputSetter) =
  if settings.deviceId.isSome:
    result.add "\"device_id\":\""
    result.add settings.deviceId.get
    result.add "\","
  if settings.volume.isSome:
    result.add "\"volume\":"
    result.add $settings.volume.get
  if result[^1] == ',':
    result.setLen result.high

func compose(result: var string, mode: VoiceSettingsModeSetter) =
  if mode.kind.isSome:
    result.add "\"type\":\""
    result.add $mode.kind.get
    result.add "\","
  if mode.autoThreshold.isSome:
    result.add "\"auto_threshold\":\""
    result.add $mode.autoThreshold.get
    result.add "\","
  if mode.threshold.isSome:
    result.add "\"threshold\":\""
    result.add $mode.threshold.get
    result.add "\","
  if mode.delay.isSome:
    result.add "\"delay\":\""
    result.add $mode.delay.get
    result.add "\","

func composeSetVoiceSettings(settings: VoiceSettingsSetter): string =
  if settings.input.isSome:
    result.add "\"input\":{"
    result.compose settings.input.get
    result.add "},"
  if settings.output.isSome:
    result.add "\"output\":{"
    result.compose settings.output.get
    result.add "},"
  if settings.mode.isSome:
    result.add "\"mode\":{"
    result.compose settings.mode.get
    result.add "},"
  if settings.automaticGainControl.isSome:
    result.add "\"automaticGainControl\":"
    result.add $settings.automaticGainControl.get
    result.add ','
  if settings.echoCancellation.isSome:
    result.add "\"echoCancellation\":"
    result.add $settings.echoCancellation.get
    result.add ','
  if settings.noiseSuppression.isSome:
    result.add "\"noiseSuppression\":"
    result.add $settings.noiseSuppression.get
    result.add ','
  if settings.qualityOfService.isSome:
    result.add "\"qualityOfService\":"
    result.add $settings.qualityOfService.get
    result.add ','
  if settings.silenceWarning.isSome:
    result.add "\"silenceWarning\":"
    result.add $settings.silenceWarning.get
    result.add ','
  if settings.deaf.isSome:
    result.add "\"deaf\":"
    result.add $settings.deaf.get
    result.add ','
  if settings.mute.isSome:
    result.add "\"mute\":"
    result.add $settings.mute.get
    result.add ','
  if result[^1] == ',':
    result.setLen result.high

func compose(result: var string, device: Device) =
  with result:
    add "\"type\":\""
    add $device.kind
    add "\",\"id\":\""
    add device.id
    add "\",\"vendor\":{\"name\":\""
    add device.vendor.name
    add "\",\"url\":\""
    add device.vendor.url
    add "\"},\"model\":{\"name\":\""
    add device.model.name
    add "\",\"url\":\""
    add device.model.url
    add "\"},\"related\":["
  if device.related.len > 0:
    result.add '"'
  for i, dev in device.related:
    result.add dev
    if i == device.related.high:
      result.add '"'
    else:
      result.add "\",\""
  result.add "]"
  if device.kind == dkAudioInput:
    with result:
      add ",\"echo_cancellation\":"
      add $device.echoCancellation
      add ",\"noise_suppression\":"
      add $device.noiseSuppression
      add ",\"automatic_gain_control\":"
      add $device.automaticGainControl
      add ",\"hardware_mute\":"
      add $device.hardwareMute

func composeSetCertifiedDevices(devices: seq[Device]): string =
  result.add "\"devices\":[{"
  for i, device in devices:
    result.compose device
    if i != devices.high:
      result.add "},{"
  result.add "}]"

func composeSetActivity(a: Activity, pid: int): string =
  result.add "\"pid\":"
  result.add $pid
  result.add ",\"activity\":"
  var act = newJObject()
  if a.details.len > 0:
    act["details"] = a.details.newJString
  if a.state.len > 0:
    act["state"] = a.state.newJString
  if a.url.len > 0:
    act["url"] = a.url.newJString
  if a.assets.isSome:
    let ass = a.assets.get
    var assets = newJObject()
    if ass.largeImage.len > 0:
      assets["large_image"] = ass.largeImage.newJString
    if ass.largeText.len > 0:
      assets["large_text"] = ass.largeText.newJString
    if ass.smallImage.len > 0:
      assets["small_image"] = ass.smallImage.newJString
    if ass.smallText.len > 0:
      assets["small_text"] = ass.smallText.newJString
    act["assets"] = assets
  if a.timestamps.start > 0 or a.timestamps.finish > 0:
    var time = newJObject()
    if a.timestamps.start > 0:
      time["start"] = a.timestamps.start.newJInt
    if a.timestamps.finish > 0:
      time["end"] = a.timestamps.finish.newJInt
    act["timestamps"] = time
  if a.instance.isSome:
    act["instance"] = a.instance.get.newJBool
  result.add $act

func composeSendActivityJoinInvite(id: int64): string =
  result.add "\"user_id\":\""
  result.add $id
  result.add '"'

func composeCloseActivityRequest(id: int64): string =
  composeSendActivityJoinInvite id

func getDiscordConfig(j: JsonNode): ServerConfig =
  result = ServerConfig(
    cdnHost: j["cdn_host"].getStr,
    apiEndpoint: j["api_endpoint"].getStr,
    environment: j["environment"].getStr
  )

func getUser(j: JsonNode): User =
  result = User(
    id: j["id"].getStr.parseBiggestInt,
    username: j["username"].getStr,
    discriminator: j["discriminator"].getStr,
    avatar: j["avatar"].getStr,
    bot: j["bot"].getBool,
    premium: j["premium_type"].getInt.PremiumKind
  )

func getApplication(j: JsonNode): Application =
  result.id = j["id"].getStr.parseInt
  result.name = j["name"].getStr
  if j.hasKey("description") and j["description"].kind == JString:
    result.description = j["description"].getStr
  if j.hasKey("icon") and j["icon"].kind == JString:
    result.icon = j["icon"].getStr
  if j.hasKey("rpc_origins") and j["rpc_origins"].kind == JArray:
    let rpcOrigins = j["rpc_origins"]
    result.rpcOrigins.newSeq rpcOrigins.len
    for i in 0..result.rpcOrigins.high:
      result.rpcOrigins[i] = rpcOrigins[i].getStr

func getPartialGuild(j: JsonNode): Guild =
  result.id = j["id"].getStr.parseInt
  result.name = j["name"].getStr

func getGuild(j: JsonNode): Guild =
  result = j.getPartialGuild
  result.iconUrl = j["icon_url"].getStr
  result.vanityUrlCode = j["vanity_url_code"].getStr

func getGuilds(j: JsonNode): seq[Guild] =
  result.newSeq j.len
  for i in 0..result.high:
    result[i] = j[i].getPartialGuild

func getVoiceStatus(j: JsonNode): VoiceStatus =
  result = VoiceStatus(
    mute: j["mute"].getBool,
    deaf: j["deaf"].getBool,
    selfMute: j["self_mute"].getBool,
    selfDeaf: j["self_deaf"].getBool,
    suppress: j["suppress"].getBool
  )

func getPan(j: JsonNode): Pan =
  result.left = j["left"].getFloat
  result.right = j["right"].getFloat

func getVoiceState(j: JsonNode): VoiceState =
  result = VoiceState(
    nick: j["nick"].getStr,
    mute: j["mute"].getBool,
    volume: j["volume"].getInt,
    pan: j["pan"].getPan,
    voiceStatus: j["voice_state"].getVoiceStatus,
    user: j["user"].getUser
  )

func getVoiceStates(j: JsonNode): seq[VoiceState] =
  result.newSeq j.len
  for i in 0..result.high:
    result[i] = j[i].getVoiceState

func getPartialChannel(j: JsonNode): Channel =
  result = Channel(
    kind: j["type"].getInt.ChannelKind,
    name: j["name"].getStr,
    id: j["id"].getStr.parseInt
  )

func getChannel(j: JsonNode): Channel =
  result = j.getPartialChannel
  result.guildId = j["guild_id"].getStr.parseInt
  case result.kind
  of ckGuildVoice:
    result.bitrate = j["bitrate"].getInt
    result.userLimit = j["user_limit"].getInt
    result.voiceStates = j["voice_states"].getVoiceStates
  else:
    result.topic = j["topic"].getStr

func getChannels(j: JsonNode): seq[Channel] =
  result.newSeq j.len
  for i in 0..result.high:
    result[i] = j[i].getPartialChannel

func getUserVoiceSettings(j: JsonNode): UserVoiceSettings =
  result = UserVoiceSettings(
    id: j["user_id"].getStr.parseInt,
    pan: j["pan"].getPan,
    volume: j["volume"].getInt,
    mute: j["mute"].getBool
  )

func getAudioDevice(j: JsonNode): AudioDevice =
  result.id = j["id"].getStr
  result.name = j["name"].getStr

func getAudioDevices(j: JsonNode): seq[AudioDevice] =
  result.newSeq j.len
  for i in 0..result.high:
    result[i] = j[i].getAudioDevice

func getVoiceSettingsInput(j: JsonNode): VoiceSettingsInput =
  result = VoiceSettingsInput(
    deviceId: j["device_id"].getStr,
    volume: j["volume"].getInt,
    availableDevices: j["available_devices"].getAudioDevices
  )

func getVoiceSettingsOutput(j: JsonNode): VoiceSettingsOutput =
  result = VoiceSettingsOutput(
    deviceId: j["device_id"].getStr,
    volume: j["volume"].getInt,
    availableDevices: j["available_devices"].getAudioDevices
  )

func getShortcutKey(j: JsonNode): ShortcutKey =
  result = ShortcutKey(
    kind: j["type"].getInt.KeyKind,
    code: j["code"].getInt,
    name: j["name"].getStr
  )

func getShortcut(j: JsonNode): seq[ShortcutKey] =
  result.newSeq j.len
  for i in 0..result.high:
    result[i] = j[i].getShortcutKey

func getVoiceSettingsMode(j: JsonNode): VoiceSettingsMode =
  result = VoiceSettingsMode(
    kind: (
      case j["type"].getStr
      of $vmPushToTalk:
        vmPushToTalk
      of $vmVoiceActivity:
        vmVoiceActivity
      else:
        raise newException(CatchableError, "Unknown voice mode")
      ),
    autoThreshold: j["auto_threshold"].getBool,
    threshold: j["threshold"].getFloat,
    shortcut: j["shortcut"].getShortcut,
    delay: j["delay"].getFloat
  )

func getVoiceSettings(j: JsonNode): VoiceSettings =
  result = VoiceSettings(
    input: j["input"].getVoiceSettingsInput,
    output: j["output"].getVoiceSettingsOutput,
    mode: j["mode"].getVoiceSettingsMode,
    automaticGainControl: j["automatic_gain_control"].getBool,
    echoCancellation: j["echo_cancellation"].getBool,
    noiseSuppression: j["noise_suppression"].getBool,
    qualityOfService: j["qos"].getBool,
    silenceWarning: j["silence_warning"].getBool,
    deaf: j["deaf"].getBool,
    mute: j["mute"].getBool
  )

proc send(d: DiscordRPC, msg: RpcMessage) =
  d.socket.write msg

proc send(d: DiscordRPC, command: Command, args = "") =
  let
    payload = composeCommand(command, args)
    msg = RpcMessage(opcode: opFrame, payload: payload)
  d.send msg

proc receiveResponse(d: DiscordRPC, opCode = opFrame): JsonNode =
  let resp = d.socket.readMessage
  assert resp.opCode == opCode
  let
    payload = resp.payload.parseJson
    event = payload["evt"]
  result = payload["data"]
  if event.kind == JString and event.getStr == "ERROR":
    var error = new DiscordRPCError
    error.code = result["code"].getInt
    error.msg = result["message"].getStr
    raise error

proc connect*(d: DiscordRPC): tuple[config: ServerConfig, user: User] =
  when defined(windows):
    d.socket.connect getSocketPath()
  else:
    d.socket.connectUnix getSocketPath()
  let payload = composeHandshake(d.clientId, RPCVersion)
  let msg = RpcMessage(opCode: opHandshake, payload: payload)
  d.send msg
  let data = d.receiveResponse
  assert data["v"].getInt == RPCVersion
  result.config = data["config"].getDiscordConfig
  result.user = data["user"].getUser

proc newDiscordRPC*(clientId: int64): DiscordRPC =
  DiscordRPC(socket: newSocket(when defined(windows): AF_INET else: AF_UNIX, protocol = IPPROTO_IP),
    clientId: clientId)

proc getOAuth2Token*(code: string, id: int64, secret: string, scopes: openArray[OAuthScope]):
    tuple[accessToken, refreshToken: string]  =
  let
    client = newHttpClient()
    headers = newHttpHeaders {"Content-Type": "application/x-www-form-urlencoded"}
    body = encodeQuery {
      "grant_type": "authorization_code",
      "code": code,
      "client_id": $id,
      "client_secret": secret,
      "scope": scopes.join " "
    }
    response = client.request(
      url = oauthUrl,
      httpMethod = HttpPost,
      headers = headers,
      body = body
    )
  let data = response.body.parseJson
  result.accessToken = data["access_token"].getStr
  result.refreshToken = data["refresh_token"].getStr

proc authorize*(d: DiscordRPC, scopes: openArray[OAuthScope], rpcToken = ""): string =
  d.send cmdAuthorize, composeAuthorize(d.clientId, scopes)
  result = d.receiveResponse["code"].getStr

proc authenticate*(d: DiscordRPC, token: string): Application =
  d.send cmdAuthenticate, composeAuthenticate(token)
  result = d.receiveResponse["application"].getApplication

proc getGuild*(d: DiscordRPC, id: int64): Guild =
  d.send cmdGetGuild, composeGetGuild(id)
  result = d.receiveResponse.getGuild

proc getGuilds*(d: DiscordRPC): seq[Guild] =
  d.send cmdGetGuilds
  result = d.receiveResponse["guilds"].getGuilds

proc getChannel*(d: DiscordRPC, id: int64): Channel =
  d.send cmdGetChannel, composeGetChannel(id)
  result = d.receiveResponse.getChannel

proc getChannels*(d: DiscordRPC, id: int64): seq[Channel] =
  d.send cmdGetChannels, composeGetChannels(id)
  result = d.receiveResponse["channels"].getChannels

proc setUserVoiceSettings*(d: DiscordRPC,
  settings: UserVoiceSettingsSetter | UserVoiceSettings): UserVoiceSettings =
  d.send cmdSetUserVoiceSettings, composeSetUserVoiceSettings(settings)
  result = d.receiveResponse.getUserVoiceSettings

proc setUserVoiceSettings*(d: DiscordRPC, id: int64, pan: Option[Pan],
    volume: Option[OutputVolume], mute: Option[bool]): UserVoiceSettings =
  d.send cmdSetUserVoiceSettings, composeSetUserVoiceSettings(id, pan, volume, mute)
  result = d.receiveResponse.getUserVoiceSettings

proc selectVoiceChannel*(d: DiscordRPC, id = none(int64), force = false): Option[Channel] =
  d.send cmdSelectVoiceChannel, composeSelectVoiceChannel(id, force)
  let data = d.receiveResponse
  if id.isSome:
    result = data.getChannel.some

proc getSelectedVoiceChannel*(d: DiscordRPC): Option[Channel] =
  d.send cmdGetSelectedVoiceChannel
  let data = d.receiveResponse
  if data.kind != JNull:
    result = data.getChannel.some

proc selectTextChannel*(d: DiscordRPC, id = none(int64)): Option[Channel] =
  d.send cmdSelectTextChannel, composeSelectTextChannel(id)
  let data = d.receiveResponse
  if id.isSome:
    result = data.getChannel.some

proc getVoiceSettings*(d: DiscordRPC): VoiceSettings =
  d.send cmdGetVoiceSettings
  result = d.receiveResponse.getVoiceSettings

proc setVoiceSettings*(d: DiscordRPC, settings: VoiceSettingsSetter | VoiceSettings): VoiceSettings =
  d.send cmdSetVoiceSettings, composeSetVoiceSettings(settings)
  result = d.receiveResponse.getVoiceSettings

proc setCertifiedDevices*(d: DiscordRPC, devices: seq[Device]) =
  d.send cmdSetCertifiedDevices, composeSetCertifiedDevices(devices)
  discard d.receiveResponse

proc setActivity*(d: DiscordRPC, a: Activity, pid = getCurrentProcessId()) =
  d.send cmdSetActivity, composeSetActivity(a, pid)

proc sendActivityJoinInvite*(d: DiscordRPC, id: int64) =
  d.send cmdSendActivityJoinInvite, composeSendActivityJoinInvite(id)

proc closeActivityRequest*(d: DiscordRPC, id: int64) =
  d.send cmdCloseActivityRequest, composeCloseActivityRequest(id)
