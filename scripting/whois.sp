/* Dependencies */

#include <sourcemod>
#include <morecolors>
#include <steamworks>
#include "whois/whois.inc"

#pragma semicolon 1
#pragma newdecls required

/* Plugin Info */

public Plugin myinfo = {
	name = "WhoIs", 
	author = "ampere", 
	description = "Provides player identification and logging capabilities.", 
	version = "2.2", 
	url = "github.com/maxijabase"
}

GlobalForward g_gfOnPermanameModified;
Database g_Database;
bool g_Late = false;
char g_ServerIP[32];
char g_ServerHostname[64];
char g_Permanames[MAXPLAYERS + 1][128];

/* Plugin Start */

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	
	g_gfOnPermanameModified = new GlobalForward("Whois_OnPermanameModified", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	
	CreateNative("Whois_GetPermaname", Native_GetPermaname);
	
	RegPluginLibrary("whois");
	g_Late = late;
}

public void OnPluginStart() {
	Database.Connect(SQL_ConnectDatabase, "whois");
	
	HookEvent("player_changename", Event_ChangeName);
	
	RegAdminCmd("sm_whois", CMD_Whois, ADMFLAG_GENERIC, "View permaname of a player");
	RegAdminCmd("sm_namehistory", CMD_Namehistory, ADMFLAG_GENERIC, "View name history of a player");
	
	RegAdminCmd("sm_thisis", CMD_Thisis, ADMFLAG_GENERIC, "Set name of a player");
	
	LoadTranslations("common.phrases");
	LoadTranslations("whois.phrases");
	
	if (SteamWorks_IsConnected()) {
		GetServerIP(g_ServerIP, sizeof(g_ServerIP), true);
	}
	
	if (g_Late) {
		OnConfigsExecuted();
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
	
}

/* Forwards */

public void OnClientPostAdminCheck(int client) {
	InsertPlayerData(client, "connect");
	CachePermaname(client);
}

public void OnClientDisconnect(int client) {
	InsertPlayerData(client, "disconnect");
	g_Permanames[client][0] = '\0';
}

/* Commands */

public Action CMD_Whois(int client, int args) {
	// Check database
	if (g_Database == null) {
		ThrowError("Database not connected");
		MC_ReplyToCommand(client, "%t", "databaseError");
		return Plugin_Handled;
	}
	
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
		FakeClientCommand(client, "sm_namehistory %N", target);
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
	char arg1[32]; GetCmdArg(1, arg1, sizeof(arg1));
	char name[32]; GetCmdArg(2, name, sizeof(name));
	int target = FindTarget(client, arg1, true, false);
	
	if (target == -1) {
		return Plugin_Handled;
	}
	
	// Update permaname in database
	char steamid[32];
	GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
	
	char query[256];
	Format(query, sizeof(query), "INSERT INTO whois_permname VALUES('%s', '%s') ON DUPLICATE KEY UPDATE name = '%s';", steamid, name, name);
	
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(GetClientUserId(target));
	pack.WriteString(name);
	g_Database.Query(SQL_OnSetPermanameCompleted, query, pack);
	
	return Plugin_Handled;
}

public Action CMD_Namehistory(int client, int args) {
	if (g_Database == null) {
		ThrowError("Database not connected");
		MC_ReplyToCommand(client, "%t", "databaseError");
		return Plugin_Handled;
	}
	
	ShowNameHistoryMenu(client, args);
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
			Menu menu = new Menu(Handler_ActivityList);
			menu.SetTitle("%t", "pickPlayer");
			
			char id[8];
			for (int i = 1; i <= MaxClients; i++) {
				if (IsClientConnected(i) && IsClientAuthorized(i) && !IsFakeClient(i)) {
					IntToString(i, id, sizeof(id));
					char name[MAX_NAME_LENGTH]; GetClientName(i, name, sizeof(name));
					menu.AddItem(id, name);
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
			GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
			
			char query[256];
			Format(query, sizeof(query), "SELECT DISTINCT name, date FROM whois_logs WHERE steam_id = '%s';", steamid);
			
			g_Database.Query(SQL_GetPlayerActivity, query, GetClientSerial(client));
			
			return;
		}
		
		default: {
			ShowNameHistoryMenu(client, 0);
			return;
		}
	}
}

public int Handler_ActivityList(Menu hMenu, MenuAction action, int client, int selection) {
	switch (action) {
		case MenuAction_Select: {
			char info[64];
			hMenu.GetItem(selection, info, sizeof(info));
			int target = StringToInt(info);
			
			if (!IsClientConnected(target) || !IsClientAuthorized(target)) {
				return 0;
			}
			
			char steamid[32];
			GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
			
			char query[256];
			Format(query, sizeof(query), "SELECT DISTINCT name, date FROM whois_logs WHERE steam_id = '%s' ORDER BY entry DESC;", steamid);
			
			g_Database.Query(SQL_GetPlayerActivity, query, GetClientSerial(client));
			
			return 1;
		}
		
		case MenuAction_End: {
			delete hMenu;
			return 0;
		}
	}
	return 1;
}

public void SQL_GetPlayerActivity(Database db, DBResultSet results, const char[] error, any data) {
	if (db == null || results == null) {
		LogError("[WhoIs] SQL_GetPlayerActivity Error >> %s", error);
		return;
	}
	
	int client = GetClientFromSerial(data);
	
	int nameCol, dateCol;
	results.FieldNameToNum("name", nameCol);
	results.FieldNameToNum("date", dateCol);
	
	int count;
	
	Menu menu = new Menu(Handler_Nothing);
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

public int Handler_Nothing(Menu hMenu, MenuAction action, int client, int selection) {
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

public void Event_ChangeName(Event e, const char[] name, bool noBroadcast) {
	char newname[64];
	int client = GetClientOfUserId(e.GetInt("userid"));
	e.GetString("newname", newname, sizeof(newname));
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
	}
	
	results.FetchString(0, g_Permanames[client], sizeof(g_Permanames[]));
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
	if (client < 1 || client > MaxClients || !IsClientInGame(client)) {
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return;
	}
	SetNativeString(2, g_Permanames[client], sizeof(g_Permanames[]));
}

/* Methods */

void CachePermaname(int client) {
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	char query[256];
	g_Database.Format(query, sizeof(query), "SELECT name FROM whois_permname WHERE steam_id = '%s'", steamid);
	
	g_Database.Query(SQL_OnPermanameReceived, query, GetClientUserId(client));
}
