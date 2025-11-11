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

namespace tvg {
    class SwCanvas;
    class Animation;
    class Picture;
}

namespace godot {

class LottieAnimation : public Node2D {
    GDCLASS(LottieAnimation, Node2D)

private:
    String animation_path;
    bool playing;
    bool looping;
    bool autoplay;
    float speed;
    float current_frame;
    float total_frames;
    float duration;
    
    Ref<ImageTexture> texture;
    Ref<Image> image;
    PackedByteArray pixel_bytes;
    std::vector<Ref<ImageTexture>> texture_ring;
    int texture_ring_index = 0;
    int texture_ring_size = 3;
    Vector2i base_picture_size;
    Vector2i render_size;
    String animation_key;
    String selected_dotlottie_animation;
    
    tvg::SwCanvas* canvas;
    tvg::Animation* animation;
    tvg::Picture* picture;
    uint32_t* buffer;
    
    bool use_animation_size;
    bool fit_into_box;
    Vector2i fit_box_size;
    bool dynamic_resolution;
    float resolution_threshold;
    Vector2i max_render_size;
    bool frame_cache_enabled = false;
    int frame_cache_budget_mb = 256;
    int frame_cache_step = 1;
    int engine_option = 1;
    bool cache_only_when_paused = true;
    int live_cache_threshold = 4;
    bool live_cache_force = false;
    bool live_cache_active = false;

    int culling_mode = 2;
    float culling_margin_px = 0.0f;

    bool render_thread_enabled = true;
    std::thread render_thread;
    std::mutex job_mutex;
    std::condition_variable job_cv;
    bool worker_stop = false;
    bool load_pending = false;
    std::string pending_path8;
    bool render_pending = false;
    Vector2i pending_r_size;
    float pending_r_frame = 0.0f;
    uint64_t next_frame_id = 1;
    uint64_t last_consumed_id = 0;
    // Render deduplication
    int last_rendered_qf = -1;
    int last_posted_qf = -1;
    Vector2i last_posted_size = Vector2i(0,0);
    bool last_visible_on_screen = false;
    bool first_frame_drawn = false;

    struct FrameResult {
        std::vector<uint8_t> rgba;
        int w = 0;
        int h = 0;
        uint64_t id = 0;
        bool ready = false;
    } latest_frame;
    std::mutex frame_mutex;

    tvg::SwCanvas* w_canvas = nullptr;
    tvg::Animation* w_animation = nullptr;
    tvg::Picture* w_picture = nullptr;
    uint32_t* w_buffer = nullptr;
    Vector2i w_render_size = Vector2i(0,0);
    Vector2i w_base_picture_size = Vector2i(0,0);
    float last_effective_scale = 0.0f;
    Vector2i last_desired_size = Vector2i(0, 0);
    bool pending_resize = false;
    Vector2i pending_target_size = Vector2i(0, 0);
    bool rendering = false;
    double _elapsed_time = 0.0;
    double _last_resize_at = -1.0;
    float _min_resize_interval = 0.10f;
    bool _uploaded_this_frame = false;
    int _last_drawn_qf = -1;

    bool fix_alpha_border = true;
    bool unpremultiply_alpha = false;

    Vector2 offset = Vector2();

    String last_lottie_zip_path;
    PackedStringArray sm_animation_ids;
    PackedStringArray sm_machine_names;
    Dictionary sm_states_by_machine;
    Dictionary sm_anim_inner_paths;
    Dictionary sm_state_segments_by_machine;
    String active_animation_id;
    String active_state_machine;
    String active_state;

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
    void _parse_dotlottie_manifest(const String &zip_path);
    String _extract_json_from_lottie_to_cache(const String &zip_path, const String &inner_path, const String &suffix_key);
    void _apply_selected_state_segment();
    String _current_state_segment_marker() const;
    bool _find_marker_range(const String &json_path, const String &marker, float &out_begin, float &out_end) const;
    void _start_worker_if_needed();
    void _stop_worker();
    void _post_load_to_worker(const String& path);
    void _post_render_to_worker(const Vector2i &size, float frame);
    void _post_segment_to_worker(float begin, float end);
    void _worker_loop();
    void _worker_free_resources();
    void _worker_apply_target_if_needed(const Vector2i &size);
    void _worker_apply_fit_transform();
    void _fix_alpha_border_rgba(uint8_t *rgba, int w, int h);
    void _unpremultiply_alpha_rgba(uint8_t *rgba, int w, int h);

    bool segment_pending = false;
    float pending_segment_begin = 0.0f;
    float pending_segment_end = 0.0f;

protected:
    static void _bind_methods();
    void _get_property_list(List<PropertyInfo> *p_list) const;
    bool _get(const StringName &p_name, Variant &r_ret) const;
    bool _set(const StringName &p_name, const Variant &p_value);

public:
    LottieAnimation();
    ~LottieAnimation();

    void _ready() override;
    void _process(double delta) override;
    void _draw() override;
    void _notification(int32_t p_what);

    void play();
    void stop();
    void pause();
    void seek(float frame);
    void set_frame(float frame);
    float get_frame() const;
    
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
    
    void set_speed(float p_speed);
    float get_speed() const;
    
    void set_render_size(const Vector2i& size);
    Vector2i get_render_size() const;
    
    float get_duration() const;
    float get_total_frames() const;
    void render_static();
    
    void set_offset(const Vector2 &p_offset);
    Vector2 get_offset() const;
};

}

#endif
