#include <sdktools>
#include <regex>
#include <basecomm>

#pragma semicolon 1
#pragma newdecls required

Regex g_FilterExpr;
char g_FilterChar[2] = "";
ArrayList g_BannedExprs;
ArrayList g_ReplacementNames;
int g_iBlockNameChangeEvents[MAXPLAYERS + 1] = {0, ...};

public Plugin myinfo =
{
	name = "NameFilter",
	author = "BotoX",
	description = "Filters player names",
	version = "1.0"
}

public void OnPluginStart()
{
	HookEvent("player_changename", Event_ChangeName, EventHookMode_Pre);
	HookUserMessage(GetUserMessageId("SayText2"), UserMessage_SayText2, true);

	LoadConfig();

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i))
			OnClientConnected(i);
	}
}

public void OnClientConnected(int client)
{
	g_iBlockNameChangeEvents[client] = 0;

	if(IsFakeClient(client))
		return;

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	if(FilterName(client, sName))
		SetClientName(client, sName);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client))
		return;

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	if(FilterName(client, sName))
	{
		g_iBlockNameChangeEvents[client] = 2;
		SetClientName(client, sName);
	}
}

public Action Event_ChangeName(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(g_iBlockNameChangeEvents[client])
	{
		g_iBlockNameChangeEvents[client]--;
		SetEventBroadcast(event, true);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action UserMessage_SayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!reliable)
		return Plugin_Continue;

	int client;
	char sMessage[32];
	char sOldName[MAX_NAME_LENGTH];
	char sNewName[MAX_NAME_LENGTH];

	if(GetUserMessageType() == UM_Protobuf)
	{
		PbReadString(msg, "msg_name", sMessage, sizeof(sMessage));

		if(!(sMessage[0] == '#' && StrContains(sMessage, "Name_Change")))
			return Plugin_Continue;

		client = PbReadInt(msg, "ent_idx");
		PbReadString(msg, "params", sOldName, sizeof(sOldName), 1);
		PbReadString(msg, "params", sNewName, sizeof(sNewName), 2);
	}
	else
	{
		client = BfReadByte(msg);
		BfReadByte(msg);
		BfReadString(msg, sMessage, sizeof(sMessage));

		if(!(sMessage[0] == '#' && StrContains(sMessage, "Name_Change")))
			return Plugin_Continue;

		BfReadString(msg, sOldName, sizeof(sOldName));
		BfReadString(msg, sNewName, sizeof(sNewName));
	}

	if(g_iBlockNameChangeEvents[client])
	{
		g_iBlockNameChangeEvents[client]--;
		return Plugin_Handled;
	}

	bool bGagged = BaseComm_IsClientGagged(client);
	if(FilterName(client, sNewName) || bGagged)
	{
		if(StrEqual(sOldName, sNewName) || bGagged)
		{
			g_iBlockNameChangeEvents[client] = 3;
			SetClientName(client, sOldName);
			return Plugin_Handled;
		}

		g_iBlockNameChangeEvents[client] = 3;
		SetClientName(client, sOldName);

		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(sNewName);

		CreateTimer(0.1, Timer_ChangeName, pack);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_ChangeName(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();
	char sName[MAX_NAME_LENGTH];
	pack.ReadString(sName, sizeof(sName));

	delete pack;

	SetClientName(client, sName);

	return Plugin_Stop;
}

void LoadConfig()
{
	if(g_FilterExpr != INVALID_HANDLE)
		CloseHandle(g_FilterExpr);

	if(g_BannedExprs)
	{
		for(int i = 0; i < g_BannedExprs.Length; i++)
		{
			Handle hRegex = g_BannedExprs.Get(i);
			CloseHandle(hRegex);
		}
	}

	delete g_BannedExprs;
	delete g_ReplacementNames;

	static char sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/NameFilter.cfg");
	if(!FileExists(sConfigFile))
		SetFailState("Could not find config: \"%s\"", sConfigFile);

	KeyValues Config = new KeyValues("NameFilter");
	if(!Config.ImportFromFile(sConfigFile))
	{
		delete Config;
		SetFailState("ImportFromFile() failed!");
	}

	Config.GetString("censor", g_FilterChar, 2, "*");

	static char sBuffer[256];
	Config.GetString("filter", sBuffer, 256);

	char sError[256];
	RegexError iError;
	g_FilterExpr = CompileRegex(sBuffer, PCRE_UTF8, sError, sizeof(sError), iError);
	if(iError != REGEX_ERROR_NONE)
	{
		delete Config;
		SetFailState(sError);
	}

	g_BannedExprs = new ArrayList();
	if(Config.JumpToKey("banned"))
	{
		if(Config.GotoFirstSubKey(false))
		{
			do
			{
				Config.GetString(NULL_STRING, sBuffer, sizeof(sBuffer));

				Handle hRegex = CompileRegex(sBuffer, PCRE_UTF8, sError, sizeof(sError), iError);
				if(iError != REGEX_ERROR_NONE)
					LogError("Error parsing banned filter: %s", sError);
				else
					g_BannedExprs.Push(hRegex);
			} while(Config.GotoNextKey(false));
			Config.GoBack();
		}
		Config.GoBack();
	}

	g_ReplacementNames = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
	if(Config.JumpToKey("names"))
	{
		if(Config.GotoFirstSubKey(false))
		{
			do
			{
				Config.GetString(NULL_STRING, sBuffer, sizeof(sBuffer));

				g_ReplacementNames.PushString(sBuffer);
			} while(Config.GotoNextKey(false));
			Config.GoBack();
		}
		Config.GoBack();
	}

	if(!g_ReplacementNames.Length)
	{
		LogError("Warning, you didn't specify any replacement names!");
		g_ReplacementNames.PushString("BAD_NAME");
	}

	delete Config;
}

bool FilterName(int client, char[] sName, int Length = MAX_NAME_LENGTH)
{
	bool bChanged = false;
	RegexError iError;

	// SourceMod Regex bug
	int Guard;
	for(Guard = 0; Guard < 100; Guard++)
	{
		if (!strlen(sName))
			break;

		int Match = MatchRegex(g_FilterExpr, sName, iError);
		if(iError != REGEX_ERROR_NONE)
		{
			if(iError == REGEX_ERROR_BADUTF8)
			{
				sName[0] = 0;
				bChanged = true;
			}
			else
				LogError("Regex Error: %d", iError);

			break;
		}

		if(Match <= 0)
			break;

		for(int i = 0; i < Match; i++)
		{
			char sMatch[MAX_NAME_LENGTH];
			if(GetRegexSubString(g_FilterExpr, i, sMatch, sizeof(sMatch)))
			{
				if(ReplaceStringEx(sName, Length, sMatch, g_FilterChar) != -1)
					bChanged = true;
			}
		}
	}
	if(Guard == 100)
		LogError("SourceMod Regex failed! \"%s\"", sName);

	if(g_BannedExprs)
	{
		for(int i = 0; i < g_BannedExprs.Length; i++)
		{
			if (!strlen(sName))
				break;

			Handle hRegex = g_BannedExprs.Get(i);
			int Match = MatchRegex(hRegex, sName, iError);
			if(iError != REGEX_ERROR_NONE)
			{
				LogError("Regex Error: %d", iError);
				continue;
			}

			if(Match <= 0)
				continue;

			int RandomName = client % g_ReplacementNames.Length;
			g_ReplacementNames.GetString(RandomName, sName, Length);
			return true;
		}
	}

	if(!bChanged)
		bChanged = TerminateNameUTF8(sName);

	if(bChanged)
	{
		TerminateNameUTF8(sName);

		if(strlen(sName) < 2)
		{
			int RandomName = client % g_ReplacementNames.Length;
			g_ReplacementNames.GetString(RandomName, sName, Length);
			return true;
		}
	}

	return bChanged;
}

// ensures that utf8 names are properly terminated
stock bool TerminateNameUTF8(char[] name)
{
	int len = strlen(name);
	for(int i = 0; i < len; i++)
	{
		int bytes = IsCharMB(name[i]);
		if(bytes > 1)
		{
			if(len - i < bytes)
			{
				name[i] = '\0';
				return true;
			}

			i += bytes - 1;
		}
	}
	return false;
}
