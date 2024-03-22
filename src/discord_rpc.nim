import std/[net, os, endians, strutils, options, tables, uri, with, typetraits, macros]
when defined(posix):
  from posix import Stat, stat, S_ISSOCK
import pkg/[jsony, uuids, puppy]

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

  Response[T] = distinct T

  RpcEvent = enum
    reReady = "READY" ## non-subscription event sent immediately after connecting, contains server information
    reError = "ERROR" ## non-subscription event sent when there is an error, including command responses
    reGuildStatus = "GUILD_STATUS" ## sent when a subscribed server's state changes
    reGuildCreate = "GUILD_CREATE" ## sent when a guild is created/joined on the client
    reChannelCreate = "CHANNEL_CREATE" ## sent when a channel is created/joined on the client
    reVoiceChannelSelect = "VOICE_CHANNEL_SELECT" ## sent when the client joins a voice channel
    reVoiceStateCreate = "VOICE_STATE_CREATE" ## sent when a user joins a subscribed voice channel
    reVoiceStateUpdate = "VOICE_STATE_UPDATE" ## sent when a user's voice state changes in a subscribed voice channel (mute, volume, etc.)
    reVoiceStateDelete = "VOICE_STATE_DELETE" ## sent when a user parts a subscribed voice channel
    reVoiceSettingsUpdate = "VOICE_SETTINGS_UPDATE" ## sent when the client's voice settings update
    reVoiceConnectionStatus = "VOICE_CONNECTION_STATUS" ## sent when the client's voice connection status changes
    reSpeakingStart = "SPEAKING_START" ## sent when a user in a subscribed voice channel speaks
    reSpeakingStop = "SPEAKING_STOP" ## sent when a user in a subscribed voice channel stops speaking
    reMessageCreate = "MESSAGE_CREATE" ## sent when a message is created in a subscribed text channel
    reMessageUpdate = "MESSAGE_UPDATE" ## sent when a message is updated in a subscribed text channel
    reMessageDelete = "MESSAGE_DELETE" ## sent when a message is deleted in a subscribed text channel
    reNotificationCreate = "NOTIFICATION_CREATE" ## sent when the client receives a notification (mention or new message in eligible channels)
    reActivityJoin = "ACTIVITY_JOIN" ## sent when the user clicks a Rich Presence join invite in chat to join a game
    reActivitySpectate = "ACTIVITY_SPECTATE" ## sent when the user clicks a Rich Presence spectate invite in chat to spectate a game
    reActivityJoinRequest = "ACTIVITY_JOIN_REQUEST" ## sent when the user receives a Rich Presence Ask to Join request

  ServerConfig* = object
    cdnHost*, apiEndpoint*, environment*: string

  PremiumKind* = enum
    pkNone, pkNitroClassic, pkNitro, pkNitroBasic

  Id* = int64

  User* = object
    id*: Id
    username*, discriminator*, globalName*, avatar*, avatarDecoration*, banner*: string
    bot*, system*, mfaEnabled*, verified*: bool
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
    id*, guildId*: Id
    name*, topic*: string
    position*: int
    case kind*: ChannelKind
    of ckGuildVoice:
      bitrate*, userLimit*: int
      voiceStates*: seq[VoiceState]
    else:
      discard

  Guild* = object
    id*: int64
    name*, iconUrl*, vanityUrlCode*: string

  Pan* = object
    left*, right*: 0.0..1.0

  InputVolume* = 0.0..100.0
  OutputVolume* = 0.0..200.0

  UserVoiceSettings* = object
    id*: Id
    pan*: Pan
    volume*: OutputVolume
    mute*: bool

  UserVoiceSettingsSetter* = object
    id*: Id
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
  when defined(windows):
    return true # TODO
  else:
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

macro addStringField(res: var string, obj, name: untyped) =
  let str = newLit "\"" & name.strVal & "\":\""
  result = quote do:
    if `obj`.`name`.len > 0:
      `res`.add `str`
      `res`.add `obj`.`name`
      `res`.add '"'
      `res`.add ','

func composeSetActivity(a: Activity, pid: int): string =
  template closeObject: untyped =
    if result[^1] == ',':
      result[^1] = '}'
      result.add ','
    else:
      result.add "},"

  result.add "\"pid\":"
  result.add $pid
  result.add ",\"activity\":{"
  result.addStringField a, details
  result.addStringField a, state
  result.addStringField a, url
  if a.assets.isSome:
    result.add "\"assets\":{"
    let ass = a.assets.get
    result.addStringField ass, large_image
    result.addStringField ass, large_text
    result.addStringField ass, small_image
    result.addStringField ass, small_text
    closeObject()
  if a.timestamps.start > 0 or a.timestamps.finish > 0:
    result.add "\"timestamps\":{"
    if a.timestamps.start > 0:
      result.add "\"start\":"
      result.addInt a.timestamps.start
      result.add ','
    if a.timestamps.finish > 0:
      result.add "\"end\":"
      result.addInt a.timestamps.finish
      result.add ','
    closeObject()
  if a.instance.isSome:
    result.add "\"instance\":"
    result.add $a.instance.get
  if result[^1] == ',':
    result[^1] = '}'
  else:
    result.add '}'

func composeSendActivityJoinInvite(id: int64): string =
  result.add "\"user_id\":\""
  result.add $id
  result.add '"'

func composeCloseActivityRequest(id: int64): string =
  composeSendActivityJoinInvite id

proc send(d: DiscordRPC, msg: RpcMessage) =
  d.socket.write msg

proc send(d: DiscordRPC, command: Command, args = "") =
  let
    payload = composeCommand(command, args)
    msg = RpcMessage(opcode: opFrame, payload: payload)
  d.send msg

proc renameHook(v: var Channel, fieldName: var string) =
  if fieldName == "type":
    fieldName = "kind"

proc parseHook(s: string, i: var int, v: var Id) =
  var str = newStringOfCap(20)
  parseHook(s, i, str)
  v = str.parseBiggestInt

proc parseHook(s: string, i: var int, v: var ChannelKind) =
  var val: int
  parseHook(s, i, val)
  v = val.ChannelKind

proc parseHook[T](s: string, i: var int, v: var Response[T]) =
  var
    dataStart = -1
    eventSeen, eventError = false
    key = newStringOfCap(5)
  eatSpace(s, i)
  eatChar(s, i, '{')
  eatSpace(s, i)
  while dataStart < 0 or not eventSeen:
    parseHook(s, i, key)
    eatChar(s, i, ':')
    case key
    of "data":
      dataStart = i
      skipValue(s, i)
    of "evt":
      eventSeen = true
      var eventStr = newStringOfCap(25)
      parseHook(s, i, eventStr)
      eventError = eventStr == $reError
    else:
      skipValue(s, i)
    inc i

  if eventError:
    var error: tuple[code: int, message: string]
    parseHook(s, dataStart, error)
    var exc = new DiscordRPCError
    exc.code = error.code
    exc.msg = error.message
    raise exc
  else:
    parseHook(s, dataStart, v.distinctBase)

proc receiveResponse[T](d: DiscordRPC, t: typedesc[T], opCode = opFrame): T =
  let resp = d.socket.readMessage
  assert resp.opCode == opCode
  when T isnot void:
    result = T resp.payload.fromJson(Response[T])

proc connect*(d: DiscordRPC): tuple[config: ServerConfig, user: User] =
  when defined(windows):
    d.socket.connect getSocketPath()
  else:
    d.socket.connectUnix getSocketPath()
  let payload = composeHandshake(d.clientId, RPCVersion)
  let msg = RpcMessage(opCode: opHandshake, payload: payload)
  d.send msg
  let (version, config, user) = d.receiveResponse(tuple[v: int, config: ServerConfig, user: User])
  assert version == RPCVersion
  result.config = config
  result.user = user

proc newDiscordRPC*(clientId: int64): DiscordRPC =
  DiscordRPC(socket: newSocket(when defined(windows): AF_INET else: AF_UNIX, protocol = IPPROTO_IP),
    clientId: clientId)

proc getOAuth2Token*(code: string, id: int64, secret: string, scopes: openArray[OAuthScope]):
    tuple[accessToken, refreshToken: string]  =
  let
    headers = @{"Content-Type": "application/x-www-form-urlencoded"}
    body = encodeQuery {
      "grant_type": "authorization_code",
      "code": code,
      "client_id": $id,
      "client_secret": secret,
      "scope": scopes.join " "
    }
    response = post(
      url = oauthUrl,
      headers = headers,
      body = body
    )
  let data = response.body.fromJson tuple[access_token, refresh_token: string]
  result.accessToken = data.access_token
  result.refreshToken = data.refresh_token

proc authorize*(d: DiscordRPC, scopes: openArray[OAuthScope], rpcToken = ""): string =
  d.send cmdAuthorize, composeAuthorize(d.clientId, scopes)
  result = d.receiveResponse(tuple[code: string]).code

proc authenticate*(d: DiscordRPC, token: string): Application =
  d.send cmdAuthenticate, composeAuthenticate(token)
  result = d.receiveResponse(tuple[application: Application]).application

proc getGuild*(d: DiscordRPC, id: int64): Guild =
  d.send cmdGetGuild, composeGetGuild(id)
  result = d.receiveResponse Guild

proc getGuilds*(d: DiscordRPC): seq[Guild] =
  d.send cmdGetGuilds
  result = d.receiveResponse(tuple[guilds: seq[Guild]]).guilds

proc getChannel*(d: DiscordRPC, id: int64): Channel =
  d.send cmdGetChannel, composeGetChannel(id)
  result = d.receiveResponse Channel

proc getChannels*(d: DiscordRPC, id: int64): seq[Channel] =
  d.send cmdGetChannels, composeGetChannels(id)
  result = d.receiveResponse(tuple[channels: seq[Channel]]).channels

proc setUserVoiceSettings*(d: DiscordRPC,
  settings: UserVoiceSettingsSetter | UserVoiceSettings): UserVoiceSettings =
  d.send cmdSetUserVoiceSettings, composeSetUserVoiceSettings(settings)
  result = d.receiveResponse UserVoiceSettings

proc setUserVoiceSettings*(d: DiscordRPC, id: int64, pan: Option[Pan],
    volume: Option[OutputVolume], mute: Option[bool]): UserVoiceSettings =
  d.send cmdSetUserVoiceSettings, composeSetUserVoiceSettings(id, pan, volume, mute)
  result = d.receiveResponse UserVoiceSettings

proc selectVoiceChannel*(d: DiscordRPC, id = none(int64), force = false): Option[Channel] =
  d.send cmdSelectVoiceChannel, composeSelectVoiceChannel(id, force)
  let data = d.receiveResponse Channel
  if id.isSome:
    result = data.some

proc getSelectedVoiceChannel*(d: DiscordRPC): Option[Channel] =
  d.send cmdGetSelectedVoiceChannel
  result = d.receiveResponse Option[Channel]

proc selectTextChannel*(d: DiscordRPC, id = none(int64)): Option[Channel] =
  d.send cmdSelectTextChannel, composeSelectTextChannel(id)
  let data = d.receiveResponse Channel
  if id.isSome:
    result = data.some

proc getVoiceSettings*(d: DiscordRPC): VoiceSettings =
  d.send cmdGetVoiceSettings
  result = d.receiveResponse VoiceSettings

proc setVoiceSettings*(d: DiscordRPC, settings: VoiceSettingsSetter | VoiceSettings): VoiceSettings =
  d.send cmdSetVoiceSettings, composeSetVoiceSettings(settings)
  result = d.receiveResponse VoiceSettings

proc setCertifiedDevices*(d: DiscordRPC, devices: seq[Device]) =
  d.send cmdSetCertifiedDevices, composeSetCertifiedDevices(devices)
  d.receiveResponse void

proc setActivity*(d: DiscordRPC, a: Activity, pid = getCurrentProcessId()) =
  d.send cmdSetActivity, composeSetActivity(a, pid)

proc sendActivityJoinInvite*(d: DiscordRPC, id: int64) =
  d.send cmdSendActivityJoinInvite, composeSendActivityJoinInvite(id)

proc closeActivityRequest*(d: DiscordRPC, id: int64) =
  d.send cmdCloseActivityRequest, composeCloseActivityRequest(id)
