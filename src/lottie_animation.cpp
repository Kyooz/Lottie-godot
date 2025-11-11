#include "lottie_animation.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/zip_reader.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/camera2d.hpp>
#include <algorithm>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <vector>

#include <thorvg.h>

using namespace godot;

#if defined(__SSSE3__)
    #include <tmmintrin.h>
    #define LOTTIE_SIMD_SSSE3 1
#endif
#if defined(__ARM_NEON)
    #include <arm_neon.h>
    #define LOTTIE_SIMD_NEON 1
#endif

static inline void _convert_argb_to_rgba_optimized(const uint32_t *src, uint8_t *dst, size_t count) {
#if LOTTIE_SIMD_SSSE3
    size_t vec_count = count / 4;
    const __m128i mask = _mm_setr_epi8(
        2, 1, 0, 3,
        6, 5, 4, 7,
        10, 9, 8, 11,
        14, 13, 12, 15
    );
    const __m128i *srcv = reinterpret_cast<const __m128i*>(src);
    __m128i *dstv = reinterpret_cast<__m128i*>(dst);
    for (size_t i = 0; i < vec_count; ++i) {
        __m128i pixels = _mm_loadu_si128(&srcv[i]);
        __m128i shuffled = _mm_shuffle_epi8(pixels, mask);
        _mm_storeu_si128(&dstv[i], shuffled);
    }
    size_t processed = vec_count * 4;
    for (size_t i = processed; i < count; ++i) {
        uint32_t p = src[i];
        dst[i*4 + 0] = (uint8_t)((p >> 16) & 0xFF);
        dst[i*4 + 1] = (uint8_t)((p >> 8) & 0xFF);
        dst[i*4 + 2] = (uint8_t)(p & 0xFF);
        dst[i*4 + 3] = (uint8_t)((p >> 24) & 0xFF);
    }
#elif LOTTIE_SIMD_NEON
    size_t vec_count = count / 4;
    static const uint8_t tbl_data[16] = {
        2,1,0,3, 6,5,4,7, 10,9,8,11, 14,13,12,15
    };
    uint8x16_t tbl = vld1q_u8(tbl_data);
    for (size_t i = 0; i < vec_count; ++i) {
        uint8x16_t pixels = vld1q_u8(reinterpret_cast<const uint8_t*>(&src[i*4]));
#if defined(__aarch64__) || defined(__ARM_FEATURE_QBIT)
        uint8x16_t shuffled = vqtbl1q_u8(pixels, tbl);
#else
        uint8_t tmp[16];
        vst1q_u8(tmp, pixels);
        uint8_t out[16];
        for (int k=0;k<16;k++) out[k] = tmp[tbl_data[k]];
        pixels = vld1q_u8(out);
        uint8x16_t shuffled = pixels;
#endif
        vst1q_u8(&dst[i*16], shuffled);
    }
    size_t processed = vec_count * 4;
    for (size_t i = processed; i < count; ++i) {
        uint32_t p = src[i];
        dst[i*4 + 0] = (uint8_t)((p >> 16) & 0xFF);
        dst[i*4 + 1] = (uint8_t)((p >> 8) & 0xFF);
        dst[i*4 + 2] = (uint8_t)(p & 0xFF);
        dst[i*4 + 3] = (uint8_t)((p >> 24) & 0xFF);
    }
#else
    for (size_t i = 0; i < count; ++i) {
        uint32_t p = src[i];
        dst[i*4 + 0] = (uint8_t)((p >> 16) & 0xFF);
        dst[i*4 + 1] = (uint8_t)((p >> 8) & 0xFF);
        dst[i*4 + 2] = (uint8_t)(p & 0xFF);
        dst[i*4 + 3] = (uint8_t)((p >> 24) & 0xFF);
    }
#endif
}

void LottieAnimation::_fix_alpha_border_rgba(uint8_t *rgba, int w, int h) {
    if (!rgba || w <= 2 || h <= 2) return;
    std::vector<uint8_t> rgb_copy((size_t)w * (size_t)h * 3);
    for (int y = 0; y < h; ++y) {
        const uint8_t *row = rgba + (size_t)y * (size_t)w * 4;
        uint8_t *dst = rgb_copy.data() + (size_t)y * (size_t)w * 3;
        for (int x = 0; x < w; ++x) {
            dst[x*3+0] = row[x*4+0];
            dst[x*3+1] = row[x*4+1];
            dst[x*3+2] = row[x*4+2];
        }
    }
    auto at = [&](int x, int y)->uint8_t* { return rgba + ((size_t)y * (size_t)w + (size_t)x) * 4; };
    auto at_rgb = [&](int x, int y)->const uint8_t* { return rgb_copy.data() + ((size_t)y * (size_t)w + (size_t)x) * 3; };
    for (int y = 1; y < h-1; ++y) {
        for (int x = 1; x < w-1; ++x) {
            uint8_t *px = at(x,y);
            if (px[3] != 0) continue;
            bool copied = false;
            for (int dy = -1; dy <= 1 && !copied; ++dy) {
                for (int dx = -1; dx <= 1 && !copied; ++dx) {
                    if (dx == 0 && dy == 0) continue;
                    uint8_t *n = at(x+dx, y+dy);
                    if (n[3] > 0) {
                        const uint8_t *nrgb = at_rgb(x+dx, y+dy);
                        px[0] = nrgb[0];
                        px[1] = nrgb[1];
                        px[2] = nrgb[2];
                        copied = true;
                    }
                }
            }
        }
    }
}

void LottieAnimation::_unpremultiply_alpha_rgba(uint8_t *rgba, int w, int h) {
    if (!rgba || w <= 0 || h <= 0) return;
    const size_t pixels = (size_t)w * (size_t)h;
    uint8_t *p = rgba;
    for (size_t i = 0; i < pixels; ++i, p += 4) {
        uint8_t a = p[3];
        if (a == 0) {
            p[0] = p[1] = p[2] = 0;
            continue;
        }
        if (a == 255) continue;
        p[0] = (uint8_t)std::min(255, (int)((int)p[0] * 255 + (a / 2)) / (int)a);
        p[1] = (uint8_t)std::min(255, (int)((int)p[1] * 255 + (a / 2)) / (int)a);
        p[2] = (uint8_t)std::min(255, (int)((int)p[2] * 255 + (a / 2)) / (int)a);
    }
}

static String _mirror_file_to_user_cache(const String &src_path) {
    if (src_path.is_empty()) return String();
    PackedByteArray bytes = FileAccess::get_file_as_bytes(src_path);
    if (bytes.is_empty()) return String();
    const String root = String("user://lottie_cache/_mirror");
    String abs_root = ProjectSettings::get_singleton()->globalize_path(root);
    DirAccess::make_dir_recursive_absolute(abs_root);
    String base = src_path.get_file();
    String mirror_name = String::num_uint64((uint64_t)src_path.hash()) + String("_") + base;
    String mirror_rel = root.path_join(mirror_name);
    Ref<FileAccess> fo = FileAccess::open(mirror_rel, FileAccess::WRITE);
    if (fo.is_null()) return String();
    fo->store_buffer(bytes);
    fo->flush();
    fo->close();
    return mirror_rel;
}
static String _extract_lottie_json_to_cache(const String &zip_path, const String &preferred_entry = String()) {
    Ref<ZIPReader> zr;
    zr.instantiate();
    if (zr.is_null()) {
        UtilityFunctions::printerr("Failed to open .lottie (zip): " + zip_path);
        return String();
    }

    String open_path = zip_path;
    Error zerr = zr->open(open_path);
    if (zerr != OK) {
        // On Web or when file is packed in PCK, mirror to user:// and try again.
        String mirrored = _mirror_file_to_user_cache(zip_path);
        if (!mirrored.is_empty()) {
            zerr = zr->open(mirrored);
            if (zerr == OK) {
                open_path = mirrored;
            }
        }
    }
    if (zerr != OK) {
        UtilityFunctions::printerr("Failed to open .lottie (zip): " + zip_path);
        return String();
    }

    PackedStringArray files = zr->get_files();
    const String cache_root = String("user://lottie_cache");
    String abs_cache_root = ProjectSettings::get_singleton()->globalize_path(cache_root);
    DirAccess::make_dir_recursive_absolute(abs_cache_root);
    String hash_name = String::num_uint64((uint64_t)zip_path.hash());
    String cache_dir = cache_root.path_join(hash_name);
    String abs_cache_dir = ProjectSettings::get_singleton()->globalize_path(cache_dir);
    DirAccess::make_dir_recursive_absolute(abs_cache_dir);

    String json_inside;
    auto file_exists_in_zip = [&](const String &p){ for (int i=0;i<files.size();++i){ if (files[i]==p) return true; } return false; };
    if (!preferred_entry.is_empty()) {
        if (file_exists_in_zip(preferred_entry)) json_inside = preferred_entry;
        if (json_inside.is_empty()) {
            String alt = String("animations/") + preferred_entry + ".json";
            if (file_exists_in_zip(alt)) json_inside = alt;
        }
        if (json_inside.is_empty()) {
            String needle = preferred_entry.to_lower();
            for (int i = 0; i < files.size(); i++) {
                String lf = files[i].to_lower();
                if (lf.ends_with(".json") && lf.find(needle) != -1) { json_inside = files[i]; break; }
            }
        }
    }
    if (json_inside.is_empty()) {
        for (int i = 0; i < files.size(); i++) {
            String f = files[i];
            String lf = f.to_lower();
            if (lf.ends_with(".json") && lf.begins_with("animations/")) { json_inside = f; break; }
        }
        if (json_inside.is_empty()) {
            for (int i = 0; i < files.size(); i++) {
                String f = files[i];
                String lf = f.to_lower();
                if (lf.ends_with("/data.json") || lf == "data.json") { json_inside = f; break; }
            }
        }
        if (json_inside.is_empty()) {
            for (int i = 0; i < files.size(); i++) {
                String f = files[i];
                String lf = f.to_lower();
                if (lf.ends_with(".json") && !lf.ends_with("manifest.json")) { json_inside = f; break; }
            }
        }
    }
    if (json_inside.is_empty()) {
        zr->close();
        UtilityFunctions::printerr(".lottie does not contain a JSON animation file");
        return String();
    }

    // Extract all files to the cache folder, so relative assets resolve.
    for (int i = 0; i < files.size(); i++) {
        String entry = files[i];
        if (entry.ends_with("/")) continue; // skip directory markers
        // Ensure parent directory exists
        String dest_rel = cache_dir.path_join(entry);
        String dest_abs = ProjectSettings::get_singleton()->globalize_path(dest_rel);
        String parent_abs = dest_abs.get_base_dir();
        DirAccess::make_dir_recursive_absolute(parent_abs);
        Ref<ZIPReader> zr3; zr3.instantiate();
        if (zr3->open(open_path) != OK) {
            UtilityFunctions::printerr("Failed to reopen .lottie for extract: " + open_path);
            return String();
        }
        PackedByteArray data = zr3->read_file(entry);
        zr3->close();
        Ref<FileAccess> fo = FileAccess::open(dest_rel, FileAccess::WRITE);
        if (fo.is_null()) {
            // Try to create parent again just in case
            DirAccess::make_dir_recursive_absolute(parent_abs);
            fo = FileAccess::open(dest_rel, FileAccess::WRITE);
        }
        if (fo.is_valid()) {
            fo->store_buffer(data);
            fo->flush();
            fo->close();
        }
    }
    // zr already closed above.

    // Return the chosen JSON inside the extracted cache dir
    String out_path = cache_dir.path_join(json_inside);
    return out_path;
}

#include <unordered_map>
static std::unordered_map<std::string, int> g_anim_usage_counts;
static inline void _registry_inc(const String &key) {
    if (key.is_empty()) return;
    g_anim_usage_counts[std::string(key.utf8().get_data())] += 1;
}
static inline void _registry_dec(const String &key) {
    if (key.is_empty()) return;
    auto it = g_anim_usage_counts.find(std::string(key.utf8().get_data()));
    if (it != g_anim_usage_counts.end()) {
        it->second -= 1; if (it->second <= 0) g_anim_usage_counts.erase(it);
    }
}
static inline int _registry_get(const String &key) {
    auto it = g_anim_usage_counts.find(std::string(key.utf8().get_data()));
    return it == g_anim_usage_counts.end() ? 0 : it->second;
}

void LottieAnimation::_parse_dotlottie_manifest(const String &zip_path) {
    last_lottie_zip_path = zip_path;
    sm_animation_ids.clear();
    sm_machine_names.clear();
    sm_states_by_machine.clear();
    sm_anim_inner_paths.clear();
    sm_state_segments_by_machine.clear();

    Ref<ZIPReader> zr;
    zr.instantiate();
    if (zr.is_null() || zr->open(zip_path) != OK) return;
    PackedStringArray files = zr->get_files();
    String manifest_path = "manifest.json";
    bool manifest_present = false;
    for (int i = 0; i < files.size(); i++) {
        String f = files[i];
        if (f.to_lower().ends_with("manifest.json")) { manifest_path = f; manifest_present = true; break; }
        if (f == manifest_path) { manifest_present = true; }
    }
    if (!manifest_present) { zr->close(); return; }
    PackedByteArray bytes = zr->read_file(manifest_path);
    // Keep `files` around for potential state machine discovery below; we'll reopen when reading contents.
    zr->close();

    String text = bytes.get_string_from_utf8();
    Variant parsed = JSON::parse_string(text);
    if (parsed.get_type() != Variant::DICTIONARY) return;
    Dictionary manifest = parsed;

    // animations: accept array or object map
    if (manifest.has("animations")) {
        Variant anv = manifest["animations"];
        if (anv.get_type() == Variant::ARRAY) {
            Array arr = anv;
            for (int i = 0; i < arr.size(); i++) {
                if (arr[i].get_type() != Variant::DICTIONARY) continue;
                Dictionary a = arr[i];
                String id = a.has("id") ? (String)a["id"] : (a.has("name") ? (String)a["name"] : String());
                if (id.is_empty()) continue;
                bool dup = false; for (int j = 0; j < sm_animation_ids.size(); j++) { if (sm_animation_ids[j] == id) { dup = true; break; } }
                if (!dup) sm_animation_ids.push_back(id);
                if (a.has("lottie")) sm_anim_inner_paths[id] = (String)a["lottie"]; // e.g. animations/<id>.json
                else if (a.has("path")) sm_anim_inner_paths[id] = (String)a["path"]; // alias used by some tools
                else sm_anim_inner_paths[id] = String("animations/") + id + ".json";
            }
        } else if (anv.get_type() == Variant::DICTIONARY) {
            Dictionary amap = anv;
            Array keys = amap.keys();
            for (int i = 0; i < keys.size(); i++) {
                String id = (String)keys[i];
                Dictionary a = amap[id];
                bool dup = false; for (int j = 0; j < sm_animation_ids.size(); j++) { if (sm_animation_ids[j] == id) { dup = true; break; } }
                if (!dup) sm_animation_ids.push_back(id);
                if (a.has("lottie")) sm_anim_inner_paths[id] = (String)a["lottie"];
                else if (a.has("path")) sm_anim_inner_paths[id] = (String)a["path"]; 
                else sm_anim_inner_paths[id] = String("animations/") + id + ".json";
            }
        }
    }
    // state machines: accept array or map; states can be array, map, or nodes list
    auto parse_states_from_variant = [](const Variant &sv) {
        PackedStringArray out;
        if (sv.get_type() == Variant::ARRAY) {
            Array st = sv;
            for (int k = 0; k < st.size(); k++) {
                if (st[k].get_type() == Variant::DICTIONARY) {
                    Dictionary sd = st[k];
                    if (sd.has("name")) out.push_back((String)sd["name"]);
                    else if (sd.has("id")) out.push_back((String)sd["id"]);
                } else if (st[k].get_type() == Variant::STRING) {
                    out.push_back((String)st[k]);
                }
            }
        } else if (sv.get_type() == Variant::DICTIONARY) {
            Dictionary st = sv;
            Array keys = st.keys();
            for (int k = 0; k < keys.size(); k++) {
                String key = (String)keys[k];
                Variant v = st[key];
                if (v.get_type() == Variant::DICTIONARY) {
                    Dictionary sd = v;
                    if (sd.has("name")) out.push_back((String)sd["name"]);
                    else out.push_back(key);
                } else {
                    out.push_back(key);
                }
            }
        }
        return out;
    };

    if (manifest.has("stateMachines")) {
        Variant smv = manifest["stateMachines"];
        if (smv.get_type() == Variant::ARRAY) {
            Array sms = smv;
            for (int i = 0; i < sms.size(); i++) {
                if (sms[i].get_type() != Variant::DICTIONARY) continue;
                Dictionary sm = sms[i];
                String name = sm.has("name") ? (String)sm["name"] : (sm.has("id") ? (String)sm["id"] : String("state_machine"));
                bool dupm = false; for (int j = 0; j < sm_machine_names.size(); j++) { if (sm_machine_names[j] == name) { dupm = true; break; } }
                if (!dupm) sm_machine_names.push_back(name);
                PackedStringArray states;
                if (sm.has("states")) states = parse_states_from_variant(sm["states"]);
                // Some tools store nodes instead of states
                if (states.is_empty() && sm.has("nodes")) states = parse_states_from_variant(sm["nodes"]);
                sm_states_by_machine[name] = states;
            }
        } else if (smv.get_type() == Variant::DICTIONARY) {
            Dictionary smap = smv;
            Array mkeys = smap.keys();
            for (int i = 0; i < mkeys.size(); i++) {
                String name = (String)mkeys[i];
                Dictionary sm = smap[name];
                bool dupm = false; for (int j = 0; j < sm_machine_names.size(); j++) { if (sm_machine_names[j] == name) { dupm = true; break; } }
                if (!dupm) sm_machine_names.push_back(name);
                PackedStringArray states;
                if (sm.has("states")) states = parse_states_from_variant(sm["states"]);
                if (states.is_empty() && sm.has("nodes")) states = parse_states_from_variant(sm["nodes"]);
                sm_states_by_machine[name] = states;
            }
        }
    }

    // Supplement: If states are not listed in manifest, try to load state machine JSONs from inside the .lottie zip.
    auto parse_states_json_text = [](const String &text, Dictionary &out_segments) -> PackedStringArray {
        PackedStringArray out;
        out_segments.clear();
        Variant v = JSON::parse_string(text);
        if (v.get_type() != Variant::DICTIONARY) return out;
        Dictionary d = v;
        if (d.has("states") && d["states"].get_type() == Variant::ARRAY) {
            Array arr = d["states"];
            for (int i = 0; i < arr.size(); i++) {
                if (arr[i].get_type() == Variant::DICTIONARY) {
                    Dictionary sd = arr[i];
                    if (sd.has("name")) {
                        String name = (String)sd["name"];
                        out.push_back(name);
                        if (sd.has("segment")) {
                            out_segments[name] = (String)sd["segment"];
                        }
                    }
                }
            }
        }
        return out;
    };

    auto try_load_states_for_machine = [&](const String &machine_name) -> PackedStringArray {
        // Heuristics: look for JSON file whose basename equals <machine_name>.json in any folder containing "state"; fallback to any such JSON.
        PackedStringArray out;
        Ref<ZIPReader> zr2; zr2.instantiate();
        if (zr2.is_null() || zr2->open(zip_path) != OK) return out;
        PackedStringArray fl = zr2->get_files();
    String target_basename = machine_name + String(".json");
        String target_basename_lc = target_basename.to_lower();
        String candidate_path;
        // 1) Exact basename match inside folders likely holding state machines
        for (int i = 0; i < fl.size(); i++) {
            String f = fl[i];
            if (f.ends_with("/")) continue;
            String fname = f.get_file();
            String folder_lc = f.get_base_dir().to_lower();
            if ((folder_lc.find("state") != -1 || folder_lc.find("machine") != -1) && fname.to_lower() == target_basename_lc) {
                candidate_path = f; break;
            }
        }
        // 2) Any file containing machine name in a "state" folder
        if (candidate_path.is_empty()) {
            String needle = machine_name.to_lower();
            for (int i = 0; i < fl.size(); i++) {
                String f = fl[i];
                if (f.ends_with("/")) continue;
                String folder_lc = f.get_base_dir().to_lower();
                String fname_lc = f.get_file().to_lower();
                if ((folder_lc.find("state") != -1 || folder_lc.find("machine") != -1) && fname_lc.ends_with(".json") && fname_lc.find(needle) != -1) {
                    candidate_path = f; break;
                }
            }
        }
        // 3) Fallback: first JSON inside any folder with "state" in path
        if (candidate_path.is_empty()) {
            for (int i = 0; i < fl.size(); i++) {
                String f = fl[i];
                if (f.ends_with("/")) continue;
                String lf = f.to_lower();
                if (lf.ends_with(".json") && lf.find("state") != -1) { candidate_path = f; break; }
            }
        }
        if (!candidate_path.is_empty()) {
            PackedByteArray bytes2 = zr2->read_file(candidate_path);
            zr2->close();
            String text2 = bytes2.get_string_from_utf8();
            Dictionary segs;
            out = parse_states_json_text(text2, segs);
            if (!out.is_empty()) {
                sm_state_segments_by_machine[machine_name] = segs;
            }
        } else {
            zr2->close();
        }
        return out;
    };

    for (int i = 0; i < sm_machine_names.size(); i++) {
        String mname = sm_machine_names[i];
        PackedStringArray existing;
        if (sm_states_by_machine.has(mname)) existing = (PackedStringArray)sm_states_by_machine[mname];
        if (existing.is_empty()) {
            PackedStringArray states = try_load_states_for_machine(mname);
            if (!states.is_empty()) sm_states_by_machine[mname] = states;
        }
    }
    if (active_animation_id.is_empty() && sm_animation_ids.size() > 0) active_animation_id = sm_animation_ids[0];
    if (active_state_machine.is_empty() && sm_machine_names.size() > 0) active_state_machine = sm_machine_names[0];
    PackedStringArray sts;
    if (sm_states_by_machine.has(active_state_machine)) sts = (PackedStringArray)sm_states_by_machine[active_state_machine];
    if (active_state.is_empty() && sts.size() > 0) active_state = sts[0];
    notify_property_list_changed();
}

String LottieAnimation::_extract_json_from_lottie_to_cache(const String &zip_path, const String &inner_path, const String &suffix_key) {
    return _extract_lottie_json_to_cache(zip_path, inner_path);
}

void LottieAnimation::_get_property_list(List<PropertyInfo> *p_list) const {
    if (animation_path.is_empty() || !animation_path.to_lower().ends_with(".lottie")) return;
    // Build enum hints
    String anim_opts;
    for (int i = 0; i < sm_animation_ids.size(); i++) { if (i>0) anim_opts += ","; anim_opts += sm_animation_ids[i]; }
    String sm_opts;
    for (int i = 0; i < sm_machine_names.size(); i++) { if (i>0) sm_opts += ","; sm_opts += sm_machine_names[i]; }
    String st_opts;
    PackedStringArray states;
    if (sm_states_by_machine.has(active_state_machine)) states = (PackedStringArray)sm_states_by_machine[active_state_machine];
    for (int i = 0; i < states.size(); i++) { if (i>0) st_opts += ","; st_opts += states[i]; }

    p_list->push_back(PropertyInfo(Variant::STRING, "state/animation", PROPERTY_HINT_ENUM, anim_opts));
    p_list->push_back(PropertyInfo(Variant::STRING, "state/machine", PROPERTY_HINT_ENUM, sm_opts));
    p_list->push_back(PropertyInfo(Variant::STRING, "state/state", PROPERTY_HINT_ENUM, st_opts));
}

bool LottieAnimation::_get(const StringName &p_name, Variant &r_ret) const {
    String name = p_name;
    if (name == "state/animation") { r_ret = active_animation_id; return true; }
    if (name == "state/machine") { r_ret = active_state_machine; return true; }
    if (name == "state/state") { r_ret = active_state; return true; }
    return false;
}

bool LottieAnimation::_set(const StringName &p_name, const Variant &p_value) {
    String name = p_name;
    if (name == "state/animation") {
        String id = (String)p_value;
        if (active_animation_id != id) {
            active_animation_id = id;
            selected_dotlottie_animation = id;
            // If current source is a .lottie, reload preferred entry
            if (!animation_path.is_empty() && animation_path.to_lower().ends_with(".lottie")) {
                _load_animation(animation_path);
                if (playing) play();
                // Apply state segment again after reloading
                _apply_selected_state_segment();
            }
        }
        return true;
    }
    if (name == "state/machine") {
        String m = (String)p_value;
        if (active_state_machine != m) {
            active_state_machine = m;
            // Reset first state of this machine
            PackedStringArray states;
            if (sm_states_by_machine.has(m)) states = (PackedStringArray)sm_states_by_machine[m];
            active_state = states.size() > 0 ? states[0] : String();
            notify_property_list_changed();
            // Apply first state's segment and play
            _apply_selected_state_segment();
            if (!active_state.is_empty()) { current_frame = 0.0f; play(); }
        }
        return true;
    }
    if (name == "state/state") {
        active_state = (String)p_value;
        // Apply selected state's segment and auto-play
        _apply_selected_state_segment();
        if (!active_state.is_empty()) { current_frame = 0.0f; play(); }
        return true;
    }
    return false;
}

void LottieAnimation::_bind_methods() {
    // Methods
    ClassDB::bind_method(D_METHOD("play"), &LottieAnimation::play);
    ClassDB::bind_method(D_METHOD("stop"), &LottieAnimation::stop);
    ClassDB::bind_method(D_METHOD("pause"), &LottieAnimation::pause);
    ClassDB::bind_method(D_METHOD("seek", "frame"), &LottieAnimation::seek);
    ClassDB::bind_method(D_METHOD("set_frame", "frame"), &LottieAnimation::set_frame);
    ClassDB::bind_method(D_METHOD("get_frame"), &LottieAnimation::get_frame);
    
    // Property methods
    ClassDB::bind_method(D_METHOD("set_animation_path", "path"), &LottieAnimation::set_animation_path);
    ClassDB::bind_method(D_METHOD("get_animation_path"), &LottieAnimation::get_animation_path);
    ClassDB::bind_method(D_METHOD("set_selected_dotlottie_animation", "id_or_path"), &LottieAnimation::set_selected_dotlottie_animation);
    ClassDB::bind_method(D_METHOD("get_selected_dotlottie_animation"), &LottieAnimation::get_selected_dotlottie_animation);
    
    ClassDB::bind_method(D_METHOD("set_playing", "playing"), &LottieAnimation::set_playing);
    ClassDB::bind_method(D_METHOD("is_playing"), &LottieAnimation::is_playing);
    
    ClassDB::bind_method(D_METHOD("set_looping", "looping"), &LottieAnimation::set_looping);
    ClassDB::bind_method(D_METHOD("is_looping"), &LottieAnimation::is_looping);
    
    ClassDB::bind_method(D_METHOD("set_autoplay", "autoplay"), &LottieAnimation::set_autoplay);
    ClassDB::bind_method(D_METHOD("is_autoplay"), &LottieAnimation::is_autoplay);
    
    ClassDB::bind_method(D_METHOD("set_speed", "speed"), &LottieAnimation::set_speed);
    ClassDB::bind_method(D_METHOD("get_speed"), &LottieAnimation::get_speed);
    
    ClassDB::bind_method(D_METHOD("set_render_size", "size"), &LottieAnimation::set_render_size);
    ClassDB::bind_method(D_METHOD("get_render_size"), &LottieAnimation::get_render_size);

    ClassDB::bind_method(D_METHOD("set_use_animation_size", "enabled"), &LottieAnimation::set_use_animation_size);
    ClassDB::bind_method(D_METHOD("is_using_animation_size"), &LottieAnimation::is_using_animation_size);

    ClassDB::bind_method(D_METHOD("set_fit_into_box", "enabled"), &LottieAnimation::set_fit_into_box);
    ClassDB::bind_method(D_METHOD("is_fit_into_box"), &LottieAnimation::is_fit_into_box);
    ClassDB::bind_method(D_METHOD("set_fit_box_size", "size"), &LottieAnimation::set_fit_box_size);
    ClassDB::bind_method(D_METHOD("get_fit_box_size"), &LottieAnimation::get_fit_box_size);

    ClassDB::bind_method(D_METHOD("set_dynamic_resolution", "enabled"), &LottieAnimation::set_dynamic_resolution);
    ClassDB::bind_method(D_METHOD("is_dynamic_resolution"), &LottieAnimation::is_dynamic_resolution);
    ClassDB::bind_method(D_METHOD("set_resolution_threshold", "threshold"), &LottieAnimation::set_resolution_threshold);
    ClassDB::bind_method(D_METHOD("get_resolution_threshold"), &LottieAnimation::get_resolution_threshold);
    ClassDB::bind_method(D_METHOD("set_max_render_size", "size"), &LottieAnimation::set_max_render_size);
    ClassDB::bind_method(D_METHOD("get_max_render_size"), &LottieAnimation::get_max_render_size);
    ClassDB::bind_method(D_METHOD("set_frame_cache_enabled", "enabled"), &LottieAnimation::set_frame_cache_enabled);
    ClassDB::bind_method(D_METHOD("is_frame_cache_enabled"), &LottieAnimation::is_frame_cache_enabled);
    ClassDB::bind_method(D_METHOD("set_frame_cache_budget_mb", "mb"), &LottieAnimation::set_frame_cache_budget_mb);
    ClassDB::bind_method(D_METHOD("get_frame_cache_budget_mb"), &LottieAnimation::get_frame_cache_budget_mb);
    ClassDB::bind_method(D_METHOD("set_frame_cache_step", "frames"), &LottieAnimation::set_frame_cache_step);
    ClassDB::bind_method(D_METHOD("get_frame_cache_step"), &LottieAnimation::get_frame_cache_step);
    ClassDB::bind_method(D_METHOD("set_engine_option", "opt"), &LottieAnimation::set_engine_option);
    ClassDB::bind_method(D_METHOD("get_engine_option"), &LottieAnimation::get_engine_option);
    // Static rendering when idle is now unconditional; only expose render_static() helper.
    ClassDB::bind_method(D_METHOD("render_static"), &LottieAnimation::render_static);
    
    ClassDB::bind_method(D_METHOD("get_duration"), &LottieAnimation::get_duration);
    ClassDB::bind_method(D_METHOD("get_total_frames"), &LottieAnimation::get_total_frames);
    ClassDB::bind_method(D_METHOD("set_culling_mode", "mode"), &LottieAnimation::set_culling_mode);
    ClassDB::bind_method(D_METHOD("get_culling_mode"), &LottieAnimation::get_culling_mode);
    ClassDB::bind_method(D_METHOD("set_culling_margin_px", "margin"), &LottieAnimation::set_culling_margin_px);
    ClassDB::bind_method(D_METHOD("get_culling_margin_px"), &LottieAnimation::get_culling_margin_px);
    ClassDB::bind_method(D_METHOD("_on_viewport_size_changed"), &LottieAnimation::_on_viewport_size_changed);
    ClassDB::bind_method(D_METHOD("set_offset", "offset"), &LottieAnimation::set_offset);
    ClassDB::bind_method(D_METHOD("get_offset"), &LottieAnimation::get_offset);
    
    // Properties
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "animation_path", PROPERTY_HINT_FILE, "*.json,*.lottie"), 
                 "set_animation_path", "get_animation_path");
    // Selection helper for .lottie bundles (hidden from inspector; controlled by plugin UI)
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "dotlottie/selected_animation", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR),
                 "set_selected_dotlottie_animation", "get_selected_dotlottie_animation");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "playing"), "set_playing", "is_playing");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "autoplay"), "set_autoplay", "is_autoplay");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "looping"), "set_looping", "is_looping");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed", PROPERTY_HINT_RANGE, "0.0,10.0,0.01"), 
                 "set_speed", "get_speed");
    // Hide legacy sizing controls from the editor; always using Fit Into Box path now.
    // Kept setters/getters bound for potential script compatibility, but not exposed as properties.
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "fit_into_box"), "set_fit_into_box", "is_fit_into_box");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "fit_box_size"), "set_fit_box_size", "get_fit_box_size");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "dynamic_resolution"), "set_dynamic_resolution", "is_dynamic_resolution");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "resolution_threshold", PROPERTY_HINT_RANGE, "0.01,1.0,0.01"), "set_resolution_threshold", "get_resolution_threshold");
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "max_render_size", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR), "set_max_render_size", "get_max_render_size");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "frame_cache/enabled", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR), "set_frame_cache_enabled", "is_frame_cache_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "frame_cache/budget_mb", PROPERTY_HINT_RANGE, "16,4096,16", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR), "set_frame_cache_budget_mb", "get_frame_cache_budget_mb");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "frame_cache/step_frames", PROPERTY_HINT_RANGE, "1,8,1", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR), "set_frame_cache_step", "get_frame_cache_step");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "engine_option", PROPERTY_HINT_ENUM, "Default,SmartRender", PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_NO_EDITOR), "set_engine_option", "get_engine_option");
    
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "offset"), "set_offset", "get_offset");
    
    ADD_SIGNAL(MethodInfo("animation_finished"));
    ADD_SIGNAL(MethodInfo("frame_changed", PropertyInfo(Variant::FLOAT, "frame")));
    ADD_SIGNAL(MethodInfo("animation_loaded", PropertyInfo(Variant::BOOL, "success")));
}

LottieAnimation::LottieAnimation() {
    animation_path = "";
    playing = false;
    looping = true;
    autoplay = false;
    speed = 1.0f;
    current_frame = 0.0f;
    total_frames = 0.0f;
    duration = 0.0f;
    render_size = Vector2i(512, 512);
    use_animation_size = false; // ignored; always fit_into_box
    fit_into_box = true; // always fit into box
    fit_box_size = Vector2i(512, 512);
    dynamic_resolution = true;
    resolution_threshold = 0.15f; // 15% change triggers reallocation
    max_render_size = Vector2i(4096, 4096);
    base_picture_size = Vector2i(512, 512);
    _elapsed_time = 0.0;
    _last_resize_at = -1.0;
    offset = Vector2();
    
    canvas = nullptr;
    animation = nullptr;
    picture = nullptr;
    buffer = nullptr;
    
    // Disable worker thread on Web (wasm32) where std::thread requires special threading support.
#ifdef __EMSCRIPTEN__
    render_thread_enabled = false;
#endif
    _initialize_thorvg();
}

LottieAnimation::~LottieAnimation() {
    // Decrement usage for current animation key
    if (!animation_key.is_empty()) _registry_dec(animation_key);
    _cleanup_thorvg();
}

void LottieAnimation::_initialize_thorvg() {
    static bool thorvg_initialized = false;
    if (!thorvg_initialized) {
        unsigned int hw_threads = std::thread::hardware_concurrency();
        unsigned int threads = hw_threads;
        
        if (threads == 0) threads = 4;
        
        if (hw_threads >= 8) {
            threads = hw_threads + 2;
        }
        
        UtilityFunctions::print("Initializing ThorVG with ", threads, " threads (CPU cores: ", hw_threads, ")");
        
        if (tvg::Initializer::init(threads) != tvg::Result::Success) {
            UtilityFunctions::printerr("Failed to initialize ThorVG");
            return;
        }
        
        UtilityFunctions::print("ThorVG initialized successfully! Active threads:", threads);
        thorvg_initialized = true;
    }
    
    tvg::EngineOption render_opt = tvg::EngineOption::Default;
    if (engine_option == 1) render_opt = tvg::EngineOption::SmartRender;
    
    canvas = tvg::SwCanvas::gen(render_opt);
    if (!canvas) {
        UtilityFunctions::printerr("Failed to create ThorVG canvas");
        return;
    }
    
    _allocate_buffer_and_target(render_size);
    // Only start worker when enabled (never on Web by default)
    _start_worker_if_needed();
}

void LottieAnimation::_cleanup_thorvg() {
    _stop_worker();
    if (picture && animation) {
        canvas->remove();
    }
    
    if (canvas) {
        delete canvas;
        canvas = nullptr;
    }
    
    if (buffer) { delete[] buffer; buffer = nullptr; }
    
    animation = nullptr;
    picture = nullptr;
}

bool LottieAnimation::_load_animation(const String& path) {
    if (path.is_empty()) {
        return false;
    }
    
    if (!canvas) {
        UtilityFunctions::printerr("ThorVG canvas not initialized");
        return false;
    }
    
    if (picture) {
    canvas->remove();
        picture = nullptr;
        animation = nullptr;
        if (buffer) memset(buffer, 0, (size_t)render_size.x * (size_t)render_size.y * sizeof(uint32_t));
        if (image.is_valid()) {
            pixel_bytes.fill(0);
            image->set_data(render_size.x, render_size.y, false, Image::FORMAT_RGBA8, pixel_bytes);
            if (texture.is_valid()) texture->update(image);
        }
    }
    
    animation = tvg::Animation::gen();
    picture = animation->picture();
    
    if (!picture) {
        UtilityFunctions::printerr("Failed to create ThorVG picture");
        return false;
    }
    
    // Load the Lottie file (.json/.lot) or handle .lottie (zip) by extracting the JSON
    String source_path = path;
    String lower = path.to_lower();
    if (lower.ends_with(".lottie")) {
        // Parse manifest to populate inspector dropdowns
        _parse_dotlottie_manifest(path);
        // Prefer mapped inner JSON path for the active animation id if present
        String preferred_inner;
        if (!active_animation_id.is_empty() && sm_anim_inner_paths.has(active_animation_id)) {
            preferred_inner = (String)sm_anim_inner_paths[active_animation_id];
        } else {
            preferred_inner = selected_dotlottie_animation;
        }
        // If a specific animation was selected from manifest, prefer extracting that entry
        String extracted = _extract_lottie_json_to_cache(path, preferred_inner);
        if (extracted.is_empty()) {
            emit_signal("animation_loaded", false);
            return false;
        }
        source_path = extracted;
    }

    // Try direct load; if it fails (e.g., file is inside the PCK on Web), mirror to user:// and retry.
    auto _try_load_path = [&](const String &p) -> bool {
        String ap = ProjectSettings::get_singleton()->globalize_path(p);
        return picture->load(ap.utf8().get_data()) == tvg::Result::Success;
    };

    bool loaded_ok = _try_load_path(source_path);
    if (!loaded_ok) {
        String mirrored = _mirror_file_to_user_cache(source_path);
        if (!mirrored.is_empty()) {
            loaded_ok = _try_load_path(mirrored);
        }
    }
    if (!loaded_ok) {
        UtilityFunctions::printerr("Failed to load Lottie animation: " + source_path);
        return false;
    }
    // Decrement usage for old key if different
    if (!animation_key.is_empty() && animation_key != source_path) {
        _registry_dec(animation_key);
    }
    animation_key = source_path; // cache key base
    _registry_inc(animation_key);
    _recompute_live_cache_state();
    
    // Get animation info
    duration = animation->duration();
    total_frames = animation->totalFrame();
    current_frame = 0.0f;
    
    // Query intrinsic size and set sizing policy
    float pw = 0.0f, ph = 0.0f;
    picture->size(&pw, &ph);
    if (pw <= 0 || ph <= 0) {
        pw = (float)render_size.x; ph = (float)render_size.y;
    }
    base_picture_size = Vector2i((int)std::ceil(pw), (int)std::ceil(ph));

    _apply_sizing_policy();
    _apply_picture_transform_to_fit();

    // Add to canvas once; keep persistent for incremental updates
    if (canvas->push(picture) != tvg::Result::Success) {
        UtilityFunctions::printerr("Failed to push picture to canvas");
        return false;
    }
    
    _create_texture();
    if (render_thread_enabled) {
        _post_load_to_worker(source_path);
        _post_render_to_worker(render_size, current_frame);
    } else {
        _render_frame(); // Draw initial frame immediately
    }
    // Ensure first frame shows even if not playing (static usage)
    if (!playing) {
        _render_frame();
        queue_redraw();
    }
    // Apply any selected state segment after load
    _apply_selected_state_segment();
    
    // Removed verbose load prints to keep output clean.
    
    emit_signal("animation_loaded", true);
    return true;
}

void LottieAnimation::_create_texture() {
    image = Image::create(render_size.x, render_size.y, false, Image::FORMAT_RGBA8);
    // Initialize to transparent to avoid white flash during rapid resizes before first frame upload
    if (image.is_valid()) {
        image->fill(Color(0, 0, 0, 0));
    }
    _recreate_texture_ring();
}

void LottieAnimation::_recreate_texture_ring() {
    texture_ring.clear();
    texture_ring.reserve(std::max(2, texture_ring_size));
    for (int i = 0; i < std::max(2, texture_ring_size); ++i) {
        Ref<ImageTexture> tex = ImageTexture::create_from_image(image);
        texture_ring.push_back(tex);
    }
    texture_ring_index = 0;
    if (!texture_ring.empty()) texture = texture_ring[0];
}

void LottieAnimation::_update_animation(float delta) {
    if (!playing || !animation || total_frames <= 0) {
        return;
    }
    
    // Update current frame
    float prev_frame = current_frame;
    current_frame += (total_frames / duration) * delta * speed;
    
    // Handle looping
    if (current_frame >= total_frames) {
        if (looping) {
            current_frame = fmod(current_frame, total_frames);
        } else {
            current_frame = total_frames - 1;
            playing = false;
            emit_signal("animation_finished");
        }
    }
    
    // Emit frame changed signal
    if ((int)prev_frame != (int)current_frame) {
        emit_signal("frame_changed", current_frame);
    }
}

void LottieAnimation::_render_frame() {
    // Reentrancy guard to avoid nested renders during rapid editor events.
    if (rendering) {
        return;
    }
    rendering = true;
    struct _RenderResetGuard { bool *flag; ~_RenderResetGuard(){ if (flag) *flag = false; } } _guard{ &rendering };

    if (!canvas || !animation || !picture || !buffer) {
        return;
    }
    // Skip if nothing changed and we've already drawn once
    int qf_now = _quantized_frame_index();
    if (first_frame_drawn && !pending_resize && qf_now == last_rendered_qf) {
        return;
    }
    // Cache fast-path: if enabled, try to reuse a shared texture
    if (frame_cache_enabled && (!cache_only_when_paused || !playing ? true : false)) {
        _ensure_cache_capacity();
        int qf = _quantized_frame_index();
        Ref<ImageTexture> cached = LottieFrameCache::get_singleton()->get(animation_key, qf, render_size);
        if (cached.is_valid()) {
            texture = cached;
            _uploaded_this_frame = true; // visual changed
            return;
        }
    }

    // Set animation frame
    animation->frame(current_frame);

    canvas->update();
    canvas->draw(false);
    canvas->sync();
    
    // Copy buffer to image (reuse persistent pixel_bytes to avoid allocations)
    if (image.is_valid()) {
        const int64_t bytes_needed = (int64_t)render_size.x * (int64_t)render_size.y * 4;
        if (pixel_bytes.size() != bytes_needed) {
            pixel_bytes.resize(bytes_needed);
        }
        // Optimized conversion ARGB -> RGBA into persistent pixel_bytes.
        _convert_argb_to_rgba_optimized(buffer, pixel_bytes.ptrw(), (size_t)render_size.x * (size_t)render_size.y);
        if (unpremultiply_alpha) {
            _unpremultiply_alpha_rgba(pixel_bytes.ptrw(), render_size.x, render_size.y);
        }
        if (fix_alpha_border) {
            _fix_alpha_border_rgba(pixel_bytes.ptrw(), render_size.x, render_size.y);
        }
        image->set_data(render_size.x, render_size.y, false, Image::FORMAT_RGBA8, pixel_bytes);
        if (!texture_ring.empty()) {
            Ref<ImageTexture> &slot = texture_ring[texture_ring_index];
            if (slot.is_valid()) {
                slot->update(image);
                texture = slot;
                texture_ring_index = (texture_ring_index + 1) % (int)texture_ring.size();
            }
        } else if (texture.is_valid()) {
            texture->update(image);
        }
        // Store in cache if enabled
        if (frame_cache_enabled && (!cache_only_when_paused || !playing ? true : false)) {
            int qf = _quantized_frame_index();
            LottieFrameCache::get_singleton()->put(animation_key, qf, render_size, texture, (size_t)bytes_needed);
        }
    }
    last_rendered_qf = qf_now;
    _uploaded_this_frame = true;
    first_frame_drawn = true;
}
int LottieAnimation::_quantized_frame_index() const {
    if (frame_cache_step <= 1) return (int)std::round(current_frame);
    int step = std::max(1, frame_cache_step);
    int idx = (int)std::round(current_frame);
    return (idx / step) * step;
}

void LottieAnimation::_ensure_cache_capacity() {
    size_t bytes = (size_t)std::max(16, frame_cache_budget_mb) * 1024ull * 1024ull;
    LottieFrameCache::get_singleton()->set_capacity_bytes(bytes);
}

void LottieAnimation::_ready() {
    // Process also in the editor to react to editor zoom.
    set_process_mode(Node::PROCESS_MODE_ALWAYS);
    set_process(true);
    set_notify_transform(true);
    if (get_viewport()) {
        get_viewport()->connect("size_changed", Callable(this, "_on_viewport_size_changed"));
    }
    // Always load when a path is set; if autoplay is off, render the first frame statically.
    if (!animation_path.is_empty()) {
        if (_load_animation(animation_path)) {
            if (autoplay) {
                play();
            } else {
                render_static();
            }
        }
    }
}

void LottieAnimation::_process(double delta) {
    _uploaded_this_frame = false; // reset per-frame flag for redraw gating
    // Coalesce pending resizes safely here, once per frame
    _elapsed_time += delta;
    if (dynamic_resolution) {
        _update_resolution_from_scale(); // computes desired and may set pending_resize
    }
    bool applied_resize = false;
    if (pending_resize && canvas) {
        // Rate-limit reallocations to avoid thrashing during fast zoom/resize
        if (_last_resize_at >= 0.0 && (_elapsed_time - _last_resize_at) < (double)_min_resize_interval) {
            // skip this frame; keep pending_resize true
        } else {
            _last_resize_at = _elapsed_time;
            pending_resize = false;
            _allocate_buffer_and_target(pending_target_size);
            _apply_picture_transform_to_fit();
            canvas->update();
            applied_resize = true;
        }
    }
    _update_animation(delta);
    if (is_visible_in_tree() || Engine::get_singleton()->is_editor_hint()) {
        // Culling disabled: always treat as visible and post/refresh on frame/size change
        bool on_screen_now = true;
        bool became_visible = false;
        if (render_thread_enabled) {
            // Ask worker to render the next desired frame
            {
                int qf = _quantized_frame_index();
                if (render_size != last_posted_size || qf != last_posted_qf) {
                    _post_render_to_worker(render_size, current_frame);
                    last_posted_size = render_size;
                    last_posted_qf = qf;
                }
            }
            // Try to upload the most recent finished frame
            {
                std::lock_guard<std::mutex> lk(frame_mutex);
                if (latest_frame.ready && latest_frame.id > last_consumed_id) {
                    if (latest_frame.w == render_size.x && latest_frame.h == render_size.y) {
                        // Ensure image/texture prepared for this size
                        if (!image.is_valid() || image->get_width() != render_size.x || image->get_height() != render_size.y) {
                            _create_texture();
                        }
                        PackedByteArray pba;
                        pba.resize((int64_t)latest_frame.rgba.size());
                        {
                            uint8_t *dst = pba.ptrw();
                            memcpy(dst, latest_frame.rgba.data(), latest_frame.rgba.size());
                        }
                        image->set_data(render_size.x, render_size.y, false, Image::FORMAT_RGBA8, pba);
                        if (!texture_ring.empty()) {
                            Ref<ImageTexture> &slot = texture_ring[texture_ring_index];
                            if (slot.is_valid()) {
                                slot->update(image);
                                texture = slot;
                                texture_ring_index = (texture_ring_index + 1) % (int)texture_ring.size();
                            }
                        } else if (texture.is_valid()) {
                            texture->update(image);
                        }
                        last_consumed_id = latest_frame.id;
                        latest_frame.ready = false;
                        _uploaded_this_frame = true; // visual changed
                    } else {
                        // Size changed; drop this frame
                        latest_frame.ready = false;
                    }
                }
            }
        } else {
            // Only render on main thread if frame or size changed
            int qf = _quantized_frame_index();
            if (pending_resize || !first_frame_drawn || qf != last_rendered_qf) {
                _render_frame();
            }
        }
    }
    // Redraw gating: redraw only when visuals changed or after applying resize
    if (_uploaded_this_frame || applied_resize) {
        queue_redraw();
        _last_drawn_qf = last_rendered_qf;
    }
}

void LottieAnimation::_draw() {
    if (texture.is_valid()) {
        // Draw at logical display size (fit_box_size), independent of internal render resolution.
        // Apply offset so Node2D position can serve as YSort pivot (e.g. feet) while image draws above it.
        Vector2 size = Vector2((float)fit_box_size.x, (float)fit_box_size.y);
        Vector2 half_box = size * 0.5f;
        // top_left = -half_box means centered; adding offset shifts the drawing
        Rect2 dst = Rect2(-half_box + offset, size);
        Rect2 src = Rect2(Vector2(0, 0), Vector2((float)render_size.x, (float)render_size.y));
        draw_texture_rect_region(texture, dst, src);
    }
}

void LottieAnimation::_notification(int32_t p_what) {
    switch (p_what) {
        case NOTIFICATION_TRANSFORM_CHANGED:
        case NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
        case NOTIFICATION_WORLD_2D_CHANGED:
            if (dynamic_resolution) {
                _update_resolution_from_scale(); // sets pending resize; actual apply happens in _process
                // redraw will be queued in _process when resize applies or a new frame uploads
            }
            break;
        default:
            break;
    }
}

void LottieAnimation::_allocate_buffer_and_target(const Vector2i &size) {
    if (size.x <= 0 || size.y <= 0) return;
    Ref<ImageTexture> old_texture = texture;
    Ref<Image> old_image = image;
    Vector2i old_render_size = render_size;

    if (buffer) { delete[] buffer; buffer = nullptr; }
    render_size = Vector2i(std::min(size.x, max_render_size.x), std::min(size.y, max_render_size.y));
    buffer = new uint32_t[(size_t)render_size.x * (size_t)render_size.y];
    memset(buffer, 0, (size_t)render_size.x * (size_t)render_size.y * sizeof(uint32_t));
    canvas->target(buffer, render_size.x, render_size.x, render_size.y, tvg::ColorSpace::ARGB8888S);
    pixel_bytes.resize((int64_t)render_size.x * (int64_t)render_size.y * 4);
    _create_texture();

    // If we had an old texture and sizes differ, scale old image into new one as a placeholder (avoids flash)
    if (old_image.is_valid() && image.is_valid() && (old_render_size != render_size)) {
        Ref<Image> temp = old_image->duplicate();
        if (temp.is_valid()) {
            temp->resize(render_size.x, render_size.y, Image::INTERPOLATE_BILINEAR);
            if (!texture_ring.empty()) {
                Ref<ImageTexture> &slot = texture_ring[0];
                if (slot.is_valid()) {
                    slot->update(temp);
                    texture = slot; // use scaled previous content until new frame arrives
                }
            } else if (texture.is_valid()) {
                texture->update(temp);
            }
        }
    }
}

void LottieAnimation::_apply_sizing_policy() {
    // Always respect fit_into_box sizing; ignore use_animation_size/render_size
    _allocate_buffer_and_target(fit_box_size);
}

void LottieAnimation::_apply_picture_transform_to_fit() {
    if (!picture) return;
    float pw = std::max(1.0f, (float)base_picture_size.x);
    float ph = std::max(1.0f, (float)base_picture_size.y);
    float sx = (float)render_size.x / pw;
    float sy = (float)render_size.y / ph;
    float s = std::min(sx, sy);
    // Compose absolute transform matrix to avoid cumulative state
    tvg::Matrix m;
    m.e11 = s;   m.e12 = 0.0f; m.e13 = (render_size.x - pw * s) * 0.5f; // tx
    m.e21 = 0.0f; m.e22 = s;   m.e23 = (render_size.y - ph * s) * 0.5f; // ty
    m.e31 = 0.0f; m.e32 = 0.0f; m.e33 = 1.0f;
    picture->transform(m);
}

String LottieAnimation::_current_state_segment_marker() const {
    if (active_state.is_empty()) return String();
    if (sm_state_segments_by_machine.has(active_state_machine)) {
        Dictionary segs = sm_state_segments_by_machine[active_state_machine];
        if (segs.has(active_state)) {
            return (String)segs[active_state];
        }
    }
    return active_state;
}

bool LottieAnimation::_find_marker_range(const String &json_path, const String &marker, float &out_begin, float &out_end) const {
    out_begin = 0.0f; out_end = 0.0f;
    if (json_path.is_empty() || marker.is_empty()) return false;
    String abs = ProjectSettings::get_singleton()->globalize_path(json_path);
    Ref<FileAccess> f = FileAccess::open(abs, FileAccess::READ);
    if (f.is_null()) return false;
    PackedByteArray data = f->get_buffer(f->get_length());
    f->close();
    String text = data.get_string_from_utf8();
    Variant v = JSON::parse_string(text);
    if (v.get_type() != Variant::DICTIONARY) return false;
    Dictionary d = v;
    // fr: frame rate; ip/op: in/out points in frames. Markers are in frames as well in many exports.
    double fr = d.has("fr") ? (double)d["fr"] : 60.0;
    if (!d.has("markers")) return false;
    Array markers = d["markers"];
    for (int i = 0; i < markers.size(); i++) {
        if (markers[i].get_type() != Variant::DICTIONARY) continue;
        Dictionary mk = markers[i];
        String name;
        if (mk.has("cm")) name = (String)mk["cm"]; // common in Bodymovin
        else if (mk.has("n")) name = (String)mk["n"]; // alternative key
        if (name != marker) continue;
        double tm = 0.0; double dr = 0.0;
        if (mk.has("tm")) tm = (double)mk["tm"]; // start frame/time
        if (mk.has("dr")) dr = (double)mk["dr"]; // duration in frames
        // Some exports may use seconds, but most use frames. We'll assume frames; if total_frames looks small, this still maps.
        out_begin = (float)tm;
        out_end = (float)(tm + dr);
        if (out_end <= out_begin) out_end = out_begin + 1.0f;
        return true;
    }
    return false;
}

void LottieAnimation::_apply_selected_state_segment() {
    String marker = _current_state_segment_marker();
    if (marker.is_empty()) return;
    // Try to resolve marker to frame range from the loaded JSON and apply range segment
    float sb = 0.0f, se = 0.0f;
    String json_path = animation_key;
    if (_find_marker_range(json_path, marker, sb, se)) {
        if (animation) animation->segment(sb, se);
        _post_segment_to_worker(sb, se);
    }
}

void LottieAnimation::_update_resolution_from_scale() {
    if (!is_inside_tree()) {
        return; // transforms not valid yet
    }
    // Compute effective on-screen scale combining node-to-canvas and viewport final transform (camera/editor zoom)
    Transform2D screen_xform;
    if (get_viewport()) {
        screen_xform = get_viewport()->get_final_transform() * get_global_transform_with_canvas();
    } else {
        // Fallback: CanvasItem's screen transform already represents local->screen
        screen_xform = get_screen_transform();
    }
    // Column vectors magnitude approximate scale along axes
    float sx = screen_xform.columns[0].length();
    float sy = screen_xform.columns[1].length();
    // Use actual scale (can be < 1 when zooming out) so we downscale the render target for crisp results at any zoom.
    float max_scale = std::max(std::abs(sx), std::abs(sy));
    Vector2 desired = Vector2((float)fit_box_size.x, (float)fit_box_size.y) * max_scale;
    Vector2i desired_i((int)std::ceil(desired.x), (int)std::ceil(desired.y));
    // Quantize to 16px grid to reduce realloc churn and improve cache hit rate
    auto q16 = [](int v){ return (v + 15) & ~15; };
    desired_i.x = q16(desired_i.x);
    desired_i.y = q16(desired_i.y);
    // Clamp to configured max
    desired_i.x = std::min(desired_i.x, max_render_size.x);
    desired_i.y = std::min(desired_i.y, max_render_size.y);
    // Optional debug: log when scale changes even if not resizing
    if (std::abs(max_scale - last_effective_scale) > 0.05f) {
    // Removed scale debug print
        last_effective_scale = max_scale;
    }
    last_desired_size = desired_i;
    // If already at desired target, skip.
    if (desired_i == render_size) {
        return;
    }

    // Compare with threshold
    float dx = std::abs((float)desired_i.x - (float)render_size.x) / std::max(1.0f, (float)render_size.x);
    float dy = std::abs((float)desired_i.y - (float)render_size.y) / std::max(1.0f, (float)render_size.y);
    if (dx > resolution_threshold || dy > resolution_threshold) {
        pending_resize = true;
        pending_target_size = desired_i;
    }
}

void LottieAnimation::_on_viewport_size_changed() {
    if (dynamic_resolution) {
        // Only compute desired size and defer actual reallocations/renders to _process
        _update_resolution_from_scale();
        queue_redraw();
    }
    // Force visibility re-evaluation on next frame to avoid stale culling after resize.
    last_visible_on_screen = false;
}

void LottieAnimation::set_use_animation_size(bool p_enable) {
    if (use_animation_size == p_enable) return;
    use_animation_size = p_enable;
    if (canvas && picture) {
        _apply_sizing_policy();
        _apply_picture_transform_to_fit();
    }
}
bool LottieAnimation::is_using_animation_size() const { return use_animation_size; }

void LottieAnimation::set_fit_into_box(bool p_enable) {
    if (fit_into_box == p_enable) return;
    fit_into_box = p_enable;
    if (canvas && picture) {
        _apply_sizing_policy();
        _apply_picture_transform_to_fit();
    }
}
bool LottieAnimation::is_fit_into_box() const { return fit_into_box; }

void LottieAnimation::set_fit_box_size(const Vector2i &p_size) {
    if (fit_box_size == p_size) return;
    fit_box_size = p_size;
    if (canvas && picture && fit_into_box) {
        _apply_sizing_policy();
        _apply_picture_transform_to_fit();
    }
}
Vector2i LottieAnimation::get_fit_box_size() const { return fit_box_size; }

void LottieAnimation::set_dynamic_resolution(bool p_enable) { dynamic_resolution = p_enable; }
bool LottieAnimation::is_dynamic_resolution() const { return dynamic_resolution; }

void LottieAnimation::set_resolution_threshold(float p_t) { resolution_threshold = std::clamp(p_t, 0.01f, 1.0f); }
float LottieAnimation::get_resolution_threshold() const { return resolution_threshold; }

void LottieAnimation::set_max_render_size(const Vector2i &p_size) { max_render_size = p_size; }
Vector2i LottieAnimation::get_max_render_size() const { return max_render_size; }

void LottieAnimation::set_frame_cache_enabled(bool p_enable) { frame_cache_enabled = p_enable; }
bool LottieAnimation::is_frame_cache_enabled() const { return frame_cache_enabled; }
void LottieAnimation::set_frame_cache_budget_mb(int p_mb) { frame_cache_budget_mb = std::max(16, p_mb); }
int LottieAnimation::get_frame_cache_budget_mb() const { return frame_cache_budget_mb; }
void LottieAnimation::set_frame_cache_step(int p_step) { frame_cache_step = std::max(1, p_step); }
int LottieAnimation::get_frame_cache_step() const { return frame_cache_step; }
void LottieAnimation::set_engine_option(int p_opt) { engine_option = (p_opt == 1 ? 1 : 0); }
int LottieAnimation::get_engine_option() const { return engine_option; }
void LottieAnimation::render_static() {
    if (!animation) return;
    if (render_thread_enabled) {
        // Force a one-shot render upload by calling main-thread render (safe, uses current frame)
        _render_frame();
    } else {
        _render_frame();
    }
    queue_redraw();
}

void LottieAnimation::set_live_cache_threshold(int p_threshold) {
    live_cache_threshold = std::max(1, p_threshold);
    _recompute_live_cache_state();
}
int LottieAnimation::get_live_cache_threshold() const { return live_cache_threshold; }
void LottieAnimation::set_live_cache_force(bool p_force) { live_cache_force = p_force; _recompute_live_cache_state(); }
bool LottieAnimation::get_live_cache_force() const { return live_cache_force; }
void LottieAnimation::set_culling_mode(int p_mode) { /* culling disabled */ }
int LottieAnimation::get_culling_mode() const { return 2; }
void LottieAnimation::set_culling_margin_px(float p_margin) { }
float LottieAnimation::get_culling_margin_px() const { return 0.0f; }

void LottieAnimation::play() {
    if (!animation) {
        if (!animation_path.is_empty()) {
            _load_animation(animation_path);
        } else {
            return;
        }
    }
    playing = true;
}

void LottieAnimation::stop() {
    playing = false;
    current_frame = 0.0f;
}

void LottieAnimation::pause() {
    playing = false;
}

void LottieAnimation::seek(float frame) {
    set_frame(frame);
}

void LottieAnimation::set_frame(float frame) {
    if (total_frames > 0) {
        current_frame = CLAMP(frame, 0.0f, total_frames - 1);
        _render_frame();
        queue_redraw();
    }
}

float LottieAnimation::get_frame() const {
    return current_frame;
}

void LottieAnimation::set_animation_path(const String& path) {
    if (animation_path != path) {
        animation_path = path;
        if (is_inside_tree()) {
            if (!path.is_empty()) {
                _load_animation(path);
                // If not a .lottie, clear manifest/state UI
                if (!animation_path.to_lower().ends_with(".lottie")) {
                    sm_animation_ids.clear();
                    sm_machine_names.clear();
                    sm_states_by_machine.clear();
                    sm_anim_inner_paths.clear();
                    sm_state_segments_by_machine.clear();
                    active_animation_id = String();
                    active_state_machine = String();
                    active_state = String();
                    notify_property_list_changed();
                }
            } else {
                // Clear current animation and visuals when path is removed
                playing = false;
                if (canvas) {
                    canvas->remove();
                }
                picture = nullptr;
                animation = nullptr;
                // Clear any pending/last worker frame so it won't upload after clearing
                {
                    std::lock_guard<std::mutex> lk(frame_mutex);
                    latest_frame.ready = false;
                    latest_frame.rgba.clear();
                    last_consumed_id = next_frame_id; // advance cursor
                }
                if (buffer) memset(buffer, 0, (size_t)render_size.x * (size_t)render_size.y * sizeof(uint32_t));
                if (image.is_valid()) {
                    pixel_bytes.fill(0);
                    image->set_data(render_size.x, render_size.y, false, Image::FORMAT_RGBA8, pixel_bytes);
                }
                // Drop current texture reference so _draw no longer draws anything
                texture.unref();
                if (render_thread_enabled) {
                    _post_load_to_worker(String()); // instruct worker to clear
                }
                queue_redraw();
            }
        }
    }
}

String LottieAnimation::get_animation_path() const {
    return animation_path;
}

void LottieAnimation::set_selected_dotlottie_animation(const String &id) {
    if (selected_dotlottie_animation == id) return;
    selected_dotlottie_animation = id;
    // If current source is a .lottie, reload with the new selection
    if (!animation_path.is_empty() && animation_path.to_lower().ends_with(".lottie") && is_inside_tree()) {
        _load_animation(animation_path);
        if (playing) play();
    }
}

String LottieAnimation::get_selected_dotlottie_animation() const {
    return selected_dotlottie_animation;
}

void LottieAnimation::set_playing(bool p_playing) {
    if (p_playing) {
        play();
    } else {
        pause();
    }
}

bool LottieAnimation::is_playing() const {
    return playing;
}

void LottieAnimation::set_looping(bool p_looping) {
    looping = p_looping;
}

bool LottieAnimation::is_looping() const {
    return looping;
}

void LottieAnimation::set_autoplay(bool p_autoplay) {
    autoplay = p_autoplay;
}

bool LottieAnimation::is_autoplay() const {
    return autoplay;
}

void LottieAnimation::set_speed(float p_speed) {
    speed = MAX(0.0f, p_speed);
}

float LottieAnimation::get_speed() const {
    return speed;
}

void LottieAnimation::set_render_size(const Vector2i& size) {
    // Interpret render_size as desired fit box size for simplicity; always fit into box
    if (size.x <= 0 || size.y <= 0) return;
    if (fit_box_size == size) return;
    fit_box_size = size;
    fit_into_box = true;
    if (canvas && picture) {
        _apply_sizing_policy();
        _apply_picture_transform_to_fit();
    }
}

Vector2i LottieAnimation::get_render_size() const {
    return render_size;
}

float LottieAnimation::get_duration() const {
    return duration;
}

float LottieAnimation::get_total_frames() const {
    return total_frames;
}

void LottieAnimation::_start_worker_if_needed() {
    if (!render_thread_enabled || render_thread.joinable()) return;
    worker_stop = false;
    load_pending = false;
    render_pending = false;
    render_thread = std::thread([this]() { _worker_loop(); });
}

void LottieAnimation::_stop_worker() {
    if (!render_thread.joinable()) return;
    {
        std::lock_guard<std::mutex> lk(job_mutex);
        worker_stop = true;
    }
    job_cv.notify_all();
    render_thread.join();
    _worker_free_resources();
}

bool LottieAnimation::_is_visible_on_screen() const {
    if (!is_inside_tree() || !get_viewport()) return true;

    if (culling_mode == 2) {
        return true; // Always visible
    }
    // Build local AABB centered at origin in local space
    const Vector2 half = Vector2((float)fit_box_size.x, (float)fit_box_size.y) * 0.5f;
    const Rect2 local_rect(-half, Vector2((float)fit_box_size.x, (float)fit_box_size.y));
    const Transform2D to_canvas = get_global_transform_with_canvas();

    // Compute bounding in world/canvas space
    Vector2 c[4];
    c[0] = to_canvas.xform(local_rect.position);
    c[1] = to_canvas.xform(local_rect.position + Vector2(local_rect.size.x, 0.0f));
    c[2] = to_canvas.xform(local_rect.position + Vector2(0.0f, local_rect.size.y));
    c[3] = to_canvas.xform(local_rect.position + local_rect.size);
    float mincx = c[0].x, maxcx = c[0].x, mincy = c[0].y, maxcy = c[0].y;
    for (int i = 1; i < 4; ++i) { mincx = std::min(mincx, c[i].x); maxcx = std::max(maxcx, c[i].x); mincy = std::min(mincy, c[i].y); maxcy = std::max(maxcy, c[i].y); }
    Rect2 world_bb(Vector2(mincx, mincy), Vector2(maxcx - mincx, maxcy - mincy));

    // Determine visible rect based on culling mode
    Rect2 visible_world;
    if (culling_mode == 1) {
        // CameraWorld: derive world rect by unprojecting viewport corners through canvas_transform^-1.
        // This correctly tracks window size changes and camera zoom/offset.
        const Rect2 vp = get_viewport()->get_visible_rect();
        const Transform2D inv_canvas = get_viewport()->get_canvas_transform().affine_inverse();
        Vector2 wc[4];
        wc[0] = inv_canvas.xform(vp.position);
        wc[1] = inv_canvas.xform(vp.position + Vector2(vp.size.x, 0.0f));
        wc[2] = inv_canvas.xform(vp.position + Vector2(0.0f, vp.size.y));
        wc[3] = inv_canvas.xform(vp.position + vp.size);
        float minx = wc[0].x, maxx = wc[0].x, miny = wc[0].y, maxy = wc[0].y;
        for (int i=1;i<4;i++){ minx = MIN(minx, wc[i].x); maxx = MAX(maxx, wc[i].x); miny = MIN(miny, wc[i].y); maxy = MAX(maxy, wc[i].y);} 
        visible_world = Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny));
    } else {
        // ViewportRect: transform world_bb to screen and intersect with viewport rect (inflated by margin)
        const Transform2D to_screen = get_viewport()->get_final_transform();
        Vector2 p[4];
        p[0] = to_screen.xform(c[0]);
        p[1] = to_screen.xform(c[1]);
        p[2] = to_screen.xform(c[2]);
        p[3] = to_screen.xform(c[3]);
        float minx = p[0].x, maxx = p[0].x, miny = p[0].y, maxy = p[0].y;
        for (int i = 1; i < 4; i++) { minx = std::min(minx, p[i].x); maxx = std::max(maxx, p[i].x); miny = std::min(miny, p[i].y); maxy = std::max(maxy, p[i].y); }
        Rect2 scr_bb(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny));
        // Inflate margin in screen pixels then convert back to world approx by inverting to_screen at the center scale.
        const float m = std::max(0.0f, culling_margin_px);
        scr_bb.position -= Vector2(m, m);
        scr_bb.size += Vector2(2*m, 2*m);
        // Convert viewport rect to screen space directly
        Rect2 vis = get_viewport()->get_visible_rect();
        return scr_bb.intersects(vis);
    }

    // Inflate margin in world units: approximate using camera zoom.x (uniform zoom expected)
    const float m = std::max(0.0f, culling_margin_px);
    if (culling_mode == 1) {
        visible_world = visible_world.grow(m);
        return visible_world.intersects(world_bb);
    }
    // Fallback conservative
    return true;
}

void LottieAnimation::_recompute_live_cache_state() {
    if (!frame_cache_enabled) { live_cache_active = false; return; }
    if (live_cache_force) { live_cache_active = true; return; }
    int count = _registry_get(animation_key);
    live_cache_active = (count >= live_cache_threshold);
    // When live cache is active, allow cache even during playback by disabling the paused-only restriction
    if (live_cache_active) cache_only_when_paused = false;
}

void LottieAnimation::_post_load_to_worker(const String& path) {
    if (!render_thread_enabled) return;
    std::lock_guard<std::mutex> lk(job_mutex);
    if (path.is_empty()) {
        pending_path8.clear();
    } else {
        String absolute_path = ProjectSettings::get_singleton()->globalize_path(path);
        pending_path8 = absolute_path.utf8().get_data();
    }
    load_pending = true;
    job_cv.notify_one();
}

void LottieAnimation::_post_render_to_worker(const Vector2i &size, float frame) {
    if (!render_thread_enabled) return;
    std::lock_guard<std::mutex> lk(job_mutex);
    pending_r_size = size;
    pending_r_frame = frame;
    render_pending = true; // last render wins
    job_cv.notify_one();
}

void LottieAnimation::_post_segment_to_worker(float begin, float end) {
    if (!render_thread_enabled) return;
    std::lock_guard<std::mutex> lk(job_mutex);
    pending_segment_begin = begin;
    pending_segment_end = end;
    segment_pending = true;
    job_cv.notify_one();
}

void LottieAnimation::_worker_free_resources() {
    if (w_picture && w_canvas) {
        w_canvas->remove();
    }
    if (w_canvas) { delete w_canvas; w_canvas = nullptr; }
    if (w_buffer) { delete[] w_buffer; w_buffer = nullptr; }
    w_animation = nullptr;
    w_picture = nullptr;
    w_render_size = Vector2i(0,0);
}

void LottieAnimation::_worker_apply_target_if_needed(const Vector2i &size) {
    if (w_render_size == size && w_buffer) return;
    if (w_buffer) { delete[] w_buffer; w_buffer = nullptr; }
    w_render_size = size;
    w_buffer = new uint32_t[(size_t)size.x * (size_t)size.y];
    memset(w_buffer, 0, (size_t)size.x * (size_t)size.y * sizeof(uint32_t));
    w_canvas->target(w_buffer, size.x, size.x, size.y, tvg::ColorSpace::ARGB8888S);
    // Fit transform will be recomputed below
}

void LottieAnimation::_worker_apply_fit_transform() {
    if (!w_picture) return;
    float pw = std::max(1.0f, (float)w_base_picture_size.x);
    float ph = std::max(1.0f, (float)w_base_picture_size.y);
    float sx = (float)w_render_size.x / pw;
    float sy = (float)w_render_size.y / ph;
    float s = std::min(sx, sy);
    tvg::Matrix m;
    m.e11 = s;   m.e12 = 0.0f; m.e13 = (w_render_size.x - pw * s) * 0.5f;
    m.e21 = 0.0f; m.e22 = s;   m.e23 = (w_render_size.y - ph * s) * 0.5f;
    m.e31 = 0.0f; m.e32 = 0.0f; m.e33 = 1.0f;
    w_picture->transform(m);
}

void LottieAnimation::_worker_loop() {
    tvg::EngineOption worker_opt = tvg::EngineOption::Default;
    if (engine_option == 1) worker_opt = tvg::EngineOption::SmartRender;
    
    w_canvas = tvg::SwCanvas::gen(worker_opt);
    if (!w_canvas) {
        UtilityFunctions::printerr("Worker: Failed to create ThorVG canvas");
        return;
    }
    
    while (true) {
        {
            std::unique_lock<std::mutex> lk(job_mutex);
            job_cv.wait(lk, [this]{ return worker_stop || load_pending || render_pending; });
            if (worker_stop) break;
        }
        // 1) Handle LOAD first if pending
        bool do_load = false;
        std::string path8_local;
    bool do_segment = false;
    float seg_begin_local = 0.0f;
    float seg_end_local = 0.0f;
        {
            std::lock_guard<std::mutex> lk(job_mutex);
            if (load_pending) {
                path8_local = pending_path8;
                load_pending = false;
                do_load = true;
            }
            if (segment_pending) {
                seg_begin_local = pending_segment_begin;
                seg_end_local = pending_segment_end;
                segment_pending = false;
                do_segment = true;
            }
        }
        if (do_load) {
            // (Re)load animation in worker thread
            // Clean previous
            if (w_picture) w_canvas->remove();
            if (path8_local.empty()) {
                // Clear resources request
                w_animation = nullptr;
                w_picture = nullptr;
            } else {
                w_animation = tvg::Animation::gen();
                w_picture = w_animation->picture();
                if (w_picture && w_picture->load(path8_local.c_str()) == tvg::Result::Success) {
                    float pw = 0.0f, ph = 0.0f;
                    w_picture->size(&pw, &ph);
                    if (pw <= 0 || ph <= 0) { pw = (float)render_size.x; ph = (float)render_size.y; }
                    w_base_picture_size = Vector2i((int)std::ceil(pw), (int)std::ceil(ph));
                    if (w_canvas->push(w_picture) == tvg::Result::Success) {
                        // ok
                    } else {
                        w_animation = nullptr;
                        w_picture = nullptr;
                    }
                } else {
                    w_animation = nullptr;
                    w_picture = nullptr;
                }
            }
        }
        if (do_segment && w_animation) {
            w_animation->segment(seg_begin_local, seg_end_local);
        }
        // 2) Handle RENDER (latest)
        Vector2i rsize_local;
        float rframe_local = 0.0f;
        {
            std::lock_guard<std::mutex> lk(job_mutex);
            if (render_pending) {
                rsize_local = pending_r_size;
                rframe_local = pending_r_frame;
                render_pending = false;
            }
        }
        if (rsize_local.x > 0 && rsize_local.y > 0) {
            if (!w_canvas || !w_animation || !w_picture) continue;
            _worker_apply_target_if_needed(rsize_local);
            _worker_apply_fit_transform();
            w_animation->frame(rframe_local);
            w_canvas->update();
            w_canvas->draw(false);
            w_canvas->sync();
            std::vector<uint8_t> tmp;
            tmp.resize((size_t)w_render_size.x * (size_t)w_render_size.y * 4);
            // Optimized ARGB->RGBA conversion for worker-produced buffer.
            _convert_argb_to_rgba_optimized(w_buffer, tmp.data(), (size_t)w_render_size.x * (size_t)w_render_size.y);
            if (unpremultiply_alpha) {
                _unpremultiply_alpha_rgba(tmp.data(), w_render_size.x, w_render_size.y);
            }
            if (fix_alpha_border) {
                _fix_alpha_border_rgba(tmp.data(), w_render_size.x, w_render_size.y);
            }
            {
                std::lock_guard<std::mutex> lk(frame_mutex);
                latest_frame.rgba.swap(tmp);
                latest_frame.w = w_render_size.x;
                latest_frame.h = w_render_size.y;
                latest_frame.id = next_frame_id++;
                latest_frame.ready = true;
            }
        }
    }
}

void LottieAnimation::set_offset(const Vector2 &p_offset) {
    offset = p_offset;
    queue_redraw();
}

Vector2 LottieAnimation::get_offset() const {
    return offset;
}
