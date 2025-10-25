#include <sdktools>
#include <regex>
#include <basecomm>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required

KeyValues g_Kv;
StringMap g_SMsteamID;

char g_sFilePath[PLATFORM_MAX_PATH], g_sSteamID[32], g_sForcedName[64], g_sOriginalName[64], g_sAdminName[64], g_sTime[32];

Regex g_FilterExpr;
char g_sFilterChar[2] = "";
ArrayList g_BannedExprs;
ArrayList g_ReplacementNames;
int g_iBlockNameChangeEvents[MAXPLAYERS + 1] = {0, ...};
ConVar g_hNFDebug;
bool g_bNFDebug = false;
bool g_bLateLoaded = false;

public Plugin myinfo =
{
	name = "NameFilter",
	author = "BotoX, .Rushaway",
	description = "Filters player names + Force names",
	url = "https://github.com/srcdslab/sm-plugin-NameFilter",
	version = "2.0.5"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("namefilter.phrases");

	RegAdminCmd("sm_forcename", Command_ForceName, ADMFLAG_BAN, "Force a player's name permanently.");
	RegAdminCmd("sm_forcednames", Command_ForcedNames, ADMFLAG_BAN, "View all forced names in a menu.");
	RegAdminCmd("sm_namefilter_reload", Command_NameFilterReload, ADMFLAG_CONFIG, "Reload NameFilter configuration.");

	g_hNFDebug = CreateConVar("sm_namefilter_debug", "0", "Enable NameFilter debug logs", FCVAR_NONE, true, 0.0, true, 1.0);
	g_bNFDebug = g_hNFDebug.BoolValue;
	g_hNFDebug.AddChangeHook(OnCvarChanged);

	HookEvent("player_changename", Event_ChangeName, EventHookMode_Pre);
	HookUserMessage(GetUserMessageId("SayText2"), UserMessage_SayText2, true);

	EnsureNameFilterInit();
	LoadConfig();
	GetNamesFromCfg();

	if (!g_bLateLoaded)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i))
			OnClientConnected(i);
	}
}

public void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_bNFDebug = g_hNFDebug.BoolValue;
	LogMessage("[NameFilter] Debug %s", g_bNFDebug ? "ENABLED" : "DISABLED");
}

public void OnMapStart()
{
	delete g_SMsteamID;
	g_SMsteamID = new StringMap();

	LoadConfig();
	GetNamesFromCfg();
}

public void OnClientConnected(int client)
{
	g_iBlockNameChangeEvents[client] = 0;

	if (IsFakeClient(client))
		return;

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	if (FilterName(client, sName))
	{
		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(sName);
		RequestFrame(OnFrameRequested, pack);
	}

	if (!IsValidClient(client))
		CreateTimer(2.0, CheckClientName, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action CheckClientName(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (client && GetClientAuthId(client, AuthId_Steam2, g_sSteamID, sizeof(g_sSteamID)) && g_SMsteamID.GetString(g_sSteamID, g_sForcedName, sizeof(g_sForcedName)))
	{
		DataPack pack = new DataPack();
		pack.WriteCell(client);
		pack.WriteString(g_sForcedName);
		RequestFrame(OnFrameRequested, pack);
	}
	return Plugin_Stop;
}

stock void OnFrameRequested(DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	char sName[MAX_NAME_LENGTH];
	pack.ReadString(sName, sizeof(sName));
	delete pack;

	if (!IsValidClient(client))
		return;

	SetClientName(client, sName);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
		return;

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	if (FilterName(client, sName))
	{
		g_iBlockNameChangeEvents[client] = 2;
		SetClientName(client, sName);
	}
}

public Action Event_ChangeName(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (g_iBlockNameChangeEvents[client])
	{
		g_iBlockNameChangeEvents[client]--;
		SetEventBroadcast(event, true);
		return Plugin_Handled;
	}

	if (!IsValidClient(client))
	{
		char NewName[64];
		event.GetString("newname", NewName, sizeof(NewName));
		if (GetClientAuthId(client, AuthId_Steam2, g_sSteamID, sizeof(g_sSteamID)) && g_SMsteamID.GetString(g_sSteamID, g_sForcedName, sizeof(g_sForcedName)))
		{
			if (!StrEqual(NewName, g_sForcedName, false))
				SetClientName(client, g_sForcedName);
		}
	}

	return Plugin_Continue;
}

public Action Command_ForceName(int client, int args)
{
	char Arg1[64], Arg2[64], TargetName[64];

	if (args != 2)
	{
		CReplyToCommand(client, "%t", "Usage");
		return Plugin_Handled;
	}

	GetCmdArg(1, Arg1, sizeof(Arg1));
	GetCmdArg(2, Arg2, sizeof(Arg2));

	int g_iTarget = FindTarget(client, Arg1, true);

	if (g_iTarget == -1)
		return Plugin_Handled;

	GetClientName(client, g_sAdminName, sizeof(g_sAdminName));

	if (client <= 0)
		Format(g_sAdminName, sizeof(g_sAdminName), "Console/Server");

	GetClientName(g_iTarget, TargetName, sizeof(TargetName));

	if (!GetClientAuthId(g_iTarget, AuthId_Steam2, g_sSteamID, sizeof(g_sSteamID)))
	{
		CReplyToCommand(client, "%t", "InvalidSteamID");
		return Plugin_Handled;
	}

	CReplyToCommand(client, "%t", "ForcedName", Arg2, TargetName, g_sSteamID);

	SetClientName(g_iTarget, Arg2);

	SetUpKeyValues();

	g_Kv.JumpToKey(g_sSteamID, true);
	g_Kv.SetString("OriginalName", TargetName);
	g_Kv.SetString("ForcedName", Arg2);
	g_SMsteamID.SetString(g_sSteamID, Arg2);
	g_Kv.SetString("AdminName", g_sAdminName);
	FormatTime(g_sTime, sizeof(g_sTime), "%d.%m.%Y %R", GetTime());
	g_Kv.SetString("Date", g_sTime);
	g_Kv.Rewind();
	g_Kv.ExportToFile(g_sFilePath);
	delete g_Kv;

	return Plugin_Handled;
}

public Action Command_ForcedNames(int client, int args)
{
	char MenuBuffer[128], MenuBuffer2[32], MenuBuffer3[128];

	Menu MainMenu = new Menu(MenuHandle);

	Format(MenuBuffer, sizeof(MenuBuffer), "%T", "MenuTitle", client);
	MainMenu.SetTitle(MenuBuffer);

	SetUpKeyValues();
	if (!g_Kv.GotoFirstSubKey())
	{
		Format(MenuBuffer2, sizeof(MenuBuffer2), "%T", "MenuEmpty", client);
		MainMenu.AddItem("", MenuBuffer2, ITEMDRAW_DISABLED);
	} else {
		do
		{
			g_Kv.GetSectionName(g_sSteamID, sizeof(g_sSteamID));
			g_Kv.GetString("ForcedName", g_sForcedName, sizeof(g_sForcedName));
			// Check if g_sForcedName is empty, if yes then skip this entry
			if (g_sForcedName[0] == '\0')
				continue;
			Format(MenuBuffer3, sizeof(MenuBuffer3), "%T", "MenuContent", client, g_sForcedName);
			MainMenu.AddItem(g_sSteamID, MenuBuffer3);
		}
		while(g_Kv.GotoNextKey());
	}
	delete g_Kv;

	MainMenu.ExitButton = true;
	MainMenu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public Action Command_NameFilterReload(int client, int args)
{
	LoadConfig();
	CReplyToCommand(client, "[NameFilter] Configuration reloaded.");
	return Plugin_Handled;
}

int MenuHandle(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char MenuBuffer[128], MenuChoice[32], MenuBuffer2[128], MenuBuffer3[32];

		Menu SubMenu = new Menu(SubMenuHandle);

		Format(MenuBuffer, sizeof(MenuBuffer), "%T", "SubMenuTitle", param1);
		SubMenu.SetTitle(MenuBuffer);

		menu.GetItem(param2, MenuChoice, sizeof(MenuChoice));

		SetUpKeyValues();
		g_Kv.JumpToKey(MenuChoice, false);
		g_Kv.GetString("ForcedName", g_sForcedName, sizeof(g_sForcedName));
		g_Kv.GetString("OriginalName", g_sOriginalName, sizeof(g_sOriginalName));
		g_Kv.GetString("AdminName", g_sAdminName, sizeof(g_sAdminName));
		g_Kv.GetString("Date", g_sTime, sizeof(g_sTime));
		delete g_Kv;

		Format(MenuBuffer2, sizeof(MenuBuffer2), "%T", "SubMenuContent", param1, g_sForcedName, g_sOriginalName, g_sAdminName, g_sTime);
		Format(MenuBuffer3, sizeof(MenuBuffer3), "%T", "SubMenuDeleteName", param1);
		SubMenu.AddItem("0", MenuBuffer2, ITEMDRAW_DISABLED);
		SubMenu.AddItem(MenuChoice, MenuBuffer3);

		SubMenu.ExitBackButton = true;
		SubMenu.Display(param1, MENU_TIME_FOREVER);
	}

	else if (action == MenuAction_End)
		delete menu;

	return 0;
}

int SubMenuHandle(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		switch(param2)
		{
			case 1:
			{
				char MenuChoice[32];
				menu.GetItem(param2, MenuChoice, sizeof(MenuChoice));
				SetUpKeyValues();
				g_Kv.JumpToKey(MenuChoice, false);
				g_Kv.DeleteThis();
				g_Kv.Rewind();
				g_Kv.ExportToFile(g_sFilePath);
				delete g_Kv;
				g_SMsteamID.Remove(MenuChoice);
				CReplyToCommand(param1, "%t", "NameDeleted");
				Command_ForcedNames(param1, param2);
			}
		}
	}

	if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
			Command_ForcedNames(param1, param2);
	}

	else if (action == MenuAction_End)
		delete menu;

	return 0;
}

void GetNamesFromCfg()
{
	SetUpKeyValues();
	g_Kv.GotoFirstSubKey();
	do
	{
		g_Kv.GetSectionName(g_sSteamID, sizeof(g_sSteamID));
		g_Kv.GetString("ForcedName", g_sForcedName, sizeof(g_sForcedName));
		g_SMsteamID.SetString(g_sSteamID, g_sForcedName);
	}
	while(g_Kv.GotoNextKey());
	delete g_Kv;
}

void SetUpKeyValues()
{
	delete g_Kv;
	BuildFilePath();
	g_Kv = new KeyValues("NameFilter");

	if (!g_Kv.ImportFromFile(g_sFilePath))
	{
		delete g_Kv;
		SetFailState("ImportFromFile() failed!");
	}

	NF_DebugLog("Using config path: %s", g_sFilePath);
}

public Action UserMessage_SayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!reliable)
		return Plugin_Continue;

	int client;
	char sMessage[32];
	char sOldName[MAX_NAME_LENGTH];
	char sNewName[MAX_NAME_LENGTH];

	if (GetUserMessageType() == UM_Protobuf)
	{
		PbReadString(msg, "msg_name", sMessage, sizeof(sMessage));

		if (!(sMessage[0] == '#' && StrContains(sMessage, "Name_Change")))
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

		if (!(sMessage[0] == '#' && StrContains(sMessage, "Name_Change")))
			return Plugin_Continue;

		BfReadString(msg, sOldName, sizeof(sOldName));
		BfReadString(msg, sNewName, sizeof(sNewName));
	}

	if (g_iBlockNameChangeEvents[client])
	{
		g_iBlockNameChangeEvents[client]--;
		return Plugin_Handled;
	}

	bool bGagged = BaseComm_IsClientGagged(client);
	if (IsValidClient(client) && IsClientInGame(client))
	{
		if (FilterName(client, sNewName) || bGagged)
		{
			if (StrEqual(sOldName, sNewName) || bGagged)
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

			CreateTimer(0.1, Timer_ChangeName, pack, TIMER_FLAG_NO_MAPCHANGE);

			return Plugin_Handled;
		}
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
	if (g_FilterExpr != INVALID_HANDLE)
		CloseHandle(g_FilterExpr);

	if (g_BannedExprs)
	{
		for (int i = 0; i < g_BannedExprs.Length; i++)
		{
			Handle hRegex = g_BannedExprs.Get(i);
			CloseHandle(hRegex);
		}
	}

	delete g_BannedExprs;
	delete g_ReplacementNames;

	if (!BuildFilePath())
		SetFailState("Could not find config: \"%s\"", g_sFilePath);

	delete g_Kv;
	g_Kv = new KeyValues("NameFilter");
	if (!g_Kv.ImportFromFile(g_sFilePath))
	{
		delete g_Kv;
		SetFailState("ImportFromFile() failed!");
	}

	g_Kv.GetString("censor", g_sFilterChar, 2, "*");
	NF_DebugLog("Loaded censor: '%s'", g_sFilterChar);

	static char sBuffer[256];
	g_Kv.GetString("filter", sBuffer, 256);
	NF_DebugLog("Loaded filter regex: %s", sBuffer);

	char sError[256];
	RegexError iError;
	g_FilterExpr = CompileRegex(sBuffer, PCRE_UTF8, sError, sizeof(sError), iError);
	if (iError != REGEX_ERROR_NONE)
	{
		delete g_Kv;
		SetFailState(sError);
	}

	g_BannedExprs = new ArrayList();
	if (g_Kv.JumpToKey("banned"))
	{
		if (g_Kv.GotoFirstSubKey(false))
		{
			do
			{
				g_Kv.GetString(NULL_STRING, sBuffer, sizeof(sBuffer));
				NF_DebugLog("Loaded banned regex: %s", sBuffer);
				Handle hRegex = CompileRegex(sBuffer, PCRE_UTF8, sError, sizeof(sError), iError);
				if (iError != REGEX_ERROR_NONE)
					LogError("Error parsing banned filter: %s", sError);
				else
					g_BannedExprs.Push(hRegex);
			} while(g_Kv.GotoNextKey(false));
			g_Kv.GoBack();
		}
		g_Kv.GoBack();
	}

	g_ReplacementNames = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
	if (g_Kv.JumpToKey("names"))
	{
		if (g_Kv.GotoFirstSubKey(false))
		{
			do
			{
				g_Kv.GetString(NULL_STRING, sBuffer, sizeof(sBuffer));
				NF_DebugLog("Loaded replacement name: %s", sBuffer);
				g_ReplacementNames.PushString(sBuffer);
			} while(g_Kv.GotoNextKey(false));
			g_Kv.GoBack();
		}
		g_Kv.GoBack();
	}

	if (!g_ReplacementNames.Length)
	{
		LogError("Warning, you didn't specify any replacement names!");
		g_ReplacementNames.PushString("BAD_NAME");
	}

	NF_DebugLog("Init done. Banned: %d, Replacements: %d", g_BannedExprs.Length, g_ReplacementNames.Length);

	delete g_Kv;
}

bool FilterName(int client, char[] sName, int Length = MAX_NAME_LENGTH)
{
	bool bChanged = false;
	RegexError iError;

	NF_DebugLog("FilterName in: '%s' (client %d)", sName, client);

	// SourceMod Regex bug
	int Guard;
	for (Guard = 0; Guard < 100; Guard++)
	{
		if (!strlen(sName))
			break;

		int Match = MatchRegex(g_FilterExpr, sName, iError);
		if (iError != REGEX_ERROR_NONE)
		{
			if (iError == REGEX_ERROR_BADUTF8)
			{
				sName[0] = 0;
				bChanged = true;
				NF_DebugLog("BAD UTF8 detected, clearing name");
			}
			else
			{
				LogError("Regex Error: %d", iError);
				NF_DebugLog("Regex error while matching filter: %d", iError);
			}

			break;
		}

		if (Match <= 0)
			break;

		for (int i = 0; i < Match; i++)
		{
			char sMatch[MAX_NAME_LENGTH];
			if (GetRegexSubString(g_FilterExpr, i, sMatch, sizeof(sMatch)))
			{
				NF_DebugLog("Matched substring: '%s'", sMatch);
				if (ReplaceStringEx(sName, Length, sMatch, g_sFilterChar) != -1)
					bChanged = true;
				NF_DebugLog("After replace -> '%s'", sName);
			}
		}
	}
	if (Guard == 100)
		LogError("SourceMod Regex failed! \"%s\"", sName);

	if (g_BannedExprs)
	{
		for (int i = 0; i < g_BannedExprs.Length; i++)
		{
			if (!strlen(sName))
				break;

			Handle hRegex = g_BannedExprs.Get(i);
			int Match = MatchRegex(hRegex, sName, iError);
			if (iError != REGEX_ERROR_NONE)
			{
				LogError("Regex Error: %d", iError);
				continue;
			}

			if (Match <= 0)
				continue;

			int RandomName = client % g_ReplacementNames.Length;
			g_ReplacementNames.GetString(RandomName, sName, Length);
			NF_DebugLog("Banned pattern matched, forcing replacement: '%s'", sName);
			return true;
		}
	}

	if (!bChanged)
		bChanged = TerminateNameUTF8(sName);

	if (bChanged)
	{
		TerminateNameUTF8(sName);

		if (strlen(sName) < 2 || IsNameOnlyWhitespace(sName))
		{
			int RandomName = client % g_ReplacementNames.Length;
			g_ReplacementNames.GetString(RandomName, sName, Length);
			NF_DebugLog("Name too short or only whitespace after filter, replacement: '%s'", sName);
			return true;
		}
	}

	NF_DebugLog("FilterName out: changed=%d final='%s'", bChanged, sName);
	return bChanged;
}

// ensures that utf8 names are properly terminated
stock bool TerminateNameUTF8(char[] name)
{
	int len = strlen(name);
	for (int i = 0; i < len; i++)
	{
		int bytes = IsCharMB(name[i]);
		if (bytes > 1)
		{
			if (len - i < bytes)
			{
				name[i] = '\0';
				return true;
			}

			i += bytes - 1;
		}
	}
	return false;
}

stock bool BuildFilePath()
{
	BuildPath(Path_SM, g_sFilePath, sizeof(g_sFilePath), "configs/NameFilter.cfg");

	// Retro compatibility
	if (!FileExists(g_sFilePath))
		BuildPath(Path_SM, g_sFilePath, sizeof(g_sFilePath), "configs/namefilter.cfg");

	// Verify if the path exist as lowercase (linux srcds)
	if (!FileExists(g_sFilePath))
		return false;

	NF_DebugLog("Resolved config path: %s", g_sFilePath);
	return true;
}

stock void EnsureNameFilterInit()
{
	if (!g_SMsteamID)
		g_SMsteamID = new StringMap();

	if (!g_BannedExprs)
		g_BannedExprs = new ArrayList();

	if (!g_ReplacementNames)
		g_ReplacementNames = new ArrayList(ByteCountToCells(MAX_NAME_LENGTH));
}

bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
}

stock void NF_DebugLog(const char[] fmt, any ...)
{
	if (!g_bNFDebug)
		return;

	static char buffer[256];
	VFormat(buffer, sizeof(buffer), fmt, 2);
	LogMessage("[NameFilter][DEBUG] %s", buffer);
}

stock bool IsNameOnlyWhitespace(const char[] name)
{
	int len = strlen(name);
	int i = 0;
	bool any = false;
	while (i < len)
	{
		// ASCII whitespace
		if (name[i] == ' ' || name[i] == '\t' || name[i] == '\n' || name[i] == '\r')
		{
			any = true;
			i++;
			continue;
		}
		// Non-breaking space (U+00A0) in UTF-8: 0xC2 0xA0
		if (i + 1 < len && name[i] == 0xC2 && name[i + 1] == 0xA0)
		{
			any = true;
			i += 2;
			continue;
		}
		return false; // found a non-whitespace code unit/sequence
	}
	return any; // true only if at least one whitespace and no other chars
}
