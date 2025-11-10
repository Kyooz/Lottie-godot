#ifndef LOTTIE_ANIMATION_H
#define LOTTIE_ANIMATION_H

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <vector>
#include <string>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include "lottie_frame_cache.h"

// Forward declarations for ThorVG
namespace tvg {
    class SwCanvas;
    class Animation;
    class Picture;
    // No public LottieAnimation API in installed headers; use Animation::segment(begin,end)
}

namespace godot {

class LottieAnimation : public Node2D {
    GDCLASS(LottieAnimation, Node2D)

private:
    // Animation properties
    String animation_path;
    bool playing;
    bool looping;
    bool autoplay;
    float speed;
    float current_frame;
    float total_frames;
    float duration;
    
    // Rendering
    Ref<ImageTexture> texture;
    Ref<Image> image;
    PackedByteArray pixel_bytes; // persistent pixel buffer (RGBA8)
    // Triple-buffering of GPU textures to reduce driver stalls
    std::vector<Ref<ImageTexture>> texture_ring;
    int texture_ring_index = 0;
    int texture_ring_size = 3; // ring size >= 2 recommended
    Vector2i base_picture_size;
    Vector2i render_size;
    String animation_key; // used for cache key
    // dotLottie selection (when animation_path ends with .lottie)
    String selected_dotlottie_animation; // manifest animations[].id or json path
    
    // ThorVG objects
    tvg::SwCanvas* canvas;
    tvg::Animation* animation;
    tvg::Picture* picture;
    uint32_t* buffer;
    
    // Sizing & resolution policies
    bool use_animation_size;
    bool fit_into_box;
    Vector2i fit_box_size;
    bool dynamic_resolution;
    float resolution_threshold;
    Vector2i max_render_size;
    // Always render first frame when not playing (static preview / SVG usage)
    // (previous render_when_idle flag removed; behavior now unconditional)
    // Performance/cache options
    bool frame_cache_enabled = false;
    int frame_cache_budget_mb = 256; // total shared budget
    int frame_cache_step = 1; // quantize frames to this step (frames)
    int engine_option = 0; // 0: Default, 1: SmartRender
    // Only use frame cache when not actively playing (avoid stalls during playback)
    // Janitor-style: rely on incremental updates rather than frame texture caching while animating.
    bool cache_only_when_paused = true;
    // Live cache during playback when many identical instances exist.
    int live_cache_threshold = 4;           // instances needed to activate live cache for this key
    bool live_cache_force = false;          // override threshold
    bool live_cache_active = false;         // computed per key

    // Culling configuration
    // Culling removed (legacy fields kept minimal to avoid ABI break but unused)
    int culling_mode = 2; // Always
    float culling_margin_px = 0.0f;

    // Worker-threaded rendering (Janitor-like pipeline): render ThorVG on a worker, upload on main.
    bool render_thread_enabled = true;
    std::thread render_thread;
    std::mutex job_mutex;
    std::condition_variable job_cv;
    bool worker_stop = false;
    // Separate pending states to avoid overwriting LOAD with RENDER
    bool load_pending = false;
    std::string pending_path8; // absolute UTF-8 path or empty to clear
    bool render_pending = false;
    Vector2i pending_r_size;
    float pending_r_frame = 0.0f;
    uint64_t next_frame_id = 1;
    uint64_t last_consumed_id = 0;
    // Render deduplication
    int last_rendered_qf = -1;
    int last_posted_qf = -1;
    Vector2i last_posted_size = Vector2i(0,0);
    bool last_visible_on_screen = false; // start as not visible to force first-time post when it becomes visible
    bool first_frame_drawn = false;

    // (Replaced single pending_job with distinct pending flags/fields above)

    struct FrameResult {
        std::vector<uint8_t> rgba; // RGBA8
        int w = 0;
        int h = 0;
        uint64_t id = 0;
        bool ready = false;
    } latest_frame;
    std::mutex frame_mutex;

    // Worker thread ThorVG resources
    tvg::SwCanvas* w_canvas = nullptr;
    tvg::Animation* w_animation = nullptr;
    tvg::Picture* w_picture = nullptr;
    uint32_t* w_buffer = nullptr; // ARGB
    Vector2i w_render_size = Vector2i(0,0);
    Vector2i w_base_picture_size = Vector2i(0,0);
    // Debug/housekeeping for dynamic resolution
    float last_effective_scale = 0.0f;
    Vector2i last_desired_size = Vector2i(0, 0);
    bool pending_resize = false;
    Vector2i pending_target_size = Vector2i(0, 0);
    bool rendering = false;
    // Resize thrash control
    double _elapsed_time = 0.0;
    double _last_resize_at = -1.0;
    float _min_resize_interval = 0.10f; // seconds between reallocations
    bool _uploaded_this_frame = false;   // for redraw gating
    int _last_drawn_qf = -1;            // track when visual changed

    // Edge artifact mitigation
    bool fix_alpha_border = true; // bleed neighbor color into fully transparent border to avoid dark fringes
    bool unpremultiply_alpha = true; // convert PMA -> straight to avoid dark halos during filtering

    // Offset between Node2D origin and drawn image center. Allows pivot for YSort without moving visuals.
    // Example: offset = Vector2(0, box_height/2) places Node2D position at bottom-center ("foot pivot").
    Vector2 offset = Vector2();

    // dotLottie manifest/state machine info (for inspector selectors)
    String last_lottie_zip_path; // original .lottie path if loaded
    PackedStringArray sm_animation_ids; // available animation ids/names
    PackedStringArray sm_machine_names; // available state machine names
    Dictionary sm_states_by_machine; // String => PackedStringArray
    Dictionary sm_anim_inner_paths; // animation id => inner json path in zip
    Dictionary sm_state_segments_by_machine; // String (machine) => Dictionary(state => segment)
    String active_animation_id;
    String active_state_machine;
    String active_state;

    // Internal methods
    void _initialize_thorvg();
    void _cleanup_thorvg();
    bool _load_animation(const String& path);
    void _update_animation(float delta);
    void _render_frame();
    void _create_texture();
    void _recreate_texture_ring();
    void _allocate_buffer_and_target(const Vector2i &size);
    void _apply_sizing_policy();
    void _apply_picture_transform_to_fit();
    void _update_resolution_from_scale();
    void _on_viewport_size_changed();
    int _quantized_frame_index() const;
    void _ensure_cache_capacity();
    bool _is_visible_on_screen() const;
    void _recompute_live_cache_state();
    // dotLottie helpers
    void _parse_dotlottie_manifest(const String &zip_path);
    String _extract_json_from_lottie_to_cache(const String &zip_path, const String &inner_path, const String &suffix_key);
    void _apply_selected_state_segment();
    String _current_state_segment_marker() const;
    bool _find_marker_range(const String &json_path, const String &marker, float &out_begin, float &out_end) const;
    // Worker helpers
    void _start_worker_if_needed();
    void _stop_worker();
    void _post_load_to_worker(const String& path);
    void _post_render_to_worker(const Vector2i &size, float frame);
    void _post_segment_to_worker(float begin, float end);
    void _worker_loop();
    void _worker_free_resources();
    void _worker_apply_target_if_needed(const Vector2i &size);
    void _worker_apply_fit_transform();
    // Postprocess helpers
    void _fix_alpha_border_rgba(uint8_t *rgba, int w, int h);
    void _unpremultiply_alpha_rgba(uint8_t *rgba, int w, int h);

    // Worker control flags
    bool segment_pending = false;
    float pending_segment_begin = 0.0f;
    float pending_segment_end = 0.0f;


protected:
    static void _bind_methods();
    // Dynamic inspector properties for state machine selectors
    void _get_property_list(List<PropertyInfo> *p_list) const;
    bool _get(const StringName &p_name, Variant &r_ret) const;
    bool _set(const StringName &p_name, const Variant &p_value);

public:
    LottieAnimation();
    ~LottieAnimation();

    // Godot lifecycle
    void _ready() override;
    void _process(double delta) override;
    void _draw() override;
    void _notification(int32_t p_what);

    // Animation control
    void play();
    void stop();
    void pause();
    void seek(float frame);
    void set_frame(float frame);
    float get_frame() const;
    
    // Properties getters/setters
    void set_animation_path(const String& path);
    String get_animation_path() const;
    void set_selected_dotlottie_animation(const String &id);
    String get_selected_dotlottie_animation() const;
    
    void set_playing(bool p_playing);
    bool is_playing() const;
    
    void set_looping(bool p_looping);
    bool is_looping() const;
    
    void set_autoplay(bool p_autoplay);
    bool is_autoplay() const;
    
    // New policy properties
    void set_use_animation_size(bool p_enable);
    bool is_using_animation_size() const;

    void set_fit_into_box(bool p_enable);
    bool is_fit_into_box() const;
    void set_fit_box_size(const Vector2i &p_size);
    Vector2i get_fit_box_size() const;

    void set_dynamic_resolution(bool p_enable);
    bool is_dynamic_resolution() const;
    void set_resolution_threshold(float p_t);
    float get_resolution_threshold() const;
    void set_max_render_size(const Vector2i &p_size);
    Vector2i get_max_render_size() const;

    void set_frame_cache_enabled(bool p_enable);
    bool is_frame_cache_enabled() const;
    void set_frame_cache_budget_mb(int p_mb);
    int get_frame_cache_budget_mb() const;
    void set_frame_cache_step(int p_step);
    int get_frame_cache_step() const;
    void set_engine_option(int p_opt);
    int get_engine_option() const;
    void set_live_cache_threshold(int p_threshold);
    int get_live_cache_threshold() const;
    void set_live_cache_force(bool p_force);
    bool get_live_cache_force() const;
    void set_culling_mode(int p_mode);
    int get_culling_mode() const;
    void set_culling_margin_px(float p_margin);
    float get_culling_margin_px() const;
    // Removed render_when_idle property; static rendering is unconditional now.

    void set_speed(float p_speed);
    float get_speed() const;
    
    void set_render_size(const Vector2i& size);
    Vector2i get_render_size() const;
    
    float get_duration() const;
    float get_total_frames() const;
    // Render first frame (or current frame) immediately when idle (not playing)
    void render_static();
    
    // Offset control for YSort pivot without moving the drawing
    void set_offset(const Vector2 &p_offset);
    Vector2 get_offset() const;
};

}

#endif // LOTTIE_ANIMATION_H
