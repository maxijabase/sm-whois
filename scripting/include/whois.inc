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
** Checks if a Steam ID is linked as an alt account
**
** @param steamid		The Steam ID to check
** @param mainSteamId		Buffer to store main account Steam ID (optional)
** @param mainSteamIdLen	Maximum length of mainSteamId buffer
** @param permaname		Buffer to store main account permaname (optional)
** @param permanameLen		Maximum length of permaname buffer
** @return			True if Steam ID is in alt links table, false otherwise
*/
native bool Whois_IsLinkedAlt(const char[] steamid, char[] mainSteamId = "", int mainSteamIdLen = 0, char[] permaname = "", int permanameLen = 0);

/*
** Called when the permaname of a user is changed
**
** @param issuer			The userid of the issuer
** @param target 		The targeted user userid
** @param name 			The new target permaname
** @noreturn
*/
forward void Whois_OnPermanameModified(int issuer, int target, const char[] name);

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