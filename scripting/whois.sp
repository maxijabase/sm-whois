/* Dependencies */

#include <sourcemod>
#include <morecolors>
#include <steamworks>
#include <whois>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma semicolon 1
#pragma newdecls required

#define UPDATE_URL "https://raw.githubusercontent.com/maxijabase/sm-whois/master/updatefile.txt"

/* Plugin Info */

public Plugin myinfo = {
  name = "WhoIs", 
  author = "ampere", 
  description = "Provides player identification and logging capabilities.", 
  version = "2.3", 
  url = "github.com/maxijabase"
}

GlobalForward g_gfOnPermanameModified;
Database g_Database;
bool g_Late = false;
char g_ServerIP[32];
char g_ServerHostname[64];
char g_Permanames[MAXPLAYERS + 1][128];
StringMap g_LinkedAlts;

/* Plugin Start */

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
  g_gfOnPermanameModified = new GlobalForward("Whois_OnPermanameModified", ET_Ignore, Param_Cell, Param_Cell, Param_String);

  CreateNative("Whois_GetPermaname", Native_GetPermaname);
  CreateNative("Whois_IsLinkedAlt", Native_IsLinkedAlt);
  RegPluginLibrary("whois");
  g_Late = late;

  return APLRes_Success;
}

public void OnPluginStart() {
  HookEvent("player_changename", Event_ChangeName);
  
  RegAdminCmd("sm_whois", CMD_Whois, ADMFLAG_GENERIC, "View permaname of a player");
  RegAdminCmd("sm_namehistory", CMD_Namehistory, ADMFLAG_GENERIC, "View name history of a player");
  
  RegAdminCmd("sm_thisis", CMD_Thisis, ADMFLAG_GENERIC, "Set name of a player");
  RegAdminCmd("sm_link", CMD_Link, ADMFLAG_GENERIC, "Link a Steam ID to an existing permaname");
  
  LoadTranslations("common.phrases");
  LoadTranslations("whois.phrases");
  
  g_LinkedAlts = new StringMap();
  
  if (SteamWorks_IsConnected()) {
    GetServerIP(g_ServerIP, sizeof(g_ServerIP), true);
  }
  
  if (g_Late) {
    OnConfigsExecuted();
  }
  
  if (LibraryExists("updater")) {
    Updater_AddPlugin(UPDATE_URL);
  }

  Database.Connect(SQL_ConnectDatabase, "whois");
}

public void OnLibraryAdded(const char[] name) {
  if (StrEqual(name, "updater")) {
    Updater_AddPlugin(UPDATE_URL);
  }
}

public void SteamWorks_SteamServersConnected() {
  GetServerIP(g_ServerIP, sizeof(g_ServerIP), true);
}

public void OnConfigsExecuted() {
  GetServerName(g_ServerHostname, sizeof(g_ServerHostname));
}

public void OnHostnameChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
  strcopy(g_ServerHostname, sizeof(g_ServerHostname), newValue);
}

/* Database Tables */

public void CreateTable() {
  char sQuery[1024] = 
  "CREATE TABLE IF NOT EXISTS whois_logs("...
  "entry INT NOT NULL AUTO_INCREMENT, "...
  "steam_id VARCHAR(64), "...
  "name VARCHAR(128), "...
  "date DATE, "...
  "time TIME, "...
  "timestamp INT, "...
  "ip VARCHAR(32), "...
  "server_ip VARCHAR(32), "...
  "server_name VARCHAR(128), "...
  "action VARCHAR(32), "...
  "PRIMARY KEY(entry)"...
  ");";
  
  g_Database.Query(SQL_GenericQuery, sQuery);
  
  sQuery = 
  "CREATE TABLE IF NOT EXISTS whois_permname("...
  "steam_id VARCHAR(64), "...
  "name VARCHAR(128), "...
  "PRIMARY KEY(steam_id)"...
  ");";
  
  g_Database.Query(SQL_GenericQuery, sQuery);
  
  sQuery = 
  "CREATE TABLE IF NOT EXISTS whois_alt_links("...
  "steam_id VARCHAR(64), "...
  "main_steam_id VARCHAR(64), "...
  "linked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "...
  "linked_by VARCHAR(64), "...
  "PRIMARY KEY(steam_id)"...
  ");";
  
  g_Database.Query(SQL_GenericQuery, sQuery);
}

/* Forwards */

public void OnClientPostAdminCheck(int client) {
  InsertPlayerData(client, "connect");
  CachePermaname(client);
  CacheLinkedAlt(client);
}

public void OnClientDisconnect(int client) {
  InsertPlayerData(client, "disconnect");
  g_Permanames[client][0] = '\0';
  
  char steamid[32];
  if (GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid))) {
    g_LinkedAlts.Remove(steamid);
  }
}

/* Commands */

public Action CMD_Whois(int client, int args) {
  // Check command usage
  if (args != 1) {
    MC_ReplyToCommand(client, "%t", "whoisUsage");
    return Plugin_Handled;
  }
  
  // Find target
  char arg[32];
  GetCmdArg(1, arg, sizeof(arg));
  
  int target = FindTarget(client, arg, true, false);
  
  if (target == -1) {
    return Plugin_Handled;
  }
  
  // Check if name is empty
  if (g_Permanames[target][0] == '\0') {
    MC_PrintToChat(client, "%t", "noName", target);
    if (CheckCommandAccess(target, "sm_namehistory", 0))
    {
      int userid = GetClientUserId(target);
      FakeClientCommand(client, "sm_namehistory #%d", userid);
    }
    return Plugin_Handled;
  }
  
  // Inform permaname
  MC_ReplyToCommand(client, "%t", "thisIsPlayer", target, g_Permanames[target]);
  return Plugin_Handled;
}

public Action CMD_Thisis(int client, int args) {
  // Check database
  if (g_Database == null) {
    ThrowError("Database not connected");
    MC_ReplyToCommand(client, "%t", "databaseError");
    return Plugin_Handled;
  }
  
  // Check command usage
  if (args != 2) {
    MC_ReplyToCommand(client, "%t", "thisisUsage");
    return Plugin_Handled;
  }
  
  // Get and check target and new permaname
  char arg1[32]; char name[32];
  GetCmdArg(1, arg1, sizeof(arg1));
  GetCmdArg(2, name, sizeof(name));
  int target = FindTarget(client, arg1, true, false);
  
  if (target == -1) {
    return Plugin_Handled;
  }
  
  // Check steam id
  char steamid[32];
  if (!GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid))) {
    MC_ReplyToCommand(client, "%t", "noSteamID", target);
    return Plugin_Handled;
  }
  
  // Insert or update permaname in database
  char query[256];
  g_Database.Format(query, sizeof(query), "INSERT INTO whois_permname VALUES('%s', '%s') ON DUPLICATE KEY UPDATE name = '%s';", steamid, name, name);
  
  DataPack pack = new DataPack();
  pack.WriteCell(GetClientUserId(client));
  pack.WriteCell(GetClientUserId(target));
  pack.WriteString(name);
  g_Database.Query(SQL_OnSetPermanameCompleted, query, pack);
  
  return Plugin_Handled;
}

public Action CMD_Namehistory(int client, int args) {
  if (g_Database == null) {
    MC_ReplyToCommand(client, "%t", "databaseError");
    return Plugin_Handled;
  }
  
  ShowNameHistoryMenu(client, args);
  return Plugin_Handled;
}

public Action CMD_Link(int client, int args) {
  // Check database
  if (g_Database == null) {
    MC_ReplyToCommand(client, "%t", "databaseError");
    return Plugin_Handled;
  }
  
  // Check command usage
  if (args != 2) {
    MC_ReplyToCommand(client, "Usage: sm_link <target_player_or_steamid> <existing_permaname_or_steamid>");
    return Plugin_Handled;
  }
  
  char arg1[64], arg2[64];
  GetCmdArg(1, arg1, sizeof(arg1));
  GetCmdArg(2, arg2, sizeof(arg2));
  
  char targetSteamId[32], mainSteamId[32];
  bool foundTarget = false, foundMain = false;
  
  // Try to find target player first
  int targetClient = FindTarget(client, arg1, true, false);
  if (targetClient != -1) {
    if (GetClientAuthId(targetClient, AuthId_Steam2, targetSteamId, sizeof(targetSteamId))) {
      foundTarget = true;
    }
  } else {
    // If not found as player, assume it's a Steam ID
    strcopy(targetSteamId, sizeof(targetSteamId), arg1);
    foundTarget = true;
  }
  
  // Try to find main player
  int mainClient = FindTarget(client, arg2, true, false);
  if (mainClient != -1) {
    if (GetClientAuthId(mainClient, AuthId_Steam2, mainSteamId, sizeof(mainSteamId))) {
      foundMain = true;
    }
  } else {
    // If not found as player, assume it's a Steam ID
    strcopy(mainSteamId, sizeof(mainSteamId), arg2);
    foundMain = true;
  }
  
  if (!foundTarget || !foundMain) {
    MC_ReplyToCommand(client, "Failed to resolve Steam IDs");
    return Plugin_Handled;
  }
  
  // Get admin Steam ID
  char adminSteamId[32];
  if (!GetClientAuthId(client, AuthId_Steam2, adminSteamId, sizeof(adminSteamId))) {
    MC_ReplyToCommand(client, "Failed to get your Steam ID");
    return Plugin_Handled;
  }
  
  // Check if target Steam ID already exists in whois_permname or whois_alt_links
  char query[512];
  DataPack pack = new DataPack();
  pack.WriteCell(GetClientUserId(client));
  pack.WriteString(targetSteamId);
  pack.WriteString(mainSteamId);
  pack.WriteString(adminSteamId);
  
  g_Database.Format(query, sizeof(query), 
    "SELECT steam_id FROM whois_permname WHERE steam_id = '%s' UNION SELECT steam_id FROM whois_alt_links WHERE steam_id = '%s'", 
    targetSteamId, targetSteamId);
  g_Database.Query(SQL_CheckTargetExists, query, pack);
  
  return Plugin_Handled;
}

/* Name History Menu */

void ShowNameHistoryMenu(int client, int args) {
  // Check console
  if (!client) {
    MC_ReplyToCommand(client, "%t", "noConsole");
    return;
  }
  
  switch (args) {
    case 0: {
      Menu menu = new Menu(Menu_NameHistory);
      menu.SetTitle("%t", "pickPlayer");
      
      char id[8];
      for (int i = 1; i <= MaxClients; i++) {
        if (IsClientConnected(i) && IsClientAuthorized(i) && !IsFakeClient(i)) {
          IntToString(i, id, sizeof(id));
          
          // Get player name
          char name[MAX_NAME_LENGTH];
          GetClientName(i, name, sizeof(name));
          
          // Get permaname if exists
          char permaname[128];
          Whois_GetPermaname(i, permaname, sizeof(permaname));
          
          // Create display name with permaname if it exists
          char displayName[MAX_NAME_LENGTH + 128];
          if (permaname[0] != '\0') {
            Format(displayName, sizeof(displayName), "%s (%s)", name, permaname);
          } else {
            strcopy(displayName, sizeof(displayName), name);
          }
          
          menu.AddItem(id, displayName);
        }
      }
      menu.Display(client, 30);
      return;
    }
    
    case 1: {
      char arg[32];
      GetCmdArg(1, arg, sizeof(arg));
      
      int target = FindTarget(client, arg, true, false);
      if (target == -1) {
        return;
      }
      
      char steamid[32];
      if (!GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid))) {
        MC_PrintToChat(client, "%t", "noSteamID", target);
        return;
      }
      
      char query[256];
      Format(query, sizeof(query), "SELECT DISTINCT name, date FROM whois_logs WHERE steam_id = '%s';", steamid);
      
      g_Database.Query(SQL_NameHistory, query, GetClientUserId(client));
      return;
    }
    
    default: {
      ShowNameHistoryMenu(client, 0);
      return;
    }
  }
}

public int Menu_NameHistory(Menu hMenu, MenuAction action, int client, int selection) {
  switch (action) {
    case MenuAction_Select: {
      char info[64];
      hMenu.GetItem(selection, info, sizeof(info));
      int target = StringToInt(info);
      
      if (!IsClientConnected(target) || !IsClientAuthorized(target)) {
        return 0;
      }
      
      char steamid[32];
      if (!GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid))) {
        MC_PrintToChat(client, "%t", "noSteamID", target);
        return 0;
      }
      
      char query[256];
      g_Database.Format(query, sizeof(query), "SELECT DISTINCT name, date FROM whois_logs WHERE steam_id = '%s' ORDER BY entry DESC;", steamid);
      g_Database.Query(SQL_NameHistory, query, GetClientSerial(client));
    }
    
    case MenuAction_End: {
      delete hMenu;
    }
  }
  return 0;
}

public void SQL_NameHistory(Database db, DBResultSet results, const char[] error, int userid) {
  if (db == null || results == null) {
    LogError("[WhoIs] SQL_NameHistory Error >> %s", error);
    return;
  }
  
  int client = GetClientOfUserId(userid);
  
  int nameCol, dateCol;
  results.FieldNameToNum("name", nameCol);
  results.FieldNameToNum("date", dateCol);
  
  int count;
  
  Menu menu = new Menu(Menu_Empty);
  menu.SetTitle("%t", "playerNameActivity");
  
  while (results.FetchRow()) {
    count++;
    char name[64]; results.FetchString(nameCol, name, sizeof(name));
    char date[32]; results.FetchString(dateCol, date, sizeof(date));
    char entry[128]; Format(entry, sizeof(entry), "%s - %s", name, date);
    char id[16]; IntToString(count, id, sizeof(id));
    menu.AddItem(id, entry, ITEMDRAW_DISABLED);
  }
  
  menu.ExitBackButton = true;
  menu.Display(client, 30);
  
  delete results;
}

public int Menu_Empty(Menu hMenu, MenuAction action, int client, int selection) {
  switch (action) {
    case MenuAction_End: {
      delete hMenu;
      return 1;
    }
    
    case MenuAction_Cancel: {
      if (selection == MenuCancel_ExitBack) {
        ShowNameHistoryMenu(client, 0);
      }
    }
  }
  return 1;
}

/* Events */

public void Event_ChangeName(Event event, const char[] name, bool dontBroadcast) {
  char newname[64];
  int client = GetClientOfUserId(event.GetInt("userid"));
  event.GetString("newname", newname, sizeof(newname));
  InsertPlayerData(client, "namechange", newname);
}

/* Log */

void InsertPlayerData(int client, const char[] action, const char[] newname = "") {
  if (!IsClientConnected(client) || !IsClientAuthorized(client) || IsFakeClient(client)) {
    return;
  }
  
  // Get Steam ID
  char steamid[32];
  if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid))) {
    LogError("[WhoIs] Error while fetching AuthID for %N", client);
  }
  
  // Get name
  char name[MAX_NAME_LENGTH];
  char safeName[128];
  GetClientName(client, name, sizeof(name));
  
  if (newname[0] != '\0') {
    g_Database.Escape(newname, safeName, sizeof(safeName));
  }
  else {
    g_Database.Escape(name, safeName, sizeof(safeName));
  }
  
  // Get IP
  char ip[16];
  GetClientIP(client, ip, sizeof(ip));
  
  char query[1024];
  g_Database.Format(query, sizeof(query), "INSERT INTO whois_logs (steam_id, name, date, time, timestamp, ip, server_ip, server_name, action) "...
    "VALUES ('%s', '%s', CURRENT_DATE(), CURTIME(), UNIX_TIMESTAMP(), '%s', '%s', '%s', '%s')", steamid, safeName, ip, g_ServerIP, g_ServerHostname, action);
  
  g_Database.Query(SQL_GenericQuery, query);
}

/* SQL Callbacks */

public void SQL_GenericQuery(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null || results == null) {
    LogError("[WhoIs] SQL_GenericQuery Error >> %s", error);
    return;
  }
  delete results;
}

public void SQL_OnSetPermanameCompleted(Database db, DBResultSet results, const char[] error, DataPack pack) {
  // Check database
  if (db == null || results == null) {
    LogError(error);
    return;
  }
  
  // Get datapack info
  pack.Reset();
  
  int issuerUID = pack.ReadCell();
  int issuerClient = GetClientOfUserId(issuerUID);
  
  int targetUID = pack.ReadCell();
  int targetClient = GetClientOfUserId(targetUID);
  
  char name[32];
  pack.ReadString(name, sizeof(name));
  delete pack;
  
  // Send forward with info
  Forward_OnPermanameModified(issuerUID, targetUID, name);
  
  // Update cache
  strcopy(g_Permanames[targetClient], sizeof(g_Permanames[]), name);
  
  // Inform admin
  MC_PrintToChat(issuerClient, "%t", "nameGiven", targetClient, name);
}

public void SQL_ConnectDatabase(Database db, const char[] error, any data) {
  if (db == null) {
    SetFailState("[WhoIs] SQL_ConnectDatabase Error >> %s", error);
  }
  
  g_Database = db;
  CreateTable();
  
  if (g_Late) {
    for (int i = 1; i <= MaxClients; i++) {
      InsertPlayerData(i, "connect-late");
      CachePermaname(i);
      CacheLinkedAlt(i);
    }
  }
  return;
}

public void SQL_OnPermanameReceived(Database db, DBResultSet results, const char[] error, int userid) {
  if (db == null || results == null) {
    LogError(error);
    return;
  }
  
  int client = GetClientOfUserId(userid);
  
  if (!results.FetchRow()) {
    strcopy(g_Permanames[client], sizeof(g_Permanames[]), "");
    return;
  }
  
  results.FetchString(0, g_Permanames[client], sizeof(g_Permanames[]));
}

public void SQL_OnLinkedAltReceived(Database db, DBResultSet results, const char[] error, DataPack pack) {
  if (db == null || results == null) {
    LogError("[WhoIs] SQL_OnLinkedAltReceived Error >> %s", error);
    delete pack;
    return;
  }
  
  pack.Reset();
  char steamid[32];
  pack.ReadString(steamid, sizeof(steamid));
  delete pack;
  
  bool isLinked = results.FetchRow();
  g_LinkedAlts.SetValue(steamid, isLinked);
}

public void SQL_CheckTargetExists(Database db, DBResultSet results, const char[] error, DataPack pack) {
  if (db == null || results == null) {
    LogError("[WhoIs] SQL_CheckTargetExists Error >> %s", error);
    delete pack;
    return;
  }
  
  pack.Reset();
  int clientUID = pack.ReadCell();
  int client = GetClientOfUserId(clientUID);
  
  char targetSteamId[32], mainSteamId[32], adminSteamId[32];
  pack.ReadString(targetSteamId, sizeof(targetSteamId));
  pack.ReadString(mainSteamId, sizeof(mainSteamId));
  pack.ReadString(adminSteamId, sizeof(adminSteamId));
  
  if (results.FetchRow()) {
    MC_PrintToChat(client, "Target Steam ID is already linked or has a permaname");
    delete pack;
    return;
  }
  
  // Check if main Steam ID exists in whois_permname
  char query[256];
  g_Database.Format(query, sizeof(query), "SELECT steam_id FROM whois_permname WHERE steam_id = '%s'", mainSteamId);
  g_Database.Query(SQL_CheckMainExists, query, pack);
}

public void SQL_CheckMainExists(Database db, DBResultSet results, const char[] error, DataPack pack) {
  if (db == null || results == null) {
    LogError("[WhoIs] SQL_CheckMainExists Error >> %s", error);
    delete pack;
    return;
  }
  
  pack.Reset();
  int clientUID = pack.ReadCell();
  int client = GetClientOfUserId(clientUID);
  
  char targetSteamId[32], mainSteamId[32], adminSteamId[32];
  pack.ReadString(targetSteamId, sizeof(targetSteamId));
  pack.ReadString(mainSteamId, sizeof(mainSteamId));
  pack.ReadString(adminSteamId, sizeof(adminSteamId));
  
  if (!results.FetchRow()) {
    MC_PrintToChat(client, "Main Steam ID does not have a permaname");
    delete pack;
    return;
  }
  
  // Insert the link
  char query[256];
  g_Database.Format(query, sizeof(query), 
    "INSERT INTO whois_alt_links (steam_id, main_steam_id, linked_by) VALUES ('%s', '%s', '%s')", 
    targetSteamId, mainSteamId, adminSteamId);
  g_Database.Query(SQL_OnLinkCompleted, query, pack);
}

public void SQL_OnLinkCompleted(Database db, DBResultSet results, const char[] error, DataPack pack) {
  pack.Reset();
  int clientUID = pack.ReadCell();
  int client = GetClientOfUserId(clientUID);
  
  char targetSteamId[32], mainSteamId[32];
  pack.ReadString(targetSteamId, sizeof(targetSteamId));
  pack.ReadString(mainSteamId, sizeof(mainSteamId));
  delete pack;
  
  if (db == null || results == null) {
    LogError("[WhoIs] SQL_OnLinkCompleted Error >> %s", error);
    MC_PrintToChat(client, "Failed to link Steam IDs");
    return;
  }
  
  // Update cache
  g_LinkedAlts.SetValue(targetSteamId, true);
  
  MC_PrintToChat(client, "Successfully linked %s to %s", targetSteamId, mainSteamId);
}

/* Forwards */

void Forward_OnPermanameModified(int userid, int target, const char[] name) {
  Call_StartForward(g_gfOnPermanameModified);
  Call_PushCell(userid);
  Call_PushCell(target);
  Call_PushString(name);
  Call_Finish();
}

/* Natives */

public int Native_GetPermaname(Handle plugin, int numParams) {
  int client = GetNativeCell(1);
  if (!IsValidClient(client)) {
    ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
    return 0;
  }
  SetNativeString(2, g_Permanames[client], sizeof(g_Permanames[]));
  return 0;
}

public int Native_IsLinkedAlt(Handle plugin, int numParams) {
  char steamid[32];
  GetNativeString(1, steamid, sizeof(steamid));
  
  bool isLinked;
  if (g_LinkedAlts.GetValue(steamid, isLinked)) {
    return isLinked;
  }
  
  return false;
}

/* Methods */

void CachePermaname(int client) {
  char steamid[32];
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  
  char query[256];
  g_Database.Format(query, sizeof(query), "SELECT name FROM whois_permname WHERE steam_id = '%s'", steamid);
  
  g_Database.Query(SQL_OnPermanameReceived, query, GetClientUserId(client));
}

void CacheLinkedAlt(int client) {
  if (!IsClientConnected(client) || !IsClientAuthorized(client) || IsFakeClient(client)) {
    return;
  }
  
  char steamid[32];
  if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid))) {
    return;
  }
  
  char query[256];
  g_Database.Format(query, sizeof(query), "SELECT steam_id FROM whois_alt_links WHERE steam_id = '%s'", steamid);
  
  DataPack pack = new DataPack();
  pack.WriteString(steamid);
  g_Database.Query(SQL_OnLinkedAltReceived, query, pack);
}

bool IsValidClient(int iClient, bool bIgnoreKickQueue = false)
{
  if 
    (
    // "client" is 0 (console) or lower - nope!
    0 >= iClient
    // "client" is higher than MaxClients - nope!
     || MaxClients < iClient
    // "client" isnt in game aka their entity hasn't been created - nope!
     || !IsClientInGame(iClient)
    // "client" is in the kick queue - nope!
     || (IsClientInKickQueue(iClient) && !bIgnoreKickQueue)
    // "client" is sourcetv - nope!
     || IsClientSourceTV(iClient)
    // "client" is the replay bot - nope!
     || IsClientReplay(iClient)
    )
  {
    return false;
  }
  return true;
} 
