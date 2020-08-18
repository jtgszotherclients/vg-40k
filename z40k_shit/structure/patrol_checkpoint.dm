/*
Todo: So I don't forget.
Tie it into the point system and the factions.
Maybe give the person who actually did it a point of potential for doing so.
*/
/obj/structure/patrol_checkpoint
	name = "Checkpoint Signaller"
	icon = 'z40k_shit/icons/obj/orbital.dmi'
	icon_state = "ob1"
	desc = "One of many consoles made to signal that the patrol has reached its destination, and stayed there long enough to do its job."
	var/location = "Southwest Factory" //A easy way to var-edit locations.
	density = 1
	anchored = 1

	//Have we checked in?
	var/checked_in = FALSE
	
	//Basically this decrements if they are near it, and it increments if they are not.
	var/checkin_pivot_timer = 10 //1 process tick is bout 2 seconds, so this is 20. integer before we are gucci
							//40 -  1 minutes and 20 seconds. integer before we fail to meet check.

	//Are we on signal cooldown?
	var/signal_cooldown = FALSE
	var/time_left = 150 //Same here, 150 * 2 = 300. So this is 300 seconds, then divided by 60 is 5. So 5 mins
	var/mob/living/logged_in_mob = null //Instead of a for loop we will get_dist between the console n this guy.

/obj/structure/patrol_checkpoint/ex_act(severity)
	return

/obj/structure/patrol_checkpoint/New()
	..()

/obj/structure/patrol_checkpoint/initialize()
	..()
	name = "Checkpoint Signal Console ([location])"
	patrol_checkpoints += src
	processing_objects += src

/obj/structure/patrol_checkpoint/Destroy()
	patrol_checkpoints -= src
	processing_objects -= src
	logged_in_mob = null
	..()

/obj/structure/patrol_checkpoint/attack_hand(mob/user)
	lets_a_go(user)

/obj/structure/patrol_checkpoint/attackby(obj/item/weapon/W, mob/user)
	..()
	if(istype(W,/obj/item/weapon/card/id))
		if(!logged_in_mob)
			var/obj/item/weapon/card/id/id_card = W	
			if(access_checkpoints in id_card.access)
				say("Checkpoint Signal in 20 Seconds. Please Standby")
				logged_in_mob = user
				checked_in = TRUE
				return
		else
			say("[user.name] already marked. Please Standby until duty has been fulfilled.")

/obj/structure/patrol_checkpoint/proc/active_signal()
	var/msg = "Patrol Checkpoint Signalled at [location]"
	say("Checkpoint Signalled. Keep fulfilling your duty.")
	var/datum/speech/speech = create_speech(msg, frequency=COMMON_FREQ, transmitter=src)
	speech.name = "[location] Checkpoint Console"
	speech.job = "Automated Announcement"
	speech.as_name = "[location] Checkpoint Console"
	speech.set_language(LANGUAGE_GALACTIC_COMMON)
	Broadcast_Message(speech, level = list(src.z))
	qdel(speech)
	for(var/role in logged_in_mob?.mind?.antag_roles)
		var/datum/role/R = logged_in_mob.mind.antag_roles[role]
		if(istype(R,/datum/role/planetary_defense_force))
			R:times_patrolled += 1 //They gain a marker.

	logged_in_mob = null

/obj/structure/patrol_checkpoint/proc/lets_a_go(mob/user)
	var/dat
	dat += {"<B> Network Interface Console</B><BR>
			<HR>
			<B>Currently checked in:</B> <I><strong>[checked_in ? "<span style=\"color:green\">TRUE</span>":"<span style=\"color:red\">FALSE</span>"]</strong></I><BR>"}

	if(!checked_in)
		dat += "<BR><I><B>SIGNAL CHECKPOINT</I></B><BR>"
		dat += "Please Scan Identification <br>"
	else
		dat += "<BR><B><span style=\"color:red\">TIME UNTIL NEXT CHECK-IN SIGNAL</span></B><BR>"
		dat += "[time_left] Seconds"

	var/datum/browser/popup = new(user, "checkpointmenu", "Network Interface Console")
	popup.set_content(dat)
	popup.open()

/obj/structure/patrol_checkpoint/process()
	if(!signal_cooldown)
		if(checked_in)
			if(get_dist(logged_in_mob,src) <= 4) //We start at 15
				checkin_pivot_timer-- //Decrement if the distance beteen us and the person who tapped in is 4 turfs or lower
			else
				checkin_pivot_timer++ //Add if the above is not true
		
			switch(checkin_pivot_timer) //Itsa switch
				if(-5 to 0) //If negative 5 to 0, we have met the goal
					active_signal()
				if(40 to 50) //If we are at this point we need to stop and reset
					var/msg = "Checkpoint Failed to Signal at [location]. Last identification was [logged_in_mob.name]"
					var/datum/speech/speech = create_speech(msg, frequency=COMMON_FREQ, transmitter=src)
					speech.name = "[location] Checkpoint Console"
					speech.job = "Automated Announcement"
					speech.as_name = "[location] Checkpoint Console"
					speech.set_language(LANGUAGE_GALACTIC_COMMON)
					Broadcast_Message(speech, level = list(src.z))
					say("Duty check Resetting. [logged_in_mob.name] noted for cowardice. Please scan your identity.")
					logged_in_mob = null
					checkin_pivot_timer = 10 //We reset this too
					checked_in = FALSE
					qdel(speech)
	else
		time_left--
		logged_in_mob = null
		if(time_left <= 0)
			signal_cooldown = FALSE
			time_left = 150


/obj/structure/patrol_checkpoint/Topic(href, href_list)
	if(usr.stat == DEAD)
		return
	var/mob/living/L = usr
	if(!istype(L))
		return

	lets_a_go(L)
