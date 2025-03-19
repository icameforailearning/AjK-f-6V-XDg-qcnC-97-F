void c_movement::edge_bug(c_usercmd* cmd)
{
    if (!vars.movement.edge_bug.properstate())
    {
        game->detectdata.detecttick = 0;
        game->detectdata.edgebugtick = 0;
        return;
    }

    const int move_type = game->local->movetype();

    if ((engine_prediction->backup.flags & 1) || move_type == MOVETYPE_NOCLIP || move_type == MOVETYPE_OBSERVER || move_type == MOVETYPE_LADDER)
    {
        game->detectdata.detecttick = 0;
        game->detectdata.edgebugtick = 0;
        return;
    }

    if (interfaces::global_vars->tick_count >= game->detectdata.detecttick && interfaces::global_vars->tick_count <= game->detectdata.edgebugtick)
    {

        if (game->detectdata.crouched)
            cmd->buttons |= IN_DUCK;
        else
            cmd->buttons &= ~IN_DUCK;


        if (game->detectdata.strafing)
        {
            cmd->forward_move = game->detectdata.forwardmove;
            cmd->side_move = game->detectdata.sidemove;
            cmd->view_angles.y = Math::NormalizeYaw(game->detectdata.startingyaw + (game->detectdata.yawdelta * (interfaces::global_vars->tick_count - game->detectdata.detecttick))); // extrapolate the viewangle using a static delta and the amount of ticks that have passed from detection
            interfaces::engine->SetViewangles(
        }
        else
        {
            cmd->forward_move = 0.f;
            cmd->side_move = 0.f;
        }


        return;
    }

    Vector originalpos = engine_prediction->backup.origin;
    Vector originalvel = engine_prediction->backup.velocity;
    int originalflags = engine_prediction->backup.flags;
    float originalfmove = cmd->forward_move;
    float originalsmove = cmd->side_move;
    Vector originalangles = cmd->view_angles;

    int ticklimit = TIME_TO_TICKS(vars.movement.edge_bug_time);
    const float m_yaw = interfaces::cvar->FindVar("m_yaw")->GetFloat();
    const float sensitivity = interfaces::cvar->FindVar("sensitivity")->GetFloat();
    float yawdelta = std::clamp(cmd->mouse_dx * m_yaw * sensitivity, -180.f, 180.f);

    //prediction

    if (interfaces::global_vars->tick_count < game->detectdata.detecttick || interfaces::global_vars->tick_count > game->detectdata.edgebugtick)
    {
        const int desiredrounds = (vars.movement.edge_bug_strafing && (yawdelta != 0.f) ? 4 : 2);
        const auto sv_gravity = interfaces::cvar->FindVar("sv_gravity");
        float gv = sv_gravity->GetFloat();

        for (int predRound = 0; predRound < desiredrounds; predRound++)
        {

            interfaces::prediction->restore_entity_to_predicted_frame(0, interfaces::prediction->Split->nCommandsPredicted - 1);

            //create desired cmd
            c_usercmd predictcmd = *cmd;

            game->detectdata.startingyaw = originalangles.y;

            if (predRound == 0)
            {
                game->detectdata.crouched = true;
                predictcmd.buttons |= IN_DUCK;
                game->detectdata.strafing = false;
                predictcmd.forward_move = 0.f;
                predictcmd.side_move = 0.f;

            }
            else if (predRound == 1)
            {
                game->detectdata.crouched = false;
                predictcmd.buttons &= ~IN_DUCK;
                game->detectdata.strafing = false;
                predictcmd.forward_move = 0.f;
                predictcmd.side_move = 0.f;

            }
            else if (predRound == 2)
            {
                game->detectdata.crouched = true;
                predictcmd.buttons |= IN_DUCK;
                game->detectdata.strafing = true;
                predictcmd.forward_move = originalfmove;
                predictcmd.side_move = originalsmove;
            }
            else if (predRound == 3)
            {
                game->detectdata.crouched = false;
                predictcmd.buttons &= ~IN_DUCK;
                game->detectdata.strafing = true;
                predictcmd.forward_move = originalfmove;
                predictcmd.side_move = originalsmove;
            }


            detectionpositions.clear();
            detectionpositions.push_back(std::pair<Vector, Vector>(game->local->origin(), game->local->velocity()));




            for (int ticksPredicted = 0; ticksPredicted < ticklimit; ticksPredicted++)
            {
                Vector old_velocity = game->local->velocity();
                int old_flags = game->local->flags();
                Vector old_pos = game->local->origin();

                if (game->detectdata.strafing)
                {
                    predictcmd.view_angles.y = Math::NormalizeYaw(originalangles.y + (yawdelta * ticksPredicted));
                }



                engine_prediction->start(&predictcmd); // predict 1 more tick
                Vector predicted_velocity = game->local->velocity();
                int predicted_flags = game->local->flags();
                detectionpositions.push_back(std::pair<Vector, Vector>(game->local->origin(), game->local->velocity()));
                engine_prediction->end();


                if ((old_flags & 1) || (predicted_flags & 1) || round(predicted_velocity.Length2D()) == 0.f || round(old_velocity.Length2D()) == 0.f || game->local->movetype() == MOVETYPE_LADDER || old_velocity.z > 0.f)
                {
                    game->detectdata.detecttick = 0;
                    game->detectdata.edgebugtick = 0;
                    break;
                }

                if (detectionpositions.size() > 2)
                {
                    if (actualebdetection(detectionpositions.at(detectionpositions.size() - 3).second, detectionpositions.at(detectionpositions.size() - 2).second, detectionpositions.at(detectionpositions.size() - 1).second, gv))
                    {

                        game->detectdata.detecttick = interfaces::global_vars->tick_count;
                        game->detectdata.edgebugtick = interfaces::global_vars->tick_count + (ticksPredicted);
                        game->detectdata.eblength = ticksPredicted;
                        game->detectdata.forwardmove = originalfmove;
                        game->detectdata.sidemove = originalsmove;
                        ebpos = game->local->origin();
                        game->detectdata.yawdelta = yawdelta;

                        if (predRound < 2)
                        {
                            cmd->forward_move = 0.f;
                            cmd->side_move = 0.f;
                        }
                        else
                        {
                            cmd->forward_move = originalfmove;
                            cmd->side_move = originalsmove;
                            cmd->view_angles.y = originalangles.y;

                        }

                        if (predRound == 0 || predRound == 2)
                        {
                            cmd->buttons |= IN_DUCK;
                        }
                        else
                        {
                            cmd->buttons &= ~IN_DUCK;
                        }

                        return;
                    }

                }
            }
        }

    }
}