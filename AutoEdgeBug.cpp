void MOVEMENT::AutoEdgeBug(CCSPlayer* pLocal, CUserCmd* pCmd)
{
	// Check if edgebug key is set and being held
	if (!IPT::GetBindState(C::Get<KeyBind_t>(Vars.keyMiscAutoEdgeBug)))
		return;
 
	if (!pLocal || !pLocal->IsAlive())
		return;
 
	// Get velocity and check if we're falling
	const Vector_t vecVelocity = pLocal->GetVelocity();
	const float flFallSpeed = std::abs(vecVelocity.z);
	
	// Only try to edgebug at reasonable speeds
	if (flFallSpeed < 100.0f)
		return;
 
	ICollideable* pCollideable = pLocal->GetCollideable();
	if (!pCollideable)
		return;
 
	// Get player's mins and maxs
	const Vector_t& vecMins = pCollideable->OBBMins();
	const Vector_t& vecMaxs = pCollideable->OBBMaxs();
 
	// Constants for prediction
	constexpr float GRAVITY = 800.0f;
	constexpr float EDGE_DISTANCE = 2.0f;
	constexpr float AIR_ACCELERATION = 12.0f;
	constexpr int PREDICTION_TICKS = 16; // Shorter, more precise prediction
	
	// Store original input for restoration
	static Vector_t vecLastValidMove;
	static QAngle_t angLastValidView;
	static Vector_t vecLastEdgeNormal;
	
	// Get current state
	Vector_t vecCurrentPos = pLocal->GetAbsOrigin();
	Vector_t vecCurrentVel = vecVelocity;
	const float flTickInterval = I::Globals->flIntervalPerTick;
 
	// Store best prediction results
	float flBestDistance = FLT_MAX;
	Vector_t vecBestPos;
	Vector_t vecBestVel;
	Vector_t vecBestNormal;
	bool bWillHitEdge = false;
	int nTicksToEdge = 0;
 
	// Precise edge prediction
	for (int i = 0; i < PREDICTION_TICKS; i++)
	{
		// Apply gravity
		vecCurrentVel.z -= (GRAVITY * flTickInterval);
 
		// Apply air acceleration
		if (std::abs(pCmd->flForwardMove) > 0.0f || std::abs(pCmd->flSideMove) > 0.0f)
		{
			float flSpeed = vecCurrentVel.Length2D();
			if (flSpeed > 0.0f)
			{
				float flNewSpeed = flSpeed + (AIR_ACCELERATION * flTickInterval);
				float flScale = flNewSpeed / flSpeed;
				vecCurrentVel.x *= flScale;
				vecCurrentVel.y *= flScale;
			}
		}
 
		// Predict next position
		Vector_t vecNextPos = vecCurrentPos + (vecCurrentVel * flTickInterval);
 
		// Check 4 corners and center for edge detection
		const Vector_t vecOffsets[] = {
			Vector_t(0, 0, 0),  // Center
			Vector_t(EDGE_DISTANCE, EDGE_DISTANCE, 0),  // Front-Right
			Vector_t(EDGE_DISTANCE, -EDGE_DISTANCE, 0), // Front-Left
			Vector_t(-EDGE_DISTANCE, EDGE_DISTANCE, 0), // Back-Right
			Vector_t(-EDGE_DISTANCE, -EDGE_DISTANCE, 0) // Back-Left
		};
 
		bool bFoundEdge = false;
		Vector_t vecEdgeNormal;
		float flClosestFraction = 1.0f;
 
		for (const auto& offset : vecOffsets)
		{
			Vector_t vecTraceStart = vecNextPos + offset;
			
			// Ground trace
			Ray_t rayGround(vecTraceStart, vecTraceStart + Vector_t(0, 0, -EDGE_DISTANCE * 2.0f), vecMins, vecMaxs);
			CTraceFilterSimple filterGround(pLocal);
			Trace_t traceGround;
			I::EngineTrace->TraceRay(rayGround, MASK_PLAYERSOLID, &filterGround, &traceGround);
 
			// Forward trace in velocity direction
			Vector_t vecForward = vecCurrentVel.Normalized() * EDGE_DISTANCE;
			Ray_t rayForward(vecTraceStart + Vector_t(0, 0, -EDGE_DISTANCE * 2.0f),
							vecTraceStart + vecForward + Vector_t(0, 0, -EDGE_DISTANCE * 2.0f),
							vecMins, vecMaxs);
			Trace_t traceForward;
			I::EngineTrace->TraceRay(rayForward, MASK_PLAYERSOLID, &filterGround, &traceForward);
 
			if (traceGround.flFraction > 0.95f && traceForward.flFraction < 0.95f)
			{
				if (traceForward.flFraction < flClosestFraction)
				{
					flClosestFraction = traceForward.flFraction;
					vecEdgeNormal = traceForward.plane.vecNormal;
					bFoundEdge = true;
				}
			}
		}
 
		// Process edge detection results
		if (bFoundEdge && vecEdgeNormal.z < 0.7f)
		{
			float flDistToEdge = (vecNextPos - vecCurrentPos).Length2D();
			if (flDistToEdge < flBestDistance)
			{
				flBestDistance = flDistToEdge;
				vecBestPos = vecNextPos;
				vecBestVel = vecCurrentVel;
				vecBestNormal = vecEdgeNormal;
				bWillHitEdge = true;
				nTicksToEdge = i;
				vecLastEdgeNormal = vecEdgeNormal;
			}
		}
 
		vecCurrentPos = vecNextPos;
		vecCurrentVel = vecCurrentVel;
	}
 
	// If we predicted an edge hit
	if (bWillHitEdge)
	{
		// Store current input if we haven't yet
		if (!bLastEdgebug)
		{
			vecLastValidMove = Vector_t(pCmd->flForwardMove, pCmd->flSideMove, 0.0f);
			angLastValidView = pCmd->angViewPoint;
		}
 
		// Only activate edgebug when we're very close
		if (nTicksToEdge <= 2)
		{
			// Lock movement
			pCmd->flForwardMove = 0.0f;
			pCmd->flSideMove = 0.0f;
			pCmd->nButtons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP);
			pCmd->nButtons |= IN_DUCK;
			
			// Set optimal angle based on edge normal
			Vector_t vecIdealDir = (vecLastEdgeNormal * -1.0f).Normalized();
			float flYaw = std::atan2(vecIdealDir.y, vecIdealDir.x) * 180.0f / 3.141592653589793f;
			pCmd->angViewPoint.y = flYaw;
			pCmd->angViewPoint.x = 89.0f;
			
			bLastEdgebug = true;
			flLastEdgebugTime = I::Globals->flCurrentTime;
		}
	}
	else if (bLastEdgebug)
	{
		// Quick release after edgebug
		if (I::Globals->flCurrentTime - flLastEdgebugTime > 0.1f)
		{
			pCmd->flForwardMove = vecLastValidMove.x;
			pCmd->flSideMove = vecLastValidMove.y;
			pCmd->angViewPoint = angLastValidView;
			pCmd->nButtons &= ~IN_DUCK;
			bLastEdgebug = false;
		}
	}
}