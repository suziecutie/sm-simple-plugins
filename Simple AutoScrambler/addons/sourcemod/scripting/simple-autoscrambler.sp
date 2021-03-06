/************************************************************************
*************************************************************************
Simple AutoScrambler
Description:
	Automatically scrambles the teams based upon a number of events.
*************************************************************************
*************************************************************************
This file is part of Simple Plugins project.

This plugin is free software: you can redistribute 
it and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the License, or
later version. 

This plugin is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this plugin.  If not, see <http://www.gnu.org/licenses/>.
*************************************************************************
*************************************************************************
File Information
$Id$
$Author$
$Revision$
$Date$
$LastChangedBy$
$LastChangedDate$
$URL$
$Copyright: (c) Simple Plugins 2008-2009$
*************************************************************************
*************************************************************************
*/

#include <simple-plugins>
#undef REQUIRE_EXTENSIONS
#undef AUTOLOAD_EXTENSIONS
#tryinclude <clientprefs>
#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "0.1.$Rev$"

enum 	e_ScrambleMode
{
	Mode_Invalid = 0,
	Mode_Random,
	Mode_TopSwap,
	Mode_Scores,
	Mode_KillRatios
};

enum 	e_RoundState
{
	Map_Start,
	Round_Setup,
	Round_Normal,
	Round_Ended
};

enum 	e_DelayReasons
{
	DelayReason_MapStart,
	DelayReason_Success,
	DelayReason_Fail,
	DelayReason_Scrambled
};

enum 	e_ScrambleReasons
{
	ScrambleReason_Invalid,
	ScrambleReason_Command,
	ScrambleReason_Vote,
	ScrambleReason_MapLoad,
	ScrambleReason_TimeLimit,
	ScrambleReason_WinStreak,
	ScrambleReason_Rounds,
	ScrambleReason_AvgScoreDiff,
	ScrambleReason_Frag,
	ScrambleReason_KDRatio,
	ScrambleReason_Dominations,
	ScrambleReason_Caps
};

enum 	e_PlayerStruct
{
	Handle:	hForcedTimer,
	bool:		bVoted,
					iFrags,
					iDeaths
};

enum 	e_TeamStruct
{
	Team_WinStreak,
	Team_Frags,
	Team_Deaths,
	Team_Goal
};

/**
Timers
*/
new		Handle:g_hAdTimer = INVALID_HANDLE;

/**
Arrays 
*/
new 	g_aPlayers[MAXPLAYERS + 1][e_PlayerStruct];
new 	g_aTeamInfo[e_Teams][e_TeamStruct];

/**
Cookies
*/
new 	Handle:g_hCookie_LastConnect = INVALID_HANDLE;
new 	Handle:g_hCookie_LastTeam = INVALID_HANDLE;
new 	Handle:g_hCookie_WasForced = INVALID_HANDLE;

/**
Other globals
*/
new		e_RoundState:g_eRoundState;
new		e_ScrambleReasons:g_eScrambleReason;

new		bool:g_bWasFullRound = false,
			bool:g_bScrambledThisRound = false,
			bool:g_bScrambleNextRound = false,
			bool:g_bUseClientprefs = false;

new		g_iRoundCount,
			g_iRoundStartTime,
			g_iAdminsPresent;
			
new		String:g_sScrambleReason[e_ScrambleReasons][128] =	{	"Invalid",
																											"Command",
																											"Vote",
																											"Map Load",
																											"Team Steam Rolled",
																											"Win Streak",
																											"Round Limit",
																											"Unbalanced Score",
																											"Unbalanced Frags",
																											"Unbalanced K/D Ratio",
																											"Unbalanced Dominations",
																											"Unbalanced Caps"
																										};

/**
Separate files to include
*/
#include "simple-plugins/sas-config.sp"
#include "simple-plugins/sas-vote.sp"
#include "simple-plugins/sas-scrambler.sp"
#include "simple-plugins/sas-menu.sp"
#include "simple-plugins/sas-daemon.sp"

public Plugin:myinfo =
{
	name = "Simple AutoScrambler",
	author = "Simple Plugins",
	description = "Automatically scrambles the teams based upon a number of events.",
	version = PLUGIN_VERSION,
	url = "http://www.simple-plugins.com"
};

public OnPluginStart()
{
	/**
	Lets start to load
	*/
	LogMessage("Simple AutoScrambler is loading...");
	
	/**
	Get game type and load the team numbers
	*/
	g_CurrentMod = GetCurrentMod();
	LoadCurrentTeams();
	
	/**
	Process the config file
	*/
	ProcessConfigFile();
	
	/**
	Hook the game events
	*/
	HookEvent("player_death", HookPlayerDeath, EventHookMode_Pre);
	LogMessage("Hooking events for [%s].", g_sGameName[g_CurrentMod]);
	switch (g_CurrentMod)
	{
		case GameType_TF:
		{
			HookEvent("teamplay_round_start", HookRoundStart, EventHookMode_PostNoCopy);
			HookEvent("teamplay_round_win", HookRoundEnd, EventHookMode_Post);
			HookEvent("teamplay_setup_finished", HookSetupFinished, EventHookMode_PostNoCopy);
			HookEvent("ctf_flag_captured", HookScored, EventHookMode_Post);
			HookEvent("teamplay_point_captured", HookScored, EventHookMode_Post);
		}
		case GameType_DOD:
		{
			HookEvent("dod_round_start", HookRoundStart, EventHookMode_PostNoCopy);
			HookEvent("dod_round_win", HookRoundEnd, EventHookMode_Post);
			HookEvent("dod_point_captured", HookScored, EventHookMode_Post);
		}
		case GameType_CSS:
		{
			HookEvent("round_start", HookRoundStart, EventHookMode_PostNoCopy);
			HookEvent("round_end", HookRoundEnd, EventHookMode_Post);
			HookEvent("bomb_exploded", HookScored, EventHookMode_Post);
			HookEvent("hostage_rescued", HookScored, EventHookMode_Post);
			HookEvent("vip_escaped", HookScored, EventHookMode_Post);
		}
		case GameType_INS:
		{
			HookEvent("round_end", HookRoundEnd, EventHookMode_Post);
		}
		default:
		{
			HookEvent("round_start", HookRoundStart, EventHookMode_PostNoCopy);
			HookEvent("round_end", HookRoundEnd, EventHookMode_Post);
		}
	}
	
	/**
	Create console variables
	*/
	CreateConVar("sas_version", PLUGIN_VERSION, "Simple AutoScrambler Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	/**
	Register the commands
	*/
	RegConsoleCmd("sm_scramble", Command_Scramble, "sm_scramble <mode>: Scrambles the teams");
	RegConsoleCmd("sm_resetscores", Command_ResetScores, "sm_resetscores: Resets the players scores");
	RegConsoleCmd("sm_scramblesetting", Command_SetSetting, "sm_scramblesetting <setting> <value>: Sets a plugin setting");
	RegConsoleCmd("sm_scramblereload", Command_Reload, "sm_scramblereload: Reloads the config file");
	CreateVoteCommand();
	
	/**
	Load translations and .cfg file
	*/
	LoadTranslations ("core.phrases");
	LoadTranslations ("common.phrases");
	LoadTranslations ("basevotes.phrases");
	LoadTranslations ("rockthevote.phrases");
	LoadTranslations ("sas.phrases");
}

public OnAllPluginsLoaded()
{
	
	/**
	Now lets check for client prefs extension
	*/
	if (CheckExtStatus("clientprefs.ext", true))
	{
		LogMessage("Client Preferences extension is loaded, checking database.");
		if (!SQL_CheckConfig("clientprefs"))
		{
			LogMessage("No 'clientprefs' database found.  Check your database.cfg file.");
			LogMessage("Plugin continued to load, but Client Preferences will not be used.");
			g_bUseClientprefs = false;
		}
		else
		{
			LogMessage("Database config 'clientprefs' was found.");
			LogMessage("Plugin will use Client Preferences.");
			g_bUseClientprefs = true;
		}
		
		/**
		Deal with client cookies
		*/
		if (g_bUseClientprefs)
		{
			g_hCookie_LastConnect = RegClientCookie("sas_lastconnect", "Timestamp of your last disconnection.", CookieAccess_Protected);
			g_hCookie_LastTeam = RegClientCookie("sas_lastteam", "Last team you were on.", CookieAccess_Protected);
			g_hCookie_WasForced = RegClientCookie("sas_wasforced", "If you were forced to this team", CookieAccess_Protected);
		}
	}
	
	/**
	Initiate The menu
	*/
	InitiateAdminMenu();
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "simpleplugins", false))
	{
		SetFailState("Core was unloaded and is required to run.");
	}
	else if (StrEqual(name, "adminmenu", false))
	{
		g_hAdminMenu = INVALID_HANDLE;
	}
}

public OnConfigsExecuted()
{
	
	/**
	Log our activity
	*/
	if (GetSettingValue("enabled"))
	{
		LogMessage("Simple AutoScrambler is set to be ENABLED");
	}
	else
	{
		LogMessage("Simple AutoScrambler is set to be DISABLED");
	}
	
	if (GetSettingValue("vote_enabled") && GetSettingValue("vote_ad_enabled"))
	{
		new Float:fAdInterval = float(GetSettingValue("vote_ad_interval"));
		g_hAdTimer = CreateTimer(fAdInterval, Timer_VoteAdvertisement, _, TIMER_REPEAT);
	}
	
	g_eScrambleReason = ScrambleReason_Invalid;
	g_bWasFullRound = true;
	g_bScrambledThisRound = false;
	g_bScrambleNextRound = false;
	ResetScores();
	ResetStreaks();
	ResetVotes();
	StartDaemon();
}

public OnMapStart()
{
	g_eRoundState = Map_Start;
	DelayVoting(DelayReason_MapStart);
}

public OnMapEnd()
{
	StopDaemon();
	StopScramble();
	StopVote();
}

public OnClientPostAdminCheck(client)
{
	if (GetUserFlagBits(client) & (ADMFLAG_VOTE|ADMFLAG_ROOT))
	{
		g_iAdminsPresent++;
	}
}

public OnClientCookiesCached(client)
{
	
	if (GetSettingValue("lock_players")
		&& (GetSettingValue("lock_reconnects"))
		&& (GetSettingValue("lockimmunity") && !IsAuthorized(client, "flag_lockimmunity"))
		&& IsValidClient(client))
	{
		new	String:sLastConnect[32],
				String:sLastTeam[3],
				String:sWasForced[3];
	
		/**
		Get the client cookies
		*/
		GetClientCookie(client, g_hCookie_LastConnect, sLastConnect, sizeof(sLastConnect));
		GetClientCookie(client, g_hCookie_LastTeam, sLastTeam, sizeof(sLastTeam));
		GetClientCookie(client, g_hCookie_WasForced, sWasForced, sizeof(sWasForced));
		
		if (StringToInt(sWasForced))
		{
			new	iCurrentTime = GetTime(),
					iConnectTime = StringToInt(sLastConnect);
	
			if (iCurrentTime - iConnectTime <= GetSettingValue("lock_duration"))
			{
	
				/**
				Bastard tried to reconnect
				*/
				SM_SetForcedTeam(client, StringToInt(sLastTeam), float(GetSettingValue("lock_duration")));
			}
		}
	}
}

public SM_OnPlayerMoved(Handle:plugin, client, oldteam, newteam)
{
	
	/**
	Make sure we called the move function
	*/
	if (plugin != GetMyHandle())
	{
		return;
	}
	
	/**
	Check if we are supposed to lock the players to the team
	*/
	if (GetSettingValue("lock_players") 
		&& g_aPlayers[client][hForcedTimer] == INVALID_HANDLE 
		&& (GetSettingValue("lockimmunity") && !IsAuthorized(client, "flag_lockimmunity")))
	{
		
		/**
		We are, set the forced team
		*/
		SM_SetForcedTeam(client, StringToInt(sLastTeam), float(GetSettingValue("lock_duration")));
	}
}

public OnClientDisconnect(client)
{
	
	/**
	Cleanup
	*/
	g_aPlayers[client][iFrags] = 0;
	g_aPlayers[client][iDeaths] = 0;
	
	/** 
	check to see if we lost a vote
	*/	
	if (g_aPlayers[client][bVoted])
	{
		g_iVotes--;
		g_aPlayers[client][bVoted] = false;
	}
	
	if (g_bUseClientprefs && IsValidClient(client))
	{
		
		/**
		Set the disconnect cookies to prevent lock bypasses
		*/
		new	String:sTimeStamp[32],
				String:sTeam[3],
				String:sWasForced[3];
	
		new	iTeam = SM_GetForcedTeam(client),
				iTime = GetTime();
		
		Format(sWasForced, sizeof(sWasForced), "%d", iTeam);
		Format(sTimeStamp, sizeof(sTimeStamp), "%d", iTime);
		Format(sTeam, sizeof(sTeam), "%d", iTeam);
		
		SetClientCookie(client, g_hCookie_LastConnect, sTimeStamp);
		SetClientCookie(client, g_hCookie_LastTeam, sTeam);
		SetClientCookie(client, g_hCookie_WasForced, sWasForced);
	}
	
	if (GetUserFlagBits(client) & (ADMFLAG_VOTE|ADMFLAG_ROOT))
	{
		g_iAdminsPresent--;
	}
}

public Action:Command_Scramble(client, args)
{

	/**
	Make sure we are enabled
	*/
	if (GetSettingValue("enabled"))
	{
		return Plugin_Handled;
	}
	
	/**
	Make sure the client is authorized to run this command.
	*/
	if (!IsAuthorized(client, "flag_scramble"))
	{
		ReplyToCommand(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return Plugin_Handled;
	}
	
	/**
	Make sure it's ok to scramble at this time
	*/
	if (!CanScramble())
	{
		return Plugin_Handled;
	}
	
	/**
	TODO: Check for command arguments and show the menu if we dont have any or they are not right
	*/
	
	/**
	Log some activity
	TODO: Add ShowActivity and maybe do this at the end of the scramble, add client, and more info
	*/
	LogAction(-1, -1, "[SAS] The scramble command was used");
	
	/**
	We are done, bug out.
	*/
	return Plugin_Handled;
}

public Action:Command_ResetScores(client, args)
{
	
	/**
	Make sure the client is authorized to run this command.
	*/
	if (!IsAuthorized(client, "flag_reset_scores"))
	{
		ReplyToCommand(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return Plugin_Handled;
	}
	
	/**
	Reset the scores
	*/
	ResetScores();
	ResetStreaks();
	
	/**
	Log some activity
	*/
	ShowActivityEx(client, "\x01\x04[SAS]\x01 ", "%t", "Reset Score Tracking", client);
	LogAction(client, -1, "%T", "Reset Score Tracking", LANG_SERVER, client);
	
	/**
	We are done, bug out.
	*/
	return Plugin_Handled;
}

public Action:Command_SetSetting(client, args)
{
	
	/**
	Make sure the client is authorized to run this command.
	*/
	if (!IsAuthorized(client, "flag_settings"))
	{
		ReplyToCommand(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return Plugin_Handled;
	}
	
	/**
	Check for command arguments
	*/
	new bool:bArgError = false;
	if (!GetCmdArgs())
	{
		
		/**
		No command arguments
		*/
		ReplyToCommand(client, "sm_scramblesetting <setting> <value>: Sets a plugin setting");
		if (GetCmdReplySource() == SM_REPLY_TO_CHAT)
		{
			ReplyToCommand(client, "%t", "CheckConsoleForList");
		}
		PrintSettings(client);
		
		/**
		We are done, bug out.
		*/
		return Plugin_Handled;
	}
	
	/**
	Get the command arguments
	*/
	new String:sArg[2][64];
	GetCmdArg(1, sArg[0], sizeof(sArg[]));
	GetCmdArg(2, sArg[1], sizeof(sArg[]));
	
	/**
	Setup some buffers
	*/
	new iBuffer;
	new String:sBuffer[64];
	
	/**
	Check to see if we can get this with the value function
	If we can, the value is an integer and we know how to set it
	*/
	if (GetTrieValue(g_hSettings, sArg[0], iBuffer))
	{
		
		/**
		We attempt to set the setting with the integer functions
		Doublechecking that they didn't send us a string for this setting
		*/
		if (!SetTrieValue(g_hSettings, sArg[0], StringToInt(sArg[1])))
		{
			
			/**
			There was a problem with the value they tried to store
			*/
			bArgError = true;
			ReplyToCommand(client, "Invalid setting");
		}
	}
	
	/**
	We couldn't get it with the value function
	Check to see if we can get this with the string function
	If we can, the value is an string and we know how to set it
	*/
	else if (GetTrieString(g_hSettings, sArg[0], sBuffer, sizeof(sBuffer)))
	{
		
		/**
		We attempt to set the setting with the string functions
		Doublechecking that they didn't send us a string for this setting
		*/
		if (!SetTrieString(g_hSettings, sArg[0], sArg[1]))
		{
			
			/**
			There was a problem with the value they tried to store
			*/
			bArgError = true;
			ReplyToCommand(client, "Invalid setting");
		}
	}
	
	/**
	It must be an invalid key cause we can't find it
	*/
	else
	{
		bArgError = true;
		ReplyToCommand(client, "Invalid key");
	}
	
	/**
	Check to see if we encountered an error
	*/
	if (bArgError)
	{
		
		/**
		Looks like we did, tell them so
		*/
		ReplyToCommand(client, "sm_scramblesetting <setting> <value>: Sets a plugin setting");
		if (GetCmdReplySource() == SM_REPLY_TO_CHAT)
		{
			ReplyToCommand(client, "%t", "CheckConsoleForList");
		}
		PrintSettings(client);
		
		/**
		We are done, bug out
		*/
		return Plugin_Handled;
	}
	else
	{
		
		/**
		We didn't have an error
		Log some activity
		*/
		ShowActivityEx(client, "\x01\x04[SAS]\x01 ", "%t", "Changed Setting", client, sArg[0], sArg[1]);
		LogAction(client, -1, "%T", "Changed Setting", LANG_SERVER, client, sArg[0], sArg[1]);
		
		/**
		Check if the timer settings were changed and restart the timer
		*/
		if (StrEqual(sArg[1], "vote_enabled")
			|| StrEqual(sArg[1], "vote_ad_enabled")
			|| StrEqual(sArg[1], "vote_ad_interval"))
		{
			ClearTimer(g_hAdTimer);
			if (GetSettingValue("vote_ad_enabled") && GetSettingValue("vote_enabled"))
			{
				new Float:fAdInterval = float(GetSettingValue("vote_ad_interval"));
				g_hAdTimer = CreateTimer(fAdInterval, Timer_VoteAdvertisement, _, TIMER_REPEAT);
			}
		}
	}
	
	/**
	We are done, bug out
	*/
	return Plugin_Handled;
}

public Action:Command_Reload(client, args)
{
	
	/**
	Make sure the client is authorized to run this command.
	*/
	if (!IsAuthorized(client, "flag_settings"))
	{
		ReplyToCommand(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return Plugin_Handled;
	}
	
	/**
	Process the config file
	*/
	ProcessConfigFile();
	
	/**
	Log some activity
	*/
	ShowActivityEx(client, "\x01\x04[SAS]\x01 ", "%t", "Reloaded Config", client);
	LogAction(client, -1, "%T", "Reloaded Config", LANG_SERVER, client);
	
	/**
	We are done, bug out.
	*/
	return Plugin_Handled;
}

public HookRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	switch (g_CurrentMod)
	{
		case GameType_TF:
		{
			CreateTimer(1.0, Timer_CheckState);
		}
		default:
		{
			g_iRoundStartTime = GetTime();
			g_eRoundState = Round_Normal;
			if (g_bScrambleNextRound)
			{
				g_bScrambleNextRound = false;
				StartScramble(e_ScrambleMode:GetSettingValue("sort_mode"));
			}
		}
	}
	g_bScrambledThisRound = false;
}

public HookSetupFinished(Handle:event, const String:name[], bool: dontBroadcast)
{
	g_iRoundStartTime = GetTime();
	g_eRoundState = Round_Normal;
}

public HookScored(Handle:event, const String:name[], bool:dontBroadCast)
{
	
	/**
	TODO: Need to deal with all the different mod point methods
	ctf, cp, hostage, vip, etc...
	*/
	
	switch (g_CurrentMod)
	{
		case GameType_TF:
		{
			new e_Teams:CappingTeam = e_Teams:GetEventInt(event, "capping_team");
			g_aTeamInfo[CappingTeam][Team_Goal] = 1;
		}
		case GameType_DOD:
		{
			//something
		}
		case GameType_CSS:
		{
			//something
		}
	}
}

public HookRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	g_eRoundState = Round_Ended;
	
	new iRoundWinner;
	g_iRoundCount++;
	AddTeamStreak(e_Teams:iRoundWinner);

	switch (g_CurrentMod)
	{
		case GameType_TF:
		{
			if (GetEventBool(event, "full_round"))
			{
				iRoundWinner = GetEventInt(event, "team");
				g_bWasFullRound = true;
			}
			else
			{
				g_iRoundCount--;
				g_bWasFullRound = false;
			}
		}
		case GameType_DOD:
		{
			iRoundWinner = GetEventInt(event, "team");
			g_bWasFullRound = true;
		}
		default:
		{
			iRoundWinner = GetEventInt(event, "winner");
			g_bWasFullRound = true;
		}
	}

	if (CanScramble() && !g_bScrambling && !g_bScrambleNextRound)
	{
		if (g_iRoundStartTime - GetTime() <= GetSettingValue("time_limit"))
		{
			g_eScrambleReason = ScrambleReason_TimeLimit;
		}
		else if (GetSettingValue("win_streak") >= g_aTeamInfo[Team1][Team_WinStreak]
			|| (GetSettingValue("win_streak") >= g_aTeamInfo[Team2][Team_WinStreak]))
		{
			g_eScrambleReason = ScrambleReason_WinStreak;
		}
		else if (g_iRoundCount > 0 && GetSettingValue("rounds") >= g_iRoundCount)
		{
			g_eScrambleReason = ScrambleReason_Rounds;
		}
		else
		{
			new iCaps;
			switch (g_CurrentMod)
			{
				case GameType_TF:
				{
					new TFGameType:eGameType = TF2_GetGameType();
					if (eGameType != TFGameMode_ARENA)
					{
						switch (eGameType)
						{
							case TFGameMode_CTF:
							{
								iCaps = GetSettingValue("tf2_intel_cap");
							}
							case TFGameMode_PL:
							{
								iCaps = GetSettingValue("tf2_pl_cap");
							}
							case TFGameMode_PLR:
							{
								iCaps = GetSettingValue("tf2_pl_cap");
							}
							case TFGameMode_KOTH:
							{
								iCaps = GetSettingValue("tf2_koth_cap");
							}
						}
					}
				}
				case GameType_DOD:
				{
					//somthing
				}
				case GameType_CSS:
				{
					//somthing
				}
			}
			
			if (iCaps && (!g_aTeamInfo[Team1][Team_Goal] || !g_aTeamInfo[Team2][Team_Goal]))
			{
				g_eScrambleReason = ScrambleReason_Caps;
			}
		}
		
		if (g_eScrambleReason != ScrambleReason_Invalid)
		{
			if (GetSettingValue("auto_action"))
			{
				StartVote();
			}
			else
			{
				StartScramble(e_ScrambleMode:GetSettingValue("sort_mode"));
			}
		}
	}
}

public Action:HookPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	/**
	If scrambling block deaths from being logged as a result of scramble
	*/
	if (g_bScrambling)
	{
		return Plugin_Handled;
	}
	
	switch (g_CurrentMod)
	{
		case GameType_TF:
		{
			
			/** 
			Check for spy fake deaths
			*/
			if (GetEventInt(event, "death_flags") & 32)
			{
				return Plugin_Continue;
			}
		}
	}
	
	/**
	Check the round state and count the kills and deaths if round is active
	*/
	if (g_eRoundState == Round_Normal)
	{
		new iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		new iVictim = GetClientOfUserId(GetEventInt(event, "userid"));
		
		if (IsValidClient(iAttacker))
		{
			new e_Teams:iAttackerTeam = e_Teams:GetClientTeam(iAttacker);
			g_aPlayers[iAttacker][iFrags]++;
			g_aTeamInfo[iAttackerTeam][Team_Frags]++;
		}
		
		if (IsValidClient(iVictim))
		{
			new e_Teams:iVictimTeam = e_Teams:GetClientTeam(iVictim);
			g_aPlayers[iVictim][iDeaths]++;
			g_aTeamInfo[iVictimTeam][Team_Deaths]++;
		}
	}
	
	return Plugin_Continue;
}

public Action:Timer_CheckState(Handle:timer, any:data)
{
	
	if (TF2_InSetup())
	{
		g_eRoundState = Round_Setup;
	}
	else
	{
		g_iRoundStartTime = GetTime();
		g_eRoundState = Round_Normal;
	}
	
	if (g_bScrambleNextRound)
	{
		g_bScrambleNextRound = false;
		StartScramble(e_ScrambleMode:GetSettingValue("sort_mode"));
	}
	
	return Plugin_Handled;
}

public Action:Timer_VoteAdvertisement(Handle:timer, any:data)
{
	if (!GetSettingValue("vote_ad_enabled") || !GetSettingValue("vote_enabled"))
	{
		g_hAdTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	new String:sBuffer[64], String:sVoteCommand[64];
	GetTrieString(g_hSettings, "vote_trigger", sBuffer, sizeof(sBuffer));
	Format(sVoteCommand, sizeof(sVoteCommand), "!%s", sBuffer);
	PrintToChatAll("\x01\x04[SAS]\x01 %t", "Vote_Advertisement", sVoteCommand);
	return Plugin_Handled;
}