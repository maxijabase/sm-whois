
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