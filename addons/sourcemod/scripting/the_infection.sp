#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <sdktools> 
#include <tf2attributes>
#include <tf2items>
#include <steamtools>

new Float:flag_pos[3];
new Float:flag_pos2[3];
enum
{
	TF_FLAGTYPE_CTF = 0, //ctf_
	TF_FLAGTYPE_ATTACK_DEFEND, //mvm_
	TF_FLAGTYPE_TERRITORY_CONTROL,
	TF_FLAGTYPE_INVADE,
	TF_FLAGTYPE_SPECIAL_DELIVERY, //sd_
	TF_FLAGTYPE_ROBOT_DESTRUCTION, //rd_ and pd_
	TF_FLAGTYPE_PLAYER_DESTRUCTION //pd_
};
public Plugin:myinfo = 
{
	name = "[TF2] The Infection",
	author = "Seamusmario",
	description = "Yet Another Zombie Survival Gamemode for TF2",
	version = "a1.1",
	url = "https://forums.alliedmods.net/showthread.php?t=343236"
}

Handle g_hSdkEquipWearable;
static ConVar cvarZombieEnable;
static ConVar cvarZombieNoDoors;
static ConVar cvarZombieTimer;
static ConVar sv_cheats;
static ConVar cvarTimeScale;
Handle g_hEquipWearable;
Handle roundEndTimer = INVALID_HANDLE;
Handle countdownTimer = INVALID_HANDLE;
new g_iCountdown;
new g_iSurvRage						[MAXPLAYERS + 1];
new bool:g_bIsPlagued[MAXPLAYERS + 1] = { false, ... };


// most of this was taken from the forums. i don't really own most of the code.
// some of it i wrote from scratch
// credit to everybody

public OnPluginStart()
{
	sv_cheats = FindConVar("sv_cheats");
	cvarTimeScale = FindConVar("host_timescale");
	Handle hConf = LoadGameConfigFile("tf2items.randomizer");
	HookEvent("post_inventory_application", Event_InvApp, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam); 
    HookEvent("teamplay_setup_finished", SetupReady);
	HookEvent("teamplay_round_start", RoundStarted);
	HookEvent("teamplay_round_win", RoundStarted2);
	AddNormalSoundHook(InfectionSH);
	RegConsoleCmd("kill", Kill);
	RegConsoleCmd("explode", Explode);
	StartPrepSDKCall(SDKCall_Player);
	if (!PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CTFPlayer::EquipWearable"))PrintToServer("[PlayerModelRandomizer] Failed to set EquipWearable from conf!");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);

	g_hSdkEquipWearable = EndPrepSDKCall();
	cvarZombieEnable = CreateConVar("sm_infection_enable", "0", "If on, The Infection gamemode will be enabled", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarZombieEnable.AddChangeHook(OnZombieCvarChange);
	cvarZombieNoDoors = CreateConVar("sm_infection_no_doors", "0", "If on while the gamemode is enabled, doors will be removed on round start.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarZombieNoDoors.AddChangeHook(OnZombieCvarChange2);
	cvarZombieTimer = CreateConVar("sm_infection_time", "0.0", "If greater than zero, A time entity will be created, and if the timer is finished, humans will win. (minutes only, float value)", FCVAR_NONE); 
	cvarZombieTimer.AddChangeHook(OnZombieCvarChange3); 

	GameData hTF2 = new GameData("sm-tf2.games"); // sourcemod's tf2 gamedata

	if (!hTF2)
	SetFailState("This plugin is designed for a TF2 dedicated server only.");

	StartPrepSDKCall(SDKCall_Player); 
	PrepSDKCall_SetVirtual(hTF2.GetOffset("RemoveWearable") - 1);    // EquipWearable offset is always behind RemoveWearable, subtract its value by 1
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hEquipWearable = EndPrepSDKCall();

	if (!g_hEquipWearable)
	SetFailState("Failed to create call: CBasePlayer::EquipWearable");
	AddCommandListener(TauntCmd, "taunt");
	AddCommandListener(TauntCmd, "+taunt");
	CreateTimer(2.0, Timer_RageMeter, _, TIMER_REPEAT);
}
public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		if (g_bIsPlagued[attacker] && attacker != victim) {
			TF2_AddCondition(victim,TFCond_Plague,TFCondDuration_Infinite);
			TF2_MakeBleed(victim,victim,90.0);
			TF2_MakeBleed(victim,victim,90.0);
			TF2_MakeBleed(victim,victim,90.0);
			TF2_MakeBleed(victim,victim,90.0);
		}
	}

}

public OnMapStart()
{
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
	    CreateTimer(0.1, MoveFlagTimer,_,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    }
	PrecacheSound(")items/powerup_pickup_plague_infected_loop.wav");
}

stock TF2_GetNameOfClass(TFClassType:iClass, String:sName[], iMaxlen)
{
	switch (iClass)
	{
		case TFClass_Scout: Format(sName, iMaxlen, "scout");
		case TFClass_Soldier: Format(sName, iMaxlen, "soldier");
		case TFClass_Pyro: Format(sName, iMaxlen, "pyro");
		case TFClass_DemoMan: Format(sName, iMaxlen, "demo");
		case TFClass_Heavy: Format(sName, iMaxlen, "heavy");
		case TFClass_Engineer: Format(sName, iMaxlen, "engineer");
		case TFClass_Medic: Format(sName, iMaxlen, "medic");
		case TFClass_Sniper: Format(sName, iMaxlen, "sniper");
		case TFClass_Spy: Format(sName, iMaxlen, "spy");
	}
}

public Action:RoundStarted2(Handle: event , const String: name[] , bool: dontBroadcast)
{
	if(GetConVarInt(cvarZombieEnable) == 1) {
 
		//ServerCommand("mp_scrambleteams 15");
		decl String:nameflag[] = "zombbotflag";
		decl String:class[] = "item_teamflag";
		new ent = FindEntityByTargetname(nameflag, class);
		if(ent != -1)
		{
			AcceptEntityInput(ent, "Kill");
		}
		decl String:nameflag2[] = "infectedbotflag";
		decl String:class2[] = "item_teamflag";
		new ent2 = FindEntityByTargetname(nameflag, class);
		if(ent2 != -1)
		{
			AcceptEntityInput(ent, "Kill");
		}

	}
}


public Action:TauntCmd(client, const String:strCommand[], iArgc)
{
	if(GetConVarInt(cvarZombieEnable) != 1)
		return Plugin_Continue;

	if(!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TFTeam_Blue || g_iSurvRage[client] < 100)
		return Plugin_Continue;

	decl Float:fOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fOrigin);
	fOrigin[2] += 20.0;

	TF2_AddCondition(client, TFCond:42, 4.0);
	CreateTimer(0.6, Timer_UseRage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	g_iSurvRage[client] = 0;
	return Plugin_Continue;
}


public Action:Timer_RageMeter(Handle:hTimer)
{
	if(GetConVarInt(cvarZombieEnable) != 1)
		return Plugin_Continue;

	for(new i = 1; i <= MaxClients; i++) if(IsValidClient(i))
	{
		if(GetClientTeam(i) == TFTeam_Blue)
		{
			SetGlobalTransTarget(i);
			if(g_iSurvRage[i] + 1 <= 100 - 1)
			{
				g_iSurvRage[i] += 2;
				PrintHintText(i, "Rage: %i", g_iSurvRage[i]);
			}
			else
			{
				g_iSurvRage[i] = 100;
				PrintHintText(i, "Taunt to Rage!");
			}
		} else {
            g_iSurvRage[i] = 0;
        }
	}
	return Plugin_Continue;
}


public Action:Timer_UseRage(Handle:hTimer, any:clientId)
{
	new client = GetClientOfUserId(clientId);
	if(!IsValidClient(client))
		return Plugin_Continue;

	decl Float:fOrigin1[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fOrigin1);

	decl Float:fOrigin2[3];
	for(new i = 1; i <= MaxClients; i++) if(IsValidClient(i))
	{
		if(GetClientTeam(i) != GetClientTeam(client) && IsPlayerAlive(i) && i != client)
		{
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", fOrigin2);
			if(!TF2_IsPlayerInCondition(i, TFCond_Ubercharged) && GetVectorDistance(fOrigin1, fOrigin2) < 800.0 && TF2_GetPlayerClass(client) == TFClass_Heavy)
			{
				new iFlags = TF_STUNFLAGS_GHOSTSCARE;
				TF2_StunPlayer(i, 5.0, _, iFlags, client);
                PrecacheSound("misc/halloween/hwn_bomb_flash.wav");
                EmitSoundToClient(i, "misc/halloween/hwn_bomb_flash.wav");
            } 
            else if(!TF2_IsPlayerInCondition(i, TFCond_Ubercharged) && GetVectorDistance(fOrigin1, fOrigin2) < 800.0 && TF2_GetPlayerClass(client) == TFClass_Medic)
			{
			    int zombieCount = GetTeamClientCount(2);
				if (GetClientTeam(i) == TFTeam_Red && GetRandomInt(1,2) == 1 && zombieCount > 8) {

                    SetEntProp(i, Prop_Send, "m_lifeState", 2);
                    ChangeClientTeam(i, 3);
                    SetEntProp(i, Prop_Send, "m_lifeState", 0); 
	                TeleportEntity(i, fOrigin2, NULL_VECTOR, NULL_VECTOR);
                    TF2_RegeneratePlayer(i);
	                TF2_AddCondition(i, TFCond:5, 10.0); 
	                TF2_AddCondition(i, TFCond:28, 30.0);
                    EmitGameSoundToAll("Halloween.spell_overheal",i);
                } else if (GetClientTeam(i) == TFTeam_Red && GetRandomInt(1,2) == 1 && zombieCount < 8) {

				    new iFlags = TF_STUNFLAGS_GHOSTSCARE;
				    TF2_StunPlayer(i, 5.0, _, iFlags, client);
                    PrecacheSound("misc/halloween/hwn_bomb_flash.wav");
                    EmitSoundToClient(i, "misc/halloween/hwn_bomb_flash.wav");

                }
            }
            else if(!TF2_IsPlayerInCondition(i, TFCond_Ubercharged) && GetVectorDistance(fOrigin1, fOrigin2) < 800.0 && TF2_GetPlayerClass(client) == TFClass_Soldier)
			{
				new iFlags = TF_STUNFLAGS_GHOSTSCARE;
				TF2_StunPlayer(i, 5.0, _, iFlags, client);
                PrecacheSound("misc/halloween/hwn_bomb_flash.wav");
                EmitSoundToClient(i, "misc/halloween/hwn_bomb_flash.wav");
			} else if (!TF2_IsPlayerInCondition(i, TFCond_Ubercharged) && GetVectorDistance(fOrigin1, fOrigin2) < 800.0) {
				EmitGameSoundToAll("Halloween.Merasmus_Stun");
                TF2_StunPlayer(i, 5.0, 0, TF_STUNFLAG_GHOSTEFFECT|TF_STUNFLAG_BONKSTUCK, i);
            }
		}
	}
}

public OnClientPutInServer(client)
{
	g_iSurvRage[client] = 0;
	OnClientDisconnect_Post(client);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		if (!IsFakeClient(client)) {
			ChangeClientTeam( client, 2 );
			ShowVGUIPanel( client, "class_red" );
		}
	}
}
public void OnZombieCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	ServerCommand("mp_restartgame_immediate 1");
    if (!GetConVarBool(convar)) {

	    Steam_SetGameDescription("Team Fortress");

    } else {

	    Steam_SetGameDescription("The Infection");

    }
}	

public Action Timer_Doors(Handle timer)
{
	int doors=-1;
	while((doors=FindEntityByClassname(doors, "func_door"))!=-1)
    {
        AcceptEntityInput(doors, "Open");
    }
	
	KillTimerSafe(timer);
}

public void KillTimerSafe(Handle &hTimer)
{
	if(hTimer != INVALID_HANDLE)
	{
		KillTimer(hTimer);
		hTimer = INVALID_HANDLE;
	}
}
public void OnZombieCvarChange2(ConVar convar, char[] oldValue, char[] newValue)
{
	if (GetConVarInt(cvarZombieNoDoors) == 1)
	{
		CreateTimer(0.1, Timer_Doors, TIMER_REPEAT);
	} else {
		ServerCommand("mp_restartgame_immediate 1");
	}
}

public void OnZombieCvarChange3(ConVar convar, char[] oldValue, char[] newValue)
{
	ServerCommand("mp_restartgame_immediate 1");
}

public void Event_InvApp(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
    CreateTimer(0.25, Timer_SetZombieReady, client, TIMER_FLAG_NO_MAPCHANGE); 
}

bool GiveVoodooItem(int client, int itemindex)
{
	int soul = CreateEntityByName("tf_wearable");
	
	if (!IsValidEntity(soul))
	{
		return false;
	}
	
	char entclass[64];
	GetEntityNetClass(soul, entclass, sizeof(entclass));
	SetEntData(soul, FindSendPropInfo(entclass, "m_iItemDefinitionIndex"), itemindex);
	SetEntData(soul, FindSendPropInfo(entclass, "m_bInitialized"), 1); 	
	SetEntData(soul, FindSendPropInfo(entclass, "m_iEntityLevel"), 6);
	SetEntData(soul, FindSendPropInfo(entclass, "m_iEntityQuality"), 13);
	SetEntProp(soul, Prop_Send, "m_bValidatedAttachedEntity", 1);		
	
	DispatchSpawn(soul);
	SDKCall(g_hEquipWearable, client, soul);
	return true;
} 

public Action OnClientCommand(int client, int args)
{
    char cmd[16];
    GetCmdArg(0, cmd, sizeof(cmd));
 
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		if (IsPlayerAlive(client) && (StrEqual(cmd, "jointeam") || StrEqual(cmd, "spectate")))
		{
			return Plugin_Handled;
		}
	}
 
    return Plugin_Continue;
}

stock int GetRandomPlayer(int team) 
{ 
    int[] clients = new int[MaxClients]; 
    int clientCount; 
    for (int i = 1; i <= MaxClients; i++) 
    { 
        if (IsClientInGame(i) && GetClientTeam(i) == team)
        { 
            clients[clientCount++] = i; 
        } 
    } 
    return (clientCount == 0) ? -1 : clients[GetRandomInt(0, clientCount - 1)]; 
}

stock void ForceTeamWin(int team)
{
    int ent = FindEntityByClassname(-1, "team_control_point_master");
    if (ent == -1)
    {
        ent = CreateEntityByName("team_control_point_master");
        DispatchSpawn(ent);
        AcceptEntityInput(ent, "Enable");
    }
    
    SetVariantInt(team);
    AcceptEntityInput(ent, "SetWinner");
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (GetConVarInt(cvarZombieEnable) == 1 && IsValidClient(attacker) && attacker != client)
	{
		if (GetClientTeam(client) == TFTeam_Blue) {
			int survCount = GetTeamClientCount(3);
			int zombieCount = GetTeamClientCount(2);
			if (survCount == 1)
			{
				ForceTeamWin(2);
				if(countdownTimer != INVALID_HANDLE)
				{
					KillTimer(countdownTimer);
					countdownTimer = INVALID_HANDLE;
				}
				if(roundEndTimer != INVALID_HANDLE)
				{
					KillTimer(roundEndTimer);
					roundEndTimer = INVALID_HANDLE;
				}
				PrecacheSound("*#music/stingers/hl1_stinger_song8.mp3")
				EmitSoundToAll("*#music/stingers/hl1_stinger_song8.mp3")
				
				for(int i=1; i<=MaxClients; i++)
				{
					if(IsClientInGame(i))
					{
						StopSound(i, SNDCHAN_STATIC, "*#music/hl1_song10.mp3");
					}
				}
			} else {
				 
				EmitGameSoundToAll("Halloween.spell_skeleton_horde_cast",client)
				CreateTimer(0.1, TeleportToOGLocation, client);
				if (survCount == 2)
				{
						
					for(int i=1; i<=MaxClients; i++)
					{
						if(IsClientInGame(i) && !IsFakeClient(i))
						{
							SendConVarValue(i, sv_cheats, "1"); 
						}
							if (IsClientInGame(i) && GetClientTeam(i) == TFTeam_Blue) {
								TF2_AddCondition(i,TFCond_CritHype,TFCondDuration_Infinite);
								TF2_AddCondition(i,TFCond_CritCola,TFCondDuration_Infinite);
								TF2_AddCondition(i,TFCond_DefenseBuffMmmph,TFCondDuration_Infinite); 
								TF2_AddCondition(i,TFCond_SpeedBuffAlly,TFCondDuration_Infinite);
								TF2_AddCondition(i,TFCond_SmallBulletResist,TFCondDuration_Infinite);
								
								TF2Attrib_SetByName(i, "damage bonus", 2.5);
							} 
					}
					for(int i=1; i<=MaxClients; i++)
					{
						if(IsClientInGame(i) && GetClientTeam(i) == TFTeam_Red) 
						{
							TF2_StunPlayer(i, 10.0, 0, TF_STUNFLAG_GHOSTEFFECT|TF_STUNFLAG_BONKSTUCK, i)
						}
					}
					EmitGameSoundToAll("Halloween.Merasmus_Stun")
					cvarTimeScale.SetFloat(0.1);
					CreateTimer(0.5, SetTimeBack);
					CreateTimer(0.5, PlaySong, client);
					
					PrecacheSound("*#music/stingers/hl1_stinger_song28.mp3")
					EmitSoundToAll("*#music/stingers/hl1_stinger_song28.mp3")

				}
			}
		}
	}
}

public Action SetTimeBack(Handle timer)
{
	for(int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			SendConVarValue(i, sv_cheats, "0");
		}
	}
	cvarTimeScale.SetFloat(1.0);
	return Plugin_Handled;
}

public Action PlaySong(Handle timer, int client)
{
	PrecacheSound("*#music/hl2_song3.mp3")
	PrecacheSound("*#music/hl2_song15.mp3")
	
	decl String:username[35];
	GetClientName(client,username,sizeof(username))

	for(int i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{ 
			PrintToChat(i, "%s is now the last remaining survivor!",username);	 
		}
		if(IsClientInGame(i) && GetClientTeam(i) == TFTeam_Blue)
		{
				switch(GetRandomInt(1,3)) {
					case 1: {
						EmitSoundToClient(i, "*#music/hl2_song3.mp3");
					}
					case 2: { 
						EmitSoundToClient(i, "*#music/hl2_song15.mp3");
					}
				}
		}
	}
	return Plugin_Handled;
}
public Action TeleportToOGLocation(Handle timer, int client)
{
    ChangeClientTeam(client, 2); 
	decl Float:origin[3];
	decl Float:angles[3];
	GetClientAbsOrigin(client, origin);	
	GetClientEyeAngles(client, angles);	
	TF2_RespawnPlayer(client); 
	TF2_RegeneratePlayer(client);
	TeleportEntity(client, origin, angles, NULL_VECTOR);
    decl String:username[35];
	GetClientName(client,username,sizeof(username))
	PrintToChat(client, "You got infected!");	
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == _:TFTeam_Blue && !IsFakeClient(i) && i != client)
		{ 
			PrintToChat(i, "%s got infected!",username);	 
		}
	}
	//EmitGameSoundToAll("Halloween.SFX",client)
	EmitGameSoundToAll("Halloween.spell_skeleton_horde_rise",client)
}

public Action:Kill(client, args) {
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		return Plugin_Handled;
	}
}

public Action:Explode(client, args) {
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		return Plugin_Handled;
	}
}
public OnClientDisconnect_Post(client)
{
	g_bIsPlagued[client] = false;
}
public Action RoundEnd(Handle timer, int client)
{
	ForceTeamWin(3);
}
public Action Countdown(Handle timer, int client)
{
	if (g_iCountdown <= 0)
		return Plugin_Stop;
	PrintCenterTextAll("%d ",g_iCountdown)
	g_iCountdown--;
	return Plugin_Continue;
}
public Action Timer_SetZombieReady(Handle timer, int client)
{
	if (GetConVarInt(cvarZombieEnable) == 1){
		if (GetClientTeam(client) == TFTeam_Red) { 

	    	TF2Attrib_RemoveAll(client);   
			TF2_RemoveWeaponSlot(client, 0);
			TF2_RemoveWeaponSlot(client, 1);
			TF2_RemoveWeaponSlot(client, 3);
			TF2_RemoveWeaponSlot(client, 4);
			TF2_RemoveWeaponSlot(client, 5);
			TF2_RemoveWeaponSlot(client, 6);
			TF2_RemoveWeaponSlot(client, 7);
			TF2_RemoveWeaponSlot(client, 8);
			TF2_RemoveWeaponSlot(client, 9);
			InitializeZombieClass(client);
			TF2_SwitchtoSlot(client, 2);
	    	TF2Attrib_SetByName(client, "move speed penalty", 0.8);
	    	TF2Attrib_SetByName(client, "dmg taken from blast reduced", 1.5);
	    	TF2Attrib_SetByName(client, "dmg taken from fire reduced", 1.35);
	    	TF2Attrib_SetByName(client, "dmg taken from bullets reduced", 1.02); 
	    	TF2Attrib_SetByName(client, "building cost reduction", 50.0);
	    	TF2Attrib_SetByName(client, "healing received penalty", 0.4);
	    	TF2Attrib_SetByName(client, "damage penalty", 1.5);
	    	TF2Attrib_SetByName(client, "zombiezombiezombiezombie", 1.0);
	    	TF2Attrib_SetByName(client, "SPELL: Halloween voice modulation", 0.0);
	    	TF2Attrib_SetByName(client, "heal on kill", 100.0); 
			TF2Attrib_SetByName(client, "deploy time decreased", 0.7);
			TF2Attrib_SetByName(client, "melee range multiplier", 0.7);
			TF2Attrib_SetByName(client, "melee bounds multiplier", 1.3);
			if (TF2_GetPlayerClass(client) == TFClass_Pyro) {
				TF2Attrib_SetByName(client, "melee range multiplier", 2.5); 
				TF2Attrib_SetByName(client, "Set DamageType Ignite", 1.0);
	    		TF2Attrib_SetByName(client, "dmg taken from blast increased", 0.7);
	    		TF2Attrib_SetByName(client, "dmg taken from fire increased", -1.2);
	    		TF2Attrib_SetByName(client, "dmg taken from bullets increased", 0.8);
	    		TF2Attrib_SetByName(client, "move speed penalty", 1.05);
			}
	    	TF2Attrib_SetByName(client, "damage bonus vs burning", 1.5);
	    	TF2Attrib_SetByName(client, "gesture speed increase", 0.8);
	    	TF2Attrib_SetByName(client, "fire rate penalty", 1.2);
			switch(TF2_GetPlayerClass(client))
			{
				case TFClass_Scout: GiveVoodooItem(client, 5617);
				case TFClass_Soldier: GiveVoodooItem(client, 5618);
				case TFClass_Pyro: GiveVoodooItem(client, 5624);
				case TFClass_DemoMan: GiveVoodooItem(client, 5620);
				case TFClass_Heavy: GiveVoodooItem(client, 5619);
				case TFClass_Engineer: GiveVoodooItem(client, 5621);
				case TFClass_Medic: GiveVoodooItem(client, 5622);
				case TFClass_Sniper: GiveVoodooItem(client, 5625);
				case TFClass_Spy: GiveVoodooItem(client, 5623); 
			}

			if (GetRandomInt(1,40) == 1) {

        		decl String:username[35];
				GetClientName(client,username,sizeof(username))
				for (new i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i) && GetClientTeam(i) == _:TFTeam_Blue && !IsFakeClient(i))
					{
						PrintToChat(i, "DANGER: %s has a stronger variant of the Zombification Virus!",username);	
					}
					else if (IsClientInGame(i) && GetClientTeam(i) == _:TFTeam_Red && !IsFakeClient(i))
					{
						PrintToChat(i, "%s became stronger!",username);	
					}
				}
				EmitGameSoundToAll("Powerup.PickUpPlague")
	    		TF2Attrib_SetByName(client, "max health additive bonus", 500.0);
	    		TF2Attrib_SetByName(client, "dmg taken from blast reduced", 1.2); 
	    		TF2Attrib_SetByName(client, "dmg taken increased", 0.3); 
				SetVariantString("1.5");
				AcceptEntityInput(client, "SetModelScale");
				g_bIsPlagued[client] = true;
				TF2_SetHealth(client, 350 + 500);

			} else {

				g_bIsPlagued[client] = false;

			}
			if (GetRandomInt(1,90) == 1) {

				PrecacheSound("ambient/alarms/klaxon1.wav")
        		decl String:username[35];
				GetClientName(client,username,sizeof(username))
				for (new i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i) && GetClientTeam(i) == _:TFTeam_Blue && !IsFakeClient(i))
					{
						PrintToChat(i, "ALERT: %s became a giant!",username);	
						EmitSoundToClient(i,"ambient/alarms/klaxon1.wav")
					}
				}
					PrintToChat(client, "You've just become a Giant!");	
					PrintToChat(client, "Giants are a very large and dangerous type of Zombie. Consider them as a boss. When spawned as a giant, you might have really low health. You should hide before attacking enemies first if that ever happens.");
        		decl String:classname[35];
				decl String:Mdl[PLATFORM_MAX_PATH];
				TF2_GetNameOfClass(TF2_GetPlayerClass(client), classname, sizeof(classname));
				
				Format(Mdl, sizeof(Mdl), "models/bots/%s_boss/bot_%s_boss.mdl", classname, classname);
				if(TF2_GetPlayerClass(client) == TFClass_Medic || TF2_GetPlayerClass(client) == TFClass_Sniper || TF2_GetPlayerClass(client) == TFClass_Engineer || TF2_GetPlayerClass(client) == TFClass_Spy)
					Format(Mdl, sizeof(Mdl), "models/bots/%s/bot_%s.mdl", classname, classname);
					
				ReplaceString(Mdl, sizeof(Mdl), "demoman", "demo", false);
				SetVariantString(Mdl);
				AcceptEntityInput(client, "SetCustomModel");
				SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
				SetVariantString("1.8");
				AcceptEntityInput(client, "SetModelScale");
	    		TF2Attrib_SetByName(client, "move speed bonus", 0.5);
	    		TF2Attrib_SetByName(client, "override footstep sound set", 2.0);
	    		TF2Attrib_SetByName(client, "damage penalty", 2.0);
	    		TF2Attrib_SetByName(client, "bleeding duration", 5.0);
	    		TF2Attrib_SetByName(client, "max health additive bonus", 14000.0);
	    		TF2Attrib_SetByName(client, "health regen", 500.0); 
	    		TF2Attrib_SetByName(client, "dmg taken increased", 3.0); 
				TF2Attrib_SetByName(client, "melee range multiplier", 2.0);
				TF2Attrib_SetByName(client, "melee bounds multiplier", 1.5);
				TF2Attrib_SetByName(client, "heal on kill", 500.0);
				TF2Attrib_SetByName(client, "no self blast dmg", 1.0); 
	    	TF2Attrib_SetByName(client, "fire rate penalty", 1.0);
				TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.01);
				TF2_SetHealth(client, 350 + 14000);

			} else {
				
				SetVariantString("");
				AcceptEntityInput(client, "SetCustomModel");

			}

			CreateTimer(0.1, Timer_Makezombie2, client, TIMER_FLAG_NO_MAPCHANGE);
		} else {
			
	    	TF2Attrib_RemoveAll(client);   
			TF2Attrib_SetByName(client, "deploy time decreased", 1.3);
			TF2Attrib_SetByName(client, "dmg taken increased", 0.75);
	    	TF2Attrib_SetByName(client, "dmg taken from fire reduced", 0.8);
	    	TF2Attrib_SetByName(client, "damage bonus", 1.8); 
	    	TF2Attrib_SetByName(client, "health regen", 20.0); 
	    	TF2Attrib_SetByName(client, "heal on kill", 5.0); 
	    	TF2Attrib_SetByName(client, "heal on hit for rapidfire", 2.0); 
	    	TF2Attrib_SetByName(client, "mad milk syringes", 4.0); 
	    	TF2Attrib_SetByName(client, "applies snare effect", 0.65); 
	    	TF2Attrib_SetByName(client, "dmg taken from crit reduced", 1.3);
	    	TF2Attrib_SetByName(client, "applies snare effect", 0.65); 
	    	TF2Attrib_SetByName(client, "dmg taken from blast reduced", 10.0);
	    	TF2Attrib_SetByName(client, "projectile penetration", 1.0);
	    	TF2Attrib_SetByName(client, "increased air control", 0.1);
	    	TF2Attrib_SetByName(client, "self dmg push force decreased", 0.2);
			TF2Attrib_SetByName(client, "faster reload rate", 0.9);
			if (TF2_GetPlayerClass(client) == TFClass_Engineer) {

				TF2Attrib_SetByName(client, "mod wrench builds minisentry", 1.0);

			}

			SetVariantString("");
			AcceptEntityInput(client, "SetCustomModel");
			
			g_bIsPlagued[client] = false;
			CreateTimer(0.1, Timer_UnZombie, client, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

stock TF2_SetHealth(client, NewHealth)
{
	SetEntProp(client, Prop_Send, "m_iHealth", NewHealth, 1);
	SetEntProp(client, Prop_Data, "m_iHealth", NewHealth, 1);
}

stock InitializeZombieClass(client)
{
	new Handle:hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	if (hWeapon != INVALID_HANDLE)
	{
		new i = client;
		if (TF2_GetPlayerClass(client) == TFClass_Scout) {

			switch(GetRandomInt(0,5)) {
				case 3: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_bat_fish");
					TF2Items_SetItemIndex(hWeapon, 572);
					PrintToChat(i, "You are now the Fast Zombie.");	
					PrintToChat(i, "Fast Zombies are Scouts with extremely high speed. They can cause bleeding to enemies, and mark them for death.");	
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "218 ; 1.0 ; 149 ; 5.0 ; 107 ; 3.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 4: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_bat");
					TF2Items_SetItemIndex(hWeapon, 325);
					PrintToChat(i, "You are now the Mini Clubber.");	
					PrintToChat(i, "Mini Clubbers are Scouts that are similar to Clubbers. They can stun enemies.");	
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "182 ; 15.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
			} 
			if (!IsFakeClient(client)) {  

				new Handle:hMilk = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
					TF2Items_SetClassname(hMilk, "tf_weapon_jar_milk");
					TF2Items_SetItemIndex(hMilk, 222);
					PrintToChat(i, "Your class has the ability to stun enemies with your Mad Milk.");	
					TF2Items_SetLevel(hMilk, 100);
					TF2Items_SetQuality(hMilk, 5); 
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "313 ; 0.65 ; 218 ; 1.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hMilk, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hMilk, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hMilk, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hMilk);
					EquipPlayerWeapon(client, weapon); 

					CloseHandle(hMilk);
					
			}

		} else if (TF2_GetPlayerClass(client) == TFClass_Heavy) {

			switch(GetRandomInt(0,5)) {
				case 3: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_fists");
					TF2Items_SetItemIndex(hWeapon, 43);
					PrintToChat(i, "You are now the Killer Boxer.");	
					PrintToChat(i, "Killer Boxers are, killers. They can receive minicrit boosts upon killing an enemy. They deal massive amount of damage, can take damage to the Enemy Medic's patient, and causes knockback.");	
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "2 ; 2.0 ; 613 ; 8.0 ; 2030 ; 1.0 ; 360 ; 1.0 ; 522 ; 1.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 4: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_fists");
					PrintToChat(i, "You are now the Sharpened Heavy.");	
					PrintToChat(i, "Sharpened Heavies are really fast, and can cause bleeding to other enemies. Enemies deal small amount of damage from this class.");	
					TF2Items_SetItemIndex(hWeapon, 426);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "6 ; 0.6 ; 107 ; 1.5 ; 1 ; 0.5 ; 149 ; 5.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 5: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Tumor.");	
					PrintToChat(i, "Tumors have a Bread Bite mimic that can backstab. No melee swinging animation is shown. When backstabbing enemies, it is possible to disguise as them.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_knife");
					TF2Items_SetItemIndex(hWeapon, 1100);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "2 ; 1.2 ; 2030 ; 1.0 ; 154 ; 1.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
			}

		} else if (TF2_GetPlayerClass(client) == TFClass_Pyro) {

			switch(GetRandomInt(0,5)) {
				case 3: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_fireaxe");
					TF2Items_SetItemIndex(hWeapon, 38);
					PrintToChat(i, "You are now the Igniter.");	
					PrintToChat(i, "Igniters can deal massive damage to enemies who are under an inferno. They have really fast spped, and is a very dangerous class to mess with.");	
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "208 ; 1.0 ; 795 ; 3.0 ; 107 ; 1.3");
					new String:weaponAttribsArray[32][32]; 
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 4: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_fireaxe");
					TF2Items_SetItemIndex(hWeapon, 834);
					PrintToChat(i, "You are now the Stunner.");	
					PrintToChat(i, "Stunners are Pyros that have an electric sign. Their weapon can stun enemies and deal critical damage to stunned teammates.");	
					TF2Items_SetLevel(hWeapon, 813);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "2 ; 1.1 ; 436 ; 1.0 ; 437 ; 1.0 ; 182 ; 2.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 5: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Third Degree.");	
					PrintToChat(i, "Third Degrees are Pyros. They can cause severe damage to Enemy Medics.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_fireaxe");
					TF2Items_SetItemIndex(hWeapon, 593);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "350 ; 1.0 ; 2 ; 1.1 ; 360 ; 1.0 ; 478 ; 3");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
			}

		} else if (TF2_GetPlayerClass(client) == TFClass_Soldier) {

			switch(GetRandomInt(0,5)) {
				case 3: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_shovel");
					TF2Items_SetItemIndex(hWeapon, 416);
					PrintToChat(i, "You are now the Market Gardener.");	
					PrintToChat(i, "Market Gardeners can stun enemies for 10 seconds. Stunners must go after the stunned enemy to kill them faster.`");	
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "182 ; 10.0`");
					new String:weaponAttribsArray[32][32]; 
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 4: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_shovel");
					TF2Items_SetItemIndex(hWeapon, 128);
					PrintToChat(i, "You are now the Equalizer.");	
					PrintToChat(i, "Equalizers are a extremely dangerous class. Damage will increase depending on the health. ");	
					TF2Items_SetLevel(hWeapon, 128);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "115 ; 1.0 ; 107 ; 1.2");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 5: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Pain Train.");	
					PrintToChat(i, "Pain Trains are extremely fast. They can have an increase in speed depending on the health.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_shovel");
					TF2Items_SetItemIndex(hWeapon, 154);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "107 ; 2.0 ; 235 ; 2.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
			}

		} else if (TF2_GetPlayerClass(client) == TFClass_DemoMan) {

			switch(GetRandomInt(0,9)) {
				case 2: {
					PrintToChat(i, "You are now the knight.");	
					PrintToChat(i, "Knights have a battleaxe that has a faster attack rate than most swords.");	
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_sword");
					TF2Items_SetItemIndex(hWeapon, 172);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "2 ; 1.1 ; 6 ; 0.8");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 3: {
					
					PrintToChat(i, "You are now the specialized knight.");	
					PrintToChat(i, "Specialized Knights are the Type 2 variant of regular knights. Their battleaxes deal more damage than the regular one.");	
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					TF2Items_SetClassname(hWeapon, "tf_weapon_sword");
					TF2Items_SetItemIndex(hWeapon, 172);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "2 ; 1.5 ; 6 ; 0.8");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 4: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the clubber.");	
					PrintToChat(i, "Clubbers have a spiked club that is capable of bleeding and decapitating.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_sword");
					TF2Items_SetItemIndex(hWeapon, 325);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "149 ; 5.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 5: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Drunken Wretch.");	
					PrintToChat(i, "Drunken Wretches are capable of bleeding enemies with a melee hit. Thus being a hazardous enemy to deal with.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_bottle");
					TF2Items_SetItemIndex(hWeapon, 609);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "149 ; 15.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 6: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Boomer.");	
					PrintToChat(i, "Boomers are demomen with a enhanced Ullapool Caber. They are capable of instant killing and suiciding.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_stickbomb");
					TF2Items_SetItemIndex(hWeapon, 307);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "107 ; 2.0 ; 2 ; 2.0 ; 330 ; 7.0 ; 207 ; 5.0 ; 412 ; 0.2 ; 26 ; -120.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
			}

		} else if (TF2_GetPlayerClass(client) == TFClass_Medic) {

			switch(GetRandomInt(0,4)) {
				case 2: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Cannibal.");	
					PrintToChat(i, "Cannibals are Battle Medics who desperately want to eat non-infected people. Their weapon is capable of bleeding, and has a 8% damage bonus.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_bonesaw");
					TF2Items_SetItemIndex(hWeapon, 37);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "2 ; 1.08 ; 149 ; 10.0 ; 107 ; 0.8 ; 811 ; 1.0 ; 551 ; 1.0");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
				case 3: {
					
					TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
					PrintToChat(i, "You are now the Healer.");	
					PrintToChat(i, "Healers are Battle Medics who help other infected. They can taunt to heal other teammates around them.");	
					TF2Items_SetClassname(hWeapon, "tf_weapon_bonesaw");
					TF2Items_SetItemIndex(hWeapon, 304);
					TF2Items_SetLevel(hWeapon, 100);
					TF2Items_SetQuality(hWeapon, 5);
					new String:weaponAttribs[256];
					//This is so, so bad and I am so very, very sorry, but TF2Attributes will be better.
					Format(weaponAttribs, sizeof(weaponAttribs), "200 ; 1.0 ; 149 ; 2.0 ; 201 ; 1.5 ; 6 ; 0.6");
					new String:weaponAttribsArray[32][32];
					new attribCount = ExplodeString(weaponAttribs, " ; ", weaponAttribsArray, 32, 32);
					if (attribCount > 0) {
						TF2Items_SetNumAttributes(hWeapon, attribCount/2);
						new i2 = 0;
						for (new i = 0; i < attribCount; i+=2) {
							TF2Items_SetAttribute(hWeapon, i2, StringToInt(weaponAttribsArray[i]), StringToFloat(weaponAttribsArray[i+1]));
							i2++;
						}
					} else {
						TF2Items_SetNumAttributes(hWeapon, 0);
					}
					new weapon = TF2Items_GiveNamedItem(client, hWeapon);
					EquipPlayerWeapon(client, weapon);

					CloseHandle(hWeapon);
					
				}
			}

		}
	}	
}

public Action Timer_UnZombie(Handle timer, int client)	
{

	SetEntProp(client, Prop_Send, "m_bForcedSkin", 0);
	SetEntProp(client, Prop_Send, "m_nForcedSkin", 0);

}
public Action Timer_Makezombie2(Handle timer, int client)	
{
	if (IsValidClient(client) && IsPlayerAlive(client) && GetClientTeam(client)==2 && TF2_GetPlayerClass(client) !=TFClass_Spy)
	{
		//TF2Attrib_SetByName(client, "player skin override", 1.0);
		TF2Attrib_SetByName(client, "zombiezombiezombiezombie", 1.0);
		SetEntProp(client, Prop_Send, "m_bForcedSkin", 1);
		SetEntProp(client, Prop_Send, "m_nForcedSkin", 4);
	} 
	if (IsValidClient(client) && IsPlayerAlive(client) && GetClientTeam(client)==3 && TF2_GetPlayerClass(client) !=TFClass_Spy)
	{
		//TF2Attrib_SetByName(client, "player skin override", 1.0);
		TF2Attrib_SetByName(client, "zombiezombiezombiezombie", 1.0);
		SetEntProp(client, Prop_Send, "m_bForcedSkin", 1);
		SetEntProp(client, Prop_Send, "m_nForcedSkin", 5);
	}	
	if (IsValidClient(client) && IsPlayerAlive(client) && GetClientTeam(client)==2 && TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		//TF2Attrib_SetByName(client, "player skin override", 1.0);
		TF2Attrib_SetByName(client, "zombiezombiezombiezombie", 1.0);
		SetEntProp(client, Prop_Send, "m_bForcedSkin", 1);
		SetEntProp(client, Prop_Send, "m_nForcedSkin", 22);
	}
	if (IsValidClient(client) && IsPlayerAlive(client) && GetClientTeam(client)==3 && TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		//TF2Attrib_SetByName(client, "player skin override", 1.0);
		TF2Attrib_SetByName(client, "zombiezombiezombiezombie", 1.0);
		SetEntProp(client, Prop_Send, "m_bForcedSkin", 1);
		SetEntProp(client, Prop_Send, "m_nForcedSkin", 23);
	}

	return Plugin_Handled;	
}

stock TF2_SwitchtoSlot(client, slot)
{
	if (slot >= 0 && slot <= 5 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		decl String:classname[64];
		new wep = GetPlayerWeaponSlot(client, slot);
		if (wep > MaxClients && IsValidEdict(wep) && GetEdictClassname(wep, classname, sizeof(classname)))
		{
			FakeClientCommandEx(client, "use %s", classname);
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", wep);
		}
	}
}


public Event_PlayerTeam(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
    new userid = GetEventInt(hEvent, "userid");
    new team = GetEventInt(hEvent, "team");
    new client = GetClientOfUserId(userid);
}
stock bool:IsValidTeam(client)
{
	new team = GetClientTeam(client);
	if (team == TFTeam_Red || team == TFTeam_Blue)
		return true;
	return false;
}
public RoundStarted(Handle:hEvent, const String:name[], bool:dontBroadcast)
{ 
	if (GetConVarInt(cvarZombieEnable) == 1)
	{	
		if(roundEndTimer != INVALID_HANDLE)
		{
			KillTimer(roundEndTimer);
			roundEndTimer = INVALID_HANDLE;
		}
		if(countdownTimer != INVALID_HANDLE)
		{
			KillTimer(countdownTimer);
			countdownTimer = INVALID_HANDLE;
		}
		if (GetConVarFloat(cvarZombieTimer) >= 1.0)
		{
			new time = GetConVarFloat(cvarZombieTimer) * 60; 
			PrintToChatAll("The round will end in %f seconds. Survive while you still can.", time)
			roundEndTimer = CreateTimer(time, RoundEnd);
			g_iCountdown = RoundFloat(time);
			countdownTimer = CreateTimer(1.0, Countdown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
		for(new i = 1; i <= MaxClients; i++) if(IsValidClient(i))
		{
			g_iSurvRage[i] = 0;
		}

		if (GetConVarInt(cvarZombieNoDoors) == 1)
		{
			CreateTimer(0.1, Timer_Doors, TIMER_REPEAT);
		}
	    CreateTimer(0.0, LoadSomeStuff);
	    CreateTimer(0.1, MoveFlagTimer,_,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		// from https://forums.alliedmods.net/showthread.php?p=1359262 but new syntax
		new i, j, num_players, current_team, player_team;
		decl valid_players[MaxClients];
		// scramble teams
		
		for(i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i) && IsValidTeam(i))
				valid_players[num_players++] = i;
		}
		SortIntegers(valid_players, num_players, Sort_Random);
		
		current_team = GetRandomInt(2, 3);
		
		for(i = 0; i < num_players; i++) {
			j = valid_players[i];
			player_team = GetClientTeam(j); 
			if(player_team != current_team)
				ChangeClientTeam(j, current_team);

			TF2_RespawnPlayer(j);
			current_team = GetRandomInt(2, 3);
		}
	}
		
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{ 
			SetEntProp(i, Prop_Send, "m_bForcedSkin", 0);
			SetEntProp(i, Prop_Send, "m_nForcedSkin", 0);
		}
	}
}

stock bool:IsValidClient(client)
{
	if(client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;

	if(IsClientSourceTV(client) || IsClientReplay(client))
		return false;

	return true;
}

public SetupReady(Handle:hEvent, const String:name[], bool:dontBroadcast) {
	
	PrecacheSound("*#music/hl2_song12_long.mp3");
	PrecacheSound("*#music/hl2_song11.mp3");
	PrecacheSound("*#music/hl2_song13.mp3");
	PrecacheSound("*#music/hl2_song17.mp3");
	PrecacheSound("*#music/hl2_song19.mp3");
	PrecacheSound("*#music/hl2_song0.mp3");
	PrecacheSound("*#music/hl2_song4.mp3");
	PrecacheSound("*#music/hl2_song8.mp3");
	PrecacheSound("*#music/hl1_song9.mp3");
	PrecacheSound("*#music/hl1_song14.mp3");
	PrecacheSound("*#music/hl1_song19.mp3");
	
	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		for(int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i))
			{	
				switch(GetRandomInt(1,11)) {
					case 1: {
						EmitSoundToClient(i, "*#music/hl2_song12_long.mp3");
					}
					case 2: {
						EmitSoundToClient(i, "*#music/hl2_song11.mp3");
					}
					case 3: {
						EmitSoundToClient(i, "*#music/hl2_song13.mp3");
					}
					case 4: {
						EmitSoundToClient(i, "*#music/hl2_song17.mp3");
					}
					case 5: {
						EmitSoundToClient(i, "*#music/hl2_song19.mp3");
					}
					case 6: {
						EmitSoundToClient(i, "*#music/hl2_song0.mp3");
					}
					case 7: {
						EmitSoundToClient(i, "*#music/hl2_song4.mp3");
					}
					case 8: {
						EmitSoundToClient(i, "*#music/hl2_song8.mp3");
					}
					case 9: {
						EmitSoundToClient(i, "*#music/hl1_song9.mp3");
					}
					case 10: {
						EmitSoundToClient(i, "*#music/hl1_song14.mp3");
					}
					case 11: {
						EmitSoundToClient(i, "*#music/hl1_song19.mp3");
					}
				}
			}
		}
	}
}

public Action:LoadSomeStuff(Handle:timer,any:userid)
{	
	new teamflags = CreateEntityByName("item_teamflag");
	if(IsValidEntity(teamflags))
	{
		DispatchKeyValue(teamflags, "targetname", "infectedbotflag");
		DispatchKeyValue(teamflags, "trail_effect", "0");
		DispatchKeyValue(teamflags, "ReturnTime", "1");
		DispatchKeyValue(teamflags, "flag_model", "models/empty.mdl");
		DispatchSpawn(teamflags);
		SetEntProp(teamflags, Prop_Send, "m_iTeamNum", 3);
	}
	new teamflags2 = CreateEntityByName("item_teamflag");
	if(IsValidEntity(teamflags2))
	{
		DispatchKeyValue(teamflags2, "targetname", "survbotflag");
		DispatchKeyValue(teamflags2, "trail_effect", "0");
		DispatchKeyValue(teamflags2, "ReturnTime", "1");
		DispatchKeyValue(teamflags2, "flag_model", "models/empty.mdl");
		DispatchSpawn(teamflags2);
		SetEntProp(teamflags2, Prop_Send, "m_iTeamNum", 2);
	}
	CreateTimer(0.5, LoadStuff2);
}

public Action:LoadStuff2(Handle:timer)
{
	decl String:name[] = "infectedbotflag";
	decl String:class[] = "item_teamflag";
	new ent = FindEntityByTargetname(name, class);
	if(ent != -1)
	{
		SDKHook(ent, SDKHook_StartTouch, OnFlagTouch );
		SDKHook(ent, SDKHook_Touch, OnFlagTouch );
	}
	new ent2 = FindEntityByTargetname("survbotflag", class);
	if(ent2 != -1)
	{
		SDKHook(ent2, SDKHook_StartTouch, OnFlagTouch );
		SDKHook(ent2, SDKHook_Touch, OnFlagTouch );
	}
}


public Action:OnFlagTouch(point, client)
{
	for(client=1;client<=MaxClients;client++)
	{
		if(IsClientInGame(client))
		{
			return Plugin_Handled; 
		}
	}
	
	return Plugin_Continue;
}


stock FindEntityByTargetname(const String:targetname[], const String:classname[])
{
  decl String:namebuf[32];
  new index = -1;
  namebuf[0] = '\0';
 
  while(strcmp(namebuf, targetname) != 0
    && (index = FindEntityByClassname(index, classname)) != -1)
    GetEntPropString(index, Prop_Data, "m_iName", namebuf, sizeof(namebuf));
 
  return(index);
}

public Action:MoveFlagTimer(Handle:timer)
{
	for(new client=1;client<=MaxClients;client++)
	{
		if(IsClientInGame(client))
		{
			if(IsPlayerAlive(client))
			{
				new team = GetClientTeam(client);
				decl String:name[] = "infectedbotflag";
				decl String:class[] = "item_teamflag";
				new iEnt = -1;
				new ent = FindEntityByTargetname(name, class);
				if(ent != -1)
				{
					if((iEnt = FindEntityByClassname(iEnt, "tank_boss")) != INVALID_ENT_REFERENCE)
					{
						if(IsValidEntity(iEnt))
						{
							decl Float:TankLoc[3];
							GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", TankLoc);
							TankLoc[2] += 20.0;
							TeleportEntity(ent, TankLoc, NULL_VECTOR, NULL_VECTOR);
						}
					}
					else if(team == 3)
					{
						GetClientAbsOrigin(client, flag_pos);
						TeleportEntity(ent, flag_pos, NULL_VECTOR, NULL_VECTOR);
					}
				}
				decl String:name2[] = "survbotflag";
				new iEnt2 = -1;
				new ent2 = FindEntityByTargetname(name2, class);
				if(ent2 != -1)
				{
					if(team == 2)
					{
						GetClientAbsOrigin(client, flag_pos2);
						TeleportEntity(ent2, flag_pos2, NULL_VECTOR, NULL_VECTOR);
					}
				}
			}
		}
	}
}


public Action:InfectionSH(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
    int client = entity;

	if (GetConVarInt(cvarZombieEnable) == 1)
	{
		if (StrContains(sample, "music") == -1 && (StrContains(sample, "weapons") != -1 || StrContains(sample, "vo") != -1)) {

			if (IsValidClient(client) && GetClientTeam(client) == 2) {
				ReplaceString(sample, sizeof(sample), "Severe", "Sharp");
				ReplaceString(sample, sizeof(sample), "CrticialDeath", "Sharp");
				ReplaceString(sample, sizeof(sample), "CriticalDeath", "Sharp");
				if (g_bIsPlagued[client] == true) {

					pitch = 65;

				} else {

					pitch = 80;

				}
				if (StrContains(sample, "vo") != -1) {
					EmitSoundToAll(sample,client,channel,level,flags,volume,pitch);
				}
				return Plugin_Changed;
			} else if (IsValidClient(client) && GetClientTeam(client) == 3 && StrContains(sample, "vo") == -1) {
				pitch = GetRandomInt(92,108);  
				return Plugin_Changed;
			} else if (IsValidClient(client) && GetClientTeam(client) == 3 && StrContains(sample, "vo") != -1) {
				pitch = GetRandomInt(90,100); 
				EmitSoundToAll(sample,client,channel,level,flags,volume,pitch);
				return Plugin_Changed;
			}

		}
	}
	return Plugin_Continue;
}