#ifndef LOTTIE_STATE_MACHINE_H
#define LOTTIE_STATE_MACHINE_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

// Forward declaration
class LottieAnimation;

// State class representing a single animation state
class LottieAnimationState : public Resource {
    GDCLASS(LottieAnimationState, Resource)

private:
    String state_name;
    String animation_path;
    bool loop;
    float speed;
    float blend_time;

protected:
    static void _bind_methods();

public:
    LottieAnimationState();
    ~LottieAnimationState();

    void set_state_name(const String& name);
    String get_state_name() const;

    void set_animation_path(const String& path);
    String get_animation_path() const;

    void set_loop(bool p_loop);
    bool get_loop() const;

    void set_speed(float p_speed);
    float get_speed() const;

    void set_blend_time(float time);
    float get_blend_time() const;
};

// Transition class representing a transition between states
class LottieStateTransition : public Resource {
    GDCLASS(LottieStateTransition, Resource)

private:
    String from_state;
    String to_state;
    String condition_parameter;
    Variant condition_value;
    String condition_mode; // "equals", "greater", "less", "not_equals"
    float transition_time;
    bool auto_advance;

protected:
    static void _bind_methods();

public:
    LottieStateTransition();
    ~LottieStateTransition();

    void set_from_state(const String& state);
    String get_from_state() const;

    void set_to_state(const String& state);
    String get_to_state() const;

    void set_condition_parameter(const String& param);
    String get_condition_parameter() const;

    void set_condition_value(const Variant& value);
    Variant get_condition_value() const;

    void set_condition_mode(const String& mode);
    String get_condition_mode() const;

    void set_transition_time(float time);
    float get_transition_time() const;

    void set_auto_advance(bool advance);
    bool get_auto_advance() const;

    bool evaluate_condition(const Dictionary& parameters) const;
};

// Main state machine class
class LottieStateMachine : public Resource {
    GDCLASS(LottieStateMachine, Resource)

private:
    Array states; // Array of LottieAnimationState
    Array transitions; // Array of LottieStateTransition
    String current_state;
    String default_state;
    Dictionary parameters;
    
    float blend_progress;
    String blend_from_state;
    String blend_to_state;
    bool is_blending;

    Ref<LottieAnimationState> _find_state(const String& state_name) const;
    Array _find_valid_transitions() const;

protected:
    static void _bind_methods();

public:
    LottieStateMachine();
    ~LottieStateMachine();

    // State management
    void add_state(const Ref<LottieAnimationState>& state);
    void remove_state(const String& state_name);
    Ref<LottieAnimationState> get_state(const String& state_name) const;
    Array get_all_states() const;
    int get_state_count() const;

    // Transition management
    void add_transition(const Ref<LottieStateTransition>& transition);
    void remove_transition(const String& from_state, const String& to_state);
    Array get_all_transitions() const;
    int get_transition_count() const;

    // State control
    void set_current_state(const String& state_name);
    String get_current_state() const;

    void set_default_state(const String& state_name);
    String get_default_state() const;

    // Parameter management
    void set_parameter(const String& param_name, const Variant& value);
    Variant get_parameter(const String& param_name) const;
    Dictionary get_all_parameters() const;
    bool has_parameter(const String& param_name) const;

    // State machine update
    void update(float delta, LottieAnimation* animation_node);
    void reset();

    // Blending
    bool is_in_blend() const;
    float get_blend_progress() const;
};

}

#endif // LOTTIE_STATE_MACHINE_H
