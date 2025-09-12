# sm-whois

SourceMod plugin for player identification, permanames, and alt account linking.

## Features

- **Permanames**: Assign persistent names to players that override display names
- **Name History**: Track and view all names a player has used
- **Alt Account Linking**: Link Steam IDs to existing permanames
- **Activity Logging**: Log player connections, disconnections, and name changes

## Commands

| Command | Permission | Description |
|---------|------------|-------------|
| `sm_whois <player>` | `ADMFLAG_GENERIC` | View permaname of a player |
| `sm_thisis <player> <name>` | `ADMFLAG_GENERIC` | Set permaname for a player |
| `sm_namehistory [player]` | `ADMFLAG_GENERIC` | View name history (menu if no args) |
| `sm_link <target> <main_account>` | `ADMFLAG_GENERIC` | Link Steam ID to existing permaname |

## Natives

```sourcepawn
// Get a client's permaname
native int Whois_GetPermaname(int client, char[] buffer, int maxlen);

// Check if Steam ID is linked as alt account
native bool Whois_IsLinkedAlt(const char[] steamid);
```

## Forward

```sourcepawn
// Called when permaname is modified
forward void Whois_OnPermanameModified(int issuer, int target, const char[] name);
```

## Database Tables

- **whois_logs**: Connection/disconnection/namechange activity
- **whois_permname**: Steam ID to permaname mappings  
- **whois_alt_links**: Alt account links to main accounts

## Installation

1. Upload `whois.smx` to `plugins/`
2. Upload `whois.inc` to `scripting/include/`
3. Upload `whois.phrases.txt` to `translations/`
4. Configure database connection named "whois" in `databases.cfg`

## Dependencies

- MoreColors
- SteamWorks
