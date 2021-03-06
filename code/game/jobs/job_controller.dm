var/global/datum/controller/occupations/job_master

/datum/controller/occupations
		//List of all jobs
	var/list/occupations = list()
		//Players who need jobs
	var/list/unassigned = list()
		//Debug info
	var/list/job_debug = list()

	var/list/crystal_ball = list() //This should be an assoc. list. Job = # of players ready. Configured by predict_manifest() in obj.dm

	var/priority_jobs_remaining = 3 //Limit on how many prioritized jobs can be had at once.
	var/list/labor_consoles = list()


/datum/controller/occupations/proc/SetupOccupations(var/faction = "Station")
	occupations = list()
	var/list/all_jobs = typesof(/datum/job)
	if(!all_jobs.len)
		to_chat(world, "<span class='danger'>Error setting up jobs, no job datums found</span>")
		return 0
	for(var/J in all_jobs)
		var/datum/job/job = new J()
		if(!job)
			continue
		if(job.faction != faction)
			continue

		if(job.must_be_map_enabled)
			if(!map)
				continue
			if(!map.enabled_jobs.Find(job.type))
				continue

		if(map.disabled_jobs.Find(job.type))
			continue

		occupations += job


	return 1


/datum/controller/occupations/proc/Debug(var/text)
	if(!Debug2)
		return 0
	job_debug.Add(text)
	return 1

/datum/controller/occupations/proc/GetJob(var/rank)
	RETURN_TYPE(/datum/job)
	if(!rank)
		return null
	for(var/datum/job/J in occupations)
		if(!J)
			continue
		if(J.title == rank)
			return J
	return null

/datum/controller/occupations/proc/GetPlayerAltTitle(mob/new_player/player, rank)
	return player.client.prefs.GetPlayerAltTitle(GetJob(rank))

/datum/controller/occupations/proc/AssignRole(var/mob/new_player/player, var/rank, var/latejoin = 0)
	Debug("Running AR, Player: [player], Rank: [rank], LJ: [latejoin]")
	if(player && player.mind && rank)
		var/datum/job/job = GetJob(rank)
		if(!job)
			return 0
		if(jobban_isbanned(player, rank))
			return 0
		if(!job.player_old_enough(player.client))
			return 0
		var/position_limit = job.get_total_positions()
		if(!latejoin)
			position_limit = job.spawn_positions
		if((job.current_positions < position_limit) || position_limit == -1)
			Debug("Player: [player] is now Rank: [rank], JCP:[job.current_positions], JPL:[position_limit]")
			player.mind.assigned_role = rank
			player.mind.role_alt_title = GetPlayerAltTitle(player, rank)

			unassigned -= player
			job.current_positions++

			for(var/obj/machinery/computer/labor/L in labor_consoles)
				L.updateUsrDialog()

			return 1
	Debug("AR has failed, Player: [player], Rank: [rank]")
	return 0

/datum/controller/occupations/proc/FreeRole(var/rank, mob/user)	//making additional slot on the fly
	var/datum/job/job = GetJob(rank)
	if(job && job.current_positions >= job.get_total_positions())
		job.bump_position_limit()
		if(user)
			log_admin("[key_name(user)] has freed up a slot for the [rank] job.")
			message_admins("[key_name_admin(user)] has freed up a slot for the [rank] job.")
		for(var/mob/new_player/player in player_list)
			to_chat(player, "<span class='notice'>The [rank] job is now available!</span>")
		return 1
	return 0

/datum/controller/occupations/proc/CheckPriorityFulfilled(var/rank)
	var/datum/job/job = GetJob(rank)
	if(job.current_positions >= job.get_total_positions() && job.priority)
		job_master.TogglePriority(rank)

/datum/controller/occupations/proc/TogglePriority(var/rank, mob/user)
	var/datum/job/job = GetJob(rank)
	if(job)
		if(job.priority)
			job.priority = FALSE
			priority_jobs_remaining++
		else
			if(priority_jobs_remaining < 1)
				return 0
			job.priority = TRUE
			priority_jobs_remaining--
		if(user)
			log_admin("[key_name(user)] has set the priority of the [rank] job to [job.priority].")
			message_admins("[key_name_admin(user)] has set the priority of the [rank] job to [job.priority].")
		for(var/mob/new_player/player in player_list)
			to_chat(player, "<span class='notice'>The [rank] job is [job.priority ? "now highly requested!" : "no longer highly requested."]</span>")
		return 1
	return 0

/datum/controller/occupations/proc/IsJobPrioritized(var/rank)
	var/datum/job/job = GetJob(rank)
	if(job)
		return job.priority
	return 0

/datum/controller/occupations/proc/GetPrioritizedJobs() //Returns a list of job datums.
	. = list()
	for(var/datum/job/J in occupations)
		if(J.priority)
			. += J

/datum/controller/occupations/proc/GetUnprioritizedJobs() //Returns a list of job datums.
	. = list()
	for(var/datum/job/J in occupations)
		if(!J.priority)
			. += J

/datum/controller/occupations/proc/FindOccupationCandidates(datum/job/job, level, flag)
	Debug("Running FOC, Job: [job], Level: [level], Flag: [flag]")
	var/list/candidates = list()
	for(var/mob/new_player/player in unassigned)
		if(jobban_isbanned(player, job.title))
			Debug("FOC isbanned failed, Player: [player]")
			continue
		if(!job.player_old_enough(player.client))
			Debug("FOC player not old enough, Player: [player]")
			continue
		if(flag && !player.client.desires_role(job.title))
			Debug("FOC flag failed, Player: [player], Flag: [flag], ")
			continue
		if(player.client.prefs.GetJobDepartment(job, level) & job.flag)
			Debug("FOC pass, Player: [player], Level:[level]")
			candidates += player
	return candidates

/datum/controller/occupations/proc/GiveRandomJob(var/mob/new_player/player)
	Debug("GRJ Giving random job, Player: [player]")
	for(var/datum/job/job in shuffle(occupations))
		if(!job)
			continue

		if(job.no_random_roll)
			continue

		if(job.title in command_positions) //If you want a command position, select it!
			continue

		if(jobban_isbanned(player, job.title))
			Debug("GRJ isbanned failed, Player: [player], Job: [job.title]")
			continue

		if(!job.player_old_enough(player.client))
			Debug("GRJ player not old enough, Player: [player]")
			continue

		if((job.current_positions < job.spawn_positions) || job.spawn_positions == -1)
			Debug("GRJ Random job given, Player: [player], Job: [job]")
			AssignRole(player, job.title)
			unassigned -= player
			break

/datum/controller/occupations/proc/ResetOccupations()
	for(var/mob/new_player/player in player_list)
		if((player) && (player.mind))
			player.mind.assigned_role = null
			player.mind.special_role = null
	SetupOccupations()
	unassigned = list()
	return


	///This proc is called before the level loop of DivideOccupations() and will try to select a head, ignoring ALL non-head preferences for every level until it locates a head or runs out of levels to check
/datum/controller/occupations/proc/FillHeadPosition()
	for(var/level = 1 to 3)
		for(var/command_position in command_positions)
			var/datum/job/job = GetJob(command_position)
			if(!job)
				continue
			var/list/candidates = FindOccupationCandidates(job, level)
			if(!candidates.len)
				continue
			var/mob/new_player/candidate = pick(candidates)
			if(AssignRole(candidate, command_position))
				return 1
	return 0


	///This proc is called at the start of the level loop of DivideOccupations() and will cause head jobs to be checked before any other jobs of the same level
/datum/controller/occupations/proc/CheckHeadPositions(var/level)
	for(var/command_position in command_positions)
		var/datum/job/job = GetJob(command_position)
		if(!job)
			continue
		var/list/candidates = FindOccupationCandidates(job, level)
		if(!candidates.len)
			continue
		var/mob/new_player/candidate = pick(candidates)
		AssignRole(candidate, command_position)
	return


/datum/controller/occupations/proc/FillAIPosition()
	var/ai_selected = 0
	var/datum/job/job = GetJob("AI")
	if(!job)
		return 0
	if((job.title == "AI") && (config) && (!config.allow_ai))
		return 0

	for(var/i = job.get_total_positions(), i > 0, i--)
		for(var/level = 1 to 3)
			var/list/candidates = list()
			if(ticker.mode.name == "AI malfunction")//Make sure they want to malf if its malf
				candidates = FindOccupationCandidates(job, level, MALF)
			else
				candidates = FindOccupationCandidates(job, level)
			if(candidates.len)
				var/mob/new_player/candidate = pick(candidates)
				if(AssignRole(candidate, "AI"))
					ai_selected++
					break
		//Malf NEEDS an AI so force one if we didn't get a player who wanted it
		if((ticker.mode.name == "AI malfunction")&&(!ai_selected))
			unassigned = shuffle(unassigned)
			for(var/mob/new_player/player in unassigned)
				if(jobban_isbanned(player, "AI"))
					continue
				if(AssignRole(player, "AI"))
					ai_selected++
					break
		if(ai_selected)
			return 1
		return 0


/** Proc DivideOccupations
 *  fills var "assigned_role" for all ready players.
 *  This proc must not have any side effect besides of modifying "assigned_role".
 **/
/datum/controller/occupations/proc/DivideOccupations()
	//Setup new player list and get the jobs list
	Debug("Running DO")
	SetupOccupations()

	//Holder for Triumvirate is stored in the ticker, this just processes it
	if(ticker)
		for(var/datum/job/ai/A in occupations)
			if(ticker.triai)
				A.spawn_positions = 3
		for(var/datum/job/cyborg/C in occupations)
			if(ticker.triai)
				C.spawn_positions = 3

	//Get the players who are ready
	for(var/mob/new_player/player in player_list)
		if(player.ready && player.mind && !player.mind.assigned_role)
			unassigned += player
			if(player.client.prefs.randomslot)
				player.client.prefs.random_character_sqlite(player, player.ckey)
	Debug("DO, Len: [unassigned.len]")
	if(unassigned.len == 0)
		return 0

	//Shuffle players and jobs
	unassigned = shuffle(unassigned)

	HandleFeedbackGathering()

	//Select one head
	Debug("DO, Running Head Check")
	FillHeadPosition()
	Debug("DO, Head Check end")

	//Check for an AI
	Debug("DO, Running AI Check")
	FillAIPosition()
	Debug("DO, AI Check end")

	//Other jobs are now checked
	Debug("DO, Running Standard Check")


	// New job giving system by Donkie
	// This will cause lots of more loops, but since it's only done once it shouldn't really matter much at all.
	// Hopefully this will add more randomness and fairness to job giving.

	// Loop through all levels from high to low
	var/list/shuffledoccupations = shuffle(occupations)
	for(var/level = 1 to 3)
		//Check the head jobs first each level
		CheckHeadPositions(level)

		// Loop through all unassigned players
		for(var/mob/new_player/player in unassigned)

			// Loop through all jobs
			for(var/datum/job/job in shuffledoccupations)
				if(TryAssignJob(player,level,job))
					unassigned -= player
					break

	// Hand out random jobs to the people who didn't get any in the last check
	// Also makes sure that they got their preference correct

	//People who wants to be peasants, sure, go on.
	Debug("DO, Running peasants Check 1")
	var/datum/job/assist = new /datum/job/peasant()
	var/list/peasants_candidates = FindOccupationCandidates(assist, 3)
	Debug("AC1, Candidates: [peasants_candidates.len]")
	for(var/mob/new_player/player in peasants_candidates)
		Debug("AC1 pass, Player: [player]")
		AssignRole(player, "Peasant")
		peasants_candidates -= player
	Debug("DO, AC1 end")
	
	for(var/mob/new_player/player in unassigned)
		if(player.client.prefs.alternate_option == GET_RANDOM_JOB)
			GiveRandomJob(player)

	Debug("DO, Standard Check end")

	Debug("DO, Running AC2")

	// For those who wanted to be assistant if their preferences were filled, here you go.
	for(var/mob/new_player/player in unassigned)
		if(player.client.prefs.alternate_option == BE_PEASANT)
			Debug("AC2 Assistant located, Player: [player]")
			AssignRole(player, "Peasant")

	//For ones returning to lobby
	for(var/mob/new_player/player in unassigned)
		if(player.client.prefs.alternate_option == RETURN_TO_LOBBY)
			to_chat(player, "<span class='danger'>You have been returned to lobby due to your job preferences being filled.")
			player.ready = 0
			unassigned -= player
	return 1

/datum/controller/occupations/proc/TryAssignJob(var/mob/new_player/player, var/level, var/datum/job/job)
	if(!job)
		return FALSE
	if(jobban_isbanned(player, job.title))
		Debug("DO isbanned failed, Player: [player], Job:[job.title]")
		return FALSE
	if(!job.player_old_enough(player.client))
		Debug("DO player not old enough, Player: [player], Job:[job.title]")
		return FALSE
	// If the player wants that job on this level, then try give it to him.
	if(player.client.prefs.GetJobDepartment(job, level) & job.flag)

		// If the job isn't filled
		if((job.current_positions < job.spawn_positions) || job.spawn_positions == -1)
			Debug("DO pass, Player: [player], Level:[level], Job:[job.title]")
			AssignRole(player, job.title)
			return TRUE

/datum/controller/occupations/proc/EquipRank(var/mob/living/carbon/human/H, var/rank, var/joined_late = 0)
	if(!H)
		return 0
	var/datum/job/job = GetJob(rank)
	if(!joined_late)
		var/obj/S = null
		for(var/obj/effect/landmark/start/sloc in landmarks_list)
			if(sloc.name != rank)
				continue
			if(locate(/mob/living) in sloc.loc)
				continue
			S = sloc
			break
		if(!S)
			S = locate("start*[rank]") // use old stype
		if(istype(S, /obj/effect/landmark/start) && istype(S.loc, /turf))
			H.forceMove(S.loc)

	var/balance_wallet = 0
	if(job && !job.no_starting_money)
		//give them an account in the station database
		// Total between $200 and $500
		var/balance_bank = rand(100,250)
		balance_wallet = rand(100,250)
		var/bank_pref_number = H.client.prefs.bank_security
		var/bank_pref = bank_security_num2text(bank_pref_number)
		if(centcomm_account_db)
			var/datum/money_account/M = create_account(H.real_name, balance_bank, null, wage_payout = job.wage_payout, security_pref = bank_pref_number)
			global.allowable_payroll_amount += job.wage_payout + 10 //Adding an overhead of 10 credits per crew member
			if(H.mind)
				var/remembered_info = ""
				remembered_info += "<b>Your account number is:</b> #[M.account_number]<br>"
				remembered_info += "<b>Your account pin is:</b> [M.remote_access_pin]<br>"
				remembered_info += "<b>Your bank account funds are:</b> $[balance_bank]<br>"
				remembered_info += "<b>Your virtual wallet funds are:</b> $[balance_wallet]<br>"

				if(M.transaction_log.len)
					var/datum/transaction/T = M.transaction_log[1]
					remembered_info += "<b>Your account was created:</b> [T.time], [T.date] at [T.source_terminal]<br>"
				H.mind.store_memory(remembered_info)

				H.mind.initial_account = M

			// If they're head, give them the account info for their department
			if(H.mind && job.head_position)
				var/remembered_info = ""
				var/datum/money_account/department_account = department_accounts[job.department]

				if(department_account)
					remembered_info += "<b>Your department's account number is:</b> #[department_account.account_number]<br>"
					remembered_info += "<b>Your department's account pin is:</b> [department_account.remote_access_pin]<br>"
					remembered_info += "<b>Your department's account funds are:</b> $[department_account.money]<br>"

				H.mind.store_memory(remembered_info)

			spawn()
				to_chat(H, "<span class='danger'>Your bank account number is: <span class='darknotice'>[M.account_number]</span>, your bank account pin is: <span class='darknotice'>[M.remote_access_pin]</span></span>")
				to_chat(H, "<span class='danger'>Your virtual wallet funds are: <span class='darknotice'>$[balance_wallet]</span>, your bank account funds are: <span class='darknotice'>$[balance_bank]</span></span>")
				to_chat(H, "<span class='danger'>Your bank account security level is set to: <span class='darknotice'>[bank_pref]</span></span>")

	var/alt_title = null

	if(job)
		job.equip(H) //Outfit datum
	else
		to_chat(H, "Your job is [rank] and the game just can't handle it! Please report this bug to an administrator.")

	H.job = rank


	if(H.mind)
		H.mind.assigned_role = rank
		alt_title = H.mind.role_alt_title

		switch(rank)
			if("Mobile MMI")
				H.MoMMIfy()
				return 1

	if(job)
		job.introduce(H, (alt_title ? alt_title : rank))
	else
		to_chat(H, "<B>You are the [alt_title ? alt_title : rank].</B>")
		to_chat(H, "<b>As the [alt_title ? alt_title : rank] you answer directly to [job.supervisors]. Special circumstances may change this.</b>")
		if(job.req_admin_notify)
			to_chat(H, "<b>You are playing a job that is important for Game Progression. If you have to disconnect, please notify the admins via adminhelp.</b>")

	if(job && job.priority)
		job.priority_reward_equip(H)

	return 1

/datum/controller/occupations/proc/HandleFeedbackGathering()
	for(var/datum/job/job in occupations)
		var/tmp_str = "|[job.title]|"

		var/level1 = 0 //high
		var/level2 = 0 //medium
		var/level3 = 0 //low
		var/level4 = 0 //never
		var/level5 = 0 //banned
		var/level6 = 0 //account too young
		for(var/mob/new_player/player in player_list)
			if(!(player.ready && player.mind && !player.mind.assigned_role))
				continue //This player is not ready
			if(jobban_isbanned(player, job.title))
				level5++
				continue
			if(!job.player_old_enough(player.client))
				level6++
				continue
			if(player.client.prefs.GetJobDepartment(job, 1) & job.flag)
				level1++
			else if(player.client.prefs.GetJobDepartment(job, 2) & job.flag)
				level2++
			else if(player.client.prefs.GetJobDepartment(job, 3) & job.flag)
				level3++
			else
				level4++ //not selected

		tmp_str += "HIGH=[level1]|MEDIUM=[level2]|LOW=[level3]|NEVER=[level4]|BANNED=[level5]|YOUNG=[level6]|-"
		feedback_add_details("job_preferences",tmp_str)
