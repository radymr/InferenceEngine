class CorpAIController extends AIController;

var CorpGame    CorpGameInfo;
var CorpPawn    ThisPawn;

// Objective Variables
var CorpPawn    TargetPawnObjective;
var int         TargetPawnGrouping;
var CorpCell    TargetCellObjective;
var int         TargetPawnDistance;
var byte        SelectedAbilityIndex;
var int         counter;
var CorpCell    TargetCell;

var() CorpPawn    SupportPawnObjective;
var bool IFF;

// Pathfinding
var CorpCell    DestinationCell;
var CorpCell    CachedDestinationCell;
var bool        bPawnNearDestination;
var float       DistanceRemaining;
var Rotator     CachedMoveRotation;

// Temp
var array<CorpPawn> DeployedUnits;
var byte            SelectedPosition;
var int             chance;

//Inference Engine Variables.
var array<string> WorkingMemoryArray;
var array<string> KnowledgeBaseArray;
	//Knowledge Base
Var int Attack;
Var int Move;


/////////////////////////////////////////////////////////////////////
//              Global Funcitons - Native functions
/////////////////////////////////////////////////////////////////////

simulated event PostBeginPlay() 
{
	super.PostBeginPlay();
	
	CorpGameInfo = CorpGame(WorldInfo.Game);

	CachedMoveRotation.Yaw = 0;
}

simulated event Tick(float DeltaTime)
{
	super.Tick(DeltaTime);

	UnitMove(DeltaTime);

	if(Pawn != none)
	{
		// Hackjob method of making sure this pawn DOES NOT ROTATE DAMMIT.
		// Controller Rotation -> Pawn Rotation (Note PlayerController does NOT have this problem)
		// If we do the usual rotation like the player, at the end of each move the pawn will rotate slowly to the way he came...
		Pawn.SetRotation(CachedMoveRotation);
	}


}

// This function forces the pawn to look in the direction it is moving towards. (Note that this is not really a native function)
// Will activate only when there is some velocity added to the pawn.
function UnitMove(float DeltaTime)
{
	local Vector PawnXYLocation;
	local Vector DestinationXYLocation;
	local Vector    Destination;
	local Vector2D  DistanceCheck;
	local Rotator   MoveRotation;

	// If for some reason we got here, get out.
	if (Pawn == none)
		return;

	if (VSize(Pawn.Velocity) > 0)
	{

		//Get player destination for a check on distance left. (calculate distance)
		Destination = GetDestinationPosition();
		DistanceCheck.X = Destination.X - Pawn.Location.X;
		DistanceCheck.Y = Destination.Y - Pawn.Location.Y;
		DistanceRemaining = Sqrt((DistanceCheck.X*DistanceCheck.X) + (DistanceCheck.Y*DistanceCheck.Y));

		bPawnNearDestination = DistanceRemaining < 10.0f;

		PawnXYLocation.X = Pawn.Location.X;
		PawnXYLocation.Y = Pawn.Location.Y;

		DestinationXYLocation.X = GetDestinationPosition().X;
		DestinationXYLocation.Y = GetDestinationPosition().Y;

		// Set rotation to the destination.
		MoveRotation = Rotator(DestinationXYLocation - PawnXYLocation);
		if (!bPawnNearDestination)
			CachedMoveRotation = MoveRotation;

		Pawn.SetRotation(CachedMoveRotation);
	}
}


function SetAttackDirection(CorpCell TargetDirection)
{
	local Vector PawnXYLocation;
	local Vector DestinationXYLocation;
	local float TempDegrees;

	if (TargetDirection == none)
		return;
	if (TargetDirection.PathNode == none)
		return;
	if (Pawn == none)
		return;

	PawnXYLocation.X = Pawn.Location.X;
	PawnXYLocation.Y = Pawn.Location.Y;
	DestinationXYLocation.X = TargetDirection.PathNode.Location.X;
	DestinationXYLocation.Y = TargetDirection.PathNode.Location.Y;

	CachedMoveRotation = Rotator(DestinationXYLocation - PawnXYLocation);
	TempDegrees = CachedMoveRotation.Yaw * UnrRotToDeg;

	CachedMoveRotation.Yaw = TempDegrees * DegToUnrRot;
}



function SetUnitDirection(CorpCell TargetDirection)
{
	local Vector PawnXYLocation;
	local Vector DestinationXYLocation;
	local float TempDegrees;

	if (TargetDirection == none)
		return;
	if (TargetDirection.PathNode == none)
		return;
	if (Pawn == none)
		return;

	PawnXYLocation.X = Pawn.Location.X;
	PawnXYLocation.Y = Pawn.Location.Y;
	DestinationXYLocation.X = TargetDirection.PathNode.Location.X;
	DestinationXYLocation.Y = TargetDirection.PathNode.Location.Y;

	CachedMoveRotation = Rotator(DestinationXYLocation - PawnXYLocation);
	TempDegrees = CachedMoveRotation.Yaw * UnrRotToDeg;

	if (TempDegrees > 315 || (TempDegrees >= 0 && TempDegrees <= 45))
		CachedMoveRotation.Yaw = 0;
	else if (TempDegrees > 45 && TempDegrees <= 135)
		CachedMoveRotation.Yaw = 90 * DegToUnrRot;
	else if (TempDegrees > 135 && TempDegrees <= 225)
		CachedMoveRotation.Yaw = 180 * DegToUnrRot;
	else
		CachedMoveRotation.Yaw = 270 * DegToUnrRot;
}

simulated event Possess(Pawn inPawn, bool bVehicleTransition)
{
	super.Possess(inPawn, bVehicleTransition);
	ThisPawn = CorpPawn(inPawn);
}

/////////////////////////////////////////////////////////////////////
//           Objective Tasks
/////////////////////////////////////////////////////////////////////


/**
 * Our main function for finding a target enemy to fight.
 * Order of targeting:
 *      1) Enemy with lowest health
 *      2) Adjacent enemy (1 space away)
 *      3) Weak ranged enemies (2 spaces away)
 *      4) Any enemy within sight distance      - DONE
 */
function FindTargetObjective()
{
	local CorpPawn PossiblePawn, TempPawn;
	local int PossiblePawnDist, TempPawnDist;
	local CorpPawn_BlueCollar_Ranged RangedPawn;
	local int CorpOwner;
	local int friend;
	local array<CorpPawn> PossiblePawns, PossibleTempPawnsOne, PossibleTempPawnsTwo;
	local int friendsInArea;

	`log("Trying to find the the objective");
	`log("This Pawn is: " @ ThisPawn);
	if (ThisPawn == none)
		return;

	if(ThisPawn.CharacterJob == "Blue Collar Melee")
	{
		`log("Well we got into the job assignment");	
		PossiblePawns = CorpGameInfo.GetAreaPawn(ThisPawn.GetGridLocation(), ThisPawn.CorpSightRadius);
		foreach PossiblePawns(TempPawn)
		{
			`log("We got to this point so far, inside the loop");
			if((float(ThisPawn.CurrentHealthPoints) / float(ThisPawn.MaxHealthPoints)) > 0.25)
			{
				if (PossiblePawn == none && TempPawn.TeamIndex != ThisPawn.TeamIndex)
				{ // First pawn we see, target it.
					PossiblePawn = TempPawn;
					PossiblePawnDist = FindDistanceToPawn(TempPawn);
				}
				else if (TempPawn.TeamIndex != ThisPawn.TeamIndex)
				{ // Target any enemy we see that is closest first.
					TempPawnDist = FindDistanceToPawn(TempPawn);

					if (TempPawnDist < PossiblePawnDist)
					{
						PossiblePawn = TempPawn;
						PossiblePawnDist = TempPawnDist;
					}
				}
			}
			if ((float(ThisPawn.CurrentHealthPoints) / float(ThisPawn.MaxHealthPoints)) <= 0.25  || (ThisPawn.CanMove() == true && ThisPawn.CanAtk() == false))
			{
				`log("WE GOT IN HERE");
				if (PossiblePawn == none && TempPawn.TeamIndex == ThisPawn.TeamIndex)
				{ // First pawn we see, target it.
					PossiblePawn = TempPawn;
					PossiblePawnDist = FindDistanceToPawn(TempPawn);
				}
				else if (TempPawn.TeamIndex == ThisPawn.TeamIndex)
				{ // Target any enemy we see that is closest first.
					TempPawnDist = FindDistanceToPawn(TempPawn);

					if (TempPawnDist < PossiblePawnDist)
					{
						PossiblePawn = TempPawn;
						PossiblePawnDist = TempPawnDist;
					}
				}
			} 
		}
	}
	else if(ThisPawn.CharacterJob == "Blue Collar Ranged")
	{
		RangedPawn = CorpPawn_BlueCollar_Ranged(ThisPawn);
		if (RangedPawn != none)
		{
			TargetCell = none;  // Initialize TargetCell

			PossiblePawns = CorpGameInfo.GetAreaPawn(ThisPawn.GetGridLocation(), ThisPawn.CorpSightRadius);
			foreach PossiblePawns(TempPawn)
			{			
				if (PossiblePawn == none && TempPawn.TeamIndex != ThisPawn.TeamIndex)
				{ // First pawn we see, target it.
					PossiblePawn = TempPawn;
					PossiblePawnDist = FindDistanceToPawn(TempPawn);
				}
				else if (TempPawn.TeamIndex != ThisPawn.TeamIndex)
				{ // Target any enemy we see that is closest first.
					TempPawnDist = FindDistanceToPawn(TempPawn);

					if (TempPawnDist < PossiblePawnDist)
					{
						PossiblePawn = TempPawn;
						PossiblePawnDist = TempPawnDist;
					}
				}
			}

			if (PossiblePawnDist <= 1)
			{
				if (PossiblePawn.CurrentCell.Position.X > ThisPawn.CurrentCell.Position.X)
				{
					TargetCell.Position.X = ThisPawn.CurrentCell.Position.X - (ThisPawn.BaseAttackRange / 2);
				}
				else if (PossiblePawn.CurrentCell.Position.X < ThisPawn.CurrentCell.Position.X)
				{
					TargetCell.Position.X = ThisPawn.CurrentCell.Position.X + (ThisPawn.BaseAttackRange / 2);
				}
				else if (PossiblePawn.CurrentCell.Position.Y > ThisPawn.CurrentCell.Position.Y)
				{
					TargetCell.Position.Y = ThisPawn.CurrentCell.Position.Y - (ThisPawn.BaseAttackRange / 2);
				}
				else if (PossiblePawn.CurrentCell.Position.Y < ThisPawn.CurrentCell.Position.Y)
				{
					TargetCell.Position.Y = ThisPawn.CurrentCell.Position.Y + (ThisPawn.BaseAttackRange / 2);
				}
			}
		}
	}

	else if(ThisPawn.CharacterJob == "IT Wizard" || ThisPawn.CharacterJob == "IT Controller")
	{
		PossiblePawns = CorpGameInfo.GetAreaPawn(ThisPawn.GetGridLocation(), ThisPawn.CorpSightRadius);
		foreach PossiblePawns(TempPawn)
		{	
			if (PossiblePawn == none && TempPawn.TeamIndex != ThisPawn.TeamIndex)
			{ // First pawn we see, we grab all of the pawns around it.
				PossibleTempPawnsOne = CorpGameInfo.GetAreaPawn(PossiblePawn.GetGridLocation(), ThisPawn.SpecialAbilities[1].BlastRadius);
				PossiblePawnDist = FindDistanceToPawn(TempPawn);
				PossiblePawn = TempPawn;
			}
			else if (TempPawn.TeamIndex != ThisPawn.TeamIndex)
			{ // Target any enemy we see that is closest first.
				//TempPawnDist = FindDistanceToPawn(TempPawn);
				PossibleTempPawnsTwo = CorpGameInfo.GetAreaPawn(TempPawn.GetGridLocation(), ThisPawn.SpecialAbilities[1].BlastRadius);
				if (PossibleTempPawnsOne.Length < PossibleTempPawnsTwo.Length || TempPawn.CurrentHealthPoints < PossiblePawn.CurrentHealthPoints)
				{
					PossiblePawn = TempPawn;
					PossibleTempPawnsOne = PossibleTempPawnsTwo;
					//PossiblePawnDist = TempPawnDist;
				}
			}
		}
	}
	else if(ThisPawn.CharacterJob == "PR File Clerk")
	{
		PossiblePawns = CorpGameInfo.GetAreaPawn(ThisPawn.GetGridLocation(), ThisPawn.CorpSightRadius);
		FriendsInArea = 0;
		//checks to see if we have friendly pawns around us
		foreach PossiblePawns(TempPawn)
		{
			if(TempPawn.TeamIndex == ThisPawn.TeamIndex && TempPawn != ThisPawn)
			{
				FriendsInArea = FriendsInArea + 1;
			}
		}

		if(FriendsInArea != 0)
		{
			foreach PossiblePawns(TempPawn)
			{
				if (PossiblePawn == none && TempPawn.TeamIndex == ThisPawn.TeamIndex && TempPawn != ThisPawn)
				{ 
					// First pawn we see, target it.
					PossiblePawn = TempPawn;
					PossiblePawnDist = FindDistanceToPawn(TempPawn);
				}

				else if (TempPawn.TeamIndex == ThisPawn.TeamIndex && TempPawn != ThisPawn)
				{ 
					// Target any enemy we see that is closest first.
					TempPawnDist = FindDistanceToPawn(TempPawn);
				
					if (TempPawnDist < PossiblePawnDist)
					{
						PossiblePawn = TempPawn;
						PossiblePawnDist = TempPawnDist;
					}
				}
			}
		}
		else if (FriendsInArea == 0)
		{
			foreach PossiblePawns(TempPawn)
			{
				if (PossiblePawn == none && TempPawn.TeamIndex != ThisPawn.TeamIndex)
				{ 
					// First pawn we see, target it.
					PossiblePawn = TempPawn;
					PossiblePawnDist = FindDistanceToPawn(TempPawn);
				
				}
				else if (TempPawn.TeamIndex != ThisPawn.TeamIndex)
				{
					// Target any enemy we see that is closest first.
					TempPawnDist = FindDistanceToPawn(TempPawn);

					if (TempPawnDist < PossiblePawnDist)
					{
						PossiblePawn = TempPawn;
						PossiblePawnDist = TempPawnDist;
					}
				}
			}
		}

		if(PossiblePawn == none)
		{
			PossiblePawn = ThisPawn;
			PossiblePawnDist = FindDistanceToPawn(ThisPawn);
		}

	}
	else if(ThisPawn.CharacterJob == "PR Motivational Speaker")
	{
		PossiblePawns = CorpGameInfo.GetAreaPawn(ThisPawn.GetGridLocation(), 3);

		foreach PossiblePawns(TempPawn)
		{
			if(TempPawn.TeamIndex != ThisPawn.TeamIndex)
				CorpOwner++;
			else if(TempPawn.TeamIndex == ThisPawn.TeamIndex)
				friend++;
		}
		if(CorpOwner > friend)
			IFF = false;
		else
			IFF = true;
		if(PossiblePawns.Length == 1)
		{
			PossiblePawn = PossiblePawns[0];
			PossiblePawnDist = FindDistanceToPawn(PossiblePawn);
		}
		else
		{
			PossiblePawn = none;
			PossiblePawnDist = 0;
		}
	}
	


	// Log the target pawn and its distance.
	TargetPawnObjective = PossiblePawn;
	TargetPawnDistance = PossiblePawnDist;
	TargetPawnGrouping = PossibleTempPawnsOne.Length;
}

// Update information on the target. Mainly just how far it is.
function UpdateTargetObjective()
{
	if (TargetPawnObjective == none)
		return;

	TargetPawnDistance = FindDistanceToPawn(TargetPawnObjective);
}

/////////////////////////////////////////////////////////////////////
//            Unit Movement and Distance
/////////////////////////////////////////////////////////////////////

// Distance to a cell using pathfinding.
function int FindDistanceToCell(CorpCell Cell)
{
	if(Pawn != none)
	{
		// You must do this in order for the pathing to be accurate. Otherwise it'll try pathing around its initial point!
		CorpPawn(Pawn).CurrentCell.UnBlockCell();

		FindPathTo(Cell.PathNode.Location);

		CorpPawn(Pawn).CurrentCell.BlockCell();
		return RouteCache.Length;
	}

	return 0;
}

// Distance to a pawn. Uses FindDistanceToCell for this.
function int FindDistanceToPawn(CorpPawn Target)
{
	local int Distance;

	// Tell the pawn's cell to unblock it self. This way we get a true distance to the cell it occupies.
	Target.CurrentCell.UnBlockCell();

	Distance = FindDistanceToCell(Target.CurrentCell);

	Target.CurrentCell.BlockCell();

	return Distance;
}

/** Generates a path to a target pawn. It will find shortest route to get to this destination.
 *  @param  Target      Pawn you are trying to get to. 
 *  @param  Offset      How far away you wish to be from the target. Offset is n+1 from the target (An offset of 2 -> 2+1=3 spaces away).
 */
function UnitPathToPawn(CorpPawn Target, optional int OffSet)
{
	local array<CorpCell> CellList;
	local CorpCell TempCell, PossibleCell;
	local int TempDist, PossibleDist;

	CellList = CorpGameInfo.GetArea(Target.GetGridLocation(), 1+Offset, AREA_Edge);
	foreach CellList(TempCell)
	{
		if (PossibleCell == none && TempCell.OccupiedBy == none)
		{
			PossibleCell = TempCell;
			PossibleDist = FindDistanceToCell(TempCell);
		}
		else if (TempCell.OccupiedBy == none)
		{
			TempDist = FindDistanceToCell(TempCell);

			if (TempDist < PossibleDist)
			{
				PossibleCell = TempCell;
				PossibleDist = TempDist;
			}
		}
	}


	if (PossibleCell == none && GetStateName() == 'MoveStandby' || !(ThisPawn.CanMove()))
	{
		`log("well we cant move anymore might as well finish");
		FinishAction();
		return;
	}

	UnitPathTo(PossibleCell);
}

// The main pathing function that begins the pathing process.
function UnitPathTo(CorpCell Cell)
{
	`log("function: UnitPathTo");
	if (Cell == CachedDestinationCell)
	{
		`log("Deleting CachedDestinationCell");
		CachedDestinationCell = none;
	}

	if(ThisPawn != none && Cell.OccupiedBy == none)
	{
		`log("Getting things ready for the movement");
		SetDestinationPosition(Cell.PathNode.Location);
		DestinationCell = Cell;
		ExecutePathFindMove();
	}
	else
	{
		`log("We are just going to end this function");
		FinishAction();
	}
}


// Makes the call to the FindPathTo so that a list of possible PathNodes will be cached in RouteCache.
function ExecutePathFindMove()
{
	`log("Function: ExecutePathFindMove()");
	// Begin by disabling the current spot.
	CorpPawn(Pawn).CurrentCell.UnBlockCell();

	// Produce a path to the destination.
	ScriptedMoveTarget = FindPathTo(GetDestinationPosition());

	`Log("Route length is"@RouteCache.Length);

	// Begin the pathfinding job.
	if( RouteCache.Length > 0 )
	{
		if (Abs(VSize(RouteCache[0].Location - CorpPawn(Pawn).CurrentCell.PathNode.Location)) > 75)
		{
			`Log("Pathfinding - What the shat is this thing doing?");
			AvoidLongPath();
			return;
		}
		`log("time to pathfind");
		GotoState('PathFind');
	}
	else
	{
		`log("well we are just not moving after finding our target");
		FinishAction();
		return;
	}   
}

// Oh shit dawg. What is that scout trying to do? This tries to find an adjacent cell to path to, fixing our walking through walls problem.
// This is not done yet. It must find an optimal cell to go towards before moving forward.
function AvoidLongPath()
{
	local array<CorpCell> SurroundingCells;
//	local Vector2D Start, Destination;

	`Log("Pathfinding - Avoiding that path like the plague.");

	if (DestinationCell == CachedDestinationCell)
	{
		`warn("ALORT - We ran into an endless loop. Breaking out.");
		FinishAction();
		return;
	}

	// Left to right, Bottom to top.
	SurroundingCells = CorpGameInfo.GetArea(CorpPawn(Pawn).CurrentCell.Position, 1);

//	Start = CorpPawn(Pawn).CurrentCell.Position;
//	Destination = DestinationCell.Position;

	// Keep this for after we do the avoiding. This gets reused at the end of the pathfind.
	CachedDestinationCell = DestinationCell;

	// Path to your "optimized" cell.
	if (SurroundingCells.Length != 0)
		UnitPathTo(SurroundingCells[0]);
}

function bool WanderMove() 
{

	local array<CorpCell> PossibleDestinationCells;
	local int NumberOfCells;
	local int RandomIndex;
	local CorpCell TempCell;
    
		PossibleDestinationCells = CorpGameInfo.GetArea(ThisPawn.GetGridLocation(), ThisPawn.BaseMoveDistance,,);
	NumberOfCells = PossibleDestinationCells.Length;	
	if(NumberOfCells > 0)
	{
		RandomIndex = Rand(NumberOfCells);
		`Log("Let's wander around.");
		`Message2("Let's wander around.");
		`Log("destCell: " @PossibleDestinationCells[RandomIndex]);
		foreach PossibleDestinationCells(TempCell)
		{
			`log("Cell: " @ Tempcell);
		}
			`log("we didn't have an objective"); 
			TargetCell = PossibleDestinationCells[RandomIndex];
			`log("we are leaving wandermove");
			return true;
	}
	else
	{
		// No where to go..
		`Log("No place to go? Let's stay where I am.");
		return true;
	}
	return false; //something went wrong
}

/////////////////////////////////////////////////////////////////////
//            Unit Path Highlighting
/////////////////////////////////////////////////////////////////////

// Uses the list of path nodes generated for pathfinding to highlight the grid.
function HighlightPath()
{
	local int n;

	for(n = 0; n < RouteCache.Length && n < ThisPawn.CurrentMoveDistance; n++)
	{
		CorpPathNode(RouteCache[n]).ParentCell.SetUnusable();
	}
}

function ResetPath()
{
	local int n;

	for(n = 0; n < RouteCache.Length; n++)
	{
		CorpPathNode(RouteCache[n]).ParentCell.Reset();
	}
}

/////////////////////////////////////////////////////////////////////
//                State Machine - Global Functions
/////////////////////////////////////////////////////////////////////
// Signal for the AI to begin its turn.
function BeginTurn();

// Global finish action command. Tell the controller to reset down to your default state.
function FinishAction()
{
	GotoState('IdleStandby');
}

function LetsMove()
{
	GotoState('MoveStandby');
}

// Tells the game that this AI has finished it's turn.
function EndTurn()
{
	ThisPawn.ResetActions();
	ThisPawn.EndTurn();
	CorpGameInfo.TurnEnd();
}

// Figure out which attack to use if any available. For now that is just to attack when in range. If we chose an action, return true.
function bool ChooseAttackAction()
{
	// How to do a normal attack (with no additional logic)
	if (TargetPawnDistance <= ThisPawn.BaseAttackRange && ThisPawn.CanAtk() && ThisPawn.IsEnemy(TargetPawnObjective))
	{
		GotoState('AttackStandby');
		return true;
	}

	// How to do a special ability. Normally instead of 0 you'd use SelectedAbilityIndex
	ThisPawn.SetAbility(0);

	if (ThisPawn.SelectedAbility != none)
	{
		if (TargetPawnDistance <= ThisPawn.SelectedAbility.Range && ThisPawn.CanAtk())
		{
		//	GotoState('AbilityStandby');
			return true;
		}
	}

	return false;
}

/////////////////////////////////////////////////////////////////////
//                State Machine - Actions
/////////////////////////////////////////////////////////////////////

/**
 * The example AI Routine List below is the basic principles for how a human player would control their game, but programmed and simplified.
 * Please visit the wiki for more indepth info: http://jdserv.kicks-ass.net:8378/corp/wiki/index.php?title=Artificial_Intelligence
 * 
 * AI Routine List
 * ---------------
 * 1.   Idle Standby
 *          Await the command for your turn to begin from CorpGame.
 * 2.   Find Objectives
 *          Choose from a priority list what the current objective should be starting from self preservation.
 *          Example: Self Preservation -> Unit backup -> Preset Objective -> Attack Unit -> Defend
 * 3a.  Choose Best Action
 *          How best to perform your objective. This will choose to prioritize skills over basic actions.
 * 3b.  Choose Best Route
 *          Pathfind to objective, but not actually take the step. Not needed if nearby.
 * 4.   Perform Actions
 *          All calculations have been done, perform your tasks
 * 4a.  Move Action
 *          If needed, move down the path generated.
 * 4b.  Attack Action
 *          If needed, attack the enemy that is within range.
 * 4c.  Skill Action
 *          Performed over attack action if deemed needed.
 * 4d.  Item Action
 *          Situational. Mainly for self presevation.
 * 5.   End Turn
 *          Tell game that the pawn has completed all available actions.
 */

///////////////////////////////////////////////
//              Inference Engine            ///
///////////////////////////////////////////////
	
function WorkingMemory()
{
	local int i; //counter

	`Message2("Working Memory Being Accessed");

	//clears array.
	for(i = 0; i<WorkingMemoryArray.Length; i++)
	{
		WorkingMemoryArray[i] = "NULL";
	}

	if (thispawn.Health > 60)
		WorkingMemoryArray[0] = "High Health";
	else if (thispawn.Health < 60 && thispawn.Health > 30 )
		WorkingMemoryArray[0] = "Medium Health";
	else if (thispawn.Health < 30 )
		WorkingMemoryArray[0] = "Low Health";

	`Message2("Working Memory [0] = " $WorkingMemoryArray[0]$ " ");
	`Message2(" & Thispawn.health = " $ThisPawn.Health$ " ");
}
function KnowledgeBase()
{
	local int i;

	`Message2("Knowledge Base Being Accessed");

	//Clears Array
	for(i = 0; i<KnowledgeBaseArray.Length; i++)
	{
		KnowledgeBaseArray[i] = "NULL";
	}

	//Considers the working memory, fires rules.
	if (WorkingMemoryArray[0] == "High Health")
	{
		Attack = 1;
		`Message2("RHS = Attack");
	} else {
		Move = 1;
		`Message2("RHS = Move");
	}

	//assigns the array.
	if (Attack == 1)
		KnowledgeBaseArray[0] = "Attack";
	if (Move == 1)
		KnowledgeBaseArray[1] = "Move";
}
function Agenda()
{
	`Message2("Agenda Being Accessed");

	//Priority from highest to lowest.
	if (KnowledgeBaseArray[0] == "Attack"){ //Attack being highest priority
		`Message2("Moving to Attack State");
		//FindTargetObjective();
		//find closest enemy pawn
		//make that pawn the objective.
		//if pawn not in range, move then try to attack.
		GotoState('AttackStandby');
	}
	if (KnowledgeBaseArray[1] == "Move"){ //Move Being second highest Priority
		`Message2("Moving to Move Away State");
		WanderMove();
		SetTimer(1,false, 'EndTurn');
	}
}   


auto state IdleStandby
{

	// Native event function. Automatically called when the state starts.
	event BeginState(Name PreviousStateName)
	{
		// Find your objective again.
		UpdateTargetObjective();

		// Tell the camera to stop focusing on the pawn. We only want it focused on actions
		CorpGameInfo.PlayerControl.UnitUnfocus();

		// Choose your next action depending on the action that this state came from.
		switch(PreviousStateName)
		{
			case 'PathFind':
				ThisPawn.bHasMoved = true;
				if (!ChooseAttackAction())
					SetTimer(1,false, 'EndTurn');
				break;
			case 'AttackStandby':
			case 'AbilityStandby':
			case 'MoveStandby':
				if (CorpGameInfo.CurrentTeam != 0)
				{ // If the team is not the player's turn, end the turn.
					SetTimer(1,false, 'EndTurn');
				}
				break;
		}
	}

	// Native event function. Automatically called when the state ends.
	event EndState(Name NextStateName)
	{
		// Tell the camera to focus on this AI's pawn. We only want it focusing on actions being made.
		switch(NextStateName)
		{
			case 'PathFind':
			case 'AttackStandby':
			case 'AbilityStandby':
			case 'MoveStandby':
				CorpGameInfo.PlayerControl.UnitFocus(ThisPawn);
				break;
			default:
				ThisPawn.CurrentCell.OccupiedBy = none;
				ThisPawn.CurrentCell.UnBlockCell();
				break;
		}
	}
	

	// We just got the go ahead to begin our turn.
	function BeginTurn()
	{
		if (ThisPawn == none)
		{
			EndTurn();
			return;
		}

		// Find an objective to perform...
		//FindTargetObjective();
		
		//using Inference Engine.
		WorkingMemory();    //All known stats in the world at the moment this function is called.
		KnowledgeBase();    //All known rules or possible decisions for the NPC to make.
		Agenda();           //Sets the priority of rules that are being fired, 
							//making the most intelligent rule to be the most likely executed.

		/*
		// If we have a target...
		if (TargetPawnObjective != none)
		{		
			GotoState('MoveStandby');
		}
		else if (TargetPawnObjective == none && ThisPawn.IsAliveAndWell())
			GotoState('MoveStandby');

		else if (CorpGameInfo.CurrentTeam != 0)
		{ // If we don't and its our turn, end your turn, we probably have a dead pawn.
			EndTurn();
		}*/

		//EndTurn();
	}

Begin:
	`Log("Waiting for the go ahead.");
}


/** The move state machine.
 *  Performs the basic movement after a 1 second delay to your TargetPawnObjective.
 *  The delay is to show the move area on thee grid for a visual feedback.
 *  Override this state to do various specific movements such as roaming.
 *  TargetPawnObjective in this case is required before we step into this state. (Unless you override it to change this requirement)
 */
state MoveStandby
{
	
	function BeginAction()
	{
		`log("State: MoveStandby");
		ThisPawn.FinishState();
		if (TargetCell == none && TargetPawnObjective != none)
		{
			`log("We found a TargetPawnObjective");
			`log("TargetPawnDistance is " @ TargetPawnDistance); 
			`log("BaseAttackRange is" @ ThisPawn.BaseAttackRange); 
			if ((ThisPawn.CanAtk()) && TargetPawnDistance <= ThisPawn.BaseAttackRange)
			{
				`log("We are attacking first");
				ChooseAttackAction();
			}
			else
				UnitPathToPawn(TargetPawnObjective);
		}
		else if (TargetCell != none && TargetPawnObjective == none)
		{
			`log("We found a TargetCell");
			UnitPathTo(TargetCell);
			TargetCell = none;
		}
		else
		{
			`log("Well nothing was found time to wander");
			WanderMove();
			UnitPathTo(TargetCell);
			TargetCell = none;
		}
	}
	Begin:
		ThisPawn.StartMoveStandby();
		SetTimer(1, false, 'BeginAction');
}

/** The basic attack state machine. Only used to do basic melee/ranged attacks.
 *  Performs the basic attack action after a 1 second delay to your TargetPawnObjective.
 *  The delay is to show the attack area on thee grid for a visual feedback.
 *  No need to override this state.
 *  TargetPawnObjective in this case is required before we step into this state. (Unless you override it to change this requirement)
 */
state AttackStandby
{
	function BeginAction()
	{
		ThisPawn.FinishState();
		if(TargetPawnObjective != ThisPawn)  
			SetAttackDirection(TargetPawnObjective.CurrentCell);
		ThisPawn.BasicAttack(TargetPawnObjective);
		ThisPawn.bHasAttacked = true;
		TargetPawnObjective = none;
		TargetCell = none;

		chance = Rand(100);
		//if this pawn can still move there is a 30% chance that it will randomly go somewhere. otherwise it'll just sit there
		if(ThisPawn.CanMove() && chance < 30)
		{
			GoToState('MoveStandby');
		}
		else
		{
			`log("we will be leaving the attack phase");
			FinishAction();
		}
	}

	Begin:
		ThisPawn.StartAttackStandby();
		SetTimer(1, false, 'BeginAction');
}





/** The ability state machine. Enter this state only after you've chosen an ability to use.
 *  Performs the task of using the ability after a 1 second delay on your TargetPawnObjective['s cell] or TargetCellObjective.
 *  Override this state if you wish to change who and how it applies the ability on.
 *  As it is now, TargetPawnObjective or TargetCellObjective is required for this to work.
 *  Also required is that ThisPawn has SelectedAbility set. Use the function SetAbility(Index) for this.
 */
state AbilityStandby
{
	// If we have a Pawn objctive, use it on it's cell. If we have a Cell objective we target that cell instead.
	function BeginAction()
	{
		ThisPawn.FinishState();
		if (TargetCellObjective == none)
		{
			if(TargetCellObjective != ThisPawn.CurrentCell)
			{ 
				`log("Calling Set Unit Direction");
				SetAttackDirection(TargetPawnObjective.CurrentCell);
			}
			ThisPawn.UseAbility(TargetPawnObjective.CurrentCell);
		}
		else
		{
			if(TargetCellObjective != ThisPawn.CurrentCell)
			{  
				`log("Calling Set Unit Direction");
				SetAttackDirection(TargetCellObjective);
			}
			ThisPawn.UseAbility(TargetCellObjective);
		}
		// Clear the selected ability before ending this round.
		ThisPawn.ClearAbility();
		ThisPawn.bHasAttacked = true;
		TargetPawnObjective = none;
		TargetCell =none;
		chance = Rand(100);
		if(ThisPawn.CanMove() && chance < 30)
		{
			GoToState('MoveStandby');
		}
		else
		{
			`log("we will be leaving the attack phase");
			FinishAction();
		}
	}

	Begin:
		if (ThisPawn.SelectedAbility == none)
		{
			`Message2("AI has not chosesn an ability!");
			GotoState('IdleStandBy');
		}
		else
		{
			ThisPawn.StartSpecialAbilityStandby();
			SetTimer(1, false, 'BeginAction');
		}
}

/////////////////////////////////////////////////////////////////////
//                State Machine - Movement
/////////////////////////////////////////////////////////////////////

// These are actually on the AIController class! We need to change much of this code anyway, so this is fine.

state PathFind
{
	event BeginState(name PreviousStateName)
	{
		`log("did this happen");
		HighlightPath();
		`log("ok we got past that point");
	}

	event EndState(name NextStateName)
	{
		`log("Leaving Pathfinding");
		CorpPawn(Pawn).CurrentCell.BlockCell();
		ResetPath();
		CorpPawn(Pawn).bHasMoved = true;
	}

	// Disable global functions
	function UnitSelected(CorpPawn SelectedPawn);
	function UnitUnselected(optional CorpPawn UnselectedPawn);

Begin:
	`log("we got to the state");
	bCollideWorld = true;
	`log("Just before we enter Pathfind");
	if( RouteCache.Length > 0 )
	{
		//for each route in routecache push a ScriptedMove state.
		ScriptedRouteIndex = 0;
		`log("Entering the Pathfinding State");
		while (Pawn != None && ScriptedRouteIndex < RouteCache.length && ScriptedRouteIndex >= 0  && 
			ScriptedRouteIndex < CorpPawn(Pawn).CurrentMoveDistance && !CorpPawn(Pawn).CurrentCell.bBearTrapped)
		{
			`log("we got into the pathfinding state atleast");
			//Get the next route (PathNode actor) as next MoveTarget.
			//ScriptedMoveTarget = RouteCache[ScriptedRouteIndex];

			// Getting the exact position on the floor.
			ScriptedMoveTarget = CorpPathNode(RouteCache[ScriptedRouteIndex]).ParentCell;
			if (ScriptedMoveTarget != None)
			{
				//`Log("ScriptedMove_"$ScriptedRouteIndex@"["$CorpPathNode(RouteCache[ScriptedRouteIndex]).Position.X$"]["$CorpPathNode(RouteCache[ScriptedRouteIndex]).Position.Y$"]");
				PushState('ScriptedMove');
			}
			else
			{
				`Log("ERROR - ScriptedMoveTarget is invalid for index:"@ScriptedRouteIndex);
			}
			ScriptedRouteIndex++;
		}

		if (CorpPawn(Pawn).CurrentCell.bBearTrapped)
		{
			CorpPawn(Pawn).CurrentCell.bBearTrapped = false;
			CorpPawn(Pawn).CurrentCell.Reset();
		}
		
		GotoState('IdleStandby');
	}	
}

state ScriptedMove
{
	// Disable global functions
	function UnitSelected(CorpPawn SelectedPawn);
	function UnitUnselected(optional CorpPawn UnselectedPawn);

Begin:
	bCollideWorld = true;
	while(ScriptedMoveTarget != none && Pawn != none && !Pawn.ReachedDestination(ScriptedMoveTarget))
	{
		SetDestinationPosition(ScriptedMoveTarget.Location);
		MoveTo(GetDestinationPosition());
	}
	PopState();
}


DefaultProperties
{
	Name='CorpAIController'
	bIgnoreBaseRotation=true
	CachedMoveRotation=(Pitch=0,Roll=0,Yaw=0)
}
