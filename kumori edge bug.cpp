bool Movement::edgebug_check(CUserCmd* cmd)
{
    if (!g_LocalPlayer || !g_LocalPlayer->IsAlive() || !g_EngineClient->IsInGame() || !g_EngineClient->IsConnected())
    {
        return false;
    }

    if (const auto mt = g_LocalPlayer->m_nMoveType(); mt == MOVETYPE_LADDER || mt == MOVETYPE_NOCLIP)
    {
        return false;
    }

    static auto sv_gravity = g_CVar->FindVar("sv_gravity");
    // first 5.62895 second 8.293333
    if (edgebug_velocity_backup.z < -5.62895 && g_LocalPlayer->m_vecVelocity().z > edgebug_velocity_backup.z && g_LocalPlayer->m_vecVelocity().z < -8.293333)
    {
        float previous_velocity = g_LocalPlayer->m_vecVelocity().z;
        const float gravity_velocity_constant = round(-sv_gravity->GetFloat() * g_GlobalVars->interval_per_tick + previous_velocity);

        engine_prediction::Get().Repredict(cmd);
        engine_prediction::Get().Restore();

        if (gravity_velocity_constant == round(g_LocalPlayer->m_vecVelocity().z) && g_LocalPlayer->m_nMoveType() != MOVETYPE_LADDER)
        {
            return true;
        }
    }

    float gravity_vel = (sv_gravity->GetFloat() * 0.5f * g_GlobalVars->interval_per_tick);

    if (edgebug_velocity_backup.z < -gravity_vel && round(g_LocalPlayer->m_vecVelocity().z) == -round(gravity_vel) && g_LocalPlayer->m_nMoveType() != MOVETYPE_LADDER)
    {
        return true;
    }

    return false;
}

void Movement::edgebug_pre_pred(CUserCmd* cmd)
{
    if (!g_LocalPlayer)
        return;

    edgebug_flags_backup = g_LocalPlayer->m_fFlags();
    edgebug_velocity_backup = g_LocalPlayer->m_vecVelocity();
    pixelsurf_flags_backup = g_LocalPlayer->m_fFlags();
    pixelsurf_velocity_backup = g_LocalPlayer->m_vecVelocity();

    if ((edgebug_should && should_duck_next) || (pixelsurf_should && pixelsurf_should_duck_next))
    {
        cmd->buttons |= IN_DUCK;
    }
}

void Movement::edgebug_lock(float& x, float& y)
{
    if (!g_Options.movement.edgebug2.enable || !GetAsyncKeyState(g_Options.movement.edgebug2.key))
    {
        edgebug_should = false;
        return;
    }

    if (!g_LocalPlayer || !g_LocalPlayer->IsAlive() || !g_EngineClient->IsInGame() || !g_EngineClient->IsConnected())
    {
        edgebug_should = false;
        return;
    }

    if (const auto fg = g_LocalPlayer->m_fFlags(); fg == FL_INWATER || fg == FL_WATERJUMP)
    {
        edgebug_should = false;
        return;
    }

    if (const auto mt = g_LocalPlayer->m_nMoveType(); mt == MOVETYPE_LADDER || mt == MOVETYPE_NOCLIP)
    {
        edgebug_should = false;
        return;
    }

    if (edgebug_should)
    {
        if (x != 0.0)
        {
            float v3 = (float)(edgebug_prediction_timestamp + edgebug_prediction_ticks - g_GlobalVars->tickcount) / x;
            float v4 = 100.0 / (atan2f(edgebug_prediction_ticks, v3) + 100.0 + (float)(g_Options.movement.edgebug2.mouselock * edgebug_mouse_offset));
            if (!isnan(v4))
                x = x * v4;
        }
    }
}

void Movement::edgebug_post_pred(CUserCmd* cmd)
{
    if (!g_Options.movement.edgebug2.enable || !GetAsyncKeyState(g_Options.movement.edgebug2.key))
    {
        edgebug_should = false;
        return;
    }

    if (!g_LocalPlayer || !g_LocalPlayer->IsAlive() || !g_EngineClient->IsInGame() || !g_EngineClient->IsConnected())
    {
        edgebug_should = false;
        return;
    }

    if (const auto fg = g_LocalPlayer->m_fFlags(); fg == FL_INWATER || fg == FL_WATERJUMP)
    {
        edgebug_should = false;
        return;
    }

    if (const auto mt = g_LocalPlayer->m_nMoveType(); mt == MOVETYPE_LADDER || mt == MOVETYPE_NOCLIP)
    {
        edgebug_should = false;
        return;
    }

    struct movement_vars_t
    {
        Vector viewangles;
        Vector view_delta;
        float forwardmove;
        float sidemove;
        int buttons;
    };

    static movement_vars_t bmove;
    movement_vars_t omove;
    omove.viewangles = cmd->viewangles;
    omove.view_delta = (cmd->viewangles - edgebug_old_viewangles);
    omove.forwardmove = cmd->forwardmove;
    omove.sidemove = cmd->sidemove;
    omove.buttons = cmd->buttons;

    if (!edgebug_should)
    {
        bmove = omove;
    }

    Vector current_angles;

    int pred_cap = g_Options.movement.edgebug2.tick;
    int edgebug_pred_cound = 0;
    float highest_ground = 0.f;
    int search_dir = 0;
    int last_pred_ground = 0;
    int predict_amount = g_Options.movement.edgebug2.tick;

    for (int t = 0; edgebug_pred_cound < pred_cap; t++)
    {
        memory->restoreEntityToPredictedFrame(0, g_Prediction->m_nCommandsPredicted() - 1);
        edgebug_velocity_backup = g_LocalPlayer->m_vecVelocity();

        static int last_type = 0;

        if (edgebug_should)
        {
            t = last_type;
        }

        bool do_strafe = g_Options.movement.edgebug2.strafeassist && (t < 2 || t > 3);
        bool do_duck = t == 1 || t == 3;

        if (t > 3)
        {
            if (last_pred_ground < 2)
                break;

            bmove.view_delta += (bmove.view_delta / 2) * search_dir;
        }

        current_angles = bmove.viewangles;

        for (int i = 0; i < predict_amount && edgebug_pred_cound < pred_cap; i++)
        {
            if (do_strafe)
            {
                current_angles += bmove.view_delta;
                cmd->forwardmove = bmove.forwardmove;
                cmd->sidemove = bmove.sidemove;

                Vector backup_viewangles = cmd->viewangles;
                cmd->viewangles = current_angles;
                Math::start_movement_fix(cmd);
                cmd->viewangles = backup_viewangles;
                Math::end_movement_fix(cmd);
            }
            else
            {
                cmd->forwardmove = 0.f;
                cmd->sidemove = 0.f;
            }

            if (do_duck)
            {
                cmd->buttons |= IN_DUCK;
            }
            else
            {
                cmd->buttons &= ~IN_DUCK;
            }

            engine_prediction::Get().Repredict(cmd);
            edgebug_should = edgebug_check(cmd);
            edgebug_velocity_backup = g_LocalPlayer->m_vecVelocity();
            engine_prediction::Get().Restore();

            edgebug_pred_cound++;

            if (!edgebug_should && t > 3 && g_LocalPlayer->m_vecOrigin().z < highest_ground)
            {
                search_dir = -1;
                break;
            }

            if (g_LocalPlayer->m_fFlags() & 1)
            {
                if (t == 0)
                {
                    highest_ground = g_LocalPlayer->m_vecOrigin().z;
                }

                if (t == 2)
                {
                    search_dir = g_LocalPlayer->m_vecOrigin().z < highest_ground ? -1 : 1;
                }

                if (t > 3)
                {
                    search_dir = 1;

                    if (g_LocalPlayer->m_vecOrigin().z < highest_ground)
                    {
                        search_dir = -1;
                    }
                    else
                    {
                        highest_ground = g_LocalPlayer->m_vecOrigin().z;
                    }
                }

                last_pred_ground = i;

                break;
            }

            if (g_LocalPlayer->m_nMoveType() == MOVETYPE_LADDER)
            {
                break;
            }

            if (edgebug_should)
            {
                if (t < 4)
                {
                    last_type = t;
                }
                else
                {
                    last_type = 0;
                }

                should_duck_next = do_duck;

                if (do_strafe)
                {
                    cmd->forwardmove = bmove.forwardmove;
                    cmd->sidemove = bmove.sidemove;
                    cmd->viewangles = bmove.viewangles + bmove.view_delta;
                    bmove.viewangles = cmd->viewangles;
                }

                edgebug_tick = g_GlobalVars->tickcount + (i + 1);
                edgebug_prediction_ticks = predict_amount;
                edgebug_prediction_timestamp = g_GlobalVars->tickcount;
                edgebug_mouse_offset = std::abs(cmd->mousedx);

                return;
            }
        }
    }

    cmd->viewangles = omove.viewangles;
    cmd->forwardmove = omove.forwardmove;
    cmd->sidemove = omove.sidemove;
    cmd->buttons = omove.buttons;
}

struct DATAFORDETECT
{
    Vector velocity;
    bool onground;
};

std::deque<DATAFORDETECT> VelocitiesForDetection;

void Movement::edgebug_detect(CUserCmd* cmd)
{
    if (!g_Options.movement.edgebug2.enable || !GetAsyncKeyState(g_Options.movement.edgebug2.key))
    {
        edgebug = false;
        return;
    }

    if (!g_LocalPlayer || !g_LocalPlayer->IsAlive() || !g_EngineClient->IsInGame() || !g_EngineClient->IsConnected())
    {
        edgebug = false;
        edgebug_amount = 0;
        return;
    }

    if (const auto fg = g_LocalPlayer->m_fFlags(); fg == FL_INWATER || fg == FL_WATERJUMP)
    {
        edgebug = false;
        return;
    }

    if (const auto mt = g_LocalPlayer->m_nMoveType(); mt == MOVETYPE_LADDER || mt == MOVETYPE_NOCLIP)
    {
        edgebug = false;
        return;
    }

    DATAFORDETECT d;
    d.velocity = g_LocalPlayer->m_vecVelocity();
    d.onground = g_LocalPlayer->m_fFlags() & FL_ONGROUND;

    VelocitiesForDetection.push_front(d);

    if (VelocitiesForDetection.size() > 2)
        VelocitiesForDetection.pop_back();

    static auto sv_Gravity = g_CVar->FindVar("sv_gravity");
    float negativezvel = sv_Gravity->GetFloat() * -0.5f * g_GlobalVars->interval_per_tick;

    if (VelocitiesForDetection.size() == 2 && ((round(negativezvel * 100.f) == round(VelocitiesForDetection.at(0).velocity.z * 100.f) && VelocitiesForDetection.at(1).velocity.z < negativezvel && !VelocitiesForDetection.at(1).onground && !VelocitiesForDetection.at(0).onground) || edgebug_tick == g_GlobalVars->tickcount))
    {
        VelocitiesForDetection.clear();

        edgebug_amount++;
        edgebug = true;

        auto g_ChatElement = FindHudElement<C_BasePlayer::C_BaseHudChat>("CHudChat");

        if (g_Options.movement.edgebug2.detect.chat.enable)
        {
            std::string randomcolor[16] = { (" \x01"),  (" \x02"),  (" \x03"),  (" \x04"),  (" \x05"),  (" \x06"),  (" \x07"),  (" \x08"),  (" \x09"),  (" \x10"),  (" \x0A"),  (" \x0B"),  (" \x0C"),  (" \x0D"),  (" \x0E"),  (" \x0F") };

            std::string picked_color;

            if (g_Options.movement.edgebug2.detect.chat.rainbow)
            {
                picked_color = (randomcolor[RandomInt(0, 15)]);
            }
            else
            {
                picked_color = (randomcolor[g_Options.movement.edgebug2.detect.chat.color]);
            }

            std::string type;

            if (!(g_LocalPlayer->m_fFlags() & FL_DUCKING))
            {
                type = "standing";
            }
            else
            {
                type = "ducking";
            }

            g_ChatElement->ChatPrintf(0, 0, std::string("").
                append(picked_color).
                append("kumori").
                append("\x01").
                append(" | ").
                append("edgebugged").
                append(" | ").
                append("count: ").
                append(picked_color).
                append(std::to_string(edgebug_amount)).
                append("\x01").
                append(" | ").
                append("mouse offset:").
                append(picked_color).
                append(std::to_string(edgebug_mouse_offset)).
                append("\x01").
                append(" | ").
                append("type:").
                append(picked_color).
                append(type).c_str());
        }

        if (g_Options.movement.edgebug2.detect.sound.enable)
        {
            switch (g_Options.movement.edgebug2.detect.sound.type)
            {
            case 0: g_EngineSound->EmitAmbientSound("ui\\beep07.wav", g_Options.movement.edgebug2.detect.sound.volume); break;
            case 1: g_EngineSound->EmitAmbientSound("survival\\money_collect_01.wav", g_Options.movement.edgebug2.detect.sound.volume); break;
            case 2: g_EngineSound->EmitAmbientSound("physics\\metal\\metal_solid_impact_bullet2.wav", g_Options.movement.edgebug2.detect.sound.volume); break;
            case 3: g_EngineSound->EmitAmbientSound("buttons\\arena_switch_press_02.wav", g_Options.movement.edgebug2.detect.sound.volume); break;
            case 4: g_EngineSound->EmitAmbientSound("training\\timer_bell.wav", g_Options.movement.edgebug2.detect.sound.volume); break;
            case 5: g_EngineSound->EmitAmbientSound("physics\\glass\\glass_impact_bullet1.wav", g_Options.movement.edgebug2.detect.sound.volume); break;
            }
        }

        if (g_Options.movement.edgebug2.detect.effect.enable)
        {
            g_LocalPlayer->HealthShotBoost() = g_GlobalVars->curtime + g_Options.movement.edgebug2.detect.effect.time;
        }
    }
    else
    {
        edgebug = false;
    }
}

void Movement::edgebug_counter()
{
    if (!g_Options.movement.edgebug2.detect.counter.enable)
    {
        return;
    }

    if (!g_LocalPlayer || !g_LocalPlayer->IsAlive() || !g_EngineClient->IsInGame() || !g_EngineClient->IsConnected())
    {
        return;
    }

    int w, h;
    g_EngineClient->GetScreenSize(w, h);

    Render::Get().RenderText("eb's: " + std::to_string(edgebug_amount), w / 2, h - g_Options.movement.edgebug2.detect.counter.pos,  15.f, Color(g_Options.movement.edgebug2.detect.counter.color[0], g_Options.movement.edgebug2.detect.counter.color[1], g_Options.movement.edgebug2.detect.counter.color[2]), true, false, true, false, g_CounterFont);
}

static auto fromAngle(const Vector& angle) noexcept
{
    return Vector{ std::cos(DEG2RAD(angle.x)) * std::cos(DEG2RAD(angle.y)), std::cos(DEG2RAD(angle.x)) * std::sin(DEG2RAD(angle.y)), -std::sin(DEG2RAD(angle.x)) };
}
