# discord_rpc

Client library for synchronous part of [Discord RPC](https://discord.com/developers/docs/topics/rpc), which includes Rich Presence.

## Installation

`nimble install discord_rpc`

## Example settings Rich Presence/Activity

```nim
let
  applicationId = WHATEVER
  discord = newDiscordRPC(applicationId)

discard discord.connect

discord.setActivity Activity(
  details: "Epic Application",
  state: "Doing nothing",
  assets: some ActivityAssets(
    largeImage: "icon-name",
    largeText: "yep, thats it"
  )
)
```

## Example using other RPC facilities

Needs to be compiled with `-d:ssl`.

```nim
let
  id = WHATEVER
  secret = VERY_CONFIDENTIAL
  scopes = [oasIdentify, oasRpc] # You need at least these two to do anything

  discord = newDiscordRPC(id)
  _ = discord.connect
  authorizationCode = d.authorize scopes
  (authenticationToken, _) =
    getOAuth2Token(authorizationCode, discord.client, secret, scopes)
  _ = discord.authenticate token

# Now we're set to do whatever

  guilds = discord.getGuilds
  voiceSettings = discord.getVoiceSettings
  _ = d.selectTextChannel some channelId
```
