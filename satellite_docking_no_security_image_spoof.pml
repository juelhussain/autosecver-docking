/*
 * Autonomous Satellite Docking - NO SECURITY VERSION
 * 
 * This version has SECURITY_CONTROL_ENABLED = 0
 * Demonstrates that without sliding window validation,
 * compromised images lead to HACK state.
 */

#define SECURITY_CONTROL_ENABLED 0

#define WINDOW_SIZE 3
#define COMPROMISED_THRESHOLD 2

#define MAX_DIST 300
#define MIN_DIST 0
#define CAPTURE_DIST 10
#define HACK_DIST 200

mtype = {  
    IDLE, RENDEZVOUS, VISUAL_SERVO, CAPTURE, ORU_PREP, ORU_TRANSFER,
    POST_VERIFICATION, ERROR, GROUND_INTERVENTION,
    MISSION_COMPLETE, MISSION_FAILED, HACK,
    NO_IMAGE, NORMAL_IMAGE, TARGET_DETECTED, RANDOM_IMAGE,
    INTERESTING_IMAGE, COMPROMISED_IMAGE,
    VALID, INVALID, DROPPED
};

mtype mission_state = IDLE;
bool mission_success = false;
bool mission_failure = false;
bool hack_state = false;
bool attack_occurred = false;
bool compromised_processed = false;

mtype current_image = NO_IMAGE;
mtype validation_result = VALID;

mtype window_0 = NORMAL_IMAGE;
mtype window_1 = NORMAL_IMAGE;
mtype window_2 = NORMAL_IMAGE;
byte compromised_count = 0;

int dist = 50;

bool anomaly_detected = false;
bool motors_verified = false;
bool ground_intervention_required = false;
bool system_ready = false;

chan camera_channel = [2] of { mtype };

inline validate_image_secure(img) {
    printf("SECURE validating: %e\n", img);
    
    if
    :: (img == COMPROMISED_IMAGE) ->
        compromised_count = compromised_count + 1;
        
        if
        :: (window_0 != COMPROMISED_IMAGE) ->
            validation_result = DROPPED;
            compromised_count = 0;
            printf("SECURITY: DROPPED - deviation\n");
        :: (window_0 == COMPROMISED_IMAGE && compromised_count >= COMPROMISED_THRESHOLD) ->
            validation_result = DROPPED;
            compromised_count = 0;
            printf("SECURITY: DROPPED - threshold\n");
        :: else ->
            validation_result = DROPPED;
            printf("SECURITY: DROPPED - default\n");
        fi
        
    :: (img != COMPROMISED_IMAGE) ->
        compromised_count = 0;
        validation_result = VALID;
    fi;
    
    window_2 = window_1;
    window_1 = window_0;
    window_0 = img;
}

inline validate_image_insecure(img) {
    printf("INSECURE: %e passes\n", img);
    validation_result = VALID;
    
    if
    :: (img == COMPROMISED_IMAGE) -> compromised_count = compromised_count + 1
    :: else -> compromised_count = 0
    fi;
    
    window_2 = window_1;
    window_1 = window_0;
    window_0 = img;
}

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

active proctype System() {
    mtype img;
    
    window_0 = NORMAL_IMAGE;
    window_1 = NORMAL_IMAGE;
    window_2 = NORMAL_IMAGE;
    compromised_count = 0;
    system_ready = true;
    
    printf("=== NO SECURITY VERSION ===\n");
    
end_system:
    do
    :: atomic {
        if
        :: (mission_state == IDLE) ->
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected ->
                motors_verified = true;
                mission_state = RENDEZVOUS;
            fi
            
        :: (mission_state == RENDEZVOUS) ->
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected -> mission_state = VISUAL_SERVO
            fi
            
        :: (mission_state == VISUAL_SERVO) ->
            if
            :: camera_channel?img ->
                current_image = img;
                
#if SECURITY_CONTROL_ENABLED
                validate_image_secure(img);
#else
                validate_image_insecure(img);
#endif
                
                if
                :: (validation_result == DROPPED) ->
                    printf("DROPPED\n");
                    
                :: (validation_result == VALID) ->
                    if
                    :: (img == TARGET_DETECTED) ->
                        move_closer_fast(dist);
                        if
                        :: (dist <= CAPTURE_DIST) -> mission_state = CAPTURE
                        :: (dist > CAPTURE_DIST) -> skip
                        fi
                        
                    :: (img == INTERESTING_IMAGE) ->
                        move_closer(dist);
                        
                    :: (img == RANDOM_IMAGE) ->
                        skip
                        
                    :: (img == NORMAL_IMAGE) ->
                        move_closer(dist);
                        
                    :: (img == COMPROMISED_IMAGE) ->
                        printf("!!! COMPROMISED PROCESSED !!!\n");
                        compromised_processed = true;
                        move_away(dist);
                        move_away(dist);
                        printf("Distance: %d\n", dist);
                        
                        if
                        :: (dist >= HACK_DIST) ->
                            mission_state = HACK;
                            hack_state = true;
                            printf("!!! HACK !!!\n");
                        :: (dist < HACK_DIST) -> skip
                        fi
                        
                    :: else -> skip
                    fi
                fi
                
            :: timeout -> skip
            fi
            
        :: (mission_state == CAPTURE) ->
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected -> mission_state = ORU_PREP
            fi
            
        :: (mission_state == ORU_PREP) ->
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected -> mission_state = ORU_TRANSFER
            fi
            
        :: (mission_state == ORU_TRANSFER) ->
            if
            :: anomaly_detected = true
            :: anomaly_detected = false
            :: anomaly_detected = false
            fi;
            
            if
            :: anomaly_detected -> mission_state = ERROR
            :: !anomaly_detected -> mission_state = POST_VERIFICATION
            fi
            
        :: (mission_state == POST_VERIFICATION) ->
            if
            :: ground_intervention_required -> mission_state = GROUND_INTERVENTION
            :: !ground_intervention_required -> mission_state = MISSION_COMPLETE
            fi
            
        :: (mission_state == ERROR) ->
            ground_intervention_required = true;
            mission_state = GROUND_INTERVENTION;
            
        :: (mission_state == GROUND_INTERVENTION) ->
            if
            :: true ->
                ground_intervention_required = false;
                anomaly_detected = false;
                mission_state = IDLE;
            :: true ->
                mission_state = MISSION_FAILED;
            fi
            
        :: (mission_state == HACK) ->
            hack_state = true;
            mission_failure = true;
            mission_success = false;
            mission_state = MISSION_FAILED;
            
        :: (mission_state == MISSION_COMPLETE) ->
            mission_success = true;
            mission_failure = false;
            break
            
        :: (mission_state == MISSION_FAILED) ->
            mission_failure = true;
            mission_success = false;
            break
            
        fi
    }
    od;
}

proctype Camera() {
    (system_ready);
    
end_camera:
    do
    :: (mission_success || mission_failure) -> break
    :: (!mission_success && !mission_failure) ->
        if
        :: camera_channel!TARGET_DETECTED
        :: camera_channel!TARGET_DETECTED
        :: camera_channel!TARGET_DETECTED
        :: camera_channel!NORMAL_IMAGE
        :: camera_channel!INTERESTING_IMAGE
        :: skip
        fi
    od
}

proctype Attacker() {
    byte attack_count = 0;
    byte max_attacks = 15;
    
    (system_ready);
    
end_attacker:
    do
    :: (mission_success || mission_failure) -> break
    :: (attack_count >= max_attacks) -> break
    :: (!mission_success && !mission_failure && attack_count < max_attacks) ->
        if
        :: camera_channel!COMPROMISED_IMAGE ->
            attack_occurred = true;
            attack_count = attack_count + 1;
            printf("Attack #%d\n", attack_count)
        :: camera_channel!COMPROMISED_IMAGE ->
            attack_occurred = true;
            attack_count = attack_count + 1;
            printf("Attack #%d\n", attack_count)
        :: skip
        fi
    od
}

init {
    printf("=== NO SECURITY ===\n");
    
    atomic {
        mission_state = IDLE;
        dist = 50;
        hack_state = false;
        attack_occurred = false;
        mission_success = false;
        mission_failure = false;
        compromised_processed = false;
        validation_result = VALID;
        
        run Camera();
        run Attacker();
    }
}

/* LTL Properties - Expected results for NO SECURITY version */

/* Should FAIL - hack IS reachable */
ltl safety_no_hack { [](!hack_state) }

/* Should PASS - attacks do lead to hack */
ltl attack_leads_to_hack { [](attack_occurred -> <>hack_state) }

/* Should FAIL - compromised images ARE processed */
ltl security_blocks_processing { [](!compromised_processed) }

/* Should PASS - processed compromised leads to hack */
ltl processed_leads_to_hack { [](compromised_processed -> <>hack_state) }

/* Should PASS */
ltl mission_terminates { <>(mission_success || mission_failure) }

/* Should PASS */
ltl no_success_and_hack { [](!(mission_success && hack_state)) }

/* Should PASS */
ltl hack_requires_attack { [](hack_state -> attack_occurred) }
