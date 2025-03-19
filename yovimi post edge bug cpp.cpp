void misc::edgebug(UserCmd* pCmd)
{
    
    if (!(g_keyhandler.CheckKey(config.edgebugkey, config.edgebugkey_style)))
    {
        return;
    }



    if (g_keyhandler.CheckKey(config.edgebugkey, config.edgebugkey_style))
    {
        interfaces::console->FindVar("sv_min_jump_landing_sound")->SetValue("63464578");

    }
    else
    {
        interfaces::console->FindVar("sv_min_jump_landing_sound")->SetValue("260");
    }

    static bool edgebugging = false;
    static int edgebugging_tick = 0;

    if (!edgebugging) {
        int flags = g::pLocalPlayer->Flags();
        float z_velocity = floor(g::pLocalPlayer->Velocity().z);

        for (int i = 0; i < 64; i++) {
            // Run prediction
            prediction.Start(pCmd, g::pLocalPlayer);
            {

                // Check for edgebug
                if (z_velocity < -7 && floor(g::pLocalPlayer->Velocity().z) == -7 && !(flags & FL_ONGROUND) && g::pLocalPlayer->MoveType() != MOVETYPE_NOCLIP) {
                    edgebugging = true;
                    edgebugging_tick = g::pCmd->tick_count + i;
                    break;
                }
                else {
                    z_velocity = floor(g::pLocalPlayer->Velocity().z);
                    flags = g::pLocalPlayer->Flags();
                }
            }

            // End prediciton
            prediction.End(pCmd, g::pLocalPlayer);
        }
    }
    else {
        // Lock the movement however you want
        g::pCmd->sidemove = 0.f;
        g::pCmd->forwardmove = 0.f;
        g::pCmd->upmove = 0.f;
        g::pCmd->mousedx = 0.f;

        // Check if edgebug over
        if (g::pCmd->tick_count > edgebugging_tick) {
            edgebugging = false;
            edgebugging_tick = 0;
        }
    }
}