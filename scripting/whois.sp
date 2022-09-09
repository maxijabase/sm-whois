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
	version = "2.1.1", 
	url = "github.com/maxijabase"
}

GlobalForward g_gfOnPermanameModified;
Database g_Database = null;
bool g_Late = false;
char g_cServerIP[32];
char g_cServerHostname[64];

/* Plugin Start */

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("whois");
	g_Late = late;
}

public void OnPluginStart() {
	Database.Connect(SQL_ConnectDatabase, "whois");
	
	HookEvent("player_changename", Event_ChangeName);
	
	RegConsoleCmd("sm_whois", Command_ShowName, "View set name of a player");
	RegConsoleCmd("sm_whois_full", Command_Activity, "View names of a player");
	
	g_gfOnPermanameModified = new GlobalForward("Whois_OnPermanameModified", ET_Ignore, Param_Cell, Param_Cell, Param_String);
	
	RegAdminCmd("sm_thisis", Command_SetName, ADMFLAG_GENERIC, "Set name of a player");
	
	LoadTranslations("common.phrases");
	LoadTranslations("whois.phrases");
	
	if (SteamWorks_IsConnected()) {
		GetServerIP(g_cServerIP, sizeof(g_cServerIP), true);
	}
	
	if (g_Late) {
		OnConfigsExecuted();
	}
}

public void SteamWorks_SteamServersConnected() {
	GetServerIP(g_cServerIP, sizeof(g_cServerIP), true);
}

public void OnConfigsExecuted() {
	GetServerName(g_cServerHostname, sizeof(g_cServerHostname));
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

/* Commands */

public Action Command_SetName(int client, int args) {
	if (g_Database == null) {
		ThrowError("Database not connected");
		MC_ReplyToCommand(client, "%t", "databaseError");
		return Plugin_Handled;
	}
	
	if (args != 2) {
		MC_ReplyToCommand(client, "%t", "thisisUsage");
		return Plugin_Handled;
	}
	
	char arg1[32]; GetCmdArg(1, arg1, sizeof(arg1));
	char name[32]; GetCmdArg(2, name, sizeof(name));
	int target = FindTarget(client, arg1, true, false);
	
	if (target == -1) {
		return Plugin_Handled;
	}
	
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

public Action Command_ShowName(int client, int args) {
	if (g_Database == null) {
		ThrowError("Database not connected");
		MC_ReplyToCommand(client, "%t", "databaseError");
		return Plugin_Handled;
	}
	
	if (args != 1) {
		MC_ReplyToCommand(client, "%t", "whoisUsage");
		return Plugin_Handled;
	}
	
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	
	int target = FindTarget(client, arg, true, false);
	
	if (target == -1) {
		return Plugin_Handled;
	}
	
	char steamid[32];
	GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));
	
	char query[256];
	Format(query, sizeof(query), "SELECT name FROM whois_permname WHERE steam_id = '%s';", steamid);
	
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(target);
	
	g_Database.Query(SQL_SelectPermName, query, pack);
	
	return Plugin_Handled;
}

public Action Command_Activity(int client, int args) {
	if (g_Database == null) {
		ThrowError("Database not connected");
		MC_ReplyToCommand(client, "%t", "databaseError");
		return Plugin_Handled;
	}
	
	ShowActivityMenu(client, args);
	return Plugin_Handled;
}

void ShowActivityMenu(int client, int args) {
	switch (args) {
		case 0: {
			if (!client) {
				MC_ReplyToCommand(client, "%t", "noConsole");
				return;
			}
			
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
			if (!client) {
				MC_ReplyToCommand(client, "%t", "noConsole");
				return;
			}
			
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
	}
}

public void SQL_SelectPermName(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if (db == null || results == null) {
		LogError("[WhoIs] SQL_SelectPermName Error >> %s", error);
		PrintToServer("WhoIs >> Failed to query: %s", error);
		delete results;
		return;
	}
	
	pack.Reset();
	int client = pack.ReadCell();
	int target = pack.ReadCell();
	delete pack;
	
	if (!results.FetchRow()) {
		MC_PrintToChat(client, "%t", "noName", target);
		ShowActivityMenu(client, target);
		return;
	}
	
	int nameCol;
	results.FieldNameToNum("name", nameCol);
	
	char name[128];
	results.FetchString(nameCol, name, sizeof(name));
	MC_PrintToChat(client, "%t", "thisIsPlayer", target, name);
	
	delete results;
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

public void OnClientPostAdminCheck(int client) {
	InsertPlayerData(client, "connect");
}

public void OnClientDisconnect(int client) {
	InsertPlayerData(client, "disconnect");
}

public void Event_ChangeName(Event e, const char[] name, bool noBroadcast) {
	char newname[64];
	int client = GetClientOfUserId(e.GetInt("userid"));
	e.GetString("newname", newname, sizeof(newname));
	InsertPlayerData(client, "namechange", newname);
}

void InsertPlayerData(int client, const char[] action, const char[] newname = "") {
	if (g_Database == null) {
		LogError("Database not connected");
		return;
	}
	
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
	char safeName[129];
	if (!GetClientName(client, name, sizeof(name))) {
		LogError("[WhoIs] Error while fetching Name for %N", client);
	}
	else {
		if (newname[0] != '\0') {
			g_Database.Escape(newname, safeName, sizeof(safeName));
		}
		else {
			g_Database.Escape(name, safeName, sizeof(safeName));
		}
	}
	
	// Get IP
	char ip[16];
	if (!GetClientIP(client, ip, sizeof(ip))) {
		LogError("[WhoIs] Error while fetching IP for %N", client);
	}
	
	char query[1024];
	g_Database.Format(query, sizeof(query), "INSERT INTO whois_logs (steam_id, name, date, time, timestamp, ip, server_ip, server_name, action) "...
		"VALUES ('%s', '%s', CURRENT_DATE(), CURTIME(), UNIX_TIMESTAMP(), '%s', '%s', '%s', '%s')", steamid, safeName, ip, g_cServerIP, g_cServerHostname, action);
	
	g_Database.Query(SQL_GenericQuery, query);
}

public int Handler_Nothing(Menu hMenu, MenuAction action, int client, int selection) {
	switch (action) {
		case MenuAction_End: {
			delete hMenu;
			return 1;
		}
		
		case MenuAction_Cancel: {
			if (selection == MenuCancel_ExitBack) {
				ShowActivityMenu(client, 0);
			}
		}
	}
	return 1;
}

public void SQL_GetPlayerActivity(Database db, DBResultSet results, const char[] error, any data) {
	if (db == null || results == null) {
		LogError("[WhoIs] SQL_GetPlayerActivity Error >> %s", error);
		PrintToServer("WhoIs >> Failed to query: %s", error);
		delete results;
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

public void SQL_GenericQuery(Database db, DBResultSet results, const char[] error, any data) {
	if (db == null || results == null) {
		LogError("[WhoIs] SQL_GenericQuery Error >> %s", error);
		PrintToServer("WhoIs >> Failed to query: %s", error);
		delete results;
		return;
	}
	delete results;
}

public void SQL_OnSetPermanameCompleted(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if (db == null || results == null) {
		LogError("[WhoIs] SQL_GenericQuery Error >> %s", error);
		PrintToServer("WhoIs >> Failed to query: %s", error);
		delete results;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int target = GetClientOfUserId(pack.ReadCell());
	char name[32];
	pack.ReadString(name, sizeof(name));
	delete pack;
	
	Forward_OnPermanameModified(client, target, name);
	
	MC_PrintToChat(client, "%t", "nameGiven", target, name);
}

public void SQL_ConnectDatabase(Database db, const char[] error, any data) {
	if (db == null) {
		LogError("[WhoIs] SQL_ConnectDatabase Error >> %s", error);
		PrintToServer("WhoIs >> Failed to connect to database: %s", error);
		return;
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

public void OnHostnameChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	strcopy(g_cServerHostname, sizeof(g_cServerHostname), newValue);
} 

void Forward_OnPermanameModified(int client, int target, const char[] name) {
	Call_StartForward(g_gfOnPermanameModified);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_PushString(name);
	Call_Finish();
}