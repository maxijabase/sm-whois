#if defined _whois_included
#endinput
#endif
#define _whois_included

/*
** Get's a client's permaname
**
** @param client		The client index
** @param buffer 		Buffer to store permaname
** @param maxlen		Buffer's max length
*/
native int Whois_GetPermaname(int client, char[] buffer, int maxlen);

/*
** Called when the permaname of a user is changed
**
** @param issuer			The userid of the issuer
** @param target 		The targeted user userid
** @param name 			The new target permaname
** @noreturn
*/
forward void Whois_OnPermanameModified(int issuer, int target, const char[] name);

stock void GetServerIP(char[] buffer, int size, bool showport = false) {
	int ip[4];
	SteamWorks_GetPublicIP(ip);
	
	Format(buffer, size, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
	
	if (showport) {
		Format(buffer, size, "%s:%d", buffer, FindConVar("hostport").IntValue);
	}
}

stock void GetServerName(char[] buffer, int size) {
	char hostname[128];
	FindConVar("hostname").GetString(hostname, sizeof(hostname));
	Format(buffer, size, "%s", hostname);
}

public SharedPlugin __pl_INTERFACE = 
{
	name = "whois", 
	file = "whois.smx", 
	#if defined REQUIRE_PLUGIN
	required = 1, 
	#else
	required = 0, 
	#endif
}; 