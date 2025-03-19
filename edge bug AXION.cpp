void F::MISC::MOVEMENT::EdgeBug(CCSPlayerController* controler, C_CSPlayerPawn* localPlayer, CUserCmd* cmd) {
	if (!C_GET(bool, Vars.edge_bug))
		return;

	if (!controler || !localPlayer || localPlayer->GetHealth() <= 0)
		return;

	C_CSPlayerPawn* pred = I::GameResourceService->pGameEntitySystem->Get<C_CSPlayerPawn>(controler->m_hPredictedPawn());
	if (!pred)
		return;

	static bool bhopWasEnabled = true;
	bool JumpDone;

	bool unduck = true;

	float max_radius = MATH::_PI * 2;
	float step = max_radius / 128;
	float xThick = 23;
	bool valid = GetAsyncKeyState(C_GET(KeyBind_t, Vars.edge_bug_key).uKey);
	if (!valid) {
		return;
	}

	if (valid) {
		I::Cvar->Find(FNV1A::Hash(CS_XOR("sv_min_jump_landing_sound")))->value.fl = 63464578.f;
	}
	else {
		I::Cvar->Find(FNV1A::Hash(CS_XOR("sv_min_jump_landing_sound")))->value.fl = 260;
	}

	static bool edgebugging = false;
	static int edgebugging_tick = 0;

	if (!edgebugging) {

		int flags = localPlayer->GetFlags();
		float z_velocity = floor(localPlayer->m_vecVelocity().z);

		for (int i = 0; i < 64; i++) {

			if (z_velocity < -7 && floor(localPlayer->m_vecVelocity().z) == -7 && !(flags & FL_ONGROUND) && localPlayer->GetMoveType() != MOVETYPE_NOCLIP) {
				edgebugging_tick = cmd->m_csgoUserCmd.m_pBaseCmd->m_nTickCount + i;

				edgebugging = true;
				break;
			}
			else {
				z_velocity = floor(localPlayer->m_vecVelocity().z);
				flags = localPlayer->GetFlags();
			}
		}
	}
	else {

		cmd->m_csgoUserCmd.m_pBaseCmd->m_flSideMove = 0.f;
		cmd->m_csgoUserCmd.m_pBaseCmd->m_flForwardMove = 0.f;
		cmd->m_csgoUserCmd.m_pBaseCmd->m_flUpMove = 0.f;
		cmd->m_csgoUserCmd.m_pBaseCmd->m_nMousedX = 0.f;
		cmd->m_nButtons.m_nValue |= IN_DUCK;

		if ((localPlayer->GetFlags() & 0x1)) {
			cmd->m_nButtons.m_nValue &= ~IN_JUMP;
		}

		Vector_t pos = localPlayer->GetSceneOrigin();

		for (float a = 0.f; a < max_radius; a += step) {
			Vector_t pt;
			pt.x = (xThick * cos(a)) + pos.x;
			pt.y = (xThick * sin(a)) + pos.y;
			pt.z = pos.z;

			Vector_t pt2 = pt;
			pt2.z -= 8192;
			trace_filter_t filter = {};
			I::Trace->Init(filter, localPlayer, 0x1400B, 3, 7);

			game_trace_t trace = {};
			ray_t ray = {};

			I::Trace->TraceShape(ray, &pt, &pt2, filter, trace);

			if (trace.Fraction != 1.0f && trace.Fraction != 0.0f) {
				JumpDone = true;
				cmd->m_nButtons.m_nValue |= IN_DUCK;
			}
		}


		if (cmd->m_csgoUserCmd.m_pBaseCmd->m_nTickCount > edgebugging_tick) {
			edgebugging = false;
			edgebugging_tick = 0;
		}

	}
	trace_filter_t filter = {};
	I::Trace->Init(filter, localPlayer, 0x1400B, 3, 7);

	Vector_t pos = localPlayer->GetSceneOrigin();
	if (pred->m_bInLanding()) {

		for (float a = 0.f; a < max_radius; a += step) {
			Vector_t pt;
			pt.x = (xThick * cos(a)) + pos.x;
			pt.y = (xThick * sin(a)) + pos.y;
			pt.z = pos.z;

			Vector_t pt2 = pt;
			pt2.z -= 8192;

			game_trace_t trace = {};
			ray_t ray = {};

			I::Trace->TraceShape(ray, &pt, &pt2, filter, trace);

			if (trace.Fraction != 1.0f && trace.Fraction != 0.0f) {
				JumpDone = true;


				cmd->m_csgoUserCmd.m_pBaseCmd->m_flSideMove = 0.f;
				cmd->m_csgoUserCmd.m_pBaseCmd->m_flForwardMove = 0.f;
				cmd->m_csgoUserCmd.m_pBaseCmd->m_flUpMove = 0.f;
				cmd->m_csgoUserCmd.m_pBaseCmd->m_nMousedX = 0.f;
				cmd->m_nButtons.m_nValue |= IN_DUCK;

				if ((localPlayer->GetFlags() & 0x1)) {
					cmd->m_nButtons.m_nValue &= ~IN_JUMP;
				}

			}
		}

	}
	if (cmd->m_csgoUserCmd.m_pBaseCmd->m_nTickCount > edgebugging_tick) {
		edgebugging = false;
		edgebugging_tick = 0;
	}
}