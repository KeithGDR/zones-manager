//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines

#define PLUGIN_DESCRIPTION "A sourcemod plugin with rich features for dynamic zone development."
#define PLUGIN_VERSION "1.0.2"

#define MAX_RADIUS_ZONES 256
#define MAX_ZONES 256

#define MAX_ZONE_NAME_LENGTH 128
#define MAX_ZONE_TYPE_LENGTH 64

#define MAX_EFFECT_NAME_LENGTH 128

#define MAX_KEY_NAME_LENGTH 128
#define MAX_KEY_VALUE_LENGTH 128

#define MAX_EFFECT_CALLBACKS 3
#define EFFECT_CALLBACK_ONENTERZONE 0
#define EFFECT_CALLBACK_ONACTIVEZONE 1
#define EFFECT_CALLBACK_ONLEAVEZONE 2

#define DEFAULT_MODELINDEX "sprites/laserbeam.vmt"
#define DEFAULT_HALOINDEX "materials/sprites/halo.vmt"

#define ZONE_TYPES 3
#define ZONE_TYPE_BOX 0
#define ZONE_TYPE_CIRCLE 1
#define ZONE_TYPE_POLY 2

//Sourcemod Includes
#include <sourcemod>
#include <sourcemod-misc>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>

//External Includes
#include <colorvariables>

//ConVars
ConVar convar_Status;
ConVar convar_PrecisionValue;

//Forwards
Handle g_Forward_QueueEffects_Post;
Handle g_Forward_StartTouchZone;
Handle g_Forward_TouchZone;
Handle g_Forward_EndTouchZone;
Handle g_Forward_StartTouchZone_Post;
Handle g_Forward_TouchZone_Post;
Handle g_Forward_EndTouchZone_Post;

//Globals
bool bLate;
KeyValues kZonesConfig;
bool bShowAllZones[MAXPLAYERS + 1] = {true, ...};
Handle g_hCookie_ShowZones;

bool g_bIsInZone[MAXPLAYERS + 1][MAX_ENTITY_LIMIT];

ArrayList g_hArray_Colors;
StringMap g_hTrie_ColorsData;

//Engine related stuff for entities.
int iDefaultModelIndex;
int iDefaultHaloIndex;
char sErrorModel[] = "models/error.mdl";

//Entities Data
ArrayList g_hZoneEntities;
float g_fZoneRadius[MAX_ENTITY_LIMIT];
int g_iZoneColor[MAX_ENTITY_LIMIT][4];
StringMap g_hZoneEffects[MAX_ENTITY_LIMIT];
ArrayList g_hZonePointsData[MAX_ENTITY_LIMIT];
float g_fZonePointsHeight[MAX_ENTITY_LIMIT];
float g_fZonePointsDistance[MAX_ENTITY_LIMIT];
float g_fZonePointsMin[MAX_ENTITY_LIMIT][3];
float g_fZonePointsMax[MAX_ENTITY_LIMIT][3];

//Not Box Type Zones Management
bool g_bIsInsideZone[MAXPLAYERS + 1][MAX_ENTITY_LIMIT];
bool g_bIsInsideZone_Post[MAXPLAYERS + 1][MAX_ENTITY_LIMIT];

//Effects Data
StringMap g_hTrie_EffectCalls;
StringMap g_hTrie_EffectKeys;
ArrayList g_hArray_EffectsList;

//Create Zones Data
char sCreateZone_Name[MAXPLAYERS + 1][MAX_ZONE_NAME_LENGTH];
int iCreateZone_Type[MAXPLAYERS + 1];
float fCreateZone_Start[MAXPLAYERS + 1][3];
float fCreateZone_End[MAXPLAYERS + 1][3];
float fCreateZone_Radius[MAXPLAYERS + 1];
ArrayList hCreateZone_PointsData[MAXPLAYERS + 1];
float fCreateZone_PointsHeight[MAXPLAYERS + 1];

bool bIsViewingZone[MAXPLAYERS + 1];
bool bSettingName[MAXPLAYERS + 1];
int iEditingName[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};

//Plugin Information
public Plugin myinfo =
{
	name = "Zones-Manager",
	author = "Keith Warren (Drixevel)",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://www.drixevel.com/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("zones_manager");

	CreateNative("ZonesManager_Register_Effect", Native_Register_Effect);
	CreateNative("ZonesManager_Register_Effect_Key", Native_Register_Effect_Key);
	CreateNative("ZonesManager_Request_QueueEffects", Native_Request_QueueEffects);
	CreateNative("ZonesManager_IsClientInZone", Native_IsClientInZone);
	CreateNative("ZonesManager_TeleportClientToZone", Native_TeleportClientToZone);

	g_Forward_QueueEffects_Post = CreateGlobalForward("ZonesManager_OnQueueEffects_Post", ET_Ignore);
	g_Forward_StartTouchZone = CreateGlobalForward("ZonesManager_OnStartTouchZone", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	g_Forward_TouchZone = CreateGlobalForward("ZonesManager_OnTouchZone", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	g_Forward_EndTouchZone = CreateGlobalForward("ZonesManager_OnEndTouchZone", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	g_Forward_StartTouchZone_Post = CreateGlobalForward("ZonesManager_OnStartTouchZone_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);
	g_Forward_TouchZone_Post = CreateGlobalForward("ZonesManager_OnTouchZone_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);
	g_Forward_EndTouchZone_Post = CreateGlobalForward("ZonesManager_OnEndTouchZone_Post", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);

	bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("zonesmanager.phrases");

	CreateConVar("sm_zonesmanager_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	convar_Status = CreateConVar("sm_zonesmanager_status", "1", "Status of the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	convar_PrecisionValue = CreateConVar("sm_zonesmanager_precision_value", "10.0", "Default value to use when setting a zones precision area.", FCVAR_NOTIFY, true, 0.0);

	//AutoExecConfig();

	HookEventEx("teamplay_round_start", OnRoundStart);
	HookEventEx("round_start", OnRoundStart);

	RegAdminCmd("sm_zone", Command_EditZoneMenu, ADMFLAG_ROOT, "Edit a certain zone that you're standing in.");
	RegAdminCmd("sm_editzone", Command_EditZoneMenu, ADMFLAG_ROOT, "Edit a certain zone that you're standing in.");
	RegAdminCmd("sm_editzonemenu", Command_EditZoneMenu, ADMFLAG_ROOT, "Edit a certain zone that you're standing in.");
	RegAdminCmd("sm_zones", Command_OpenZonesMenu, ADMFLAG_ROOT, "Display the zones manager menu.");
	RegAdminCmd("sm_zonesmenu", Command_OpenZonesMenu, ADMFLAG_ROOT, "Display the zones manager menu.");
	RegAdminCmd("sm_teleporttozone", Command_TeleportToZone, ADMFLAG_ROOT, "Teleport to a specific zone by name or by menu.");
	RegAdminCmd("sm_regeneratezones", Command_RegenerateZones, ADMFLAG_ROOT, "Regenerate all zones on the map.");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_ROOT, "Delete all zones on the map.");
	RegAdminCmd("sm_reloadeffects", Command_ReloadEffects, ADMFLAG_ROOT, "Reload all effects data and their callbacks.");

	g_hZoneEntities = CreateArray();

	g_hTrie_EffectCalls = CreateTrie();
	g_hTrie_EffectKeys = CreateTrie();
	g_hArray_EffectsList = CreateArray(ByteCountToCells(MAX_EFFECT_NAME_LENGTH));

	g_hArray_Colors = CreateArray(ByteCountToCells(64));
	g_hTrie_ColorsData = CreateTrie();

	g_hCookie_ShowZones = RegClientCookie("zones_manager_show_zones", "Show zones that are configured correctly to clients.", CookieAccess_Public);

	CreateTimer(0.1, Timer_DisplayZones, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	iDefaultModelIndex = PrecacheModel(DEFAULT_MODELINDEX);
	iDefaultHaloIndex = PrecacheModel(DEFAULT_HALOINDEX);
	PrecacheModel(sErrorModel);

	LogDebug("zonesmanager", "Deleting current zones map configuration from memory.");

	SaveMapConfig();
	ReparseMapZonesConfig();

	for (int i = 1; i <= MaxClients; i++)
	{
		for (int x = MaxClients; x < MAX_ENTITY_LIMIT; x++)
		{
			g_bIsInZone[i][x] = false;
		}
	}
}

void ReparseMapZonesConfig(bool delete_config = false)
{
	delete kZonesConfig;

	char sFolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFolder, sizeof(sFolder), "data/zones/");
	CreateDirectory(sFolder, 511);

	char sMap[32];
	GetCurrentMap(sMap, sizeof(sMap));

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/zones/%s.cfg", sMap);

	if (delete_config)
	{
		DeleteFile(sPath);
	}

	LogDebug("zonesmanager", "Creating keyvalues for the new map before pulling new map zones info.");
	kZonesConfig = CreateKeyValues("zones_manager");

	if (FileExists(sPath))
	{
		LogDebug("zonesmanager", "Config exists, retrieving the zones...");
		FileToKeyValues(kZonesConfig, sPath);
	}
	else
	{
		LogDebug("zonesmanager", "Config doesn't exist, creating new zones config for the map: %s", sMap);
		KeyValuesToFile(kZonesConfig, sPath);
	}

	LogDebug("zonesmanager", "New config successfully loaded.");
}

public void OnConfigsExecuted()
{
	ParseColorsData();

	if (bLate)
	{
		SpawnAllZones();

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientConnected(i);
			}

			if (AreClientCookiesCached(i))
			{
				OnClientCookiesCached(i);
			}
		}

		bLate = false;
	}
}

public void OnAllPluginsLoaded()
{
	QueueEffects();
}

void QueueEffects(bool reset = true)
{
	if (reset)
	{
		for (int i = 0; i < GetArraySize(g_hArray_EffectsList); i++)
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			GetArrayString(g_hArray_EffectsList, i, sEffect, sizeof(sEffect));

			Handle callbacks[MAX_EFFECT_CALLBACKS];
			GetTrieArray(g_hTrie_EffectCalls, sEffect, callbacks, sizeof(callbacks));

			for (int x = 0; x < MAX_EFFECT_CALLBACKS; x++)
			{
				delete callbacks[x];
			}
		}

		ClearTrie(g_hTrie_EffectCalls);
		ClearArray(g_hArray_EffectsList);
	}

	Call_StartForward(g_Forward_QueueEffects_Post);
	Call_Finish();
}

public void OnPluginEnd()
{
	ClearAllZones();
}

public void OnClientConnected(int client)
{
	bShowAllZones[client] = true;
}

public void OnClientCookiesCached(int client)
{
	char sValue[12];
	GetClientCookie(client, g_hCookie_ShowZones, sValue, sizeof(sValue));

	if (strlen(sValue) == 0)
	{
		bShowAllZones[client] = true;
		SetClientCookie(client, g_hCookie_ShowZones, "1");
	}
	else
	{
		bShowAllZones[client] = StringToBool(sValue);
	}
}

public void OnClientDisconnect(int client)
{
	for (int i = 0; i < MAX_ENTITY_LIMIT; i++)
	{
		g_bIsInZone[client][i] = false;
	}
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	RegenerateZones();
}

void ClearAllZones()
{
	for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
	{
		int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

		if (IsValidEntity(zone))
		{
			delete g_hZoneEffects[zone];
			AcceptEntityInput(zone, "Kill");
		}
	}

	ClearArray(g_hZoneEntities);
}

void SpawnAllZones()
{
	if (kZonesConfig == null)
	{
		return;
	}

	LogDebug("zonesmanager", "Spawning all zones...");

	KvRewind(kZonesConfig);
	if (KvGotoFirstSubKey(kZonesConfig))
	{
		do
		{
			char sName[MAX_ZONE_NAME_LENGTH];
			KvGetSectionName(kZonesConfig, sName, sizeof(sName));

			char sType[MAX_ZONE_TYPE_LENGTH];
			KvGetString(kZonesConfig, "type", sType, sizeof(sType));
			int type = GetZoneNameType(sType);

			float vStartPosition[3];
			KvGetVector(kZonesConfig, "start", vStartPosition);

			float vEndPosition[3];
			KvGetVector(kZonesConfig, "end", vEndPosition);

			float fRadius = KvGetFloat(kZonesConfig, "radius");

			int iColor[4] = {0, 255, 255, 255};
			KvGetColor(kZonesConfig, "color", iColor[0], iColor[1], iColor[2], iColor[3]);

			float points_height = KvGetFloat(kZonesConfig, "points_height", 256.0);

			ArrayList points = CreateArray(3);
			if (KvJumpToKey(kZonesConfig, "points") && KvGotoFirstSubKey(kZonesConfig, false))
			{
				do
				{
					char sPointID[12];
					KvGetSectionName(kZonesConfig, sPointID, sizeof(sPointID));
					int point_id = StringToInt(sPointID);

					float coordinates[3];
					KvGetVector(kZonesConfig, NULL_STRING, coordinates);

					ResizeArray(points, point_id + 1);
					SetArrayCell(points, point_id, coordinates[0], 0);
					SetArrayCell(points, point_id, coordinates[1], 1);
					SetArrayCell(points, point_id, coordinates[2], 2);
				}
				while (KvGotoNextKey(kZonesConfig, false));

				KvGoBack(kZonesConfig);
			}

			StringMap effects = CreateTrie();
			if (KvJumpToKey(kZonesConfig, "effects") && KvGotoFirstSubKey(kZonesConfig))
			{
				do
				{
					char sEffect[256];
					KvGetSectionName(kZonesConfig, sEffect, sizeof(sEffect));

					StringMap effect_data = CreateTrie();

					if (KvGotoFirstSubKey(kZonesConfig, false))
					{
						do
						{
							char sKey[256];
							KvGetSectionName(kZonesConfig, sKey, sizeof(sKey));

							char sValue[256];
							KvGetString(kZonesConfig, NULL_STRING, sValue, sizeof(sValue));

							SetTrieString(effect_data, sKey, sValue);
						}
						while (KvGotoNextKey(kZonesConfig, false));

						KvGoBack(kZonesConfig);
					}

					SetTrieValue(effects, sEffect, effect_data);
				}
				while (KvGotoNextKey(kZonesConfig));

				KvGoBack(kZonesConfig);
				KvGoBack(kZonesConfig);
			}

			CreateZone(sName, type, vStartPosition, vEndPosition, fRadius, iColor, points, points_height, effects);
		}
		while(KvGotoNextKey(kZonesConfig));
	}

	LogDebug("zonesmanager", "Zones have been spawned.");
}

int SpawnAZone(const char[] name)
{
	if (kZonesConfig == null)
	{
		return INVALID_ENT_INDEX;
	}

	KvRewind(kZonesConfig);
	if (KvJumpToKey(kZonesConfig, name))
	{
		char sType[MAX_ZONE_TYPE_LENGTH];
		KvGetString(kZonesConfig, "type", sType, sizeof(sType));
		int type = GetZoneNameType(sType);

		float vStartPosition[3];
		KvGetVector(kZonesConfig, "start", vStartPosition);

		float vEndPosition[3];
		KvGetVector(kZonesConfig, "end", vEndPosition);

		float fRadius = KvGetFloat(kZonesConfig, "radius");

		int iColor[4] = {0, 255, 255, 255};
		KvGetColor(kZonesConfig, "color", iColor[0], iColor[1], iColor[2], iColor[3]);

		float points_height = KvGetFloat(kZonesConfig, "points_height", 256.0);

		ArrayList points = CreateArray(3);
		if (KvJumpToKey(kZonesConfig, "points") && KvGotoFirstSubKey(kZonesConfig))
		{
			do
			{
				char sPointID[12];
				KvGetSectionName(kZonesConfig, sPointID, sizeof(sPointID));
				int point_id = StringToInt(sPointID);

				float coordinates[3];
				KvGetVector(kZonesConfig, NULL_STRING, coordinates);

				if (GetArraySize(points) < point_id + 1)
				{
					ResizeArray(points, point_id);
				}

				SetArrayCell(points, point_id, coordinates[0], 0);
				SetArrayCell(points, point_id, coordinates[1], 1);
				SetArrayCell(points, point_id, coordinates[2], 2);
			}
			while (KvGotoNextKey(kZonesConfig));

			KvGoBack(kZonesConfig);
		}

		StringMap effects = CreateTrie();
		if (KvJumpToKey(kZonesConfig, "effects") && KvGotoFirstSubKey(kZonesConfig))
		{
			do
			{
				char sEffect[256];
				KvGetSectionName(kZonesConfig, sEffect, sizeof(sEffect));

				StringMap effect_data = CreateTrie();

				if (KvGotoFirstSubKey(kZonesConfig, false))
				{
					do
					{
						char sKey[256];
						KvGetSectionName(kZonesConfig, sKey, sizeof(sKey));

						char sValue[256];
						KvGetString(kZonesConfig, NULL_STRING, sValue, sizeof(sValue));

						SetTrieString(effect_data, sKey, sValue);
					}
					while (KvGotoNextKey(kZonesConfig, false));

					KvGoBack(kZonesConfig);
				}

				SetTrieValue(effects, sEffect, effect_data);
			}
			while (KvGotoNextKey(kZonesConfig));

			KvGoBack(kZonesConfig);
			KvGoBack(kZonesConfig);
		}

		return CreateZone(name, type, vStartPosition, vEndPosition, fRadius, iColor, points, points_height, effects);
	}

	return INVALID_ENT_INDEX;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (strlen(sArgs) == 0)
	{
		return;
	}

	if (bSettingName[client])
	{
		strcopy(sCreateZone_Name[client], MAX_ZONE_NAME_LENGTH, sArgs);
		bSettingName[client] = false;
		OpenCreateZonesMenu(client);
	}

	if (iEditingName[client] != INVALID_ENT_REFERENCE)
	{
		int entity = EntRefToEntIndex(iEditingName[client]);

		char sName[MAX_ZONE_NAME_LENGTH];
		GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

		UpdateZonesSectionName(entity, sArgs);
		CPrintToChat(client, "Zone '%s' has been renamed successfully to '%s'.", sName, sArgs);
		iEditingName[client] = INVALID_ENT_REFERENCE;

		OpenZonePropertiesMenu(client, entity);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (client == 0 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	if (IsPlayerAlive(client))
	{
		float vecPosition[3];
		GetClientAbsOrigin(client, vecPosition);

		float vecOrigin[3];

		for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
		{
			int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

			if (IsValidEntity(zone))
			{
				switch (GetZoneType(zone))
				{
					case ZONE_TYPE_CIRCLE:
					{
						GetEntPropVector(zone, Prop_Data, "m_vecOrigin", vecOrigin);
						float distance = GetVectorDistance(vecOrigin, vecPosition);

						if (distance <= (g_fZoneRadius[zone] / 2.0))
						{
							Action action = IsNearExternalZone(client, zone, ZONE_TYPE_CIRCLE);

							if (action <= Plugin_Changed)
							{
								IsNearExternalZone_Post(client, zone, ZONE_TYPE_CIRCLE);
							}
						}
						else
						{
							Action action = IsNotNearExternalZone(client, zone, ZONE_TYPE_CIRCLE);

							if (action <= Plugin_Changed)
							{
								IsNotNearExternalZone_Post(client, zone, ZONE_TYPE_CIRCLE);
							}
						}
					}

					case ZONE_TYPE_POLY:
					{
						float origin[3];
						origin[0] = vecPosition[0];
						origin[1] = vecPosition[1];
						origin[2] = vecPosition[2];

						origin[2] += 42.5;

						static float offset = 16.5;
						float clientpoints[4][3];

						clientpoints[0] = origin;
						clientpoints[0][0] -= offset;
						clientpoints[0][1] -= offset;

						clientpoints[1] = origin;
						clientpoints[1][0] += offset;
						clientpoints[1][1] -= offset;

						clientpoints[2] = origin;
						clientpoints[2][0] -= offset;
						clientpoints[2][1] += offset;

						clientpoints[3] = origin;
						clientpoints[3][0] += offset;
						clientpoints[3][1] += offset;

						bool IsInZone;
						for (int x = 0; x < 4; x++)
						{
							if (IsPointInZone(clientpoints[i], zone))
							{
								IsInZone = true;
								break;
							}
						}

						if (IsInZone)
						{
							Action action = IsNearExternalZone(client, zone, ZONE_TYPE_POLY);

							if (action <= Plugin_Changed)
							{
								IsNearExternalZone_Post(client, zone, ZONE_TYPE_POLY);
							}
						}
						else
						{
							Action action = IsNotNearExternalZone(client, zone, ZONE_TYPE_POLY);

							if (action <= Plugin_Changed)
							{
								IsNotNearExternalZone_Post(client, zone, ZONE_TYPE_POLY);
							}
						}
					}
				}
			}
		}
	}

	return Plugin_Continue;
}

public Action Command_EditZoneMenu(int client, int args)
{
	if (!GetConVarBool(convar_Status))
	{
		return Plugin_Handled;
	}

	if (client == 0)
	{
		CReplyToCommand(client, "You must be in-game to use this command.");
		return Plugin_Handled;
	}

	FindZoneToEdit(client);
	return Plugin_Handled;
}

public Action Command_OpenZonesMenu(int client, int args)
{
	if (!GetConVarBool(convar_Status))
	{
		return Plugin_Handled;
	}

	if (client == 0)
	{
		CReplyToCommand(client, "You must be in-game to use this command.");
		return Plugin_Handled;
	}

	OpenZonesMenu(client);
	return Plugin_Handled;
}

public Action Command_TeleportToZone(int client, int args)
{
	if (!GetConVarBool(convar_Status))
	{
		return Plugin_Handled;
	}

	char sArg1[65];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sArg2[65];
	GetCmdArg(2, sArg2, sizeof(sArg2));

	switch (args)
	{
		case 0:
		{
			OpenTeleportToZoneMenu(client);
			return Plugin_Handled;
		}
		case 1:
		{
			char sCommand[64];
			GetCmdArg(0, sCommand, sizeof(sCommand));

			ReplyToCommand(client, "[SM] Usage: %s <#userid|name> <zone>", sCommand);
			return Plugin_Handled;
		}
	}

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS];
	bool tn_is_ml;

	int target_count = target_count = ProcessTargetString(sArg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_ALIVE, target_name, sizeof(target_name), tn_is_ml);

	if (target_count <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		TeleportToZone(client, sArg2);
	}

	return Plugin_Handled;
}

public Action Command_RegenerateZones(int client, int args)
{
	if (!GetConVarBool(convar_Status))
	{
		return Plugin_Handled;
	}

	RegenerateZones(client);
	return Plugin_Handled;
}

public Action Command_DeleteAllZones(int client, int args)
{
	if (!GetConVarBool(convar_Status))
	{
		return Plugin_Handled;
	}

	DeleteAllZones(client);
	return Plugin_Handled;
}

public Action Command_ReloadEffects(int client, int args)
{
	if (!GetConVarBool(convar_Status))
	{
		return Plugin_Handled;
	}

	QueueEffects();
	CReplyToCommand(client, "Effects data has been reloaded.");
	return Plugin_Handled;
}

void FindZoneToEdit(int client)
{
	int entity = GetEarliestTouchZone(client);

	if (entity == INVALID_ENT_INDEX || !IsValidEntity(entity))
	{
		CPrintToChat(client, "Error: You are not currently standing in a zone to edit.");
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	OpenEditZoneMenu(client, entity);
}

int GetEarliestTouchZone(int client)
{
	for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
	{
		int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

		if (IsValidEntity(zone) && g_bIsInZone[client][zone])
		{
			return zone;
		}
	}

	return INVALID_ENT_INDEX;
}

void OpenZonesMenu(int client)
{
	Menu menu = CreateMenu(MenuHandle_ZonesMenu);
	SetMenuTitle(menu, "Zones Manager");

	AddMenuItem(menu, "manage", "Manage Zones");
	AddMenuItem(menu, "create", "Create a Zone");
	AddMenuItem(menu, "---", "---", ITEMDRAW_DISABLED);
	AddMenuItemFormat(menu, "viewall", ITEMDRAW_DEFAULT, "Draw Zones: %s", bShowAllZones[client] ? "On" : "Off");
	AddMenuItemFormat(menu, "regenerate", ITEMDRAW_DEFAULT, "Regenerate Zones");
	AddMenuItemFormat(menu, "deleteall", ITEMDRAW_DEFAULT, "Delete all Zones");

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ZonesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "manage"))
			{
				OpenManageZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "create"))
			{
				OpenCreateZonesMenu(param1, true);
			}
			else if (StrEqual(sInfo, "viewall"))
			{
				bShowAllZones[param1] = !bShowAllZones[param1];
				SetClientCookie(param1, g_hCookie_ShowZones, bShowAllZones[param1] ? "1" : "0");
				OpenZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "regenerate"))
			{
				RegenerateZones(param1);
				OpenZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "deleteall"))
			{
				DeleteAllZones(param1);
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenTeleportToZoneMenu(int client)
{
	Menu menu = CreateMenu(MenuHandle_TeleportToZoneMenu);
	SetMenuTitle(menu, "Teleport to which zone:");

	for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
	{
		int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

		if (IsValidEntity(zone))
		{
			char sEntity[12];
			IntToString(zone, sEntity, sizeof(sEntity));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(zone, Prop_Data, "m_iName", sName, sizeof(sName));

			AddMenuItem(menu, sEntity, sName);
		}
	}

	if (GetMenuItemCount(menu) == 0)
	{
		AddMenuItem(menu, "", "[No Zones]", ITEMDRAW_DISABLED);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_TeleportToZoneMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEntity[64]; char sName[MAX_ZONE_NAME_LENGTH];
			GetMenuItem(menu, param2, sEntity, sizeof(sEntity), _, sName, sizeof(sName));

			TeleportToZone(param1, sName);
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void RegenerateZones(int client = -1)
{
	ClearAllZones();
	SpawnAllZones();

	if (IsPlayerIndex(client))
	{
		CReplyToCommand(client, "All zones have been regenerated on the map.");
	}
}

void DeleteAllZones(int client = -1, bool confirmation = true)
{
	if (!IsPlayerIndex(client))
	{
		ClearAllZones();
		ReparseMapZonesConfig(true);
		return;
	}

	if (!confirmation)
	{
		ClearAllZones();
		ReparseMapZonesConfig(true);
		CReplyToCommand(client, "All zones have been deleted from the map.");
		return;
	}

	Menu menu = CreateMenu(MenuHandle_ConfirmDeleteAllZones);
	SetMenuTitle(menu, "Are you sure you want to delete all zones on this map?");

	AddMenuItem(menu, "", "---", ITEMDRAW_DISABLED);
	AddMenuItem(menu, "Yes", "Yes");
	AddMenuItem(menu, "No", "No");

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ConfirmDeleteAllZones(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "No"))
			{
				OpenZonesMenu(param1);
				return;
			}

			DeleteAllZones(param1, false);
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenManageZonesMenu(int client)
{
	Menu menu = CreateMenu(MenuHandle_ManageZonesMenu);
	SetMenuTitle(menu, "Manage Zones:");

	for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
	{
		int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

		if (IsValidEntity(zone))
		{
			char sEntity[12];
			IntToString(zone, sEntity, sizeof(sEntity));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(zone, Prop_Data, "m_iName", sName, sizeof(sName));

			AddMenuItem(menu, sEntity, sName);
		}
	}

	if (GetMenuItemCount(menu) == 0)
	{
		AddMenuItem(menu, "", "[No Zones]", ITEMDRAW_DISABLED);
	}

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ManageZonesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEntity[12]; char sName[MAX_ZONE_NAME_LENGTH];
			GetMenuItem(menu, param2, sEntity, sizeof(sEntity), _, sName, sizeof(sName));

			OpenEditZoneMenu(param1, StringToInt(sEntity));
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenEditZoneMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = CreateMenu(MenuHandle_ManageEditMenu);
	SetMenuTitle(menu, "Manage Zone '%s':", sName);

	AddMenuItem(menu, "edit", "Edit Zone");
	AddMenuItem(menu, "delete", "Delete Zone");
	AddMenuItem(menu, "", "---", ITEMDRAW_DISABLED);
	AddMenuItem(menu, "effects_add", "Add Effect");
	AddMenuItem(menu, "effects_edit", "Edit Effect", ITEMDRAW_DISABLED);
	AddMenuItem(menu, "effects_remove", "Remove Effect");

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ManageEditMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");

			if (StrEqual(sInfo, "edit"))
			{
				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "delete"))
			{
				DisplayConfirmDeleteZoneMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "effects_add"))
			{
				if (!AddZoneEffectMenu(param1, entity))
				{
					OpenEditZoneMenu(param1, entity);
				}
			}
			else if (StrEqual(sInfo, "effects_edit"))
			{
				if (!EditZoneEffectMenu(param1, entity))
				{
					OpenEditZoneMenu(param1, entity);
				}
			}
			else if (StrEqual(sInfo, "effects_remove"))
			{
				if (!RemoveZoneEffectMenu(param1, entity))
				{
					OpenEditZoneMenu(param1, entity);
				}
			}
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenManageZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenZonePropertiesMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	char sRadiusAmount[64];
	FormatEx(sRadiusAmount, sizeof(sRadiusAmount), "\nRadius is currently: %.2f", g_fZoneRadius[entity]);

	Menu menu = CreateMenu(MenuHandle_ZonePropertiesMenu);
	SetMenuTitle(menu, "Edit properties for zone '%s':%s", sName, GetZoneType(entity) == ZONE_TYPE_CIRCLE ? sRadiusAmount : "");

	AddMenuItem(menu, "edit_name", "Name");
	AddMenuItem(menu, "edit_type", "Type");
	AddMenuItem(menu, "edit_color", "Color");

	switch (GetZoneType(entity))
	{
		case ZONE_TYPE_BOX:
		{
			AddMenuItem(menu, "edit_startpoint_a", "StartPoint A");
			AddMenuItem(menu, "edit_startpoint_a_precision", "StartPoint A Precision");
			AddMenuItem(menu, "edit_startpoint_b", "StartPoint B");
			AddMenuItem(menu, "edit_startpoint_b_precision", "StartPoint B Precision");
		}

		case ZONE_TYPE_CIRCLE:
		{
			AddMenuItem(menu, "edit_startpoint", "StartPoint");
			AddMenuItem(menu, "edit_add_radius", "Add to Radius");
			AddMenuItem(menu, "edit_remove_radius", "Remove from Radius");
		}

		case ZONE_TYPE_POLY:
		{
			AddMenuItem(menu, "edit_add_point", "Add a Point");
			AddMenuItem(menu, "edit_remove_point", "Remove last Point");
			AddMenuItem(menu, "edit_clear_points", "Clear all Points");
		}
	}

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ZonePropertiesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			if (StrEqual(sInfo, "edit_name"))
			{
				iEditingName[param1] = EntIndexToEntRef(entity);
				CPrintToChat(param1, "Type the new name for the zone '%s' in chat:", sName);
			}
			else if (StrEqual(sInfo, "edit_type"))
			{
				OpenEditZoneTypeMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_color"))
			{
				OpenEditZoneColorMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_startpoint_a"))
			{
				float vecLook[3];
				GetClientLookPoint(param1, vecLook);

				UpdateZonesConfigKeyVector(entity, "start", vecLook);

				entity = RemakeZoneEntity(entity);

				OpenZonePropertiesMenu(param1, entity);

				//TODO: Make this work

				/*float start[3];
				GetClientLookPoint(param1, start, true);

				float end[3];
				//GetEntPropVector(entity, Prop_Data, "m_vecMaxs", end);
				GetZonesVectorData(entity, "end", end);

				float fMiddle[3];
				GetMiddleOfABox(start, end, fMiddle);

				TeleportEntity(entity, fMiddle, NULL_VECTOR, NULL_VECTOR);

				// Have the mins always be negative
				start[0] = start[0] - fMiddle[0];
				if(start[0] > 0.0)
				start[0] *= -1.0;
				start[1] = start[1] - fMiddle[1];
				if(start[1] > 0.0)
				start[1] *= -1.0;
				start[2] = start[2] - fMiddle[2];
				if(start[2] > 0.0)
				start[2] *= -1.0;

				SetEntPropVector(entity, Prop_Data, "m_vecMins", start);*/
			}
			else if (StrEqual(sInfo, "edit_startpoint_b"))
			{
				float vecLook[3];
				GetClientLookPoint(param1, vecLook);

				UpdateZonesConfigKeyVector(entity, "end", vecLook);

				entity = RemakeZoneEntity(entity);

				OpenZonePropertiesMenu(param1, entity);

				//TODO: Make this work

				/*float start[3];
				//GetEntPropVector(entity, Prop_Data, "m_vecMins", start);
				GetZonesVectorData(entity, "start", start);

				float end[3];
				GetClientLookPoint(param1, end, true);

				float fMiddle[3];
				GetMiddleOfABox(start, end, fMiddle);

				TeleportEntity(entity, fMiddle, NULL_VECTOR, NULL_VECTOR);

				// And the maxs always be positive
				end[0] = end[0] - fMiddle[0];
				if(end[0] < 0.0)
				end[0] *= -1.0;
				end[1] = end[1] - fMiddle[1];
				if(end[1] < 0.0)
				end[1] *= -1.0;
				end[2] = end[2] - fMiddle[2];
				if(end[2] < 0.0)
				end[2] *= -1.0;

				SetEntPropVector(entity, Prop_Data, "m_vecMaxs", end);*/

				//UpdateZonesConfigKeyVector(entity, "end", end);
			}
			else if (StrEqual(sInfo, "edit_startpoint_a_precision"))
			{
				OpenEditZoneStartPointAMenu(param1, entity, true);
			}
			else if (StrEqual(sInfo, "edit_startpoint_b_precision"))
			{
				OpenEditZoneStartPointAMenu(param1, entity, false);
			}
			else if (StrEqual(sInfo, "edit_startpoint"))
			{
				float start[3];
				GetClientLookPoint(param1, start);

				TeleportEntity(entity, start, NULL_VECTOR, NULL_VECTOR);

				UpdateZonesConfigKeyVector(entity, "start", start);
				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_add_radius"))
			{
				g_fZoneRadius[entity] += 5.0;
				g_fZoneRadius[entity] = ClampCell(g_fZoneRadius[entity], 0.0, 430.0);

				char sValue[64];
				FloatToString(g_fZoneRadius[entity], sValue, sizeof(sValue));
				UpdateZonesConfigKey(entity, "radius", sValue);

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_remove_radius"))
			{
				g_fZoneRadius[entity] -= 5.0;
				g_fZoneRadius[entity] = ClampCell(g_fZoneRadius[entity], 0.0, 430.0);

				char sValue[64];
				FloatToString(g_fZoneRadius[entity], sValue, sizeof(sValue));
				UpdateZonesConfigKey(entity, "radius", sValue);

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_add_point"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);

				int size = GetArraySize(g_hZonePointsData[entity]);
				int actual = size + 1;

				ResizeArray(g_hZonePointsData[entity], actual);
				SetArrayCell(g_hZonePointsData[entity], size, vLookPoint[0], 0);
				SetArrayCell(g_hZonePointsData[entity], size, vLookPoint[1], 1);
				SetArrayCell(g_hZonePointsData[entity], size, vLookPoint[2], 2);

				SaveZonePointsData(entity);

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_remove_point"))
			{
				int size = GetArraySize(g_hZonePointsData[entity]);
				int actual = size - 1;

				if (size > 0)
				{
					ResizeArray(g_hZonePointsData[entity], actual);
					SaveZonePointsData(entity);
				}

				OpenZonePropertiesMenu(param1, entity);
			}
			else if (StrEqual(sInfo, "edit_clear_points"))
			{
				ClearArray(g_hZonePointsData[entity]);
				SaveZonePointsData(entity);

				OpenZonePropertiesMenu(param1, entity);
			}
			else
			{
				OpenZonePropertiesMenu(param1, entity);
			}
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenEditZoneStartPointAMenu(int client, int entity, bool whichpoint)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = CreateMenu(MenuHandle_ZoneEditStartPointMenu);
	SetMenuTitle(menu, "Edit start point %s properties for zone '%s':", whichpoint ? "A" : "B", sName);

	if (whichpoint)
	{
		AddMenuItem(menu, "a_add_x", "Add to X");
		AddMenuItem(menu, "a_add_y", "Add to Y");
		AddMenuItem(menu, "a_add_z", "Add to Z");
		AddMenuItem(menu, "a_remove_x", "Remove to X");
		AddMenuItem(menu, "a_remove_y", "Remove to Y");
		AddMenuItem(menu, "a_remove_z", "Remove to Z");
	}
	else
	{
		AddMenuItem(menu, "b_add_x", "Add to X");
		AddMenuItem(menu, "b_add_y", "Add to Y");
		AddMenuItem(menu, "b_add_z", "Add to Z");
		AddMenuItem(menu, "b_remove_x", "Remove to X");
		AddMenuItem(menu, "b_remove_y", "Remove to Y");
		AddMenuItem(menu, "b_remove_z", "Remove to Z");
	}

	PushMenuCell(menu, "entity", entity);
	PushMenuCell(menu, "whichpoint", whichpoint);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ZoneEditStartPointMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");
			bool whichpoint = view_as<bool>(GetMenuCell(menu, "whichpoint"));

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			float precision = GetConVarFloat(convar_PrecisionValue);

			if (StrEqual(sInfo, "a_add_x"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[0] += precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_add_y"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[1] += precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_add_z"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[2] += precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_remove_x"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[0] -= precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_remove_y"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[1] -= precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "a_remove_z"))
			{
				float vecPointA[3];
				GetZonesVectorData(entity, "start", vecPointA);

				vecPointA[2] -= precision;

				UpdateZonesConfigKeyVector(entity, "start", vecPointA);
			}
			else if (StrEqual(sInfo, "b_add_x"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[0] += precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_add_y"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[1] += precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_add_z"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[2] += precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_remove_x"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[0] -= precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_remove_y"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[1] -= precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else if (StrEqual(sInfo, "b_remove_z"))
			{
				float vecPointB[3];
				GetZonesVectorData(entity, "end", vecPointB);

				vecPointB[2] -= precision;

				UpdateZonesConfigKeyVector(entity, "end", vecPointB);
			}
			else
			{
				OpenZonePropertiesMenu(param1, entity);
			}

			entity = RemakeZoneEntity(entity);

			OpenEditZoneStartPointAMenu(param1, entity, whichpoint);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

int RemakeZoneEntity(int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	DeleteZone(entity);
	return SpawnAZone(sName);
}

void GetZonesVectorData(int entity, const char[] name, float[3] vecdata)
{
	if (kZonesConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	KvRewind(kZonesConfig);

	if (KvJumpToKey(kZonesConfig, sName))
	{
		KvGetVector(kZonesConfig, name, vecdata);
		KvRewind(kZonesConfig);
	}
}

void UpdateZonesSectionName(int entity, const char[] name)
{
	if (kZonesConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	KvRewind(kZonesConfig);

	if (KvJumpToKey(kZonesConfig, sName))
	{
		KvSetSectionName(kZonesConfig, name);
		KvRewind(kZonesConfig);
	}

	SaveMapConfig();

	SetEntPropString(entity, Prop_Data, "m_iName", name);
}

void UpdateZonesConfigKey(int entity, const char[] key, const char[] value)
{
	if (kZonesConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	KvRewind(kZonesConfig);

	if (KvJumpToKey(kZonesConfig, sName))
	{
		KvSetString(kZonesConfig, key, value);
		KvRewind(kZonesConfig);
	}

	SaveMapConfig();
}

void UpdateZonesConfigKeyVector(int entity, const char[] key, float[3] value)
{
	if (kZonesConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	KvRewind(kZonesConfig);

	if (KvJumpToKey(kZonesConfig, sName))
	{
		KvSetVector(kZonesConfig, key, value);
		KvRewind(kZonesConfig);
	}

	SaveMapConfig();
}

void SaveZonePointsData(int entity)
{
	if (kZonesConfig == null)
	{
		return;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	KvRewind(kZonesConfig);

	if (KvJumpToKey(kZonesConfig, sName))
	{
		KvDeleteKey(kZonesConfig, "points");

		if (KvJumpToKey(kZonesConfig, "points", true))
		{
			for (int i = 0; i < GetArraySize(g_hZonePointsData[entity]); i++)
			{
				char sID[12];
				IntToString(i, sID, sizeof(sID));

				float coordinates[3];
				GetArrayArray(g_hZonePointsData[entity], i, coordinates, sizeof(coordinates));

				KvSetVector(kZonesConfig, sID, coordinates);
			}
		}

		KvRewind(kZonesConfig);
	}

	SaveMapConfig();
}

void OpenEditZoneTypeMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	char sAddendum[256];
	FormatEx(sAddendum, sizeof(sAddendum), " for %s", sName);

	Menu menu = CreateMenu(MenuHandler_EditZoneTypeMenu);
	SetMenuTitle(menu, "Choose a new zone type%s:", sAddendum);

	for (int i = 0; i < ZONE_TYPES; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));

		char sType[MAX_ZONE_TYPE_LENGTH];
		GetZoneTypeName(i, sType, sizeof(sType));

		AddMenuItem(menu, sID, sType);
	}

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_EditZoneTypeMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12]; char sType[MAX_ZONE_TYPE_LENGTH];
			GetMenuItem(menu, param2, sID, sizeof(sID), _, sType, sizeof(sType));
			//int type = StringToInt(sID);

			int entity = GetMenuCell(menu, "entity");

			UpdateZonesConfigKey(entity, "type", sType);

			entity = RemakeZoneEntity(entity);

			OpenZonePropertiesMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenEditZoneColorMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	char sAddendum[256];
	FormatEx(sAddendum, sizeof(sAddendum), " for %s", sName);

	Menu menu = CreateMenu(MenuHandler_EditZoneColorMenu);
	SetMenuTitle(menu, "Choose a new zone color%s:", sAddendum);

	for (int i = 0; i < GetArraySize(g_hArray_Colors); i++)
	{
		char sColor[64];
		GetArrayString(g_hArray_Colors, i, sColor, sizeof(sColor));

		int colors[4];
		GetTrieArray(g_hTrie_ColorsData, sColor, colors, sizeof(colors));

		char sVector[64];
		FormatEx(sVector, sizeof(sVector), "%i %i %i %i", colors[0], colors[1], colors[2], colors[3]);

		AddMenuItem(menu, sVector, sColor);
	}

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_EditZoneColorMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sVector[64]; char sColor[64];
			GetMenuItem(menu, param2, sVector, sizeof(sVector), _, sColor, sizeof(sColor));

			int entity = GetMenuCell(menu, "entity");

			UpdateZonesConfigKey(entity, "color", sVector);

			int color[4];
			GetTrieArray(g_hTrie_ColorsData, sColor, color, sizeof(color));
			g_iZoneColor[entity] = color;

			OpenEditZoneColorMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void DisplayConfirmDeleteZoneMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = CreateMenu(MenuHandle_ManageConfirmDeleteZoneMenu);
	SetMenuTitle(menu, "Are you sure you want to delete '%s':", sName);

	AddMenuItem(menu, "yes", "Yes");
	AddMenuItem(menu, "no", "No");

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_ManageConfirmDeleteZoneMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			int entity = GetMenuCell(menu, "entity");

			if (StrEqual(sInfo, "no"))
			{
				OpenEditZoneMenu(param1, entity);
				return;
			}

			char sName[MAX_ZONE_NAME_LENGTH];
			GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

			DeleteZone(entity, true);
			CPrintToChat(param1, "You have deleted the zone '%s'.", sName);

			OpenManageZonesMenu(param1);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void OpenCreateZonesMenu(int client, bool reset = false)
{
	if (reset)
	{
		ResetCreateZoneVariables(client);
	}

	if (iCreateZone_Type[client] == ZONE_TYPE_POLY && hCreateZone_PointsData[client] == null)
	{
		hCreateZone_PointsData[client] = CreateArray(3);
	}
	else if (iCreateZone_Type[client] != ZONE_TYPE_POLY)
	{
		delete hCreateZone_PointsData[client];
	}

	char sType[MAX_ZONE_TYPE_LENGTH];
	GetZoneTypeName(iCreateZone_Type[client], sType, sizeof(sType));

	Menu menu = CreateMenu(MenuHandle_CreateZonesMenu);
	SetMenuTitle(menu, "Create a Zone:");

	AddMenuItem(menu, "create", "Create Zone", strlen(sCreateZone_Name[client]) > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	AddMenuItem(menu, "", "---", ITEMDRAW_DISABLED);

	AddMenuItemFormat(menu, "name", ITEMDRAW_DEFAULT, "Name: %s", strlen(sCreateZone_Name[client]) > 0 ? sCreateZone_Name[client] : "N/A");
	AddMenuItemFormat(menu, "type", ITEMDRAW_DEFAULT, "Type: %s", sType);

	switch (iCreateZone_Type[client])
	{
		case ZONE_TYPE_BOX:
		{
			AddMenuItem(menu, "start", "Set Starting Point", ITEMDRAW_DEFAULT);
			AddMenuItem(menu, "end", "Set Ending Point", ITEMDRAW_DEFAULT);
		}

		case ZONE_TYPE_CIRCLE:
		{
			AddMenuItem(menu, "start", "Set Starting Point", ITEMDRAW_DEFAULT);
			AddMenuItemFormat(menu, "radius", ITEMDRAW_DEFAULT, "Set Radius: %.2f", fCreateZone_Radius[client]);
		}

		case ZONE_TYPE_POLY:
		{
			AddMenuItem(menu, "add", "Add Zone Point", ITEMDRAW_DEFAULT);
			AddMenuItem(menu, "remove", "Remove Last Point", ITEMDRAW_DEFAULT);
			AddMenuItem(menu, "clear", "Clear All Points", ITEMDRAW_DEFAULT);
		}
	}

	AddMenuItemFormat(menu, "view", ITEMDRAW_DEFAULT, "View Zone: %s", bIsViewingZone[client] ? "On" : "Off");

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandle_CreateZonesMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "name"))
			{
				bSettingName[param1] = true;
				CPrintToChat(param1, "Type the name of this new zone in chat:");
			}
			else if (StrEqual(sInfo, "type"))
			{
				iCreateZone_Type[param1]++;

				if (iCreateZone_Type[param1] > ZONE_TYPES)
				{
					iCreateZone_Type[param1] = ZONE_TYPE_BOX;
				}

				OpenZoneTypeMenu(param1);
			}
			else if (StrEqual(sInfo, "start"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);
				Array_Copy(vLookPoint, fCreateZone_Start[param1], 3);
				//CPrintToChat(param1, "Starting point: %.2f/%.2f/%.2f", fCreateZone_Start[param1][0], fCreateZone_Start[param1][1], fCreateZone_Start[param1][2]);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "end"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);
				Array_Copy(vLookPoint, fCreateZone_End[param1], 3);
				//CPrintToChat(param1, "Ending point: %.2f/%.2f/%.2f", fCreateZone_End[param1][0], fCreateZone_End[param1][1], fCreateZone_End[param1][2]);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "radius"))
			{
				fCreateZone_Radius[param1] += 5.0;

				if (fCreateZone_Radius[param1] > 430.0)
				{
					fCreateZone_Radius[param1] = 0.0;
				}

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "add"))
			{
				float vLookPoint[3];
				GetClientLookPoint(param1, vLookPoint);

				int size = GetArraySize(hCreateZone_PointsData[param1]);
				int actual = size + 1;

				ResizeArray(hCreateZone_PointsData[param1], actual);
				SetArrayCell(hCreateZone_PointsData[param1], size, vLookPoint[0], 0);
				SetArrayCell(hCreateZone_PointsData[param1], size, vLookPoint[1], 1);
				SetArrayCell(hCreateZone_PointsData[param1], size, vLookPoint[2], 2);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "remove"))
			{
				int size = GetArraySize(hCreateZone_PointsData[param1]);
				int actual = size - 1;

				if (size > 0)
				{
					ResizeArray(hCreateZone_PointsData[param1], actual);
				}

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "clear"))
			{
				ClearArray(hCreateZone_PointsData[param1]);

				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "view"))
			{
				bIsViewingZone[param1] = !bIsViewingZone[param1];
				OpenCreateZonesMenu(param1);
			}
			else if (StrEqual(sInfo, "create"))
			{
				CreateNewZone(param1);
				OpenZonesMenu(param1);
			}
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

bool AddZoneEffectMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = CreateMenu(MenuHandler_AddZoneEffect);
	SetMenuTitle(menu, "Add a zone effect to %s:", sName);

	for (int i = 0; i < GetArraySize(g_hArray_EffectsList); i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		GetArrayString(g_hArray_EffectsList, i, sEffect, sizeof(sEffect));

		int draw = ITEMDRAW_DEFAULT;

		StringMap values;
		if (GetTrieValue(g_hZoneEffects[entity], sEffect, values) && values != null)
		{
			draw = ITEMDRAW_DISABLED;
		}

		AddMenuItem(menu, sEffect, sEffect, draw);
	}

	if (GetMenuItemCount(menu) == 0)
	{
		AddMenuItem(menu, "", "[No Effects]", ITEMDRAW_DISABLED);
	}

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	return true;
}

public int MenuHandler_AddZoneEffect(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			GetMenuItem(menu, param2, sEffect, sizeof(sEffect));

			int entity = GetMenuCell(menu, "entity");

			AddEffectToZone(entity, sEffect);

			OpenEditZoneMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

bool EditZoneEffectMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = CreateMenu(MenuHandler_EditZoneEffect);
	SetMenuTitle(menu, "Pick a zone effect to edit for %s:", sName);

	for (int i = 0; i < GetArraySize(g_hArray_EffectsList); i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		GetArrayString(g_hArray_EffectsList, i, sEffect, sizeof(sEffect));

		StringMap values;
		if (GetTrieValue(g_hZoneEffects[entity], sEffect, values) && values != null)
		{
			AddMenuItem(menu, sEffect, sEffect);
		}
	}

	if (GetMenuItemCount(menu) == 0)
	{
		AddMenuItem(menu, "", "[No Effects]", ITEMDRAW_DISABLED);
	}

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	return true;
}

public int MenuHandler_EditZoneEffect(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			GetMenuItem(menu, param2, sEffect, sizeof(sEffect));

			int entity = GetMenuCell(menu, "entity");

			OpenEditZoneMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void AddEffectToZone(int entity, const char[] effect)
{
	if (kZonesConfig == null)
	{
		return;
	}

	KvRewind(kZonesConfig);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	StringMap keys;
	GetTrieValue(g_hTrie_EffectKeys, effect, keys);

	if (KvJumpToKey(kZonesConfig, sName) && KvJumpToKey(kZonesConfig, "effects", true) && KvJumpToKey(kZonesConfig, effect, true))
	{
		if (keys != null)
		{
			SetTrieValue(g_hZoneEffects[entity], effect, CloneHandle(keys));

			Handle map = CreateTrieSnapshot(keys);

			for (int i = 0; i < TrieSnapshotLength(map); i++)
			{
				char sKey[MAX_KEY_NAME_LENGTH];
				GetTrieSnapshotKey(map, i, sKey, sizeof(sKey));

				char sValue[MAX_KEY_VALUE_LENGTH];
				GetTrieString(keys, sKey, sValue, sizeof(sValue));

				KvSetString(kZonesConfig, sKey, sValue);
			}

			delete map;
		}

		KvRewind(kZonesConfig);
	}

	SaveMapConfig();
}

stock void UpdateZoneEffectKey(int entity, const char[] effect_name, const char[] key, char[] value)
{
	if (kZonesConfig == null)
	{
		return;
	}

	KvRewind(kZonesConfig);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (KvJumpToKey(kZonesConfig, sName) && KvJumpToKey(kZonesConfig, "effects", true) && KvJumpToKey(kZonesConfig, effect_name, true))
	{
		if (strlen(value) == 0)
		{
			StringMap keys;
			GetTrieValue(g_hTrie_EffectKeys, effect_name, keys);

			GetTrieString(keys, key, value, MAX_KEY_VALUE_LENGTH);
		}

		KvSetString(kZonesConfig, key, value);
		KvRewind(kZonesConfig);
	}

	SaveMapConfig();
}

bool RemoveZoneEffectMenu(int client, int entity)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Menu menu = CreateMenu(MenuHandler_RemoveZoneEffect);
	SetMenuTitle(menu, "Add a zone type to %s to remove:", sName);

	for (int i = 0; i < GetArraySize(g_hArray_EffectsList); i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		GetArrayString(g_hArray_EffectsList, i, sEffect, sizeof(sEffect));

		int draw = ITEMDRAW_DEFAULT;

		StringMap values;
		if (!GetTrieValue(g_hZoneEffects[entity], sEffect, values))
		{
			draw = ITEMDRAW_DISABLED;
		}

		AddMenuItem(menu, sEffect, sEffect, draw);
	}

	PushMenuCell(menu, "entity", entity);

	SetMenuExitBackButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	return true;
}

public int MenuHandler_RemoveZoneEffect(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sEffect[MAX_EFFECT_NAME_LENGTH];
			GetMenuItem(menu, param2, sEffect, sizeof(sEffect));

			int entity = GetMenuCell(menu, "entity");

			RemoveEffectFromZone(entity, sEffect);

			OpenEditZoneMenu(param1, entity);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenEditZoneMenu(param1, GetMenuCell(menu, "entity"));
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void RemoveEffectFromZone(int entity, const char[] effect)
{
	if (kZonesConfig == null)
	{
		return;
	}

	KvRewind(kZonesConfig);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	StringMap values;
	if (GetTrieValue(g_hZoneEffects[entity], effect, values))
	{
		delete values;
		RemoveFromTrie(g_hZoneEffects[entity], effect);
	}

	if (KvJumpToKey(kZonesConfig, sName) && KvJumpToKey(kZonesConfig, "effects", true) && KvJumpToKey(kZonesConfig, effect))
	{
		KvDeleteThis(kZonesConfig);
		KvRewind(kZonesConfig);
	}

	SaveMapConfig();
}

void OpenZoneTypeMenu(int client)
{
	char sAddendum[256];
	FormatEx(sAddendum, sizeof(sAddendum), " for %s", sCreateZone_Name[client]);

	Menu menu = CreateMenu(MenuHandler_ZoneTypeMenu);
	SetMenuTitle(menu, "Choose a zone type%s:", strlen(sCreateZone_Name[client]) > 0 ? sAddendum : "");

	for (int i = 0; i < ZONE_TYPES; i++)
	{
		char sID[12];
		IntToString(i, sID, sizeof(sID));

		char sType[MAX_ZONE_TYPE_LENGTH];
		GetZoneTypeName(i, sType, sizeof(sType));

		AddMenuItem(menu, sID, sType);
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_ZoneTypeMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[12]; char sType[MAX_ZONE_TYPE_LENGTH];
			GetMenuItem(menu, param2, sID, sizeof(sID), _, sType, sizeof(sType));
			int type = StringToInt(sID);

			char sAddendum[256];
			FormatEx(sAddendum, sizeof(sAddendum), " for %s", sCreateZone_Name[param1]);

			iCreateZone_Type[param1] = type;
			CPrintToChat(param1, "Zone type%s set to %s.", sAddendum, sType);
			OpenCreateZonesMenu(param1);
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				OpenCreateZonesMenu(param1);
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

void CreateNewZone(int client)
{
	if (strlen(sCreateZone_Name[client]) == 0)
	{
		CPrintToChat(client, "You must set a zone name in order to create it.");
		OpenCreateZonesMenu(client);
		return;
	}

	KvRewind(kZonesConfig);

	if (KvJumpToKey(kZonesConfig, sCreateZone_Name[client]))
	{
		KvRewind(kZonesConfig);
		CPrintToChat(client, "Zone already exists, please pick a different name.");
		OpenCreateZonesMenu(client);
		return;
	}

	KvJumpToKey(kZonesConfig, sCreateZone_Name[client], true);

	char sType[MAX_ZONE_TYPE_LENGTH];
	GetZoneTypeName(iCreateZone_Type[client], sType, sizeof(sType));
	KvSetString(kZonesConfig, "type", sType);

	int iColor[4];
	iColor[0] = 255;
	iColor[1] = 255;
	iColor[2] = 0;
	iColor[3] = 255;

	char sColor[64];
	FormatEx(sColor, sizeof(sColor), "%i %i %i %i", iColor[0], iColor[1], iColor[2], iColor[3]);
	KvSetString(kZonesConfig, "color", sColor);

	fCreateZone_PointsHeight[client] = 256.0;

	switch (iCreateZone_Type[client])
	{
		case ZONE_TYPE_BOX:
		{
			KvSetVector(kZonesConfig, "start", fCreateZone_Start[client]);
			KvSetVector(kZonesConfig, "end", fCreateZone_End[client]);
		}

		case ZONE_TYPE_CIRCLE:
		{
			KvSetVector(kZonesConfig, "start", fCreateZone_Start[client]);
			KvSetFloat(kZonesConfig, "radius", fCreateZone_Radius[client]);
		}

		case ZONE_TYPE_POLY:
		{
			KvSetFloat(kZonesConfig, "points_height", fCreateZone_PointsHeight[client]);

			if (KvJumpToKey(kZonesConfig, "points", true))
			{
				for (int i = 0; i < GetArraySize(hCreateZone_PointsData[client]); i++)
				{
					char sID[12];
					IntToString(i, sID, sizeof(sID));

					float coordinates[3];
					GetArrayArray(hCreateZone_PointsData[client], i, coordinates, sizeof(coordinates));
					KvSetVector(kZonesConfig, sID, coordinates);
				}
			}
		}
	}

	SaveMapConfig();

	CreateZone(sCreateZone_Name[client], iCreateZone_Type[client], fCreateZone_Start[client], fCreateZone_End[client], fCreateZone_Radius[client], iColor, hCreateZone_PointsData[client], fCreateZone_PointsHeight[client]);
	CPrintToChat(client, "Zone '%s' has been created successfully.", sCreateZone_Name[client]);
	bIsViewingZone[client] = false;
}

void ResetCreateZoneVariables(int client)
{
	sCreateZone_Name[client][0] = '\0';
	iCreateZone_Type[client] = ZONE_TYPE_BOX;
	Array_Fill(fCreateZone_Start[client], 3, 0.0);
	Array_Fill(fCreateZone_End[client], 3, 0.0);
	fCreateZone_Radius[client] = 0.0;
	delete hCreateZone_PointsData[client];
	fCreateZone_PointsHeight[client] = 0.0;

	bIsViewingZone[client] = false;
	bSettingName[client] = false;
}

void GetZoneTypeName(int type, char[] buffer, int size)
{
	switch (type)
	{
		case ZONE_TYPE_BOX: strcopy(buffer, size, "Standard");
		case ZONE_TYPE_CIRCLE: strcopy(buffer, size, "Radius/Circle");
		case ZONE_TYPE_POLY: strcopy(buffer, size, "Polygons");
	}
}

int GetZoneType(int entity)
{
	char sClassname[64];
	GetEntityClassname(entity, sClassname, sizeof(sClassname));

	if (StrEqual(sClassname, "trigger_multiple"))
	{
		return ZONE_TYPE_BOX;
	}
	else if (StrEqual(sClassname, "info_target"))
	{
		return g_hZonePointsData[entity] != null ? ZONE_TYPE_POLY : ZONE_TYPE_CIRCLE;
	}

	return ZONE_TYPE_BOX;
}

int GetZoneNameType(const char[] sType)
{
	if (StrEqual(sType, "Standard"))
	{
		return ZONE_TYPE_BOX;
	}
	else if (StrEqual(sType, "Radius/Circle"))
	{
		return ZONE_TYPE_CIRCLE;
	}
	else if (StrEqual(sType, "Polygons"))
	{
		return ZONE_TYPE_POLY;
	}

	return ZONE_TYPE_BOX;
}

void SaveMapConfig()
{
	if (kZonesConfig == null)
	{
		return;
	}

	char sMap[32];
	GetCurrentMap(sMap, sizeof(sMap));

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/zones/%s.cfg", sMap);

	KvRewind(kZonesConfig);
	KeyValuesToFile(kZonesConfig, sPath);
}

public Action Timer_DisplayZones(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && bIsViewingZone[i])
		{
			switch (iCreateZone_Type[i])
			{
				case ZONE_TYPE_BOX:
				{
					Effect_DrawBeamBoxToClient(i, fCreateZone_Start[i], fCreateZone_End[i], iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 0.2, 5.0, 5.0, 2, 1.0, {255, 0, 0, 255}, 0);
				}

				case ZONE_TYPE_CIRCLE:
				{
					TE_SetupBeamRingPoint(fCreateZone_Start[i], fCreateZone_Radius[i], fCreateZone_Radius[i] + 4.0, iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 0.2, 5.0, 0.0, {255, 0, 0, 255}, 0, 0);
					TE_SendToClient(i, 0.0);
				}

				case ZONE_TYPE_POLY:
				{
					int size = GetArraySize(hCreateZone_PointsData[i]);

					if (size < 1)
					{
						continue;
					}

					for (int x = 0; x < size; x++)
					{
						float coordinates[3];
						GetArrayArray(hCreateZone_PointsData[i], x, coordinates, sizeof(coordinates));

						int index;

						if (x + 1 == size)
						{
							index = 0;
						}
						else
						{
							index = x + 1;
						}

						float nextpoint[3];
						GetArrayArray(hCreateZone_PointsData[i], index, nextpoint, sizeof(nextpoint));

						TE_SetupBeamPoints(coordinates, nextpoint, iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 2.0, 3.0, 3.0, 0, 0.0, {255, 0, 0, 255}, 10);
						TE_SendToClient(i);
					}
				}
			}
		}

		if (IsClientInGame(i) && bShowAllZones[i])
		{
			float vecOrigin[3];
			float vecStart[3];
			float vecEnd[3];

			for (int x = 0; x < GetArraySize(g_hZoneEntities); x++)
			{
				int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, x));

				if (IsValidEntity(zone))
				{
					GetEntPropVector(zone, Prop_Data, "m_vecOrigin", vecOrigin);

					switch (GetZoneType(zone))
					{
						case ZONE_TYPE_BOX:
						{
							GetAbsBoundingBox(zone, vecStart, vecEnd);
							Effect_DrawBeamBoxToClient(i, vecStart, vecEnd, iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 0.2, 5.0, 5.0, 2, 1.0, g_iZoneColor[zone], 0);
						}

						case ZONE_TYPE_CIRCLE:
						{
							TE_SetupBeamRingPoint(vecOrigin, g_fZoneRadius[zone], g_fZoneRadius[zone] + 4.0, iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 0.2, 5.0, 0.0, g_iZoneColor[zone], 0, 0);
							TE_SendToClient(i, 0.0);
						}

						case ZONE_TYPE_POLY:
						{
							int size = GetArraySize(g_hZonePointsData[zone]);

							if (size < 1)
							{
								continue;
							}

							for (int y = 0; y < size; y++)
							{
								float coordinates[3];
								GetArrayArray(g_hZonePointsData[zone], y, coordinates, sizeof(coordinates));

								int index;

								if (y + 1 == size)
								{
									index = 0;
								}
								else
								{
									index = y + 1;
								}

								float nextpoint[3];
								GetArrayArray(g_hZonePointsData[zone], index, nextpoint, sizeof(nextpoint));

								TE_SetupBeamPoints(coordinates, nextpoint, iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 2.0, 3.0, 3.0, 0, 0.0, g_iZoneColor[zone], 10);
								TE_SendToClient(i);
							}
						}
					}
				}
			}
		}
	}
}

void GetAbsBoundingBox(int ent, float mins[3], float maxs[3])
{
	float origin[3];

	GetEntPropVector(ent, Prop_Data, "m_vecOrigin", origin);
	GetEntPropVector(ent, Prop_Data, "m_vecMins", mins);
	GetEntPropVector(ent, Prop_Data, "m_vecMaxs", maxs);

	mins[0] += origin[0];
	mins[1] += origin[1];
	mins[2] += origin[2];

	maxs[0] += origin[0];
	maxs[1] += origin[1];
	maxs[2] += origin[2];
}

int CreateZone(const char[] sName, int type, float start[3], float end[3], float radius, int color[4], ArrayList points = null, float points_height = 256.0, StringMap effects = null)
{
	char sType[MAX_ZONE_TYPE_LENGTH];
	GetZoneTypeName(type, sType, sizeof(sType));

	LogDebug("zonesmanager", "Spawning Zone: %s - %s - %.2f/%.2f/%.2f - %.2f/%.2f/%.2f - %.2f", sName, sType, start[0], start[1], start[2], end[0], end[1], end[2], radius);

	int entity = INVALID_ENT_INDEX;
	switch (type)
	{
		case ZONE_TYPE_BOX:
		{
			entity = CreateEntityByName("trigger_multiple");

			if (IsValidEntity(entity))
			{
				DispatchKeyValue(entity, "targetname", sName);
				DispatchKeyValue(entity, "spawnflags", "64");
				DispatchSpawn(entity);

				SetEntProp(entity, Prop_Data, "m_spawnflags", 64);
				SetEntProp(entity, Prop_Send, "m_nSolidType", 2);
				SetEntityModel(entity, sErrorModel);

				float fMiddle[3];
				GetMiddleOfABox(start, end, fMiddle);

				TeleportEntity(entity, fMiddle, NULL_VECTOR, NULL_VECTOR);

				// Have the mins always be negative
				start[0] = start[0] - fMiddle[0];
				if(start[0] > 0.0)
				start[0] *= -1.0;
				start[1] = start[1] - fMiddle[1];
				if(start[1] > 0.0)
				start[1] *= -1.0;
				start[2] = start[2] - fMiddle[2];
				if(start[2] > 0.0)
				start[2] *= -1.0;

				// And the maxs always be positive
				end[0] = end[0] - fMiddle[0];
				if(end[0] < 0.0)
				end[0] *= -1.0;
				end[1] = end[1] - fMiddle[1];
				if(end[1] < 0.0)
				end[1] *= -1.0;
				end[2] = end[2] - fMiddle[2];
				if(end[2] < 0.0)
				end[2] *= -1.0;

				SetEntPropVector(entity, Prop_Data, "m_vecMins", start);
				SetEntPropVector(entity, Prop_Data, "m_vecMaxs", end);

				SDKHook(entity, SDKHook_StartTouchPost, Zones_StartTouch);
				SDKHook(entity, SDKHook_TouchPost, Zones_Touch);
				SDKHook(entity, SDKHook_EndTouchPost, Zones_EndTouch);
				SDKHook(entity, SDKHook_StartTouchPost, Zones_StartTouchPost);
				SDKHook(entity, SDKHook_TouchPost, Zones_TouchPost);
				SDKHook(entity, SDKHook_EndTouchPost, Zones_EndTouchPost);
			}
		}

		case ZONE_TYPE_CIRCLE:
		{
			entity = CreateEntityByName("info_target");

			if (IsValidEntity(entity))
			{
				DispatchKeyValue(entity, "targetname", sName);
				DispatchKeyValueVector(entity, "origin", start);
				DispatchSpawn(entity);
			}
		}

		case ZONE_TYPE_POLY:
		{
			entity = CreateEntityByName("info_target");

			if (IsValidEntity(entity))
			{
				DispatchKeyValue(entity, "targetname", sName);
				DispatchKeyValueVector(entity, "origin", start);
				DispatchSpawn(entity);

				g_hZonePointsData[entity] = points != null ? view_as<ArrayList>(CloneHandle(points)) : CreateArray(3);
				g_fZonePointsHeight[entity] = points_height;

				float tempMin[3];
				float tempMax[3];
				float greatdiff;

				for (int i = 0; i < GetArraySize(g_hZonePointsData[entity]); i++)
				{
					float coordinates[3];
					GetArrayArray(g_hZonePointsData[entity], i, coordinates, sizeof(coordinates));

					for (int j = 0; j < 3; j++)
					{
						if(tempMin[j] == 0.0 || tempMin[j] > coordinates[j]) {
							tempMin[j] = coordinates[j];
						}
						if(tempMax[j] == 0.0 || tempMax[j] < coordinates[j]) {
							tempMax[j] = coordinates[j];
						}
					}

					float coordinates2[3];
					GetArrayArray(g_hZonePointsData[entity], 0, coordinates2, sizeof(coordinates2));

					float diff = CalculateHorizontalDistance(coordinates2, coordinates, false);
					if(diff > greatdiff) {
						greatdiff = diff;
					}
				}

				for (int y = 0; y < 3; y++)
				{
					g_fZonePointsMin[entity][y] = tempMin[y];
					g_fZonePointsMax[entity][y] = tempMax[y];
				}

				g_fZonePointsDistance[entity] = greatdiff;
			}
		}
	}

	if (IsValidEntity(entity))
	{
		PushArrayCell(g_hZoneEntities, EntIndexToEntRef(entity));
		g_fZoneRadius[entity] = radius;

		delete g_hZoneEffects[entity];
		g_hZoneEffects[entity] = effects != null ? view_as<StringMap>(CloneHandle(effects)) : CreateTrie();

		g_iZoneColor[entity] = color;
	}

	LogDebug("zonesmanager", "Zone %s has been spawned %s as a %s zone with the entity index %i.", sName, IsValidEntity(entity) ? "successfully" : "not successfully", sType, entity);

	delete points;
	delete effects;
	return entity;
}

Action IsNearExternalZone(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Action result = Plugin_Continue;

	if (!g_bIsInsideZone[client][entity])
	{
		Call_StartForward(g_Forward_StartTouchZone);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish(result);

		g_bIsInsideZone[client][entity] = true;
	}
	else
	{
		Call_StartForward(g_Forward_TouchZone);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish(result);
	}

	return result;
}

Action IsNotNearExternalZone(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Action result = Plugin_Continue;

	if (g_bIsInsideZone[client][entity])
	{
		Call_StartForward(g_Forward_EndTouchZone);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish(result);

		g_bIsInsideZone[client][entity] = false;
	}

	return result;
}

void IsNearExternalZone_Post(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (!g_bIsInsideZone_Post[client][entity])
	{
		CallEffectCallback(entity, client, EFFECT_CALLBACK_ONENTERZONE);

		Call_StartForward(g_Forward_StartTouchZone_Post);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish();

		g_bIsInsideZone_Post[client][entity] = true;

		g_bIsInZone[client][entity] = true;
	}
	else
	{
		CallEffectCallback(entity, client, EFFECT_CALLBACK_ONACTIVEZONE);

		Call_StartForward(g_Forward_TouchZone_Post);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish();
	}
}

void IsNotNearExternalZone_Post(int client, int entity, int type)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	if (g_bIsInsideZone_Post[client][entity])
	{
		CallEffectCallback(entity, client, EFFECT_CALLBACK_ONLEAVEZONE);

		Call_StartForward(g_Forward_EndTouchZone_Post);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushString(sName);
		Call_PushCell(type);
		Call_Finish();

		g_bIsInsideZone_Post[client][entity] = false;

		g_bIsInZone[client][entity] = false;
	}
}

public Action Zones_StartTouch(int entity, int other)
{
	int client = other;

	if (!IsPlayerIndex(client))
	{
		return Plugin_Continue;
	}

	g_bIsInZone[client][entity] = true;

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(g_Forward_StartTouchZone);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);

	Action result = Plugin_Continue;
	Call_Finish(result);

	return result;
}

public Action Zones_Touch(int entity, int other)
{
	int client = other;

	if (!IsPlayerIndex(client))
	{
		return Plugin_Continue;
	}

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(g_Forward_TouchZone);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);

	Action result = Plugin_Continue;
	Call_Finish(result);

	return result;
}

public Action Zones_EndTouch(int entity, int other)
{
	int client = other;

	if (!IsPlayerIndex(client))
	{
		return Plugin_Continue;
	}

	g_bIsInZone[client][entity] = false;

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(g_Forward_EndTouchZone);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);

	Action result = Plugin_Continue;
	Call_Finish(result);

	return result;
}

public void Zones_StartTouchPost(int entity, int other)
{
	int client = other;

	if (!IsPlayerIndex(client))
	{
		return;
	}

	CallEffectCallback(entity, client, EFFECT_CALLBACK_ONENTERZONE);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(g_Forward_StartTouchZone_Post);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);
	Call_Finish();
}

public void Zones_TouchPost(int entity, int other)
{
	int client = other;

	if (!IsPlayerIndex(client))
	{
		return;
	}

	CallEffectCallback(entity, client, EFFECT_CALLBACK_ONACTIVEZONE);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(g_Forward_TouchZone_Post);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);
	Call_Finish();
}

public void Zones_EndTouchPost(int entity, int other)
{
	int client = other;

	if (!IsPlayerIndex(client))
	{
		return;
	}

	CallEffectCallback(entity, client, EFFECT_CALLBACK_ONLEAVEZONE);

	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	Call_StartForward(g_Forward_EndTouchZone_Post);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushString(sName);
	Call_PushCell(ZONE_TYPE_BOX);
	Call_Finish();
}

void CallEffectCallback(int entity, int client, int callback)
{
	for (int i = 0; i < GetArraySize(g_hArray_EffectsList); i++)
	{
		char sEffect[MAX_EFFECT_NAME_LENGTH];
		GetArrayString(g_hArray_EffectsList, i, sEffect, sizeof(sEffect));

		Handle callbacks[MAX_EFFECT_CALLBACKS]; StringMap values;
		if (GetTrieArray(g_hTrie_EffectCalls, sEffect, callbacks, sizeof(callbacks)) && callbacks[callback] != null && GetForwardFunctionCount(callbacks[callback]) > 0 && GetTrieValue(g_hZoneEffects[entity], sEffect, values))
		{
			Call_StartForward(callbacks[callback]);
			Call_PushCell(client);
			Call_PushCell(entity);
			Call_PushCell(values);
			Call_Finish();
		}
	}
}

void DeleteZone(int entity, bool permanent = false)
{
	char sName[MAX_ZONE_NAME_LENGTH];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, sizeof(sName));

	int index = FindValueInArray(g_hZoneEntities, EntIndexToEntRef(entity));
	RemoveFromArray(g_hZoneEntities, index);

	delete g_hZoneEffects[entity];

	AcceptEntityInput(entity, "Kill");

	if (permanent)
	{
		KvRewind(kZonesConfig);
		if (KvJumpToKey(kZonesConfig, sName))
		{
			KvDeleteThis(kZonesConfig);
		}

		SaveMapConfig();
	}
}

void RegisterNewEffect(Handle plugin, const char[] effect_name, Function function1 = INVALID_FUNCTION, Function function2 = INVALID_FUNCTION, Function function3 = INVALID_FUNCTION)
{
	if (plugin == null || strlen(effect_name) == 0)
	{
		return;
	}

	Handle callbacks[MAX_EFFECT_CALLBACKS];
	int index = FindStringInArray(g_hArray_EffectsList, effect_name);

	if (index != INVALID_ARRAY_INDEX)
	{
		GetTrieArray(g_hTrie_EffectCalls, effect_name, callbacks, sizeof(callbacks));

		for (int i = 0; i < MAX_EFFECT_CALLBACKS; i++)
		{
			delete callbacks[i];
		}

		ClearKeys(effect_name);

		RemoveFromTrie(g_hTrie_EffectCalls, effect_name);
		RemoveFromArray(g_hArray_EffectsList, index);
	}

	if (function1 != INVALID_FUNCTION)
	{
		callbacks[EFFECT_CALLBACK_ONENTERZONE] = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		AddToForward(callbacks[EFFECT_CALLBACK_ONENTERZONE], plugin, function1);
	}

	if (function2 != INVALID_FUNCTION)
	{
		callbacks[EFFECT_CALLBACK_ONACTIVEZONE] = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		AddToForward(callbacks[EFFECT_CALLBACK_ONACTIVEZONE], plugin, function2);
	}

	if (function3 != INVALID_FUNCTION)
	{
		callbacks[EFFECT_CALLBACK_ONLEAVEZONE] = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
		AddToForward(callbacks[EFFECT_CALLBACK_ONLEAVEZONE], plugin, function3);
	}

	SetTrieArray(g_hTrie_EffectCalls, effect_name, callbacks, sizeof(callbacks));
	PushArrayString(g_hArray_EffectsList, effect_name);
}

void RegisterNewEffectKey(const char[] effect_name, const char[] key, const char[] defaultvalue)
{
	StringMap keys;

	if (!GetTrieValue(g_hTrie_EffectKeys, effect_name, keys) || keys == null)
	{
		keys = CreateTrie();
	}

	SetTrieString(keys, key, defaultvalue);
	SetTrieValue(g_hTrie_EffectKeys, effect_name, keys);
}

void ClearKeys(const char[] effect_name)
{
	StringMap keys;
	if (GetTrieValue(g_hTrie_EffectKeys, effect_name, keys))
	{
		delete keys;
		RemoveFromTrie(g_hTrie_EffectKeys, effect_name);
	}
}

void GetMiddleOfABox(const float vec1[3], const float vec2[3], float buffer[3])
{
	float mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);

	mid[0] /= 2.0;
	mid[1] /= 2.0;
	mid[2] /= 2.0;

	AddVectors(vec1, mid, buffer);
}

bool GetClientLookPoint(int client, float lookposition[3], bool beam = false)
{
	float vEyePos[3];
	GetClientEyePosition(client, vEyePos);

	float vEyeAng[3];
	GetClientEyeAngles(client, vEyeAng);

	Handle hTrace = TR_TraceRayFilterEx(vEyePos, vEyeAng, MASK_SHOT, RayType_Infinite, TraceEntityFilter_NoPlayers);
	bool bHit = TR_DidHit(hTrace);

	TR_GetEndPosition(lookposition, hTrace);

	CloseHandle(hTrace);

	if (beam)
	{
		TE_SetupBeamPoints(vEyePos, lookposition, iDefaultModelIndex, iDefaultHaloIndex, 0, 30, 5.0, 5.0, 5.0, 0, 0.0, {255, 0, 0, 255}, 10);
		TE_SendToClient(client);
	}

	return bHit;
}

public bool TraceEntityFilter_NoPlayers(int entity, int contentsMask)
{
	return false;
}

stock void Array_Fill(any[] array, int size, any value, int start = 0)
{
	if (start < 0)
	{
		start = 0;
	}

	for (int i = start; i < size; i++)
	{
		array[i] = value;
	}
}

stock void Array_Copy(const any[] array, any[] newArray, int size)
{
	for (int i = 0; i < size; i++)
	{
		newArray[i] = array[i];
	}
}

stock void Effect_DrawBeamBoxToClient(int client, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const color[4] = {255, 0, 0, 255}, int speed = 0)
{
	int clients[1];
	clients[0] = client;
	Effect_DrawBeamBox(clients, 1, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

stock void Effect_DrawBeamBoxToAll(const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const color[4] = {255, 0, 0, 255}, int speed = 0)
{
	int clients[MaxClients];
	int numClients;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			clients[numClients++] = i;
		}
	}

	Effect_DrawBeamBox(clients, numClients, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

stock void Effect_DrawBeamBox(int[] clients,int numClients, const float bottomCorner[3], const float upperCorner[3], int modelIndex, int haloIndex, int startFrame = 0, int frameRate = 30, float life = 5.0, float width = 5.0, float endWidth = 5.0, int fadeLength = 2, float amplitude = 1.0, const color[4] = {255, 0, 0, 255}, int speed = 0)
{
	float corners[8][3];

	for (int i = 0; i < 4; i++)
	{
		Array_Copy(bottomCorner, corners[i], 3);
		Array_Copy(upperCorner, corners[i + 4], 3);
	}

	corners[1][0] = upperCorner[0];
	corners[2][0] = upperCorner[0];
	corners[2][1] = upperCorner[1];
	corners[3][1] = upperCorner[1];
	corners[4][0] = bottomCorner[0];
	corners[4][1] = bottomCorner[1];
	corners[5][1] = bottomCorner[1];
	corners[7][0] = bottomCorner[0];

	for (int i = 0; i < 4; i++)
	{
		int j = ( i == 3 ? 0 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for (int i = 4; i < 8; i++)
	{
		int j = ( i == 7 ? 4 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}

	for (int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i+4], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
		TE_Send(clients, numClients);
	}
}

void ParseColorsData(const char[] config = "configs/zone_colors.cfg")
{
	ClearArray(g_hArray_Colors);
	ClearTrie(g_hTrie_ColorsData);

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), config);

	KeyValues kv = CreateKeyValues("zone_colors");

	int color[4];
	char sBuffer[64];

	if (FileExists(sPath))
	{
		if (FileToKeyValues(kv, sPath) && KvGotoFirstSubKey(kv, false))
		{
			do
			{
				char sColor[64];
				KvGetSectionName(kv, sColor, sizeof(sColor));

				KvGetColor(kv, NULL_STRING, color[0], color[1], color[2], color[3]);

				PushArrayString(g_hArray_Colors, sColor);
				SetTrieArray(g_hTrie_ColorsData, sColor, color, sizeof(color));
			}
			while (KvGotoNextKey(kv, false));
		}
	}
	else
	{
		PushArrayString(g_hArray_Colors, "Clear");
		color = {255, 255, 255, 0};
		SetTrieArray(g_hTrie_ColorsData, "Clear", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		KvSetString(kv, "Clear", sBuffer);

		PushArrayString(g_hArray_Colors, "Red");
		color = {255, 0, 0, 255};
		SetTrieArray(g_hTrie_ColorsData, "Red", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		KvSetString(kv, "Red", sBuffer);

		PushArrayString(g_hArray_Colors, "Green");
		color = {0, 255, 0, 255};
		SetTrieArray(g_hTrie_ColorsData, "Green", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		KvSetString(kv, "Green", sBuffer);

		PushArrayString(g_hArray_Colors, "Blue");
		color = {0, 0, 255, 255};
		SetTrieArray(g_hTrie_ColorsData, "Blue", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		KvSetString(kv, "Blue", sBuffer);

		PushArrayString(g_hArray_Colors, "White");
		color = {255, 255, 255, 255};
		SetTrieArray(g_hTrie_ColorsData, "White", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		KvSetString(kv, "White", sBuffer);

		PushArrayString(g_hArray_Colors, "Black");
		color = {0, 0, 0, 255};
		SetTrieArray(g_hTrie_ColorsData, "Black", color, sizeof(color));
		FormatEx(sBuffer, sizeof(sBuffer), "%i %i %i %i", color[0], color[1], color[2], color[3]);
		KvSetString(kv, "Black", sBuffer);

		KeyValuesToFile(kv, sPath);
	}

	delete kv;
	LogMessage("Successfully parsed %i colors for zones.", GetArraySize(g_hArray_Colors));
}

bool TeleportToZone(int client, const char[] zone)
{
	if (!IsPlayerIndex(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	int entity = INVALID_ENT_INDEX; char sName[64];
	for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
	{
		entity = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

		if (IsValidEntity(entity))
		{
			GetEntPropString(entity, Prop_Send, "m_iName", sName, sizeof(sName));

			if (StrEqual(sName, zone))
			{
				break;
			}
		}
	}

	if (!IsEntityIndex(entity))
	{
		PrintToChat(client, "Sorry, couldn't find the zone '%s' for you to teleport to.", zone);
		return false;
	}

	float fMiddle[3];
	switch (GetZoneType(entity))
	{
		case ZONE_TYPE_BOX:
		{
			float start[3];
			GetZonesVectorData(entity, "start", start);

			float end[3];
			GetZonesVectorData(entity, "end", end);

			GetMiddleOfABox(start, end, fMiddle);
		}

		case ZONE_TYPE_CIRCLE:
		{
			GetZonesVectorData(entity, "start", fMiddle);
		}

		case ZONE_TYPE_POLY:
		{
			PrintToChat(client, "Sorry, Polygon zones aren't currently supported for teleporting.");
			return false;
		}
	}

	TeleportEntity(client, fMiddle, NULL_VECTOR, NULL_VECTOR);
	PrintToChat(client, "You have been teleported to '%s'.", zone);

	return true;
}

//Down to just above the natives, these functions are made by 'Deathknife' and repurposed by me for this plugin.
//Fucker can maths
//by Deathknife
bool IsPointInZone(float point[3], int zone)
{
	//Check if point is in the zone
	if (!IsOriginInBox(point, zone))
	{
		return false;
	}

	//Get a ray outside of the polygon
	float ray[3];
	ray = point;
	ray[1] += g_fZonePointsDistance[zone] + 50.0;
	ray[2] = point[2];

	//Store the x and y intersections of where the ray hits the line
	float xint;
	float yint;

	//Intersections for base bottom and top(2)
	float baseY;
	float baseZ;
	float baseY2;
	float baseZ2;

	//Calculate equation for x + y
	float eq[2];
	eq[0] = point[0] - ray[0];
	eq[1] = point[2] - ray[2];

	//This is for checking if the line intersected the base
	//The method is messy, came up with it myself, and might not work 100% of the time.
	//Should work though.

	//Bottom
	int lIntersected[64];
	float fIntersect[64][3];

	//Top
	int lIntersectedT[64];
	float fIntersectT[64][3];

	//Count amount of intersetcions
	int intersections = 0;

	//Count amount of intersection for BASE
	int lIntNum = 0;
	int lIntNumT = 0;

	//Get slope
	float lSlope = (ray[2] - point[2]) / (ray[1] - point[1]);
	float lEq = (lSlope & ray[0]) - ray[2];
	lEq = -lEq;

	//Get second slope
	//float lSlope2 = (ray[1] - point[1]) / (ray[0] - point[0]);
	//float lEq2 = (lSlope2 * point[0]) - point[1];
	//lEq2 = -lEq2;

	//Loop through every point of the zone
	int size = GetArraySize(g_hZonePointsData[zone]);

	for (int i = 0; i < size; i++)
	{
		//Get current & next point
		float currentpoint[3];
		GetArrayArray(g_hZonePointsData[zone], i, currentpoint, sizeof(currentpoint));

		float nextpoint[3];

		//Check if its the last point, if it is, join it with the first
		if (size == i + 1)
		{
			GetArrayArray(g_hZonePointsData[zone], 0, nextpoint, sizeof(nextpoint));
		}
		else
		{
			GetArrayArray(g_hZonePointsData[zone], i + 1, nextpoint, sizeof(nextpoint));
		}

		//Check if the ray intersects the point
		//Ignore the height parameter as we will check against that later
		bool didinter = get_line_intersection(ray[0], ray[1], point[0], point[1], currentpoint[0], currentpoint[1], nextpoint[0], nextpoint[1], xint, yint);

		//Get intersections of the bottom
		bool baseInter = get_line_intersection(ray[1], ray[2], point[1], point[2], currentpoint[1], currentpoint[2], nextpoint[1], nextpoint[2], baseY, baseZ);

		//Get intersections of the top
		bool baseInter2 = get_line_intersection(ray[1], ray[2], point[1], point[2], currentpoint[1] + g_fZonePointsHeight[zone], currentpoint[2] + g_fZonePointsHeight[zone], nextpoint[1] + g_fZonePointsHeight[zone], nextpoint[2] + g_fZonePointsHeight[zone], baseY2, baseZ2);

		//If base intersected, store the line for later
		if (baseInter && lIntNum < sizeof(fIntersect))
		{
			lIntersected[lIntNum] = i;
			fIntersect[lIntNum][1] = baseY;
			fIntersect[lIntNum][2] = baseZ;
			lIntNum++;
		}

		if (baseInter2 && lIntNumT < sizeof(fIntersectT))
		{
			lIntersectedT[lIntNumT] = i;
			fIntersectT[lIntNumT][1] = baseY2;
			fIntersectT[lIntNum][2] = baseZ2;
			lIntNumT++;
		}

		//If ray intersected line, check against height
		if (didinter)
		{
			//Get the height of intersection

			//Get slope of line it hit
			float m1 = (nextpoint[2] - currentpoint[2]) / (nextpoint[0] - currentpoint[0]);

			//Equation y = mx + c | mx - y = -c
			float l1 = (m1 * currentpoint[0]) - currentpoint[2];
			l1 = -l1;

			float y2 = (m1 * xint) + l1;

			//Get slope of ray
			float y = (lSlope * xint) + lEq;

			if (y > y2 && y < y2 + 128.0 + g_fZonePointsHeight[zone])
			{
				//The ray intersected the line and is within the height
				intersections++;
			}
		}
	}

	//Now we check for base hitting
	//This method is weird, but works most of the time
	for (int k = 0; k < lIntNum; k++)
	{
		for (int l = k + 1; l < lIntNum; l++)
		{
			if (l == k)
			{
				continue;
			}

			int i = lIntersected[k];
			int j = lIntersected[l];

			if (i == j)
			{
				continue;
			}

			float currentpoint[2][3];
			float nextpoint[2][3];

			if (GetArraySize(g_hZonePointsData[zone]) == i + 1)
			{
				GetArrayArray(g_hZonePointsData[zone], i, currentpoint[0], 3);
				GetArrayArray(g_hZonePointsData[zone], 0, nextpoint[0], 3);
			}
			else
			{
				GetArrayArray(g_hZonePointsData[zone], i, currentpoint[0], 3);
				GetArrayArray(g_hZonePointsData[zone], i + 1, nextpoint[0], 3);
			}

			if (GetArraySize(g_hZonePointsData[zone]) == j + 1)
			{
				GetArrayArray(g_hZonePointsData[zone], j, currentpoint[1], 3);
				GetArrayArray(g_hZonePointsData[zone], 0, nextpoint[1], 3);
			}
			else
			{
				GetArrayArray(g_hZonePointsData[zone], j, currentpoint[1], 3);
				GetArrayArray(g_hZonePointsData[zone], j + 1, nextpoint[1], 3);
			}

			//Get equation of both lines then find slope of them
			float m1 = (nextpoint[0][1] - currentpoint[0][1]) / (nextpoint[0][0] - currentpoint[0][0]);
			float m2 = (nextpoint[1][1] - currentpoint[1][1]) / (nextpoint[1][0] - currentpoint[1][0]);
			float lEq1 = (m1 * currentpoint[0][0]) - currentpoint[0][1];
			float lEq2 = (m2 * currentpoint[1][0]) - currentpoint[1][1];
			lEq1 = -lEq1;
			lEq2 = -lEq2;

			//Get x point of intersection
			float xPoint1 = ((fIntersect[k][1] - lEq1) / m1);
			float xPoint2 = ((fIntersect[l][1] - lEq2 / m2));

			if (xPoint1 > point[0] > xPoint2 || xPoint1 < point[0] < xPoint2)
			{
				intersections++;
			}
		}
	}

	for (int k = 0; k < lIntNumT; k++)
	{
		for (int l = k + 1; l < lIntNumT; l++)
		{
			if (l == k)
			{
				continue;
			}

			int i = lIntersectedT[k];
			int j = lIntersectedT[l];

			if (i == j)
			{
				continue;
			}

			float currentpoint[2][3];
			float nextpoint[2][3];

			if (GetArraySize(g_hZonePointsData[zone]) == i + 1)
			{
				GetArrayArray(g_hZonePointsData[zone], i, currentpoint[0], 3);
				GetArrayArray(g_hZonePointsData[zone], 0, nextpoint[0], 3);
			}
			else
			{
				GetArrayArray(g_hZonePointsData[zone], i, currentpoint[0], 3);
				GetArrayArray(g_hZonePointsData[zone], i + 1, nextpoint[0], 3);
			}

			if (GetArraySize(g_hZonePointsData[zone]) == j + 1)
			{
				GetArrayArray(g_hZonePointsData[zone], j, currentpoint[1], 3);
				GetArrayArray(g_hZonePointsData[zone], 0, nextpoint[1], 3);
			}
			else
			{
				GetArrayArray(g_hZonePointsData[zone], j, currentpoint[1], 3);
				GetArrayArray(g_hZonePointsData[zone], j + 1, nextpoint[1], 3);
			}

			//Get equation of both lines then find slope of them
			float m1 = (nextpoint[0][1] - currentpoint[0][1]) / (nextpoint[0][0] - currentpoint[0][0]);
			float m2 = (nextpoint[1][1] - currentpoint[1][1]) / (nextpoint[1][0] - currentpoint[1][0]);
			float lEq1 = (m1 * currentpoint[0][0]) - currentpoint[0][1];
			float lEq2 = (m2 * currentpoint[1][0]) - currentpoint[1][1];
			lEq1 = -lEq1;
			lEq2 = -lEq2;

			//Get x point of intersection
			float xPoint1 = ((fIntersectT[k][1] - lEq1) / m1);
			float xPoint2 = ((fIntersectT[l][1] - lEq2 / m2));

			if (xPoint1 > point[0] > xPoint2 || xPoint1 < point[0] < xPoint2)
			{
				intersections++;
			}
		}
	}

	if (intersections <= 0 || intersections % 2 == 0)
	{
		return false;
	}

	return true;
}

bool IsOriginInBox(float origin[3], int zone)
{
	if(origin[0] >= g_fZonePointsMin[zone][0] && origin[1] >= g_fZonePointsMin[zone][1] && origin[2] >= g_fZonePointsMin[zone][2] && origin[0] <= g_fZonePointsMax[zone][0] + g_fZonePointsHeight[zone] && origin[1] <= g_fZonePointsMax[zone][1] + g_fZonePointsHeight[zone] && origin[2] <= g_fZonePointsMax[zone][2] + g_fZonePointsHeight[zone])
	{
		return true;
	}

	return false;
}

bool get_line_intersection(float p0_x, float p0_y, float p1_x, float p1_y, float p2_x, float p2_y, float p3_x, float p3_y, float &i_x, float &i_y)
{
	float s1_x = p1_x - p0_x;
	float s1_y = p1_y - p0_y;
	float s2_x = p3_x - p2_x;
	float s2_y = p3_y - p2_y;

	float s = (-s1_y * (p0_x - p2_x) + s1_x * (p0_y - p2_y)) / (-s2_x * s1_y + s1_x * s2_y);
	float t = ( s2_x * (p0_y - p2_y) - s2_y * (p0_x - p2_x)) / (-s2_x * s1_y + s1_x * s2_y);

	if (s >= 0 && s <= 1 && t >= 0 && t <= 1)
	{
		// Collision detected
		i_x = p0_x + (t * s1_x);
		i_y = p0_y + (t * s1_y);

		return true;
	}

	return false; // No collision
}

float CalculateHorizontalDistance(float vec1[3], float vec2[3], bool squared = false)
{
	if (squared)
	{
		if (vec1[0] < 0.0)
		{
			vec1[0] *= -1;
		}

		if (vec1[1] < 0.0)
		{
			vec1[1] *= -1;
		}

		vec1[0] = SquareRoot(vec1[0]);
		vec1[1] = SquareRoot(vec1[1]);

		if (vec2[0] < 0.0)
		{
			vec2[0] *= -1;
		}

		if (vec2[1] < 0.0)
		{
			vec2[1] *= -1;
		}

		vec2[0] = SquareRoot(vec2[0]);
		vec2[1] = SquareRoot(vec2[1]);
	}

	return SquareRoot( Pow((vec1[0] - vec2[0]), 2.0) +  Pow((vec1[1] - vec2[1]), 2.0) );
}

//Natives
public int Native_Register_Effect(Handle plugin, int numParams)
{
	int size;
	GetNativeStringLength(1, size);

	char[] sEffect = new char[size + 1];
	GetNativeString(1, sEffect, size + 1);

	Function function1 = GetNativeFunction(2);
	Function function2 = GetNativeFunction(3);
	Function function3 = GetNativeFunction(4);

	RegisterNewEffect(plugin, sEffect, function1, function2, function3);
}

public int Native_Register_Effect_Key(Handle plugin, int numParams)
{
	int size;
	GetNativeStringLength(1, size);

	char[] sEffect = new char[size + 1];
	GetNativeString(1, sEffect, size + 1);

	size = 0;
	GetNativeStringLength(2, size);

	char[] sKey = new char[size + 1];
	GetNativeString(2, sKey, size + 1);

	size = 0;
	GetNativeStringLength(3, size);

	char[] sDefaultValue = new char[size + 1];
	GetNativeString(3, sDefaultValue, size + 1);

	RegisterNewEffectKey(sEffect, sKey, sDefaultValue);
}

public int Native_Request_QueueEffects(Handle plugin, int numParams)
{
	QueueEffects();
}

public int Native_IsClientInZone(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!IsPlayerIndex(client))
	{
		return false;
	}

	int size;
	GetNativeStringLength(2, size);

	char[] sName = new char[size + 1];
	GetNativeString(2, sName, size + 1);

	for (int i = 0; i < GetArraySize(g_hZoneEntities); i++)
	{
		int zone = EntRefToEntIndex(GetArrayCell(g_hZoneEntities, i));

		if (IsValidEntity(zone))
		{
			char sName2[64];
			GetEntPropString(zone, Prop_Send, "m_iName", sName2, sizeof(sName2));

			if (StrEqual(sName, sName2))
			{
				return g_bIsInZone[client][zone];
			}
		}
	}

	return false;
}

public int Native_TeleportClientToZone(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (!IsPlayerIndex(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	int size;
	GetNativeStringLength(2, size);

	char[] sName = new char[size + 1];
	GetNativeString(2, sName, size + 1);

	return TeleportToZone(client, sName);
}
