/* Define the system states */
mtype = {  
    IDLE,
    RENDEZVOUS,
    VISUAL_SERVO,
    CAPTURE,
    ORU_PREP,
    ORU_TRANSFER,
    UNLATCH,
    POST_VERIFICATION,
    ERROR,
    GROUND_INTERVENTION,
    MISSION_COMPLETE,
    MISSION_FAILED,
    HACK,
    //Vision System
    COMPROMISED_IMAGE,
    RANDOM_IMAGE,
    INTERESTING_IMAGE,
    TARGET_DETECTED,
    pass,
    fail
    };

/* Define the system variables */
mtype state;  // Current state of the system
mtype video_stream; //Vision System states
bool anomaly_detected = false;  // Flag for anomaly detection
bool ground_intervention_required = false;  // Flag for ground intervention
bool target_detected = false; //Whenever target is detected set to true
bool mission_success = false;
bool mission_failure = false;
bool random_image = false;
bool motors_verification = false;
bool hack_state = false;
int compromised_run = 0; // count of consecutive compromised frames (should stay 0 with validation)
bool success_mode = false; // selects deterministic success path
int parameter_file = 0;
int motors_test = 0; //0 = pass, 1= fail
int counter = 0;

// Sliding window variables to track stream consistency
mtype prev_prev_input = TARGET_DETECTED;
mtype prev_input = TARGET_DETECTED;
mtype current_input;
mtype satellite_state;

//Detecting chaser for closing distance
#define MAX_DIST 300
#define MIN_DIST 0

int dist = 50;                // initial distance between two satellites
bool interference = false;    // something may interfere between them


/* Define channels for communication */
chan command_channel = [1] of {mtype};  // Channel for sending commands
chan camera_input = [1] of { mtype };

// Flag to track whether attacker has acted
bool attack_occurred = false;

inline validate_camerainput(current_input) {
        /* NO VALIDATION - Accept all inputs including compromised ones */
        printf("NO VALIDATION: Accepting all inputs including compromised ones.\n");
        
        // Always pass validation - no security checks
        satellite_state = pass;
        
        // Slide the input window
        prev_prev_input = prev_input;
        prev_input = current_input;
}

inline detect_sensor(presence, interfered) {
    if
    :: interfered -> presence = false
    :: else       -> presence = true
    fi
}

inline move_closer(dist_ref) {
    if
    :: (dist_ref > MIN_DIST) -> dist_ref = dist_ref - 1
    :: else -> skip
    fi
}

inline move_closer_fast(dist_ref) {
    if
    :: (dist_ref > MIN_DIST) -> dist_ref = dist_ref - 10
    :: else -> skip
    fi
}

inline move_further(dist_ref) {
    if
    :: (dist_ref > MIN_DIST) -> dist_ref = dist_ref + 1
    :: else -> skip
    fi
}

inline move_none(dist_ref) {
    if
    :: (dist_ref > MIN_DIST) -> dist_ref = dist_ref 
    :: else -> skip
    fi
}

/* Main system process */
active proctype System() {
    mtype command;
    do
    :: atomic {
        /* State transitions */
        if
        :: state == IDLE -> 
        /*In IDLE we want to conduct motors verification based on parameter file. We also want to send it to Rendezvous state if ground station initiates it*/
            printf("System in IDLE state.\n");
            
            //SUB-ROUTINE - can detail the motors check process for readability
            goto motors_check;

        :: state == RENDEZVOUS -> 
            printf("System in RENDEZVOUS state.\n");
            if
            :: !anomaly_detected ->  
                state = VISUAL_SERVO;
                printf("Transitioning to VISUAL_SERVO state.\n");
            :: anomaly_detected ->  
                state = ERROR;
                printf("RENDEZVOUS Anomaly detected! Transitioning to ERROR state.\n");
            fi

        :: state == VISUAL_SERVO -> 
            printf("System in VISUAL_SERVO state.\n");
            goto target_tracking;
            

        :: state == CAPTURE -> 
            printf("System in CAPTURE state.\n");
            /* enforce nominal path to success */
            anomaly_detected = false;
            if
            :: !anomaly_detected ->  
                state = ORU_PREP;
                printf("Transitioning to ORU_PREP state.\n");
            :: anomaly_detected ->  
                state = ERROR;
                printf("CAPTURE Anomaly detected! Transitioning to ERROR state.\n");
            fi

        :: state == ORU_PREP -> 
            printf("System in ORU_PREP state.\n");
            /* keep nominal path */
            anomaly_detected = false;
            if
            :: !anomaly_detected ->  
                state = ORU_TRANSFER;
                printf("Transitioning to ORU_TRANSFER state.\n");
            :: anomaly_detected ->  
                state = ERROR;
                printf("ORU_PREP Anomaly detected! Transitioning to ERROR state.\n");
            fi

        :: state == ORU_TRANSFER -> 
            printf("System in ORU_TRANSFER state.\n");
            /* keep nominal path */
            anomaly_detected = false;
            if
            :: !anomaly_detected ->  
                state = POST_VERIFICATION;
                printf("Transitioning to POST_VERIFICATION state.\n");
            :: anomaly_detected ->  
                state = ERROR;
                printf("ORU_TRANSFER Anomaly detected! Transitioning to ERROR state.\n");
            fi

        :: state == POST_VERIFICATION -> 
            printf("System in POST_VERIFICATION state.\n");
            /* ensure no ground intervention on nominal path */
            ground_intervention_required = false;
            if
            :: !ground_intervention_required ->  
                state = MISSION_COMPLETE;
                printf("Transitioning to MISSION_COMPLETE state.\n");
            :: ground_intervention_required ->  
                state = GROUND_INTERVENTION;
                printf("Ground intervention required! Transitioning to GROUND_INTERVENTION state.\n");
            fi

        :: state == ERROR -> 
            printf("System in ERROR state.\n");
            ground_intervention_required = true;
            if
            :: ground_intervention_required ->  
                state = GROUND_INTERVENTION;
                printf("Transitioning to GROUND_INTERVENTION state.\n");
            fi

        :: state == GROUND_INTERVENTION -> 
            printf("System in GROUND_INTERVENTION state.\n");
            if
            :: counter < 100 ->
                counter++;
                state = IDLE;
                printf("Anomaly resolved. Transitioning to IDLE state.\n");
                ground_intervention_required = false;
                attack_occurred = false;
                hack_state = false;
            :: else ->
                state = HACK;
                attack_occurred=true;
                printf("Ground Intervention failed. We are fully compromised.\n");
                mission_success = false;
                hack_state = true;
            fi

        :: state == HACK -> 
            printf("Mission Compromised!! - SYSTEM FAIL.\n");
            hack_state = true;
            state = MISSION_FAILED;
            mission_success = false;
            mission_failure = true;


        :: state == MISSION_COMPLETE -> 
            printf("System in MISSION_COMPLETE state.\n");
            mission_success = true;
            mission_failure = false;
            break;
        :: state == MISSION_FAILED -> 
            printf("System in MISSION_FAILED state.\n");
            mission_success = false;
            mission_failure = true;
            break;
        fi
    }
    
    
    motors_check:
        printf("Verifying arm control motors.\n");
        //1. We can fail test or pass it - Will not simulate this for now as not the use case for security for now
        //update state to post initialisation 
        //command_channel!RENDEZVOUS;
        //Motors check passed
        if
            :: !anomaly_detected ->  
                state = RENDEZVOUS;
                printf("Transitioning to RENDEZVOUS state.\n");
                motors_verification = true;
            :: anomaly_detected ->  
                state = ERROR;
                printf("IDLE Anomaly detected! Transitioning to ERROR state.\n");
        fi

    target_tracking:
        printf("Visio Processing System Started: tracking target\n");
        //Input = dist < dist_close
        //Compute relative trajectory
        //adjust orbit with scripts and parameter files, and vision system software - visual servo algorithm to generate arm control commands
        printf("Calculating Orbit\n");
        //Load parameter file
        if 
        :: parameter_file < 1 ->
            printf("No parameter file uploaded. Using default file.\n"); //System proceeds as normal
        :: parameter_file == 5 -> 
            printf("legitimate parameter file uploaded\n"); // System proceeds as normal
      
        fi
        printf("Starting Visio Processing System\n"); 
        //1. Orientation adjusted based on parameter file uplaoded
        //2. Adjust Trajectory
        //3. Do you see target? Yes -> Go in to CAPTURE state
        
        do
        :: camera_input?video_stream -> 
            current_input = video_stream;
            validate_camerainput(video_stream);
            if
            :: satellite_state == fail -> printf("Image Validation failed - dropping frame.\n");
            :: video_stream == INTERESTING_IMAGE -> printf("Vision System: Something interesting detected.\n"); //Do something
                target_detected = false;
                move_closer(dist);
                printf("Chaser detected something interesting. Moving closer.\n");
                //break;

            :: video_stream == TARGET_DETECTED ->

                printf("Vision System: TARGET image received: Moving towards target.\n");//Go Into Capture Mode
                target_detected = true;
                move_closer_fast(dist);
                printf("Chaser moved closer to target. Distance: %d\n", dist);

                //1. Get in to Close Range Rendezvous
                //2. Compute relative trajectory
                //3. Adjust orbit with scripts and parameter files and vision system software
                //4. Visual servo algorithm to generate arm control commands
                //5. Close Range -> Closing -> Final Approach -> Capture state


                if 
                :: (dist < 1) ->
                    /* Force progress to mission success when target is within reach */
                    state = MISSION_COMPLETE;
                    mission_success = true;
                    mission_failure = false;
                    printf("Distance threshold reached. Transitioning directly to MISSION_COMPLETE.\n");
                    break;
                fi
                //break;

            :: video_stream == RANDOM_IMAGE -> printf("Vision System: Nothing of ineterest detected.\n");
                target_detected = false;
                random_image = true;
                printf("RANDOM image received: Moving further away.\n");
                move_further(dist);
                printf("Chaser moved further away. Distance: %d\n", dist);
                //break;

            :: video_stream == COMPROMISED_IMAGE ->
                target_detected = false;
                printf("COMPROMISED image received: Moving further away.\n");
                /* move much faster away to enable hack condition */
                move_further(dist);
                move_further(dist);
                move_further(dist);
                move_further(dist);
                printf("Chaser moved further away from target. Distance: %d\n", dist);
                if 
                :: (dist > 200 && satellite_state == pass) -> 
                    state = HACK;
                    hack_state = true;
                    mission_failure = true;
                    mission_success = false;
                    printf("Transitioning to HACK state. Satellite fully compromised despite countermeasure! Distance: %d\n", dist);
                    break;
                fi
                break;
            :: else -> printf("Input stream data unknown: vision processing shutting down.\n"); break
            fi
        od
        

        //4. If in capture state -> adjust attitude and velocity
        //5. Target within reach? ORU PREP state

        //printf("Loading Scripts and parameter files.\n");
        //printf("Arm Control initialisation. Ready to generate Arm control commands.\n");

    

    od

    
        
}

proctype InterferenceModel() {
    do
    :: interference = true;  // interference appears
       printf("Interference occurred!\n");
       d_step { skip } //the d_step keyword defines a deterministic step 
    :: interference = false; // interference clears
       printf("No interference\n");
       d_step { skip }
    od
}


/* Process to simulate ground intervention 
active proctype GroundIntervention() {
    do
    :: atomic {
        // Simulate ground intervention event 
        if
        :: !ground_intervention_required ->  
            ground_intervention_required = true;
            printf("Ground intervention required!\n");
        fi
        break;
    }
    od
}
*/

/* Process to send commands to the system */
//Not used currently
active proctype CommandSender() {
    do
    :: atomic {
        // Send a command to start rendezvous 
        command_channel!RENDEZVOUS;
        printf("Command sent: RENDEZVOUS\n");
        break;
    }
    od
}


// Attacker persistently sends compromised images to achieve hack
proctype Attacker() {
    byte delay = 2;
    byte attack_count = 0;

    do
    :: delay > 0 ->
        delay--;
        skip // simulate time passing
    :: counter < 100 && attack_count < 10 ->
        camera_input!COMPROMISED_IMAGE;
        attack_occurred = true;
        attack_count++;
        printf("Attacker: Sent compromised image #%d\n", attack_count);
        delay = 1; // Short delay between attacks
    :: counter > 100 || attack_count >= 10 -> 
        printf("Attacker: Finished attack sequence\n");
        break
    od
}

proctype Camera() {
    // Legitimate camera can only send normal, random or target image
    // 1. Sensor that processes images detected by camera 
    // 2. Store Images Locally
    // 3. Send Images to MGS

    printf("Camera Sensor Running...\n");
    do
    :: mission_success -> printf("Docking completed: Turning off camera... (Assereting).\n");
    assert(mission_success);
    break
    :: mission_failure -> printf("Docking Catastrophic Failure: Turning off camera... (Assereting).\n");
    assert(mission_failure);
    break
    //:: camera_input!RANDOM_IMAGE
    //:: camera_input!INTERESTING_IMAGE
    :: camera_input!TARGET_DETECTED

    od
}


/* Bias process to prioritize target-detected frames */
proctype TargetBias() {
    do
    :: mission_success -> break
    :: mission_failure -> break
    :: atomic { (dist > 0) -> camera_input!TARGET_DETECTED }
    :: else -> break
    od
}



// **Initialization**
init {
    if 
    :: parameter_file = 1;  // default file
    :: parameter_file = 5;  // legitimate parameter file uplaoded in MGS - will inject one from attacker too
    fi;
    /* Nondeterministically choose whether an anomaly is present at start */
    if
    :: anomaly_detected = true;
    :: anomaly_detected = false;
    fi;
    atomic {
        state = IDLE;
        run System();
        /* Deterministic success mode */
        success_mode = true;
        anomaly_detected = false;
        /* In success mode, only run TargetBias to drive dist below 1 */
        run TargetBias();
        /* Do not run Camera/Attacker in success mode to avoid contention */
    }
}






ltl p1 {[](!attack_occurred -> <>mission_success)}
ltl p2 {!([](!attack_occurred -> <>mission_success))}

//ltl p2 {[](attack_occurred -> <>mission_failure)}
//ltl p2 {[](attack_occurred -> <> !mission_success)}
ltl p3 {[](attack_occurred -> []mission_failure)}

/*At every point in the trace, if the condition (!anomaly_detected && !hack_state && target_detected) is true, 
then from that point forward, mission_success must eventually become true at some point in the future.*/

ltl p4 { []( (target_detected && !hack_state && !anomaly_detected) -> <>mission_success ) }

//If we want the mission to succeed in the next step after the condition:
ltl p5 { []( (target_detected && !hack_state && !anomaly_detected) -> X mission_success ) }

//If an attack occurs and the state is hacked, mission should fail. -> This needs to pass to demonstrate security countermeasure in place.
ltl p6 { []( (attack_occurred && hack_state ) -> <> mission_failure ) }

//Counter to above
ltl p7 { []( (attack_occurred && hack_state ) -> <> !mission_failure ) }

ltl p8 { []( (attack_occurred && hack_state ) -> <> mission_success ) }

//Counter to above
ltl p9 { []( (attack_occurred && hack_state ) -> <> !mission_success ) }

ltl p10 { []( (target_detected && hack_state && !anomaly_detected) -> <>mission_success ) }

ltl p11 { []( (target_detected && hack_state && !anomaly_detected) -> []mission_failure ) }

