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
**********
*/
new Handle:g_hAdminMenu = INVALID_HANDLE;

/**
checks for the menu plugin
and adds options to the admin menu
*/
stock InitiateAdminMenu()
{
	new Handle:hTopMenu = INVALID_HANDLE;
	if (LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(hTopMenu);
	}
}

/** 
adds options to the main admin menu
*/
public OnAdminMenuReady(Handle:hMenu)
{
	if (hMenu == g_hAdminMenu)
	{
		return;
	}
	g_hAdminMenu = hMenu;
	new TopMenuObject:menu_category = AddToTopMenu(hMenu, "Simple Autoscrambler", TopMenuObject_Category, Handle_Category, INVALID_TOPMENUOBJECT);
	AddToTopMenu(hMenu, "Start a Scramble", TopMenuObject_Item, AdminMenu_Scramble, menu_category, "sm_scramble", ADMFLAG_GENERIC);
	
	AddToTopMenu(hMenu, "Reset Scores", TopMenuObject_Item, AdminMenu_ResetScores, menu_category, "sm_resetscores", ADMFLAG_GENERIC);
	
	AddToTopMenu(hMenu, "Reload Config", TopMenuObject_Item, AdminMenu_Reload, menu_category, "sm_scramblereload", ADMFLAG_GENERIC);
	
	AddToTopMenu(hMenu, "Cancel Scramble", TopMenuObject_Item, AdminMenu_Cancel, menu_category, "sm_scramble", ADMFLAG_GENERIC);
}

/**
formats the titles for the sas category
*/
public Handle_Category(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayTitle:
		{
			SetGlobalTransTarget(client);
			Format(buffer, maxlength, "%t", "Menu Subtitle");
		}
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "Simple Autoscrambler");
		}
	}
}

/**
menu scramble callback
*/
public AdminMenu_Scramble(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength)
{
	if (!IsAuthorized(client, "flag_scramble"))
	{
		PrintToChat(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return;
	}
	switch (action)
	{
		case TopMenuAction_DisplayOption:
		{
			SetGlobalTransTarget(client);
			Format(buffer, maxlength, "%t", "Start a Scramble");
		}
		case TopMenuAction_SelectOption:
		{
			ShowScrambleMenu(client);
		}
	}
}

/**
menu score_rest callback
*/
public AdminMenu_ResetScores(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength)
{
	if (!IsAuthorized(client, "flag_reset_scores"))
	{
		PrintToChat(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return;
	}
	switch (action)
	{
		case TopMenuAction_DisplayOption:
		{
			SetGlobalTransTarget(client);
			Format(buffer, maxlength, "%t", "Reset Scores");
		}
		case TopMenuAction_SelectOption:
		{
			ResetScores();
			ResetStreaks();
			
			/**
			Log some activity
			*/
			ShowActivityEx(client, "\x01\x04[SAS]\x01 ", "%N reset the score tracking for the scrambler", client);
			LogAction(client, -1, "%N reset the score tracking for the scrambler", client);
		}
	}
}

/**
menu reload config file callback
*/
public AdminMenu_Reload(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength)
{
	if (!IsAuthorized(client, "flag_settings"))
	{
		PrintToChat(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return;
	}
	switch (action)
	{
		case TopMenuAction_DisplayOption:
		{
			SetGlobalTransTarget(client);
			Format(buffer, maxlength, "%t", "Reload Config");
		}
		case TopMenuAction_SelectOption:
		{
			ProcessConfigFile();
			
			/**
			Log some activity
			*/
			ShowActivityEx(client, "\x01\x04[SAS]\x01 ", "%N reloaded the scrambler config file", client);
			LogAction(client, -1, "%N reloaded the config file", client);
		}
	}
}

/**
menu cancel scramble callback
*/
public AdminMenu_Cancel(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength)
{
	if (!IsAuthorized(client, "flag_scramble"))
	{
		PrintToChat(client, "\x01\x04[SAS]\x01 %t", "No Access");
		return;
	}
	switch (action)
	{
		case TopMenuAction_DisplayOption:
		{
			SetGlobalTransTarget(client);
			Format(buffer, maxlength, "%t", "Cancel Actions");
		}
		case TopMenuAction_SelectOption:
		{
			g_bScrambledThisRound = false;
			StopScramble();
			StopVote();
			
			/**
			Log some activity
			*/
			ShowActivityEx(client, "\x01\x04[SAS]\x01 ", "%N canceled all pending actions", client);
			LogAction(client, -1, "%N canceled all pending actions", client);
		}
	}
}

/** 
Second scramble menu
*/
stock ShowScrambleMenu(client)
{
	new Handle:hScrambleMenu = INVALID_HANDLE,
			String:sBuffer[255];
	hScrambleMenu = CreateMenu(Menu_Scramble);
	SetGlobalTransTarget(client);	
	Format(sBuffer, sizeof(sBuffer), "%t", "ScrambleMenu When");
	SetMenuTitle(hScrambleMenu, sBuffer);
	
	SetMenuExitButton(hScrambleMenu, true);
	SetMenuExitBackButton(hScrambleMenu, true);
	
	SetGlobalTransTarget(client);	
	Format(sBuffer, sizeof(sBuffer), "%t", "Scramble Next Round");
	AddMenuItem(hScrambleMenu, "", sBuffer);
	
	SetGlobalTransTarget(client);	
	Format(sBuffer, sizeof(sBuffer), "%t", "Scramble Now");
	AddMenuItem(hScrambleMenu, "", sBuffer);
	
	DisplayMenu(hScrambleMenu, client, MENU_TIME_FOREVER);
}

/**
callback for start-a-scramble menu
*/
public Menu_Scramble(Handle:scrambleMenu, MenuAction:action, client, param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			g_eScrambleReason = ScrambleReason_Command;
			if (!param2)
			{
				g_bScrambleNextRound = true;
			}
			else
			{
				/**
				show mode selection menu
				*/
				
				new Handle:hModeMenu = INVALID_HANDLE,
						String:sBufer[64];
				hModeMenu = CreateMenu(Menu_ModeSelect);
				
				SetGlobalTransTarget(client);
				Format(sBuffer, sizeof(sBuffer), "%t", "Choose Mode");
				SetMenuTitle(hModeMenu, sBuffer);
				
				SetMenuExitButton(hModeMenu, true);
				SetMenuExitBackButton(hModeMenu, true);
				
				SetGlobalTransTarget(client);
				Format(sBuffer, sizeof(sBuffer), "%t", "Default Mode");
				AddMenuItem(hModeMenu, "", sBuffer);
				
				SetGlobalTransTarget(client);
				Format(sBuffer, sizeof(sBuffer), "%t", "Random Mode");
				AddMenuItem(hModeMenu, "", sBuffer);
				
				SetGlobalTransTarget(client);
				Format(sBuffer, sizeof(sBuffer), "%t", "Swap Top");
				AddMenuItem(hModeMenu, "", sBuffer);
				
				SetGlobalTransTarget(client);
				Format(sBuffer, sizeof(sBuffer), "%t", "Score Sort");
				AddMenuItem(hModeMenu, "", sBuffer);
				
				SetGlobalTransTarget(client);
				Format(sBuffer, sizeof(sBuffer), "%t", "Ratio Sort");
				AddMenuItem(hModeMenu, "", sBuffer);
				
				DisplayMenu(hModeMenu, client, MENU_TIME_FOREVER);	
			}
		}
		
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack )
			{
				RedisplayAdminMenu(g_hAdminMenu, client);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(scrambleMenu);
		}
	}
}

/**
callback for scramble-now mode selection
*/
public Menu_ModeSelect(Handle:scrambleMenu, MenuAction:action, client, param2 )
{
	switch (action)
	{
		case MenuAction_Select:
		{
			new e_ScrambleMode:mode;
			if (!param2)
			{
				mode = e_ScrambleMode:GetSettingValue("sort_mode");
			}
			else
			{
				mode = e_ScrambleMode:param2;
			}
			
			StartScramble(mode);
		}
		
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack )
			{
				RedisplayAdminMenu(g_hAdminMenu, client);
			}
		}
		
		case MenuAction_End:
		{
			CloseHandle(scrambleMenu);
		}
	}
}



