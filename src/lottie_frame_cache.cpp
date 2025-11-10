#include "lottie_frame_cache.h"
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

static LottieFrameCache *singleton = nullptr;

LottieFrameCache *LottieFrameCache::get_singleton() {
    if (!singleton) singleton = memnew(LottieFrameCache);
    return singleton;
}

Ref<ImageTexture> LottieFrameCache::get(const String &anim_key, int frame, const Vector2i &size) {
    Key key{anim_key, frame, size.x, size.y};
    auto it = _map.find(key);
    if (it == _map.end()) return Ref<ImageTexture>();
    _touch(key);
    return it->second.tex;
}

void LottieFrameCache::put(const String &anim_key, int frame, const Vector2i &size, const Ref<ImageTexture> &tex, size_t bytes) {
    if (bytes == 0 || tex.is_null()) return;
    Key key{anim_key, frame, size.x, size.y};
    auto it = _map.find(key);
    if (it != _map.end()) {
        // Replace and adjust usage
        _used -= it->second.bytes;
        it->second.tex = tex;
        it->second.bytes = bytes;
        _used += bytes;
        _touch(key);
    } else {
        _lru.push_front(key);
        Entry e; e.tex = tex; e.bytes = bytes; e.lru_it = _lru.begin();
        _map.emplace(key, e);
        _used += bytes;
    }
    _evict_if_needed();
}

void LottieFrameCache::set_capacity_bytes(size_t bytes) {
    _capacity = bytes;
    _evict_if_needed();
}

void LottieFrameCache::clear() {
    _map.clear();
    _lru.clear();
    _used = 0;
}

void LottieFrameCache::_touch(const Key &key) {
    auto it = _map.find(key);
    if (it == _map.end()) return;
    _lru.erase(it->second.lru_it);
    _lru.push_front(key);
    it->second.lru_it = _lru.begin();
}

void LottieFrameCache::_evict_if_needed() {
    while (_used > _capacity && !_lru.empty()) {
        const Key &old = _lru.back();
        auto it = _map.find(old);
        if (it != _map.end()) {
            _used -= it->second.bytes;
            _map.erase(it);
        }
        _lru.pop_back();
    }
}
