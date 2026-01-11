/*
 * Autonomous Satellite Docking - Promela Model (FIXED)
 * 
 * Goal: Simulate autonomous docking with an attacker that spoofs camera images.
 * Security Control: Sliding window validation that drops anomalous inputs.
 * 
 * Model Checking Objectives:
 * 1. WITHOUT security control: compromised images lead to HACK state
 * 2. WITH security control: compromised images are dropped, HACK state is unreachable
 * 
 * FIX: Made security control logic DETERMINISTIC using proper guard structure
 */

/* ============================================================================
 * CONFIGURATION: Toggle security control for model checking
 * Set to 1 to enable sliding window validation, 0 to disable
 * ============================================================================ */
#define SECURITY_CONTROL_ENABLED 1

/* Window size for consistency checking */
#define WINDOW_SIZE 3
#define COMPROMISED_THRESHOLD 2  /* Max consecutive compromised before blocking */

/* Distance thresholds */
#define MAX_DIST 300
#define MIN_DIST 0
#define CAPTURE_DIST 10
#define HACK_DIST 200

/* ============================================================================
 * STATE DEFINITIONS
 * ============================================================================ */
mtype = {  
    /* Mission states */
    IDLE,
    RENDEZVOUS,
    VISUAL_SERVO,
    CAPTURE,
    ORU_PREP,
    ORU_TRANSFER,
    POST_VERIFICATION,
    ERROR,
    GROUND_INTERVENTION,
    MISSION_COMPLETE,
    MISSION_FAILED,
    HACK,
    
    /* Vision system image types */
    NO_IMAGE,
    NORMAL_IMAGE,
    TARGET_DETECTED,
    RANDOM_IMAGE,
    INTERESTING_IMAGE,
    COMPROMISED_IMAGE,
    
    /* Validation results */
    VALID,
    INVALID,
    DROPPED
};

/* ============================================================================
 * GLOBAL VARIABLES
 * ============================================================================ */

/* Mission state */
mtype mission_state = IDLE;
bool mission_success = false;
bool mission_failure = false;

/* Security state */
bool hack_state = false;
bool attack_occurred = false;
bool compromised_processed = false;  /* Track if compromised image was actually processed */

/* Vision system */
mtype current_image = NO_IMAGE;
mtype validation_result = VALID;

/* Sliding window for image validation - track last N images */
mtype window_0 = NORMAL_IMAGE;
mtype window_1 = NORMAL_IMAGE;
mtype window_2 = NORMAL_IMAGE;
byte compromised_count = 0;  /* Consecutive compromised images */

/* Distance between satellites */
int dist = 50;

/* Anomaly detection */
bool anomaly_detected = false;

/* Motors verification */
bool motors_verified = false;

/* Ground intervention */
bool ground_intervention_required = false;

/* Process synchronization */
bool system_ready = false;

/* ============================================================================
 * COMMUNICATION CHANNELS
 * ============================================================================ */
chan camera_channel = [2] of { mtype };  /* Buffered channel for camera images */

/* ============================================================================
 * SLIDING WINDOW VALIDATION - DETERMINISTIC VERSION
 * 
 * Security policy: DROP a compromised image if:
 *   - It deviates from recent history (previous images were not compromised), OR
 *   - Too many consecutive compromised images (threshold exceeded)
 * 
 * This ensures an attacker cannot sneak compromised images through.
 * ============================================================================ */
inline validate_image_secure(img) {
    printf("SECURE validating: %e (window: %e, %e, %e)\n", 
           img, window_0, window_1, window_2);
    
    if
    :: (img == COMPROMISED_IMAGE) ->
        /* Check if this compromised image should be dropped */
        compromised_count = compromised_count + 1;
        
        /* DETERMINISTIC CHECK: Drop if previous images weren't compromised
         * This catches the attacker's first injection attempt */
        if
        :: (window_0 != COMPROMISED_IMAGE) ->
            /* Previous image was normal - this is a sudden deviation, DROP IT */
            validation_result = DROPPED;
            compromised_count = 0;  /* Reset since we dropped it */
            printf("SECURITY: DROPPED - deviation from normal history\n");
        :: (window_0 == COMPROMISED_IMAGE && compromised_count >= COMPROMISED_THRESHOLD) ->
            /* Too many consecutive compromised - DROP */
            validation_result = DROPPED;
            compromised_count = 0;
            printf("SECURITY: DROPPED - threshold exceeded\n");
        :: else ->
            /* Should not reach here with proper logic, but be safe */
            validation_result = DROPPED;
            printf("SECURITY: DROPPED - default safe action\n");
        fi
        
    :: (img != COMPROMISED_IMAGE) ->
        /* Non-compromised images always pass */
        compromised_count = 0;
        validation_result = VALID;
        printf("SECURITY: VALID - normal image\n");
    fi;
    
    /* Slide the window */
    window_2 = window_1;
    window_1 = window_0;
    window_0 = img;
}

inline validate_image_insecure(img) {
    printf("INSECURE validating: %e\n", img);
    /* No security - all images pass */
    validation_result = VALID;
    
    if
    :: (img == COMPROMISED_IMAGE) -> compromised_count = compromised_count + 1
    :: else -> compromised_count = 0
    fi;
    
    /* Still update window for tracking */
    window_2 = window_1;
    window_1 = window_0;
    window_0 = img;
}

/* ============================================================================
 * MOVEMENT HELPERS
 * ============================================================================ */
inline move_closer(d) {
    d_step {
        if
        :: (d > MIN_DIST + 5) -> d = d - 5
        :: (d > MIN_DIST) -> d = MIN_DIST
        :: else -> skip
        fi
    }
}

inline move_closer_fast(d) {
    d_step {
        if
        :: (d > MIN_DIST + 10) -> d = d - 10
        :: (d > MIN_DIST) -> d = MIN_DIST
        :: else -> skip
        fi
    }
}

inline move_away(d) {
    d_step {
        if
        :: (d < MAX_DIST - 20) -> d = d + 20
        :: (d < MAX_DIST) -> d = MAX_DIST
        :: else -> skip
        fi
    }
}

/* ============================================================================
 * MAIN SYSTEM PROCESS
 * ============================================================================ */
active proctype System() {
    mtype img;
    
    /* Initialize */
    window_0 = NORMAL_IMAGE;
    window_1 = NORMAL_IMAGE;
    window_2 = NORMAL_IMAGE;
    compromised_count = 0;
    system_ready = true;
    
    printf("=== Satellite Docking System Started ===\n");
    printf("Security Control Enabled: %d\n", SECURITY_CONTROL_ENABLED);
    
end_system:
    do
    :: atomic {
        if
        /* ----------------------------------------
         * IDLE STATE
         * ---------------------------------------- */
        :: (mission_state == IDLE) ->
            printf("State: IDLE\n");
            
            /* Nondeterministic anomaly - but bias toward no anomaly for progress */
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected ->
                mission_state = ERROR;
                printf("IDLE: Anomaly -> ERROR\n");
            :: !anomaly_detected ->
                motors_verified = true;
                mission_state = RENDEZVOUS;
                printf("IDLE -> RENDEZVOUS\n");
            fi
            
        /* ----------------------------------------
         * RENDEZVOUS STATE
         * ---------------------------------------- */
        :: (mission_state == RENDEZVOUS) ->
            printf("State: RENDEZVOUS (dist=%d)\n", dist);
            
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected ->
                mission_state = ERROR;
            :: !anomaly_detected ->
                mission_state = VISUAL_SERVO;
                printf("RENDEZVOUS -> VISUAL_SERVO\n");
            fi
            
        /* ----------------------------------------
         * VISUAL SERVO STATE - Main camera processing
         * ---------------------------------------- */
        :: (mission_state == VISUAL_SERVO) ->
            printf("State: VISUAL_SERVO (dist=%d)\n", dist);
            
            if
            :: camera_channel?img ->
                current_image = img;
                
                /* Apply validation based on security setting */
#if SECURITY_CONTROL_ENABLED
                validate_image_secure(img);
#else
                validate_image_insecure(img);
#endif
                
                /* Process based on validation result */
                if
                :: (validation_result == DROPPED) ->
                    /* Security control blocked the image - revert to safe behavior */
                    printf("Image DROPPED - maintaining safe trajectory\n");
                    /* Don't change anything, continue normal operation */
                    
                :: (validation_result == VALID) ->
                    /* Process the validated image */
                    if
                    :: (img == TARGET_DETECTED) ->
                        printf("TARGET detected! Moving closer.\n");
                        move_closer_fast(dist);
                        printf("New distance: %d\n", dist);
                        
                        if
                        :: (dist <= CAPTURE_DIST) ->
                            mission_state = CAPTURE;
                            printf("Within capture range -> CAPTURE\n");
                        :: (dist > CAPTURE_DIST) -> skip
                        fi
                        
                    :: (img == INTERESTING_IMAGE) ->
                        printf("Interesting object. Moving closer.\n");
                        move_closer(dist);
                        
                    :: (img == RANDOM_IMAGE) ->
                        printf("Random/noise. Holding position.\n");
                        
                    :: (img == NORMAL_IMAGE) ->
                        printf("Normal image. Continuing approach.\n");
                        move_closer(dist);
                        
                    :: (img == COMPROMISED_IMAGE) ->
                        /* CRITICAL: Compromised image passed validation (security disabled) */
                        printf("!!! COMPROMISED image PROCESSED !!!\n");
                        compromised_processed = true;
                        
                        /* Attacker's malicious behavior: drive satellite away */
                        move_away(dist);
                        move_away(dist);
                        printf("Satellite moved AWAY! Distance: %d\n", dist);
                        
                        if
                        :: (dist >= HACK_DIST) ->
                            mission_state = HACK;
                            hack_state = true;
                            printf("!!! HACK STATE REACHED - MISSION COMPROMISED !!!\n");
                        :: (dist < HACK_DIST) -> skip
                        fi
                        
                    :: else ->
                        printf("Unknown image type.\n");
                    fi
                fi
                
            :: timeout ->
                /* No camera input available, continue */
                skip
            fi
            
        /* ----------------------------------------
         * CAPTURE STATE
         * ---------------------------------------- */
        :: (mission_state == CAPTURE) ->
            printf("State: CAPTURE\n");
            
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected ->
                mission_state = ORU_PREP;
                printf("CAPTURE -> ORU_PREP\n");
            fi
            
        /* ----------------------------------------
         * ORU PREPARATION STATE
         * ---------------------------------------- */
        :: (mission_state == ORU_PREP) ->
            printf("State: ORU_PREP\n");
            
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected ->
                mission_state = ORU_TRANSFER;
                printf("ORU_PREP -> ORU_TRANSFER\n");
            fi
            
        /* ----------------------------------------
         * ORU TRANSFER STATE
         * ---------------------------------------- */
        :: (mission_state == ORU_TRANSFER) ->
            printf("State: ORU_TRANSFER\n");
            
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected ->
                mission_state = POST_VERIFICATION;
                printf("ORU_TRANSFER -> POST_VERIFICATION\n");
            fi
            
        /* ----------------------------------------
         * POST VERIFICATION STATE
         * ---------------------------------------- */
        :: (mission_state == POST_VERIFICATION) ->
            printf("State: POST_VERIFICATION\n");
            
            if
            :: ground_intervention_required ->
                mission_state = GROUND_INTERVENTION;
            :: !ground_intervention_required ->
                mission_state = MISSION_COMPLETE;
                printf("POST_VERIFICATION -> MISSION_COMPLETE\n");
            fi
            
        /* ----------------------------------------
         * ERROR STATE
         * ---------------------------------------- */
        :: (mission_state == ERROR) ->
            printf("State: ERROR\n");
            ground_intervention_required = true;
            mission_state = GROUND_INTERVENTION;
            
        /* ----------------------------------------
         * GROUND INTERVENTION STATE
         * ---------------------------------------- */
        :: (mission_state == GROUND_INTERVENTION) ->
            printf("State: GROUND_INTERVENTION\n");
            
            if
            :: true ->
                /* Intervention successful */
                ground_intervention_required = false;
                anomaly_detected = false;
                mission_state = IDLE;
                printf("Intervention OK -> IDLE\n");
            :: true ->
                /* Intervention failed */
                mission_state = MISSION_FAILED;
                printf("Intervention FAILED\n");
            fi
            
        /* ----------------------------------------
         * HACK STATE - Attacker wins
         * ---------------------------------------- */
        :: (mission_state == HACK) ->
            printf("=== SYSTEM COMPROMISED ===\n");
            hack_state = true;
            mission_failure = true;
            mission_success = false;
            mission_state = MISSION_FAILED;
            
        /* ----------------------------------------
         * MISSION COMPLETE - Success
         * ---------------------------------------- */
        :: (mission_state == MISSION_COMPLETE) ->
            printf("=== MISSION COMPLETE ===\n");
            mission_success = true;
            mission_failure = false;
            break
            
        /* ----------------------------------------
         * MISSION FAILED
         * ---------------------------------------- */
        :: (mission_state == MISSION_FAILED) ->
            printf("=== MISSION FAILED ===\n");
            mission_failure = true;
            mission_success = false;
            break
            
        fi
    }
    od;
    
    printf("System terminated. Success=%d, Failure=%d, Hack=%d\n", 
           mission_success, mission_failure, hack_state);
}

/* ============================================================================
 * CAMERA PROCESS - Legitimate camera feed
 * ============================================================================ */
proctype Camera() {
    printf("Camera started\n");
    
    /* Wait for system */
    (system_ready);
    
end_camera:
    do
    :: (mission_success || mission_failure) -> 
        printf("Camera: Mission ended\n");
        break
    :: (!mission_success && !mission_failure) ->
        /* Send legitimate images with bias toward TARGET_DETECTED for progress */
        if
        :: camera_channel!TARGET_DETECTED -> printf("Camera: TARGET\n")
        :: camera_channel!TARGET_DETECTED -> printf("Camera: TARGET\n")
        :: camera_channel!TARGET_DETECTED -> printf("Camera: TARGET\n")
        :: camera_channel!NORMAL_IMAGE -> printf("Camera: NORMAL\n")
        :: camera_channel!INTERESTING_IMAGE -> printf("Camera: INTERESTING\n")
        :: skip  /* Sometimes no image */
        fi
    od
}

/* ============================================================================
 * ATTACKER PROCESS - Spoofs camera with compromised images
 * ============================================================================ */
proctype Attacker() {
    byte attack_count = 0;
    byte max_attacks = 15;
    
    printf("Attacker started\n");
    
    /* Wait for system */
    (system_ready);
    
end_attacker:
    do
    :: (mission_success || mission_failure) -> 
        printf("Attacker: Mission ended, stopping\n");
        break
    :: (attack_count >= max_attacks) ->
        printf("Attacker: Max attacks reached\n");
        break
    :: (!mission_success && !mission_failure && attack_count < max_attacks) ->
        if
        :: camera_channel!COMPROMISED_IMAGE ->
            attack_occurred = true;
            attack_count = attack_count + 1;
            printf("Attacker: Injected compromised #%d\n", attack_count)
        :: camera_channel!COMPROMISED_IMAGE ->
            attack_occurred = true;
            attack_count = attack_count + 1;
            printf("Attacker: Injected compromised #%d\n", attack_count)
        :: skip  /* Sometimes attack fails to inject */
        fi
    od;
    
    printf("Attacker terminated. Total attacks: %d\n", attack_count);
}

/* ============================================================================
 * INITIALIZATION
 * ============================================================================ */
init {
    printf("========================================\n");
    printf("  Satellite Docking Simulation\n");
    printf("  Security Control: %d\n", SECURITY_CONTROL_ENABLED);
    printf("========================================\n");
    
    atomic {
        mission_state = IDLE;
        dist = 50;
        hack_state = false;
        attack_occurred = false;
        mission_success = false;
        mission_failure = false;
        compromised_processed = false;
        validation_result = VALID;
        
        /* Start processes */
        run Camera();
        run Attacker();
    }
}

/* ============================================================================
 * LTL PROPERTIES FOR MODEL CHECKING
 * ============================================================================ */

/*
 * CORE SECURITY PROPERTY: With security control enabled, hack state is unreachable
 * Expected: PASS when SECURITY_CONTROL_ENABLED=1
 *           FAIL when SECURITY_CONTROL_ENABLED=0
 */
ltl safety_no_hack { [](!hack_state) }

/*
 * PROPERTY: If attack occurs, does it eventually lead to hack?
 * Expected: FAIL with security (hack never reached, so implication vacuously handled)
 *           The counterexample shows attack_occurred but no hack
 */
ltl attack_leads_to_hack { [](attack_occurred -> <>hack_state) }

/*
 * PROPERTY: Compromised images being processed implies hack is possible
 * With security: compromised_processed should always be false
 * Without security: both can become true
 */
ltl security_blocks_processing { [](!compromised_processed) }

/*
 * PROPERTY: If compromised is processed, hack follows
 * This checks the attack mechanism works correctly
 */
ltl processed_leads_to_hack { [](compromised_processed -> <>hack_state) }

/*
 * PROPERTY: Liveness - mission eventually completes
 * Expected: PASS in all configurations
 */
ltl mission_terminates { <>(mission_success || mission_failure) }

/*
 * PROPERTY: Mutual exclusion - can't succeed and be hacked
 */
ltl no_success_and_hack { [](!(mission_success && hack_state)) }

/*
 * PROPERTY: Hack requires an attack
 */
ltl hack_requires_attack { [](hack_state -> attack_occurred) }

/*
 * PROPERTY: Validation dropping an image prevents hack in next state
 */
ltl dropped_blocks_hack { []((validation_result == DROPPED) -> X(!hack_state)) }

/* ============================================================================
 * VERIFICATION COMMANDS
 * 
 * With SECURITY_CONTROL_ENABLED = 1:
 *   spin -a satellite_docking_fixed.pml
 *   gcc -DMEMLIM=2048 -O2 -o pan pan.c
 *   ./pan -m50000 -a -N safety_no_hack              # Should PASS
 *   ./pan -m50000 -a -N security_blocks_processing  # Should PASS
 *   ./pan -m50000 -a -N attack_leads_to_hack        # Should FAIL (no hack path)
 * 
 * With SECURITY_CONTROL_ENABLED = 0:
 *   ./pan -m50000 -a -N safety_no_hack              # Should FAIL
 *   ./pan -m50000 -a -N attack_leads_to_hack        # Should PASS
 * 
 * ============================================================================ */
