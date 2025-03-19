void BunnyHop::egbag(CUserCmd* pCmd, QAngle& angView)
{// this method of doing it is kinda autistic and I know the code is a bit of clusterfuck but whatever
	
	if (!GetAsyncKeyState(g_Options.edge_bug_key) )
		return;
	auto pLocal = g_LocalPlayer;

	if (iFlagsBackup & FL_ONGROUND)
		return; // imagine trying to edgebug while we on the ground lol (protip: u cunt)

	bShouldEdgebug = backupvelocity.z < -flBugSpeed && round(pLocal->m_vecVelocity().z) == -round(flBugSpeed) && pLocal->m_nMoveType() != MOVETYPE_LADDER;
	if (bShouldEdgebug) // we literally boutta bug on da edge lol
		return;

	int nCommandsPredicted = g_Prediction->Split->nCommandsPredicted;

	// backup original stuff that we change so we can restore later if no edgebug detek
	QAngle angViewOriginal = angView;
	QAngle angCmdViewOriginal = pCmd->viewangles;
	int iButtonsOriginal = pCmd->buttons;
	Vector vecMoveOriginal;
	vecMoveOriginal.x = pCmd->sidemove;
	vecMoveOriginal.y = pCmd->forwardmove;

	// static static static static static
	static Vector vecMoveLastStrafe;
	static QAngle angViewLastStrafe;
	static QAngle angViewOld = angView;
	static QAngle angViewDeltaStrafe;
	static bool bAppliedStrafeLast = false;
	if (!bAppliedStrafeLast)
	{// we didn't strafe last time so it's safe to update these, if we did strafe we don't want to change them ..
		angViewLastStrafe = angView;
		vecMoveLastStrafe = vecMoveOriginal;
	
			angViewDeltaStrafe = QAngle(angView.pitch - angViewOld.pitch, std::clamp(pCmd->viewangles.yaw - angViewOld.yaw, -(180.f / 128.f), 180.f / 128.f), 0.f);
		angViewDeltaStrafe;
	}
	bAppliedStrafeLast = false;
	angViewOld = angView;
	
	for (int t = 0; t < 4; t++)
	{
		static int iLastType;
		if (iLastType)
		{
			t = iLastType;
			iLastType = 0;
		}
		memesclass->restoreEntityToPredictedFrame(0, nCommandsPredicted - 1); // reset player to before engine prediction was ran (-1 because this whole function is only called after pred in cmove)
		if (iButtonsOriginal& IN_DUCK&& t < 2) // if we already unducking then don't unduck pusi
			t = 2;
		bool bApplyStrafe = !(t % 2); // t == 0 || t == 2
		bool bApplyDuck = t > 1;

		// set base cmd values that we need
		pCmd->viewangles = angViewLastStrafe;
		pCmd->buttons = iButtonsOriginal;
		pCmd->sidemove = vecMoveLastStrafe.x;
		pCmd->forwardmove = vecMoveLastStrafe.y;

		for (int i = 0; i < 64; i++)
		{
			// apply cmd changes for prediction
			if (bApplyDuck)
				pCmd->buttons |= IN_DUCK;
			else
				pCmd->buttons &= ~IN_DUCK;
			if (bApplyStrafe)
			{
				pCmd->viewangles += angViewDeltaStrafe;
				pCmd->viewangles.normalize();
				pCmd->viewangles.Clamp();
			}
			else
			{
				pCmd->sidemove = 0.f;
				pCmd->forwardmove = 0.f;
			}
			Vector PrePredVelocity = g_LocalPlayer->m_vecVelocity();
			// run prediction

			prediction->StartPrediction(pCmd);
			prediction->EndPrediction();
			float RaznVelocity = PrePredVelocity.z - g_LocalPlayer->m_vecVelocity().z;
			Vector VeloDelta = (g_LocalPlayer->m_vecVelocity().toAngle() - PrePredVelocity.toAngle()).normalize();
			bShouldEdgebug = floor(g_LocalPlayer->m_vecVelocity().z) > floor(PrePredVelocity.z) && PrePredVelocity.z * 0.25f > RaznVelocity && VeloDelta.y < 45.f && !(pLocal->m_fFlags() & 1) && backupvelocity.z < -round(flBugSpeed) && pLocal->m_vecVelocity().z < 0.f && hypotf(PrePredVelocity.x, PrePredVelocity.y) < hypotf(g_LocalPlayer->m_vecVelocity().x, g_LocalPlayer->m_vecVelocity().y);
			backupvelocity.z = pLocal->m_vecVelocity().z;
			if (!bShouldEdgebug)
				bShouldEdgebug = backupvelocity.z < -flBugSpeed && round(pLocal->m_vecVelocity().z) == -round(flBugSpeed) && pLocal->m_nMoveType() != MOVETYPE_LADDER;
			if (bShouldEdgebug)
			{
				
				iEdgebugButtons = pCmd->buttons; // backup iButtons state
				if (bApplyStrafe)
				{// if we hit da bug wit da strafe we gotta make sure we strafe right
					bAppliedStrafeLast = true;
					angView = (angViewLastStrafe + angViewDeltaStrafe);
					angView.normalize();
					angView.Clamp();
					angViewLastStrafe = angView;
					pCmd->sidemove = vecMoveLastStrafe.x;
					pCmd->forwardmove = vecMoveLastStrafe.y;
				}
				/* restore angViewPoint back to what it was, we only modified it for prediction purposes
				*  we use movefix instead of changing angViewPoint directly
				*  so we have pSilent pEdgebug (perfect-silent; prediction-edgebug) ((lol))
				*/
				pCmd->viewangles = angCmdViewOriginal;
				iLastType = t;
				return;
			}

			if (pLocal->m_fFlags() & FL_ONGROUND || pLocal->m_nMoveType() == MOVETYPE_LADDER)
				break;
		}
	}

	/* if we got this far in the function then we won't hit an edgebug in any of the predicted scenarios
	*  so we gotta restore everything back to what it was originally
	*/
	pCmd->viewangles = angCmdViewOriginal;
	angView = angViewOriginal;
	pCmd->buttons = iButtonsOriginal;
	pCmd->sidemove = vecMoveOriginal.x;
	pCmd->forwardmove = vecMoveOriginal.y;
}