#include <amxmodx>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <fakemeta_util>
#include <fun>
#include <hamsandwich>
#include <vector>

#define TARGETS 31
#define RINGS 3
#define TASK_RESPAWN 100
#define TASK_EQUIP 200
#define TASK_BOT_COUNT 300
#define BOT_STEP 0.033
#define BOT_SPEED 220.0
#define STRAFE_SPEED 180.0
#define RESPAWN_DELAY 0.3
#define CHALLENGE_SECONDS 60.0
#define SHOT_TRACKED (1 << 0)
#define SHOT_FIRED (1 << 1)
#define SHOT_HIT (1 << 2)
#define CS_JOINED 0
#define CS_MENU_OFF 0
#define CS_MENU_CHOOSE_TEAM 1
#define CS_MENU_CHANGE_TEAM 2
#define CS_TEAM_AUTOSELECT 5
#define TARGET_MODEL "models/player/leet/leet.mdl"
#define USP_CHOICE 4

new const g_ruleNames[][] = {
    "mp_round_infinite", "mp_roundrespawn_time", "mp_timelimit",
    "mp_freezetime", "mp_autoteambalance", "mp_limitteams", "mp_roundtime",
    "mp_respawn_immunitytime", "mp_weapondrop", "mp_infinite_ammo",
    "mp_freeforall", "mp_friendlyfire"
};
new const g_warmupValues[] = {1, -1, 0, 0, 0, 0, 30, 0, 0, 1, 1, 0};
new g_rulePointers[sizeof g_ruleNames];
new g_previousValues[sizeof g_ruleNames][32];

new g_slotByClient[33];
new g_clientBySlot[TARGETS + 1];
new g_targetCount;
new g_ringMask = (1 << RINGS) - 1;
new g_ringBySlot[TARGETS + 1];
new bool:g_activeSlots[TARGETS + 1];
new Float:g_positions[TARGETS + 1][3];
new Float:g_angles[TARGETS + 1][3];
new Float:g_trackRadius[TARGETS + 1];
enum {BOT_STAND, BOT_RUN, BOT_STRAFE};
new const g_botModeNames[][] = {"STAND", "RUN", "STRAFE"};
new g_botMode;
new bool:g_randomSpawns, bool:g_headOnly;
new bool:g_relocateOnSpawn[33];
new Float:g_deathOrigin[33][3], Float:g_botFacing[33][3];
new Float:g_strafeUntil[33], Float:g_strafeSide[33];
new Float:g_lastBotStep;
new g_targetModelIndex;

new const g_buttonNames[][] = {
    "aim_ak47", "aim_m4a1", "aim_awp", "aim_deagle", "aim_usp", "aim_famas",
    "aim_stand", "aim_run", "aim_bot_minus", "aim_bot_plus",
    "aim_near", "aim_mid", "aim_far", "aim_strafe", "aim_random", "aim_head", "aim_test"
};
new const g_ringLabels[][] = {"NEAR", "MID", "FAR"};
new const g_indicatorNames[][] = {"aim_led_near", "aim_led_mid", "aim_led_far", "aim_led_random", "aim_led_head"};
new g_indicators[sizeof g_indicatorNames];
new const g_weapons[][] = {
    "weapon_ak47", "weapon_m4a1", "weapon_awp", "weapon_deagle", "weapon_usp", "weapon_famas"
};
enum
{
    CONTROL_STAND = sizeof g_weapons, CONTROL_RUN, CONTROL_MINUS, CONTROL_PLUS,
    CONTROL_NEAR, CONTROL_MID, CONTROL_FAR, CONTROL_STRAFE, CONTROL_RANDOM, CONTROL_HEAD, CONTROL_TEST
};
new const g_weaponIds[] = {CSW_AK47, CSW_M4A1, CSW_AWP, CSW_DEAGLE, CSW_USP, CSW_FAMAS};
new const g_weaponLabels[][] = {"AK-47", "M4A1", "AWP", "Desert Eagle", "USP", "FAMAS"};
new const g_weaponModels[][] = {
    "models/w_ak47.mdl", "models/w_m4a1.mdl", "models/w_awp.mdl",
    "models/w_deagle.mdl", "models/w_usp.mdl", "models/w_famas.mdl"
};
new const g_reserveAmmo[] = {90, 90, 30, 35, 100, 90};
new const g_clipSizes[] = {30, 30, 10, 7, 12, 25};
new const g_targetWeapons[][] = {
    "weapon_knife", "weapon_glock18", "weapon_ak47", "weapon_usp", "weapon_m4a1"
};
new g_buttons[sizeof g_buttonNames];
new g_weaponByClient[33];
new g_primaryChoice[33];
new g_secondaryChoice[33] = {USP_CHOICE, ...};
new bool:g_useHeld[33];
new bool:g_toggleShotUsed[33];
new g_teamMenu;
new g_timerHud, g_hideWeaponMessage;
new Float:g_timerEnd;
new bool:g_hideTimerPending[33];
new g_challengeHud;
new Float:g_challengeEnd[33];
new g_shotFlags[33], g_shots[33], g_hits[33], g_kills[33], g_headshots[33];
new g_shotDepth[33];

public plugin_precache()
{
    new map[32];
    get_mapname(map, charsmax(map));
    if (!equali(map, "!00_AIM_WARMUP"))
        return;

    g_targetModelIndex = precache_model(TARGET_MODEL);
    for (new weapon; weapon < sizeof g_weaponModels; weapon++)
        precache_model(g_weaponModels[weapon]);
}

public plugin_init()
{
    register_plugin("Aim Warmup", "4.5", "Codex");

    new map[32];
    get_mapname(map, charsmax(map));
    if (!equali(map, "!00_AIM_WARMUP"))
    {
        pause("ad");
        return;
    }

    RegisterHam(Ham_Spawn, "player", "on_spawn", 1, true);
    RegisterHam(Ham_Killed, "player", "on_killed", 1, true);
    RegisterHam(Ham_TraceAttack, "player", "on_target_trace", 0, true);
    RegisterHam(Ham_TakeDamage, "player", "on_target_damage", 0, true);
    RegisterHam(Ham_TakeDamage, "func_button", "on_panel_damage");
    new weaponClass[32];
    for (new weaponId = 1; weaponId <= CSW_P90; weaponId++)
    {
        if (!(CSW_ALL_GUNS & (1 << weaponId)))
            continue;

        get_weaponname(weaponId, weaponClass, charsmax(weaponClass));
        RegisterHam(Ham_Weapon_PrimaryAttack, weaponClass, "begin_shot_tracking");
        RegisterHam(Ham_Weapon_PrimaryAttack, weaponClass, "end_shot_tracking", 1);
        if (weaponId == CSW_FAMAS || weaponId == CSW_GLOCK18)
        {
            // The rest of a burst fires from ItemPostFrame after PrimaryAttack returns.
            RegisterHam(Ham_Item_PostFrame, weaponClass, "begin_shot_tracking");
            RegisterHam(Ham_Item_PostFrame, weaponClass, "end_shot_tracking", 1);
        }
    }
    register_forward(FM_PlaybackEvent, "on_fire_event");
    register_forward(FM_StartFrame, "move_bots");
    register_forward(FM_CmdStart, "on_player_command");
    register_clcmd("chooseteam", "open_team_menu");
    register_clcmd("jointeam", "on_jointeam");
    register_clcmd("menuselect", "on_stock_menu_choice");
    register_clcmd("say /ct", "switch_to_ct");
    register_event("DeathMsg", "record_challenge_kill", "a");
    register_message(get_user_msgid("RoundTime"), "on_round_time");
    register_message(get_user_msgid("ShowTimer"), "hide_stock_timer");
    g_hideWeaponMessage = get_user_msgid("HideWeapon");
    register_message(g_hideWeaponMessage, "on_hide_weapon");
    g_timerHud = CreateHudSyncObj();
    g_challengeHud = CreateHudSyncObj();
    set_task(1.0, "draw_round_timer", 0, "", 0, "b");
    g_teamMenu = menu_create("Aim Warmup", "on_team_choice");
    menu_additem(g_teamMenu, "Join CT");
    menu_additem(g_teamMenu, "Join T");
}

public on_round_time(message, destination, id)
{
    new seconds = get_msg_arg_int(1);
    if (seconds > 0)
        g_timerEnd = floatmax(g_timerEnd, get_gametime() + float(seconds));

    if (id > 0 && !g_slotByClient[id])
    {
        g_hideTimerPending[id] = true;
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public hide_stock_timer()
{
    return PLUGIN_HANDLED;
}

public on_hide_weapon(message, destination, id)
{
    set_msg_arg_int(1, ARG_BYTE, warmup_hud_mask(id, get_msg_arg_int(1)));
    if (id > 0)
        g_hideTimerPending[id] = false;
}

warmup_hud_mask(id, mask)
{
    if (id > 0 && !g_slotByClient[id] && is_user_alive(id))
        mask &= ~(HIDEHUD_WEAPONS | HIDEHUD_CROSSHAIR | HIDEHUD_ALL);

    return mask | HIDEHUD_TIMER;
}

send_hud_mask(id)
{
    g_hideTimerPending[id] = false;
    new mask = get_ent_data(id, "CBasePlayer", "m_iHideHUD");
    message_begin(MSG_ONE, g_hideWeaponMessage, _, id);
    write_byte(warmup_hud_mask(id, mask));
    message_end();
}

public draw_round_timer()
{
    if (g_timerEnd <= 0.0)
        return;

    new seconds = max(0, floatround(g_timerEnd - get_gametime(), floatround_ceil));
    new players[32], count;
    get_players(players, count, "h");
    for (new index; index < count; index++)
    {
        new id = players[index];
        if (g_slotByClient[id])
            continue;

        if (g_hideTimerPending[id])
            send_hud_mask(id);

        set_hudmessage(255, 186, 70, -1.0, 0.925, 0, 0.0, 1.15, 0.0, 0.0);
        ShowSyncHudMsg(id, g_timerHud, "%02d:%02d", seconds / 60, seconds % 60);
        draw_challenge(id);
    }
}

public plugin_cfg()
{
    if (!get_cvar_pointer("mp_round_infinite"))
        return;

    for (new rule; rule < sizeof g_ruleNames; rule++)
    {
        new pointer = get_cvar_pointer(g_ruleNames[rule]);
        if (!pointer)
            continue;

        g_rulePointers[rule] = pointer;
        get_pcvar_string(pointer, g_previousValues[rule], charsmax(g_previousValues[]));
        set_pcvar_num(pointer, g_warmupValues[rule]);
    }
}

public OnConfigsExecuted()
{
    new infiniteRound = get_cvar_pointer("mp_round_infinite");
    if (!infiniteRound)
    {
        log_amx("ReGameDLL_CS is required for continuous rounds.");
        return;
    }

    new targetName[32], ringName[8];
    for (new slot = 1; slot <= TARGETS; slot++)
    {
        formatex(targetName, charsmax(targetName), "aim_target_%d", slot);
        new marker = find_ent_by_tname(-1, targetName);
        if (!marker)
        {
            log_amx("Missing map spawn: %s", targetName);
            return;
        }

        entity_get_string(marker, EV_SZ_netname, ringName, charsmax(ringName));
        new ring = str_to_num(ringName) - 1;
        if (ring < 0 || ring >= RINGS)
        {
            log_amx("Missing or invalid ring for %s", targetName);
            return;
        }
        g_ringBySlot[slot] = ring;
        entity_get_vector(marker, EV_VEC_origin, g_positions[slot]);
        entity_get_vector(marker, EV_VEC_angles, g_angles[slot]);
        g_positions[slot][2] -= 2.0;
        g_trackRadius[slot] = floatsqroot(g_positions[slot][0] * g_positions[slot][0]
            + g_positions[slot][1] * g_positions[slot][1]);
    }

    for (new rule; rule < sizeof g_rulePointers; rule++)
        if (g_rulePointers[rule])
            set_pcvar_num(g_rulePointers[rule], g_warmupValues[rule]);

    for (new button; button < sizeof g_buttonNames; button++)
        g_buttons[button] = find_ent_by_tname(-1, g_buttonNames[button]);
    for (new indicator; indicator < sizeof g_indicatorNames; indicator++)
        g_indicators[indicator] = find_ent_by_tname(-1, g_indicatorNames[indicator]);
    update_indicators();

    mount_weapon_models();
    g_targetCount = target_capacity();
    apply_target_count();

    // The initial round may have cached the listen-server menu's timer.
    // Start a fresh round once, after the map's rules have been applied.
    server_cmd("sv_restart 1");
}

update_indicators()
{
    for (new index; index < sizeof g_indicators; index++)
    {
        new indicator = g_indicators[index];
        if (!indicator)
            continue;

        new bool:enabled;
        if (index < RINGS)
            enabled = (g_ringMask & (1 << index)) != 0;
        else
            enabled = index == RINGS ? g_randomSpawns : g_headOnly;

        new effects = pev(indicator, pev_effects);
        set_pev(indicator, pev_effects, enabled ? effects & ~EF_NODRAW : effects | EF_NODRAW);
    }
}

mount_weapon_models()
{
    new targetName[24], Float:origin[3];
    for (new weapon; weapon < sizeof g_weaponModels; weapon++)
    {
        formatex(targetName, charsmax(targetName), "aim_display_%d", weapon + 1);
        new display = find_ent_by_tname(-1, targetName);
        if (!display)
            continue;

        entity_get_vector(display, EV_VEC_origin, origin);
        entity_set_model(display, g_weaponModels[weapon]);
        entity_set_int(display, EV_INT_solid, SOLID_NOT);
        entity_set_origin(display, origin);
    }
}

public plugin_end()
{
    for (new rule; rule < sizeof g_rulePointers; rule++)
    {
        if (g_rulePointers[rule])
            set_pcvar_string(g_rulePointers[rule], g_previousValues[rule]);
    }
    if (g_teamMenu)
        menu_destroy(g_teamMenu);
}

target_capacity()
{
    new otherClients = get_playersnum(1);
    for (new slot = 1; slot <= TARGETS; slot++)
        if (g_clientBySlot[slot])
            otherClients--;

    return clamp(MaxClients - max(1, otherClients), 0, TARGETS);
}

schedule_target_count()
{
    remove_task(TASK_BOT_COUNT);
    set_task(0.1, "apply_target_count", TASK_BOT_COUNT);
}

enabled_target_capacity()
{
    new count;
    for (new slot = 1; slot <= TARGETS; slot++)
        if (g_ringMask & (1 << g_ringBySlot[slot]))
            count++;

    return min(target_capacity(), count);
}

public apply_target_count()
{
    new remaining = min(g_targetCount, target_capacity());
    new bool:kicked;
    for (new slot = 1; slot <= TARGETS; slot++)
    {
        g_activeSlots[slot] = remaining > 0 && (g_ringMask & (1 << g_ringBySlot[slot])) != 0;
        if (g_activeSlots[slot])
            remaining--;

        new id = g_clientBySlot[slot];
        if (id && !g_activeSlots[slot])
        {
            server_cmd("kick #%d", get_user_userid(id));
            kicked = true;
        }
    }

    if (kicked)
        server_exec();

    for (new slot = 1; slot <= TARGETS; slot++)
        if (g_activeSlots[slot] && !g_clientBySlot[slot])
            add_target(slot);
}

add_target(slot)
{
    new name[24];
    formatex(name, charsmax(name), "Target %d", slot);

    new id = engfunc(EngFunc_CreateFakeClient, name);
    if (!id)
    {
        log_amx("Could not create %s. Check the server player limit.", name);
        return;
    }

    engfunc(EngFunc_FreeEntPrivateData, id);
    dllfunc(MetaFunc_CallGameEntity, "player", id);

    new reject[128];
    if (!dllfunc(DLLFunc_ClientConnect, id, name, "127.0.0.1", reject))
    {
        server_cmd("kick ^"%s^"", name);
        log_amx("Could not connect %s: %s", name, reject);
        return;
    }

    dllfunc(DLLFunc_ClientPutInServer, id);
    set_pev(id, pev_flags, pev(id, pev_flags) | FL_FAKECLIENT);
    g_slotByClient[id] = slot;
    g_clientBySlot[slot] = id;
    cs_set_user_team(id, CS_TEAM_T, CS_T_LEET);
    set_ent_data(id, "CBasePlayer", "m_iJoiningState", CS_JOINED);
    set_ent_data(id, "CBasePlayer", "m_iMenu", CS_MENU_OFF);
    ExecuteHamB(Ham_CS_RoundRespawn, id);
}

public on_spawn(id)
{
    if (!is_user_alive(id))
        return;

    new slot = g_slotByClient[id];
    if (slot)
    {
        new Float:mins[3], Float:maxs[3];
        pev(id, pev_mins, mins);
        pev(id, pev_maxs, maxs);
        cs_set_user_model(id, "leet");
        engfunc(EngFunc_SetModel, id, TARGET_MODEL);
        engfunc(EngFunc_SetSize, id, mins, maxs);
        set_ent_data(id, "CBasePlayer", "m_modelIndexPlayer", g_targetModelIndex);
        cs_set_user_armor(id, 0, CS_ARMOR_NONE);
        position_bot(id, slot, g_randomSpawns && g_relocateOnSpawn[id]);
        g_relocateOnSpawn[id] = false;
    }

    if (is_playing_team(cs_get_user_team(id)))
    {
        remove_task(TASK_EQUIP + id);
        set_task(0.1, "equip_player", TASK_EQUIP + id);
    }
}

position_bot(id, slot, bool:relocate = false)
{
    new Float:origin[3];
    origin = g_positions[slot];
    g_botFacing[id] = g_angles[slot];
    if (relocate)
        randomize_bot_spawn(id, g_trackRadius[slot], origin, g_botFacing[id]);

    engfunc(EngFunc_SetOrigin, id, origin);
    set_pev(id, pev_angles, g_botFacing[id]);
    set_pev(id, pev_v_angle, g_botFacing[id]);
    set_pev(id, pev_fixangle, 0);
    set_pev(id, pev_effects, pev(id, pev_effects) & ~EF_NODRAW);
    set_pev(id, pev_velocity, Float:{0.0, 0.0, 0.0});
    set_pev(id, pev_movetype, MOVETYPE_WALK);
    g_strafeUntil[id] = 0.0;
    g_strafeSide[id] = 0.0;
}

randomize_bot_spawn(id, Float:radius, Float:origin[3], Float:angles[3])
{
    new Float:candidate[3];
    candidate[2] = origin[2];
    new trace = create_tr2();
    for (new attempt; attempt < 32; attempt++)
    {
        new Float:angle = random_float(0.0, 360.0);
        candidate[0] = radius * floatcos(angle, degrees);
        candidate[1] = radius * floatsin(angle, degrees);
        if (get_distance_f(candidate, g_deathOrigin[id]) < 80.0)
            continue;

        engfunc(EngFunc_TraceHull, candidate, candidate, DONT_IGNORE_MONSTERS, HULL_HUMAN, id, trace);
        new Float:fraction;
        get_tr2(trace, TR_flFraction, fraction);
        if (get_tr2(trace, TR_StartSolid) || get_tr2(trace, TR_AllSolid) || fraction < 1.0)
            continue;

        origin = candidate;
        angles[1] = angle < 180.0 ? angle + 180.0 : angle - 180.0;
        break;
    }
    free_tr2(trace);
}

public move_bots()
{
    new Float:now = get_gametime();
    new Float:elapsed = now - g_lastBotStep;
    if (elapsed < BOT_STEP)
        return;

    g_lastBotStep = now;
    new stepMillis = clamp(floatround(elapsed * 1000.0), 1, 50);
    new Float:position[3], Float:direction[3], Float:angles[3];
    for (new id = 1; id <= MaxClients; id++)
    {
        new slot = g_slotByClient[id];
        if (!slot || !is_user_alive(id))
            continue;

        if (g_botMode == BOT_STAND)
        {
            engfunc(EngFunc_RunPlayerMove, id, g_botFacing[id], 0.0, 0.0, 0.0, 0, 0, stepMillis);
            continue;
        }

        pev(id, pev_origin, position);
        new Float:radius = floatsqroot(position[0] * position[0] + position[1] * position[1]);
        new Float:correction = floatclamp((g_trackRadius[slot] - radius) / 70.0, -1.0, 1.0);
        if (g_botMode == BOT_STRAFE)
        {
            if (now >= g_strafeUntil[id])
            {
                if (g_strafeSide[id] == 0.0)
                    g_strafeSide[id] = random_num(0, 1) ? 1.0 : -1.0;
                else
                    g_strafeSide[id] = random_num(0, 3) ? -g_strafeSide[id] : 0.0;
                g_strafeUntil[id] = now + random_float(0.22, 0.70);
            }
            direction[0] = -position[0];
            direction[1] = -position[1];
            vector_to_angle(direction, angles);
            set_user_maxspeed(id, STRAFE_SPEED);
            engfunc(EngFunc_RunPlayerMove, id, angles, -correction * 85.0, g_strafeSide[id] * STRAFE_SPEED, 0.0, 0, 0, stepMillis);
            continue;
        }
        direction[0] = -position[1] + correction * position[0];
        direction[1] = position[0] + correction * position[1];
        vector_to_angle(direction, angles);
        set_user_maxspeed(id, BOT_SPEED);
        engfunc(EngFunc_RunPlayerMove, id, angles, BOT_SPEED, 0.0, 0.0, 0, 0, stepMillis);
    }
}

public equip_player(task)
{
    new id = task - TASK_EQUIP;
    if (!is_user_alive(id) || !is_playing_team(cs_get_user_team(id)))
        return;

    new slot = g_slotByClient[id];
    if (slot)
    {
        new weapon = (slot - 1) % sizeof g_targetWeapons;
        strip_user_weapons(id);
        give_item(id, g_targetWeapons[weapon]);
        engclient_cmd(id, g_targetWeapons[weapon]);
    }
    else
    {
        select_weapon(id, g_weaponByClient[id]);
    }
}

select_weapon(id, choice)
{
    g_weaponByClient[id] = choice;
    new selected = g_weaponIds[choice];
    if (selected == CSW_USP || selected == CSW_DEAGLE)
        g_secondaryChoice[id] = choice;
    else
        g_primaryChoice[id] = choice;

    new primary = g_primaryChoice[id];
    new secondary = g_secondaryChoice[id];
    if (!user_has_weapon(id, CSW_KNIFE))
        give_item(id, "weapon_knife");

    new inventory[32], count, classname[32];
    get_user_weapons(id, inventory, count);
    for (new index; index < count; index++)
    {
        new weaponId = inventory[index];
        if (weaponId < 1 || weaponId > CSW_P90 || weaponId == CSW_KNIFE
            || weaponId == g_weaponIds[primary] || weaponId == g_weaponIds[secondary])
            continue;

        get_weaponname(weaponId, classname, charsmax(classname));
        new item = find_ent_by_owner(-1, classname, id);
        if (item > 0 && ExecuteHamB(Ham_RemovePlayerItem, id, item))
        {
            set_pev(id, pev_weapons, pev(id, pev_weapons) & ~(1 << weaponId));
            ExecuteHamB(Ham_Item_Kill, item);
        }
    }

    give_selected_weapon(id, primary);
    give_selected_weapon(id, secondary);
    engclient_cmd(id, g_weapons[choice]);

    // GoldSrc uses the suit bit to enable the weapon slots and weapon HUD.
    fm_set_user_suit(id, true, false);
    new mask = get_ent_data(id, "CBasePlayer", "m_iHideHUD");
    set_ent_data(id, "CBasePlayer", "m_iHideHUD", mask & ~(HIDEHUD_WEAPONS | HIDEHUD_CROSSHAIR | HIDEHUD_ALL));
    send_hud_mask(id);
}

give_selected_weapon(id, choice)
{
    new weaponId = g_weaponIds[choice];
    if (!user_has_weapon(id, weaponId))
        give_item(id, g_weapons[choice]);
    new weapon = find_ent_by_owner(-1, g_weapons[choice], id);
    if (weapon > 0)
        cs_set_weapon_ammo(weapon, g_clipSizes[choice]);
    cs_set_user_bpammo(id, weaponId, g_reserveAmmo[choice]);
}

bool:challenge_running(id)
{
    return g_challengeEnd[id] > get_gametime();
}

start_challenge(id)
{
    if (challenge_running(id))
        return;
    if (g_challengeEnd[id])
        draw_challenge(id);
    if (!min(g_targetCount, enabled_target_capacity()))
    {
        client_print(id, print_center, "Enable at least one target");
        return;
    }

    g_shotFlags[id] = 0;
    g_shots[id] = 0;
    g_hits[id] = 0;
    g_kills[id] = 0;
    g_headshots[id] = 0;
    g_challengeEnd[id] = get_gametime() + CHALLENGE_SECONDS;
    client_print(id, print_center, "60-second test started");
}

draw_challenge(id)
{
    if (!g_challengeEnd[id])
        return;

    new timeLeft = floatround(g_challengeEnd[id] - get_gametime(), floatround_ceil);
    if (timeLeft <= 0)
    {
        g_challengeEnd[id] = 0.0;
        new Float:accuracy = g_shots[id] ? float(g_hits[id]) * 100.0 / float(g_shots[id]) : 0.0;
        client_print(id, print_chat, "[Aim] 60s: %d kills, %d headshots, %d/%d shots hit (%.1f%%).",
            g_kills[id], g_headshots[id], g_hits[id], g_shots[id], accuracy);
        set_hudmessage(160, 248, 222, -1.0, 0.15, 0, 0.0, 7.0, 0.0, 0.5);
        ShowSyncHudMsg(id, g_challengeHud, "60s result^nKills %d | Headshots %d^nAccuracy %.1f%% (%d/%d)",
            g_kills[id], g_headshots[id], accuracy, g_hits[id], g_shots[id]);
        return;
    }

    set_hudmessage(160, 248, 222, -1.0, 0.075, 0, 0.0, 1.15, 0.0, 0.0);
    ShowSyncHudMsg(id, g_challengeHud, "%ds | Kills %d | HS %d", timeLeft, g_kills[id], g_headshots[id]);
}

public begin_shot_tracking(weapon)
{
    new id = pev(weapon, pev_owner);
    if (1 <= id <= MaxClients && !g_slotByClient[id] && challenge_running(id) && !g_shotDepth[id]++)
        g_shotFlags[id] = SHOT_TRACKED;
}

public on_fire_event(flags, id)
{
    if (1 <= id <= MaxClients && (g_shotFlags[id] & SHOT_TRACKED))
        g_shotFlags[id] |= SHOT_FIRED;
}

public end_shot_tracking(weapon)
{
    new id = pev(weapon, pev_owner);
    if (id < 1 || id > MaxClients || !g_shotDepth[id] || --g_shotDepth[id])
        return;

    if (g_shotFlags[id] & SHOT_FIRED)
    {
        g_shots[id]++;
        if (g_shotFlags[id] & SHOT_HIT)
            g_hits[id]++;
    }
    g_shotFlags[id] = 0;
}

public on_target_trace(victim, attacker, Float:damage, Float:direction[3], trace, damageBits)
{
    if (!g_slotByClient[victim] || attacker < 1 || attacker > MaxClients || g_slotByClient[attacker])
        return HAM_IGNORED;

    if (g_headOnly && (!(damageBits & DMG_BULLET) || get_tr2(trace, TR_iHitgroup) != HIT_HEAD))
        return HAM_SUPERCEDE;

    if ((damageBits & DMG_BULLET) && (g_shotFlags[attacker] & SHOT_TRACKED))
        g_shotFlags[attacker] |= SHOT_HIT;

    return HAM_IGNORED;
}

public on_target_damage(victim, inflictor, attacker, Float:damage, damageBits)
{
    if (g_headOnly && g_slotByClient[victim] && 1 <= attacker <= MaxClients
        && !g_slotByClient[attacker] && !(damageBits & DMG_BULLET))
        return HAM_SUPERCEDE;

    return HAM_IGNORED;
}

public record_challenge_kill()
{
    new attacker = read_data(1), victim = read_data(2);
    if (attacker < 1 || attacker > MaxClients || !g_slotByClient[victim]
        || g_slotByClient[attacker] || !challenge_running(attacker))
        return;

    g_kills[attacker]++;
    if (read_data(3))
        g_headshots[attacker]++;
}

public on_player_command(id, command, randomSeed)
{
    if (g_slotByClient[id] || !is_user_alive(id) || !is_playing_team(cs_get_user_team(id)))
        return FMRES_IGNORED;

    new buttons = get_uc(command, UC_Buttons);
    if (!(buttons & IN_ATTACK))
        g_toggleShotUsed[id] = false;

    if (!(buttons & IN_USE))
    {
        g_useHeld[id] = false;
        return FMRES_IGNORED;
    }
    if (g_useHeld[id])
        return FMRES_IGNORED;

    g_useHeld[id] = true;
    new Float:eye[3], Float:offset[3], Float:angles[3], Float:direction[3], Float:end[3], Float:hit[3];
    pev(id, pev_origin, eye);
    pev(id, pev_view_ofs, offset);
    get_uc(command, UC_ViewAngles, angles);
    angle_vector(angles, ANGLEVECTOR_FORWARD, direction);
    for (new axis; axis < 3; axis++)
    {
        eye[axis] += offset[axis];
        end[axis] = eye[axis] + direction[axis] * 88.0;
    }

    new button = trace_line(id, eye, end, hit);
    if (!use_panel(button, id))
        return FMRES_IGNORED;

    set_uc(command, UC_Buttons, buttons & ~IN_USE);
    return FMRES_HANDLED;
}

public on_panel_damage(button, inflictor, attacker, Float:damage, damageBits)
{
    if (button <= 0 || attacker < 1 || attacker > MaxClients || g_slotByClient[attacker]
        || !is_user_alive(attacker) || !is_playing_team(cs_get_user_team(attacker))
        || !(damageBits & DMG_BULLET))
        return HAM_IGNORED;

    return use_panel(button, attacker, true) ? HAM_SUPERCEDE : HAM_IGNORED;
}

bool:use_panel(button, id, bool:shot = false)
{
    if (button <= 0)
        return false;

    for (new choice; choice < sizeof g_buttonNames; choice++)
    {
        if (g_buttons[choice] != button)
            continue;

        if (choice < sizeof g_weapons)
        {
            g_weaponByClient[id] = choice;
            remove_task(TASK_EQUIP + id);
            set_task(0.1, "equip_player", TASK_EQUIP + id);
            client_print(id, print_center, "%s", g_weaponLabels[choice]);
        }
        else if (choice <= CONTROL_RUN || choice == CONTROL_STRAFE)
        {
            new newMode = choice == CONTROL_STRAFE ? BOT_STRAFE : choice - CONTROL_STAND;
            if (newMode != g_botMode)
            {
                g_botMode = newMode;
                g_lastBotStep = get_gametime();
                for (new bot = 1; bot <= MaxClients; bot++)
                    if (g_slotByClient[bot] && is_user_alive(bot))
                        position_bot(bot, g_slotByClient[bot]);
            }

            client_print(id, print_center, "Bots: %s", g_botModeNames[g_botMode]);
        }
        else if (choice <= CONTROL_PLUS)
        {
            new maxTargets = enabled_target_capacity();
            new active = min(g_targetCount, maxTargets);
            new change = choice == CONTROL_MINUS ? -1 : 1;
            new desired = clamp(active + change, 0, maxTargets);
            if (desired != active)
            {
                g_targetCount = desired;
                schedule_target_count();
            }
            client_print(id, print_center, "Bots: %d / %d", desired, maxTargets);
        }
        else
        {
            if (shot && g_toggleShotUsed[id])
                return true;
            if (shot)
                g_toggleShotUsed[id] = true;

            switch (choice)
            {
                case CONTROL_NEAR..CONTROL_FAR:
                {
                    new ring = choice - CONTROL_NEAR;
                    new bit = 1 << ring;
                    g_ringMask ^= bit;
                    schedule_target_count();
                    new maxTargets = enabled_target_capacity();
                    client_print(id, print_center, "%s: %s | Bots: %d / %d",
                        g_ringLabels[ring], (g_ringMask & bit) ? "ON" : "OFF",
                        min(g_targetCount, maxTargets), maxTargets);
                }
                case CONTROL_RANDOM:
                {
                    g_randomSpawns = !g_randomSpawns;
                    client_print(id, print_center, "Random respawns: %s", g_randomSpawns ? "ON" : "OFF");
                }
                case CONTROL_HEAD:
                {
                    g_headOnly = !g_headOnly;
                    client_print(id, print_center, "Headshots only: %s", g_headOnly ? "ON" : "OFF");
                }
                case CONTROL_TEST: start_challenge(id);
            }
            update_indicators();
        }
        return true;
    }

    return false;
}

public open_team_menu(id)
{
    if (!is_user_connected(id) || g_slotByClient[id])
        return PLUGIN_CONTINUE;

    set_ent_data(id, "CBasePlayer", "m_iMenu", CS_MENU_OFF);
    menu_display(id, g_teamMenu);
    return PLUGIN_HANDLED;
}

public on_team_choice(id, menu, item)
{
    if (item == 0)
        change_team(id, CS_TEAM_CT);
    else if (item == 1)
        change_team(id, CS_TEAM_T);
}

public on_stock_menu_choice(id)
{
    if (!is_user_connected(id) || g_slotByClient[id])
        return PLUGIN_CONTINUE;

    new previousMenu, activeMenu;
    if (player_menu_info(id, previousMenu, activeMenu) && activeMenu == g_teamMenu)
    {
        new key[4];
        read_argv(1, key, charsmax(key));
        new choice = str_to_num(key);
        if (choice == 1 || choice == 2)
        {
            menu_cancel(id);
            return change_team(id, choice == 1 ? CS_TEAM_CT : CS_TEAM_T);
        }
        return PLUGIN_CONTINUE;
    }

    new menu = get_ent_data(id, "CBasePlayer", "m_iMenu");
    if (menu != CS_MENU_CHOOSE_TEAM && menu != CS_MENU_CHANGE_TEAM)
        return PLUGIN_CONTINUE;

    return on_jointeam(id);
}

public on_jointeam(id)
{
    new team[4];
    read_argv(1, team, charsmax(team));
    new choice = str_to_num(team);
    if (choice == _:CS_TEAM_CT || choice == CS_TEAM_AUTOSELECT)
        return change_team(id, CS_TEAM_CT);
    if (choice == _:CS_TEAM_T)
        return change_team(id, CS_TEAM_T);

    return PLUGIN_CONTINUE;
}

public switch_to_ct(id)
{
    return change_team(id, CS_TEAM_CT);
}

bool:is_playing_team(CsTeams:team)
{
    return team == CS_TEAM_CT || team == CS_TEAM_T;
}

change_team(id, CsTeams:team)
{
    if (!is_user_connected(id) || g_slotByClient[id])
        return PLUGIN_CONTINUE;

    if (is_user_alive(id))
    {
        if (cs_get_user_team(id) == team)
            return PLUGIN_HANDLED;

        user_silentkill(id);
    }

    remove_task(TASK_RESPAWN + id);
    cs_set_user_team(id, team, team == CS_TEAM_CT ? CS_CT_URBAN : CS_T_LEET);
    set_ent_data(id, "CBasePlayer", "m_iJoiningState", CS_JOINED);
    set_ent_data(id, "CBasePlayer", "m_iMenu", CS_MENU_OFF);
    ExecuteHamB(Ham_CS_RoundRespawn, id);
    return PLUGIN_HANDLED;
}

public on_killed(id, attacker, shouldGib)
{
    if (!g_slotByClient[id] && !is_playing_team(cs_get_user_team(id)))
        return;

    remove_task(TASK_RESPAWN + id);
    set_task(RESPAWN_DELAY, "respawn_player", TASK_RESPAWN + id);
    if (!g_slotByClient[id])
        return;

    set_pev(id, pev_effects, pev(id, pev_effects) | EF_NODRAW);
    g_relocateOnSpawn[id] = g_randomSpawns;
    if (g_relocateOnSpawn[id])
        pev(id, pev_origin, g_deathOrigin[id]);

    if (1 <= attacker <= MaxClients && is_user_alive(attacker)
        && !g_slotByClient[attacker] && is_playing_team(cs_get_user_team(attacker)))
    {
        new choice = g_weaponByClient[attacker];
        if (user_has_weapon(attacker, g_weaponIds[choice]))
            cs_set_user_bpammo(attacker, g_weaponIds[choice], g_reserveAmmo[choice]);
    }
}

public respawn_player(task)
{
    new id = task - TASK_RESPAWN;
    if (is_user_connected(id) && !is_user_alive(id)
        && (g_slotByClient[id] || is_playing_team(cs_get_user_team(id))))
        ExecuteHamB(Ham_CS_RoundRespawn, id);
}

public client_disconnected(id)
{
    new slot = g_slotByClient[id];
    if (slot)
    {
        g_clientBySlot[slot] = 0;
        if (g_activeSlots[slot])
            schedule_target_count();
    }

    g_slotByClient[id] = 0;
    g_weaponByClient[id] = 0;
    g_primaryChoice[id] = 0;
    g_secondaryChoice[id] = USP_CHOICE;
    g_useHeld[id] = false;
    g_toggleShotUsed[id] = false;
    g_relocateOnSpawn[id] = false;
    g_challengeEnd[id] = 0.0;
    g_shotFlags[id] = 0;
    g_shotDepth[id] = 0;
    g_hideTimerPending[id] = false;
    remove_task(TASK_RESPAWN + id);
    remove_task(TASK_EQUIP + id);
}
