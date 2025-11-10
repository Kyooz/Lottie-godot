#include "lottie_state_machine.h"
#include "lottie_animation.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// ============================================================================
// LottieAnimationState Implementation
// ============================================================================

void LottieAnimationState::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_state_name", "name"), &LottieAnimationState::set_state_name);
    ClassDB::bind_method(D_METHOD("get_state_name"), &LottieAnimationState::get_state_name);

    ClassDB::bind_method(D_METHOD("set_animation_path", "path"), &LottieAnimationState::set_animation_path);
    ClassDB::bind_method(D_METHOD("get_animation_path"), &LottieAnimationState::get_animation_path);

    ClassDB::bind_method(D_METHOD("set_loop", "loop"), &LottieAnimationState::set_loop);
    ClassDB::bind_method(D_METHOD("get_loop"), &LottieAnimationState::get_loop);

    ClassDB::bind_method(D_METHOD("set_speed", "speed"), &LottieAnimationState::set_speed);
    ClassDB::bind_method(D_METHOD("get_speed"), &LottieAnimationState::get_speed);

    ClassDB::bind_method(D_METHOD("set_blend_time", "time"), &LottieAnimationState::set_blend_time);
    ClassDB::bind_method(D_METHOD("get_blend_time"), &LottieAnimationState::get_blend_time);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "state_name"), "set_state_name", "get_state_name");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "animation_path", PROPERTY_HINT_FILE, "*.json,*.lottie"), 
                 "set_animation_path", "get_animation_path");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "loop"), "set_loop", "get_loop");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed", PROPERTY_HINT_RANGE, "0.0,10.0,0.01"), 
                 "set_speed", "get_speed");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "blend_time", PROPERTY_HINT_RANGE, "0.0,5.0,0.01"), 
                 "set_blend_time", "get_blend_time");
}

LottieAnimationState::LottieAnimationState() {
    state_name = "";
    animation_path = "";
    loop = true;
    speed = 1.0f;
    blend_time = 0.2f;
}

LottieAnimationState::~LottieAnimationState() {
}

void LottieAnimationState::set_state_name(const String& name) {
    state_name = name;
}

String LottieAnimationState::get_state_name() const {
    return state_name;
}

void LottieAnimationState::set_animation_path(const String& path) {
    animation_path = path;
}

String LottieAnimationState::get_animation_path() const {
    return animation_path;
}

void LottieAnimationState::set_loop(bool p_loop) {
    loop = p_loop;
}

bool LottieAnimationState::get_loop() const {
    return loop;
}

void LottieAnimationState::set_speed(float p_speed) {
    speed = MAX(0.0f, p_speed);
}

float LottieAnimationState::get_speed() const {
    return speed;
}

void LottieAnimationState::set_blend_time(float time) {
    blend_time = MAX(0.0f, time);
}

float LottieAnimationState::get_blend_time() const {
    return blend_time;
}

// ============================================================================
// LottieStateTransition Implementation
// ============================================================================

void LottieStateTransition::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_from_state", "state"), &LottieStateTransition::set_from_state);
    ClassDB::bind_method(D_METHOD("get_from_state"), &LottieStateTransition::get_from_state);

    ClassDB::bind_method(D_METHOD("set_to_state", "state"), &LottieStateTransition::set_to_state);
    ClassDB::bind_method(D_METHOD("get_to_state"), &LottieStateTransition::get_to_state);

    ClassDB::bind_method(D_METHOD("set_condition_parameter", "param"), &LottieStateTransition::set_condition_parameter);
    ClassDB::bind_method(D_METHOD("get_condition_parameter"), &LottieStateTransition::get_condition_parameter);

    ClassDB::bind_method(D_METHOD("set_condition_value", "value"), &LottieStateTransition::set_condition_value);
    ClassDB::bind_method(D_METHOD("get_condition_value"), &LottieStateTransition::get_condition_value);

    ClassDB::bind_method(D_METHOD("set_condition_mode", "mode"), &LottieStateTransition::set_condition_mode);
    ClassDB::bind_method(D_METHOD("get_condition_mode"), &LottieStateTransition::get_condition_mode);

    ClassDB::bind_method(D_METHOD("set_transition_time", "time"), &LottieStateTransition::set_transition_time);
    ClassDB::bind_method(D_METHOD("get_transition_time"), &LottieStateTransition::get_transition_time);

    ClassDB::bind_method(D_METHOD("set_auto_advance", "advance"), &LottieStateTransition::set_auto_advance);
    ClassDB::bind_method(D_METHOD("get_auto_advance"), &LottieStateTransition::get_auto_advance);

    ClassDB::bind_method(D_METHOD("evaluate_condition", "parameters"), &LottieStateTransition::evaluate_condition);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "from_state"), "set_from_state", "get_from_state");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "to_state"), "set_to_state", "get_to_state");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "condition_parameter"), "set_condition_parameter", "get_condition_parameter");
    ADD_PROPERTY(PropertyInfo(Variant::NIL, "condition_value"), "set_condition_value", "get_condition_value");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "condition_mode", PROPERTY_HINT_ENUM, "equals,not_equals,greater,less"), 
                 "set_condition_mode", "get_condition_mode");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "transition_time", PROPERTY_HINT_RANGE, "0.0,5.0,0.01"), 
                 "set_transition_time", "get_transition_time");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_advance"), "set_auto_advance", "get_auto_advance");
}

LottieStateTransition::LottieStateTransition() {
    from_state = "";
    to_state = "";
    condition_parameter = "";
    condition_mode = "equals";
    transition_time = 0.2f;
    auto_advance = false;
}

LottieStateTransition::~LottieStateTransition() {
}

void LottieStateTransition::set_from_state(const String& state) {
    from_state = state;
}

String LottieStateTransition::get_from_state() const {
    return from_state;
}

void LottieStateTransition::set_to_state(const String& state) {
    to_state = state;
}

String LottieStateTransition::get_to_state() const {
    return to_state;
}

void LottieStateTransition::set_condition_parameter(const String& param) {
    condition_parameter = param;
}

String LottieStateTransition::get_condition_parameter() const {
    return condition_parameter;
}

void LottieStateTransition::set_condition_value(const Variant& value) {
    condition_value = value;
}

Variant LottieStateTransition::get_condition_value() const {
    return condition_value;
}

void LottieStateTransition::set_condition_mode(const String& mode) {
    condition_mode = mode;
}

String LottieStateTransition::get_condition_mode() const {
    return condition_mode;
}

void LottieStateTransition::set_transition_time(float time) {
    transition_time = MAX(0.0f, time);
}

float LottieStateTransition::get_transition_time() const {
    return transition_time;
}

void LottieStateTransition::set_auto_advance(bool advance) {
    auto_advance = advance;
}

bool LottieStateTransition::get_auto_advance() const {
    return auto_advance;
}

bool LottieStateTransition::evaluate_condition(const Dictionary& parameters) const {
    if (auto_advance) {
        return true;
    }

    if (condition_parameter.is_empty() || !parameters.has(condition_parameter)) {
        return false;
    }

    Variant param_value = parameters[condition_parameter];

    if (condition_mode == "equals") {
        return param_value == condition_value;
    } else if (condition_mode == "not_equals") {
        return param_value != condition_value;
    } else if (condition_mode == "greater") {
        return (float)param_value > (float)condition_value;
    } else if (condition_mode == "less") {
        return (float)param_value < (float)condition_value;
    }

    return false;
}

// ============================================================================
// LottieStateMachine Implementation
// ============================================================================

void LottieStateMachine::_bind_methods() {
    // State management
    ClassDB::bind_method(D_METHOD("add_state", "state"), &LottieStateMachine::add_state);
    ClassDB::bind_method(D_METHOD("remove_state", "state_name"), &LottieStateMachine::remove_state);
    ClassDB::bind_method(D_METHOD("get_state", "state_name"), &LottieStateMachine::get_state);
    ClassDB::bind_method(D_METHOD("get_all_states"), &LottieStateMachine::get_all_states);
    ClassDB::bind_method(D_METHOD("get_state_count"), &LottieStateMachine::get_state_count);

    // Transition management
    ClassDB::bind_method(D_METHOD("add_transition", "transition"), &LottieStateMachine::add_transition);
    ClassDB::bind_method(D_METHOD("remove_transition", "from_state", "to_state"), &LottieStateMachine::remove_transition);
    ClassDB::bind_method(D_METHOD("get_all_transitions"), &LottieStateMachine::get_all_transitions);
    ClassDB::bind_method(D_METHOD("get_transition_count"), &LottieStateMachine::get_transition_count);

    // State control
    ClassDB::bind_method(D_METHOD("set_current_state", "state_name"), &LottieStateMachine::set_current_state);
    ClassDB::bind_method(D_METHOD("get_current_state"), &LottieStateMachine::get_current_state);

    ClassDB::bind_method(D_METHOD("set_default_state", "state_name"), &LottieStateMachine::set_default_state);
    ClassDB::bind_method(D_METHOD("get_default_state"), &LottieStateMachine::get_default_state);

    // Parameter management
    ClassDB::bind_method(D_METHOD("set_parameter", "param_name", "value"), &LottieStateMachine::set_parameter);
    ClassDB::bind_method(D_METHOD("get_parameter", "param_name"), &LottieStateMachine::get_parameter);
    ClassDB::bind_method(D_METHOD("get_all_parameters"), &LottieStateMachine::get_all_parameters);
    ClassDB::bind_method(D_METHOD("has_parameter", "param_name"), &LottieStateMachine::has_parameter);

    // State machine control
    ClassDB::bind_method(D_METHOD("reset"), &LottieStateMachine::reset);
    ClassDB::bind_method(D_METHOD("is_in_blend"), &LottieStateMachine::is_in_blend);
    ClassDB::bind_method(D_METHOD("get_blend_progress"), &LottieStateMachine::get_blend_progress);

    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "states"), "", "get_all_states");
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "transitions"), "", "get_all_transitions");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "current_state"), "set_current_state", "get_current_state");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "default_state"), "set_default_state", "get_default_state");

    // Signals
    ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::STRING, "from_state"), PropertyInfo(Variant::STRING, "to_state")));
    ADD_SIGNAL(MethodInfo("transition_started", PropertyInfo(Variant::STRING, "from_state"), PropertyInfo(Variant::STRING, "to_state")));
    ADD_SIGNAL(MethodInfo("transition_finished", PropertyInfo(Variant::STRING, "to_state")));
}

LottieStateMachine::LottieStateMachine() {
    current_state = "";
    default_state = "";
    blend_progress = 0.0f;
    blend_from_state = "";
    blend_to_state = "";
    is_blending = false;
}

LottieStateMachine::~LottieStateMachine() {
}

Ref<LottieAnimationState> LottieStateMachine::_find_state(const String& state_name) const {
    for (int i = 0; i < states.size(); i++) {
        Ref<LottieAnimationState> state = states[i];
        if (state.is_valid() && state->get_state_name() == state_name) {
            return state;
        }
    }
    return Ref<LottieAnimationState>();
}

Array LottieStateMachine::_find_valid_transitions() const {
    Array valid_transitions;
    
    for (int i = 0; i < transitions.size(); i++) {
        Ref<LottieStateTransition> transition = transitions[i];
        if (transition.is_valid() && transition->get_from_state() == current_state) {
            if (transition->evaluate_condition(parameters)) {
                valid_transitions.push_back(transition);
            }
        }
    }
    
    return valid_transitions;
}

void LottieStateMachine::add_state(const Ref<LottieAnimationState>& state) {
    if (state.is_valid()) {
        states.push_back(state);
    }
}

void LottieStateMachine::remove_state(const String& state_name) {
    for (int i = 0; i < states.size(); i++) {
        Ref<LottieAnimationState> state = states[i];
        if (state.is_valid() && state->get_state_name() == state_name) {
            states.remove_at(i);
            break;
        }
    }
}

Ref<LottieAnimationState> LottieStateMachine::get_state(const String& state_name) const {
    return _find_state(state_name);
}

Array LottieStateMachine::get_all_states() const {
    return states;
}

int LottieStateMachine::get_state_count() const {
    return states.size();
}

void LottieStateMachine::add_transition(const Ref<LottieStateTransition>& transition) {
    if (transition.is_valid()) {
        transitions.push_back(transition);
    }
}

void LottieStateMachine::remove_transition(const String& from_state, const String& to_state) {
    for (int i = 0; i < transitions.size(); i++) {
        Ref<LottieStateTransition> transition = transitions[i];
        if (transition.is_valid() && 
            transition->get_from_state() == from_state && 
            transition->get_to_state() == to_state) {
            transitions.remove_at(i);
            break;
        }
    }
}

Array LottieStateMachine::get_all_transitions() const {
    return transitions;
}

int LottieStateMachine::get_transition_count() const {
    return transitions.size();
}

void LottieStateMachine::set_current_state(const String& state_name) {
    if (current_state == state_name) {
        return;
    }

    Ref<LottieAnimationState> new_state = _find_state(state_name);
    if (!new_state.is_valid()) {
        UtilityFunctions::printerr("State not found: " + state_name);
        return;
    }

    String old_state = current_state;
    current_state = state_name;

    emit_signal("state_changed", old_state, current_state);
}

String LottieStateMachine::get_current_state() const {
    return current_state;
}

void LottieStateMachine::set_default_state(const String& state_name) {
    default_state = state_name;
}

String LottieStateMachine::get_default_state() const {
    return default_state;
}

void LottieStateMachine::set_parameter(const String& param_name, const Variant& value) {
    parameters[param_name] = value;
}

Variant LottieStateMachine::get_parameter(const String& param_name) const {
    if (parameters.has(param_name)) {
        return parameters[param_name];
    }
    return Variant();
}

Dictionary LottieStateMachine::get_all_parameters() const {
    return parameters;
}

bool LottieStateMachine::has_parameter(const String& param_name) const {
    return parameters.has(param_name);
}

void LottieStateMachine::update(float delta, LottieAnimation* animation_node) {
    if (!animation_node) {
        return;
    }

    // Check for valid transitions
    Array valid_transitions = _find_valid_transitions();
    
    if (valid_transitions.size() > 0) {
        // Take the first valid transition
        Ref<LottieStateTransition> transition = valid_transitions[0];
        if (transition.is_valid()) {
            String new_state = transition->get_to_state();
            Ref<LottieAnimationState> state = _find_state(new_state);
            
            if (state.is_valid()) {
                // Start transition
                blend_from_state = current_state;
                blend_to_state = new_state;
                is_blending = true;
                blend_progress = 0.0f;
                
                emit_signal("transition_started", current_state, new_state);
                
                // Update animation
                animation_node->set_animation_path(state->get_animation_path());
                animation_node->set_looping(state->get_loop());
                animation_node->set_speed(state->get_speed());
                animation_node->play();
                
                current_state = new_state;
            }
        }
    }

    // Update blend progress
    if (is_blending) {
        Ref<LottieAnimationState> state = _find_state(current_state);
        if (state.is_valid()) {
            float blend_time = state->get_blend_time();
            if (blend_time > 0.0f) {
                blend_progress += delta / blend_time;
                if (blend_progress >= 1.0f) {
                    blend_progress = 1.0f;
                    is_blending = false;
                    emit_signal("transition_finished", current_state);
                }
            } else {
                is_blending = false;
                blend_progress = 1.0f;
                emit_signal("transition_finished", current_state);
            }
        }
    }
}

void LottieStateMachine::reset() {
    if (!default_state.is_empty()) {
        set_current_state(default_state);
    }
    parameters.clear();
    is_blending = false;
    blend_progress = 0.0f;
}

bool LottieStateMachine::is_in_blend() const {
    return is_blending;
}

float LottieStateMachine::get_blend_progress() const {
    return blend_progress;
}
