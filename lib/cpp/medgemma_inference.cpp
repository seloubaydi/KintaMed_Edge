/**
 * medgemma_inference.cpp - Library Implementation for Flutter Bridge
 */

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <memory>
#include <mutex>
#include <numeric>
#include <random>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include <onnxruntime_cxx_api.h>

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image.h"
#include "stb_image_resize2.h"

#include <ort_genai.h>

#ifdef ANDROID
#include <android/log.h>
#include <sched.h>        // sched_setscheduler
#include <sys/resource.h> // setpriority
#endif

// ── File + platform logging
// ─────────────────────────────────────────────────── Logs go to BOTH the
// platform sink (logcat / stderr) AND a file on disk so you can read them from
// Flutter without adb. Call set_log_path() from Dart right after loading the
// library.

static FILE *g_log_file = nullptr;
static std::mutex g_log_mutex;

static void write_log(const char *level, const char *fmt, va_list args) {
  std::lock_guard<std::mutex> lock(g_log_mutex);

  char buf[1024];
  vsnprintf(buf, sizeof(buf), fmt, args);

  // Write to file if path was set
  if (g_log_file) {
    fprintf(g_log_file, "[%s] %s\n", level, buf);
    fflush(g_log_file);
  }

#ifdef ANDROID
  int prio = (level[0] == 'E')   ? ANDROID_LOG_ERROR
             : (level[0] == 'D') ? ANDROID_LOG_DEBUG
                                 : ANDROID_LOG_INFO;
  __android_log_print(prio, "MedGemma", "%s", buf);
#else
  fprintf(stderr, "[%s] %s\n", level, buf);
#endif
}

static void log_i(const char *fmt, ...) {
  va_list a;
  va_start(a, fmt);
  write_log("INFO", fmt, a);
  va_end(a);
}
static void log_e(const char *fmt, ...) {
  va_list a;
  va_start(a, fmt);
  write_log("ERROR", fmt, a);
  va_end(a);
}
static void log_d(const char *fmt, ...) {
  va_list a;
  va_start(a, fmt);
  write_log("DEBUG", fmt, a);
  va_end(a);
}

#define LOGI(...) log_i(__VA_ARGS__)
#define LOGE(...) log_e(__VA_ARGS__)
#define LOGD(...) log_d(__VA_ARGS__)
// ─────────────────────────────────────────────────────────────────────────────

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef void (*TokenCallback)(const char *);

const std::vector<int64_t> EOS_IDS = {1, 106};
// IMG_TOKEN_ID removed — now discovered dynamically per model (see
// MedGemmaState::image_token_id)
const int num_patches = 256;
const int embed_dim = 2560;

Ort::Value create_tensor(const std::vector<int64_t> &data,
                         const std::vector<int64_t> &shape,
                         const Ort::MemoryInfo &mem) {
  return Ort::Value::CreateTensor<int64_t>(
      mem, const_cast<int64_t *>(data.data()), data.size(), shape.data(),
      shape.size());
}

// ── Language filter ──────────────────────────────────────────────────────────
// Returns true if the UTF-8 string contains only characters acceptable in
// English medical text: ASCII printable + common Latin extended (accented
// letters like é, ü, ñ that appear in medical terms).
// Blocks: CJK, Arabic, Cyrillic, Hebrew, Thai, Devanagari, Korean, etc.
static bool is_english_token(const char *utf8) {
  if (!utf8)
    return true;
  const unsigned char *p = reinterpret_cast<const unsigned char *>(utf8);
  while (*p) {
    if (*p < 0x80) {
      // Pure ASCII — always allowed
      p++;
    } else if ((*p & 0xE0) == 0xC0) {
      // 2-byte UTF-8 sequence: U+0080..U+07FF
      // Allow Latin-1 Supplement (U+0080–U+00FF) and
      // Latin Extended-A/B (U+0100–U+024F) — covers medical/accented terms.
      // Block anything above U+024F in this range.
      uint32_t cp = ((*p & 0x1F) << 6) | (*(p + 1) & 0x3F);
      if (cp > 0x024F)
        return false; // Cyrillic starts at U+0400
      p += 2;
    } else if ((*p & 0xF0) == 0xE0) {
      // 3-byte sequence: U+0800..U+FFFF — covers CJK, Arabic, Hebrew, Thai etc.
      // Block ALL 3-byte sequences (none are needed for English medical text).
      return false;
    } else if ((*p & 0xF8) == 0xF0) {
      // 4-byte sequence: U+10000+ — emoji, rare scripts — block all.
      return false;
    } else {
      p++; // malformed — skip
    }
  }
  return true;
}

// Cache of foreign token IDs — built once per tokenizer instance.
// Maps tokenizer pointer → set of blocked token IDs.
static std::mutex g_lang_cache_mutex;
static std::unordered_map<void *, std::vector<bool>> g_foreign_token_cache;

// Call once after tokenizer is loaded to pre-compute the block set.
// Decodes every token ID 0..vocab_size-1 and marks non-English ones.
static const std::vector<bool> &get_foreign_mask(OgaTokenizer *tok,
                                                 size_t vocab_size) {
  std::lock_guard<std::mutex> lock(g_lang_cache_mutex);
  auto it = g_foreign_token_cache.find(tok);
  if (it != g_foreign_token_cache.end())
    return it->second;

  std::vector<bool> &mask = g_foreign_token_cache[tok];
  mask.resize(vocab_size, false); // false = allowed

  size_t blocked = 0;
  for (size_t i = 0; i < vocab_size; ++i) {
    int32_t tid = static_cast<int32_t>(i);
    const char *decoded = nullptr;
    if (OgaTokenizerDecode(tok, &tid, 1, &decoded) == 0 && decoded) {
      if (!is_english_token(decoded)) {
        mask[i] = true; // mark as foreign → will be suppressed
        blocked++;
      }
    }
  }
  LOGI("Language filter: blocked %zu / %zu tokens as non-English", blocked,
       vocab_size);
  return mask;
}

int64_t sample_top_p(const std::vector<float> &logits, float p = 0.75f,
                     float temp = 0.29f,
                     const std::vector<int64_t> *generated = nullptr,
                     float rep_penalty = 1.30f,
                     OgaTokenizer *tokenizer = nullptr) {
  std::vector<float> penalized = logits;

  // ── Language filter: suppress non-English tokens ──────────────────
  if (tokenizer) {
    const std::vector<bool> &foreign =
        get_foreign_mask(tokenizer, logits.size());
    for (size_t i = 0; i < penalized.size() && i < foreign.size(); ++i) {
      if (foreign[i])
        penalized[i] = -1e9f; // make effectively impossible
    }
  }

  // ── Repetition penalty ────────────────────────────────────────────
  if (generated && rep_penalty > 1.0f) {
    for (int64_t tok : *generated) {
      if (tok >= 0 && tok < (int64_t)penalized.size()) {
        if (penalized[tok] > 0.0f)
          penalized[tok] /= rep_penalty;
        else
          penalized[tok] *= rep_penalty;
      }
    }
  }

  // ── Greedy if temp near zero ──────────────────────────────────────
  if (temp < 0.01f)
    return std::max_element(penalized.begin(), penalized.end()) -
           penalized.begin();

  // ── Top-p (nucleus) sampling ──────────────────────────────────────
  std::vector<std::pair<float, int>> probs;
  probs.reserve(penalized.size());
  float sum_exp = 0.0f;
  for (size_t i = 0; i < penalized.size(); ++i) {
    float e = std::exp(penalized[i] / temp);
    probs.push_back({e, (int)i});
    sum_exp += e;
  }
  for (auto &pr : probs)
    pr.first /= sum_exp;
  std::sort(probs.rbegin(), probs.rend());

  float cumulative = 0.0f;
  for (auto &pr : probs) {
    cumulative += pr.first;
    if (cumulative >= p)
      return pr.second;
  }
  return probs[0].second;
}

struct OgaModelDeleter {
  void operator()(OgaModel *p) {
    if (p)
      OgaDestroyModel(p);
  }
};
struct OgaTokenizerDeleter {
  void operator()(OgaTokenizer *p) {
    if (p)
      OgaDestroyTokenizer(p);
  }
};

class MedGemmaState {
public:
  std::string model_dir;
  std::unique_ptr<Ort::Env> env;
  std::unique_ptr<Ort::SessionOptions> session_options;
  std::unique_ptr<Ort::SessionOptions>
      vision_session_options; // lower RAM for vision encoder
  std::unique_ptr<Ort::Session> v_sess, p_sess, e_sess, m_sess;
  std::unique_ptr<OgaTokenizer, OgaTokenizerDeleter> tokenizer;
  Ort::MemoryInfo memory_info;
  int64_t image_token_id =
      -1; // discovered at load time by tokenizing "<image>"

  MedGemmaState(const char *path)
      : model_dir(path), memory_info(Ort::MemoryInfo::CreateCpu(
                             OrtArenaAllocator, OrtMemTypeDefault)) {
    LOGI("Loading MedGemma from: %s", path);
    env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "MedGemma");
    session_options = std::make_unique<Ort::SessionOptions>();

    // ── LLM session: prioritize low peak RAM over speed ──────────────
    // int4 Gemma-2 dequantizes weights to fp32 during compute. With parallel
    // threads, multiple layers dequantize simultaneously = ~480 MB spike.
    // Single-threaded sequential execution cuts peak by ~60-70%.
    session_options->SetIntraOpNumThreads(1);
    session_options->SetInterOpNumThreads(1);
    session_options->SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
    session_options->SetGraphOptimizationLevel(
        GraphOptimizationLevel::ORT_ENABLE_BASIC);
    session_options->AddConfigEntry("session.use_mmap", "1");
    session_options->DisableMemPattern();
    session_options->DisableCpuMemArena(); // free buffers immediately, don't
                                           // cache in arena

    // ── Vision-specific session options (lower RAM footprint) ───────────
    vision_session_options = std::make_unique<Ort::SessionOptions>();
    vision_session_options->SetIntraOpNumThreads(
        2); // fewer threads = less parallel RAM
    vision_session_options->SetGraphOptimizationLevel(
        GraphOptimizationLevel::ORT_ENABLE_BASIC);
    vision_session_options->AddConfigEntry("session.use_mmap", "1");
    vision_session_options
        ->DisableMemPattern(); // don't pre-allocate memory pattern
    vision_session_options
        ->DisableCpuMemArena(); // release memory immediately after use
    vision_session_options->SetExecutionMode(
        ExecutionMode::ORT_SEQUENTIAL); // sequential = less peak RAM

    OgaConfig *config = nullptr;
    if (OgaCreateConfig(path, &config) == 0) {
      OgaModel *temp_model = nullptr;
      if (OgaCreateModelFromConfig(config, &temp_model) == 0) {
        OgaTokenizer *tok = nullptr;
        if (OgaCreateTokenizer(temp_model, &tok) == 0) {
          tokenizer.reset(tok);
          LOGI("Tokenizer loaded OK");

          // ── Discover the image token ID ──────────────────────────────
          // Do NOT hardcode — the actual ID depends on the tokenizer vocab.
          // We tokenize the literal string "<image>" and take the first token
          // that isn't BOS (token 2) as the image placeholder token.
          const char *img_probe = "<image>";
          OgaSequences *img_seq = nullptr;
          OgaCreateSequences(&img_seq);
          if (OgaTokenizerEncode(tok, img_probe, img_seq) == 0) {
            size_t img_count = OgaSequencesGetSequenceCount(img_seq, 0);
            const int32_t *img_data = OgaSequencesGetSequenceData(img_seq, 0);
            LOGI("<image> tokenizes to %zu token(s):", img_count);
            for (size_t ti = 0; ti < img_count; ++ti)
              LOGI("  [%zu] = %d", ti, img_data[ti]);
            // Take first non-BOS token as the image placeholder
            for (size_t ti = 0; ti < img_count; ++ti) {
              if (img_data[ti] != 2) { // 2 = BOS in Gemma vocab
                image_token_id = static_cast<int64_t>(img_data[ti]);
                break;
              }
            }
          }
          OgaDestroySequences(img_seq);
          if (image_token_id < 0) {
            // Fallback to known MedGemma value if probe failed
            image_token_id = 255999;
            LOGE("<image> token discovery failed — using fallback id=255999");
          }
          LOGI("Image token ID: %lld", image_token_id);
        } else {
          LOGE("OgaCreateTokenizer FAILED");
        }
        OgaDestroyModel(temp_model);
      } else {
        LOGE("OgaCreateModelFromConfig FAILED");
      }
      OgaDestroyConfig(config);
    } else {
      LOGE("OgaCreateConfig FAILED: %s", path);
    }

    auto load = [&](const std::string &p, Ort::SessionOptions &opts) {
      LOGI("Loading session: %s", p.c_str());
      return std::make_unique<Ort::Session>(*env, p.c_str(), opts);
    };
    // Vision encoder + projection use memory-conservative options
    v_sess = load(model_dir + "/vision_encoder.ort", *vision_session_options);
    p_sess =
        load(model_dir + "/vision_projection.ort", *vision_session_options);
    // Text sessions use standard options
    e_sess = load(model_dir + "/embeddings.ort", *session_options);
    m_sess = load(model_dir + "/model.onnx", *session_options);
    LOGI("All sessions loaded OK");
  }
};

// ── Image processing
// ────────────────────────────────────────────────────────── Memory layout
// during this call (all freed before returning):
//   raw JPEG buffer  : owned by caller, not freed here
//   stb decoded img  : ~w*h*3 bytes  → freed with stbi_image_free()
//   resized buffer   : 896*896*3 = 2.35 MB (vector, freed at end of scope)
//   pixel_values     : 896*896*3*4 = 9.2 MB float (returned, freed by caller)
// Peak usage while both resized + pixel_values exist: ~11.6 MB
// After return only pixel_values remains until vision encoder runs.
std::vector<float> process_image_bytes(const uint8_t *data, size_t len,
                                       std::string &error_out) {
  error_out.clear();
  LOGD("process_image_bytes: %zu bytes input", len);

  if (!data || len == 0) {
    error_out = "[IMG_ERR] Input is null or empty";
    LOGE("%s", error_out.c_str());
    return {};
  }

  // ── Decode ────────────────────────────────────────────────────────
  int w = 0, h = 0, c = 0;
  uint8_t *img = stbi_load_from_memory(reinterpret_cast<const stbi_uc *>(data),
                                       static_cast<int>(len), &w, &h, &c, 3);

  if (!img) {
    const char *reason = stbi_failure_reason();
    error_out = std::string("[IMG_ERR] Decode failed: ") +
                (reason ? reason : "unknown");
    LOGE("%s", error_out.c_str());
    return {};
  }
  LOGD("Decoded OK: %dx%d ch=%d (%.1f KB)", w, h, c, (w * h * 3) / 1024.0f);

  // ── Resize to 896x896 ─────────────────────────────────────────────
  const int TARGET = 896;
  std::vector<float> pixel_values; // declared here so we can return it

  {
    // Inner scope: resized buffer lives here and is freed when scope exits,
    // BEFORE pixel_values is fully populated — keeps peak RAM lower.
    std::vector<uint8_t> resized(static_cast<size_t>(TARGET * TARGET * 3));

    // stbir_resize_uint8_linear returns uint8_t* NOT int — must store as
    // pointer
    uint8_t *ok = stbir_resize_uint8_linear(img, w, h, 0, resized.data(),
                                            TARGET, TARGET, 0, STBIR_RGB);

    stbi_image_free(img); // free decoded image immediately after resize
    img = nullptr;

    if (ok == nullptr) {
      error_out = "[IMG_ERR] Resize failed (stbir returned null)";
      LOGE("%s", error_out.c_str());
      return {};
    }
    LOGD("Resized to %dx%d (%.1f KB)", TARGET, TARGET,
         (TARGET * TARGET * 3) / 1024.0f);

    // ── HWC uint8 → CHW float32, SigLIP normalization ────────────────
    // SigLIP (MedGemma's vision encoder) expects (value/255 - mean) / std
    // with mean=[0.5,0.5,0.5] and std=[0.5,0.5,0.5] per channel.
    // This is mathematically identical to (value/127.5 - 1.0) but written
    // explicitly so the values are easy to update if the model changes.
    // stb_image already outputs RGB order — do NOT swap to BGR.
    constexpr float MEAN = 0.5f;
    constexpr float STD = 0.5f;
    pixel_values.resize(static_cast<size_t>(3 * TARGET * TARGET));
    const int area = TARGET * TARGET;
    for (int i = 0; i < area; ++i)
      for (int ch = 0; ch < 3; ++ch)
        pixel_values[ch * area + i] =
            ((resized[i * 3 + ch] / 255.0f) - MEAN) / STD;

    // resized vector is freed here when scope exits (~2.35 MB freed)
  }

  LOGD("process_image_bytes OK: %zu floats (%.1f MB)", pixel_values.size(),
       pixel_values.size() * 4 / (1024.0f * 1024.0f));
  return pixel_values;
}
// ─────────────────────────────────────────────────────────────────────────────

extern "C" {

// ── Call this from Dart immediately after loading the library
// ───────────────── path should be something like:
// getApplicationDocumentsDirectory() + "/medgemma_log.txt"
EXPORT void set_log_path(const char *path) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  if (g_log_file) {
    fclose(g_log_file);
    g_log_file = nullptr;
  }
  if (path && path[0] != '\0') {
    g_log_file = fopen(path, "a"); // append so logs survive across calls
    if (g_log_file) {
      fprintf(g_log_file, "\n=== MedGemma session started ===\n");
      fflush(g_log_file);
    }
  }
}

EXPORT void *load_medgemma_4bit(const char *model_dir) {
  LOGI("load_medgemma_4bit: %s", model_dir);
  try {
    auto *s = new MedGemmaState(model_dir);
    LOGI("Engine ready, handle=%p", (void *)s);
    return s;
  } catch (const std::exception &e) {
    LOGE("load_medgemma_4bit EXCEPTION: %s", e.what());
    return nullptr;
  }
}

EXPORT void unload_medgemma(void *handle) {
  LOGI("unload_medgemma");
  if (handle)
    delete static_cast<MedGemmaState *>(handle);
}

EXPORT int medgemma_tokenize(void *handle, const char *text,
                             int64_t *out_tokens, int max_tokens) {
  auto state = static_cast<MedGemmaState *>(handle);
  if (!state || !state->tokenizer)
    return 0;

  OgaSequences *seq = nullptr;
  OgaCreateSequences(&seq);
  OgaTokenizerEncode(state->tokenizer.get(), text, seq);
  size_t count = OgaSequencesGetSequenceCount(seq, 0);
  const int32_t *data = OgaSequencesGetSequenceData(seq, 0);
  int actual = std::min((int)count, max_tokens);
  for (int i = 0; i < actual; ++i)
    out_tokens[i] = static_cast<int64_t>(data[i]);
  OgaDestroySequences(seq);
  return actual;
}

EXPORT void run_medgemma_inference(void *handle, uint8_t *image_bytes,
                                   int image_len, const char *prompt,
                                   int max_tokens, TokenCallback callback) {
  if (max_tokens <= 0)
    max_tokens = 512;
  LOGI("run_medgemma_inference: image_len=%d max_tokens=%d", image_len,
       max_tokens);

#ifdef ANDROID
  // Lower this thread's priority so the UI/main thread stays responsive.
  // ANDROID_PRIORITY_BACKGROUND = 10, keeps UI at normal priority (0).
  // Without this, heavy CPU usage here starves the main thread → ANR dialog.
  struct sched_param sp = {0};
  sched_setscheduler(0, SCHED_BATCH, &sp); // batch scheduling = lower priority
  setpriority(PRIO_PROCESS, 0, 10);        // nice value 10 = background
#endif
  auto state = static_cast<MedGemmaState *>(handle);
  if (!state) {
    if (callback)
      callback("[ERR] Engine handle is null");
    return;
  }

  try {
    // ── Step 1+2: Vision encode → project → copy embeddings → FREE ────
    // We use a scope so pixel_values + ORT vision tensors are freed
    // before we start building the large final_embeds buffer.
    std::vector<float> projected_embeds_vec; // 256 * 2560 * 4 = 2.5 MB

    if (image_bytes && image_len > 0) {
      LOGI("--- STEP 1: Image decode + resize ---");
      std::string img_error;

      // pixel_values: 896*896*3*4 = 9.2 MB
      std::vector<float> pixel_values = process_image_bytes(
          image_bytes, static_cast<size_t>(image_len), img_error);

      if (!img_error.empty()) {
        LOGE("%s", img_error.c_str());
        if (callback)
          callback(img_error.c_str());
        // Fall through: proceed text-only
      }

      if (!pixel_values.empty()) {
        // Pre-flight RAM check — vision encoder needs ~400 MB working memory on
        // top of the 9.2 MB input tensor. Abort early rather than let Android
        // OOM kill us.
        long avail_kb = 0;
#ifdef ANDROID
        FILE *memf = fopen("/proc/meminfo", "r");
        if (memf) {
          char line[128];
          while (fgets(line, sizeof(line), memf)) {
            if (strncmp(line, "MemAvailable:", 13) == 0) {
              sscanf(line + 13, " %ld", &avail_kb);
              break;
            }
          }
          fclose(memf);
        }
        LOGI("Available RAM before vision encoder: %ld MB", avail_kb / 1024);
        if (avail_kb > 0 && avail_kb < 600 * 1024) { // less than 600 MB free
          std::string oom_err =
              "[IMG_ERR] Insufficient RAM for vision encoder (" +
              std::to_string(avail_kb / 1024) +
              " MB free, need ~600 MB). "
              "Try closing other apps.";
          LOGE("%s", oom_err.c_str());
          if (callback)
            callback(oom_err.c_str());
          pixel_values.clear();
          pixel_values.shrink_to_fit();
          goto skip_vision; // jump past vision block safely
        }
#endif
        LOGI("--- STEP 2: Vision encoder ---");
        {
          std::vector<int64_t> v_shape = {1, 3, 896, 896};
          auto v_input = Ort::Value::CreateTensor<float>(
              state->memory_info, pixel_values.data(), pixel_values.size(),
              v_shape.data(), v_shape.size());

          const char *v_in[] = {"pixel_values"};
          const char *v_out[] = {"image_features"};
          auto v_res = state->v_sess->Run(Ort::RunOptions{nullptr}, v_in,
                                          &v_input, 1, v_out, 1);
          LOGI("Vision encoder done");

          // Free pixel_values now — no longer needed (9.2 MB freed)
          {
            std::vector<float> tmp;
            pixel_values.swap(tmp);
          }
          LOGD("pixel_values freed");

          LOGI("--- STEP 3: Vision projection ---");
          const char *p_in[] = {"image_features"};
          const char *p_out[] = {"visual_tokens"};
          auto p_res = state->p_sess->Run(Ort::RunOptions{nullptr}, p_in,
                                          &v_res[0], 1, p_out, 1);

          // Copy projected embeddings out before p_res goes out of scope
          float *proj_data = p_res[0].GetTensorMutableData<float>();
          projected_embeds_vec.assign(proj_data, proj_data + 256 * embed_dim);
          LOGI("Vision projection done (%.1f MB embed)",
               projected_embeds_vec.size() * 4 / (1024.0f * 1024.0f));

          // v_res and p_res ORT tensors freed here when scope exits
        }

        // ── FREE VISION SESSIONS — weights never needed again ─────────
        // v_sess holds SigLIP encoder weights, p_sess holds projection weights.
        // Destroying them here reclaims their RAM before the generation loop.
        {
          long before_kb = 0, after_kb = 0;
#ifdef ANDROID
          FILE *mf = fopen("/proc/meminfo", "r");
          char ln[128];
          if (mf) {
            while (fgets(ln, sizeof(ln), mf))
              if (!strncmp(ln, "MemAvailable:", 13)) {
                sscanf(ln + 13, " %ld", &before_kb);
                break;
              }
            fclose(mf);
          }
#endif
          state->v_sess.reset(); // destroys vision encoder session + weights
          state->p_sess.reset(); // destroys vision projection session + weights
#ifdef ANDROID
          mf = fopen("/proc/meminfo", "r");
          if (mf) {
            while (fgets(ln, sizeof(ln), mf))
              if (!strncmp(ln, "MemAvailable:", 13)) {
                sscanf(ln + 13, " %ld", &after_kb);
                break;
              }
            fclose(mf);
          }
          LOGI("Vision sessions freed: RAM %ld MB → %ld MB (reclaimed %ld MB)",
               before_kb / 1024, after_kb / 1024,
               (after_kb - before_kb) / 1024);
#else
          LOGI("Vision encoder + projection sessions freed");
#endif
        }
      }
    } else {
      LOGI("No image — text-only mode");
    }
  skip_vision:; // RAM guard jump target

    // ── Step 4: Tokenize ──────────────────────────────────────────────
    LOGI("--- STEP 4: Tokenize ---");
    std::vector<int64_t> tokens;
    tokens.push_back(2); // BOS

    OgaSequences *seq = nullptr;
    OgaCreateSequences(&seq);
    OgaTokenizerEncode(state->tokenizer.get(), prompt, seq);
    size_t count = OgaSequencesGetSequenceCount(seq, 0);
    const int32_t *tdata = OgaSequencesGetSequenceData(seq, 0);
    for (size_t i = 0; i < count; ++i)
      tokens.push_back(static_cast<int64_t>(tdata[i]));
    OgaDestroySequences(seq);
    LOGI("Tokenized: %zu tokens", tokens.size());

    // ── Step 5: Build embeddings ──────────────────────────────────────
    LOGI("--- STEP 5: Build embeddings ---");
    std::vector<float> final_embeds;
    std::vector<int64_t> attn_mask;
    final_embeds.reserve((tokens.size() + num_patches) * embed_dim);
    attn_mask.reserve(2048);

    LOGI("Image token ID in use: %lld — watching for it in %zu tokens",
         state->image_token_id, tokens.size());
    int img_injections = 0;
    for (auto id : tokens) {
      if (id == state->image_token_id) {
        img_injections++;
        if (!projected_embeds_vec.empty()) {
          final_embeds.insert(final_embeds.end(), projected_embeds_vec.begin(),
                              projected_embeds_vec.end());
          attn_mask.insert(attn_mask.end(), num_patches, 1);
        }
      } else {
        std::vector<int64_t> tid = {id}, t_s = {1, 1};
        auto t_tensor = create_tensor(tid, t_s, state->memory_info);
        const char *e_in[] = {"input_ids"};
        const char *e_out[] = {"embeddings"};
        auto e_res = state->e_sess->Run(Ort::RunOptions{nullptr}, e_in,
                                        &t_tensor, 1, e_out, 1);
        float *e_ptr = e_res[0].GetTensorMutableData<float>();
        final_embeds.insert(final_embeds.end(), e_ptr, e_ptr + embed_dim);
        attn_mask.push_back(1);
      }
    }

    // Free projected_embeds_vec — it is now baked into final_embeds (2.5 MB
    // freed)
    {
      std::vector<float> tmp;
      projected_embeds_vec.swap(tmp);
    }
    LOGI("Embeddings built: seq_len=%zu, final_embeds=%.1f MB, "
         "image_injections=%d",
         attn_mask.size(), final_embeds.size() * 4 / (1024.0f * 1024.0f),
         img_injections);
    if (img_injections == 0 && image_bytes && image_len > 0) {
      LOGE("WARNING: image bytes provided but image token was NEVER found in "
           "prompt!");
      LOGE("  Image token ID searched: %lld", state->image_token_id);
      LOGE("  Tokens in prompt: %zu", tokens.size());
      LOGE("  First 10 token IDs:");
      for (size_t ti = 0; ti < std::min(tokens.size(), (size_t)10); ++ti)
        LOGE("    [%zu] = %lld", ti, tokens[ti]);
      if (callback)
        callback("[WARN] Image not grounded — <image> token missing from "
                 "prompt. Output may be hallucinated.");
    }

    // ── Step 6: Chunked prefill + generation loop ────────────────────
    // Problem: sending all 174 tokens at once produces logits {1,174,256000}
    // = 178 MB on Android. Solution: chunk prefill into PREFILL_CHUNK tokens
    // at a time, each producing only {1,CHUNK,256000} logits = much smaller.
    // We discard all but the last chunk's final token logits.
    LOGI("--- STEP 6: Chunked prefill + generation ---");

    const int PREFILL_CHUNK = 16; // 16 tokens × 256000 × 4 = 16.4 MB per chunk
    const int64_t total_prefill = (int64_t)(final_embeds.size() / embed_dim);

    // Build initial empty KV cache
    std::vector<Ort::Value> m_inputs;
    float dummy_kv = 0.0f;
    // placeholder inputs_embeds and attention_mask — replaced each step
    m_inputs.push_back(Ort::Value::CreateTensor<float>(
        state->memory_info, &dummy_kv, 0,
        std::vector<int64_t>{1, 0, (int64_t)embed_dim}.data(), 3));
    m_inputs.push_back(create_tensor({}, {1, 0}, state->memory_info));
    for (int i = 0; i < 34; ++i) {
      std::vector<int64_t> kv_s = {1, 4, 0, 256};
      m_inputs.push_back(Ort::Value::CreateTensor<float>(
          state->memory_info, &dummy_kv, 0, kv_s.data(), 4));
      m_inputs.push_back(Ort::Value::CreateTensor<float>(
          state->memory_info, &dummy_kv, 0, kv_s.data(), 4));
    }

    // RunOptions applied to every LLM step
    Ort::RunOptions run_opts;
    run_opts.SetRunLogSeverityLevel(3);

    std::vector<std::string> in_names_s = {"inputs_embeds", "attention_mask"};
    std::vector<std::string> out_names_s = {"logits"};
    for (int i = 0; i < 34; ++i) {
      in_names_s.push_back("past_key_values." + std::to_string(i) + ".key");
      in_names_s.push_back("past_key_values." + std::to_string(i) + ".value");
      out_names_s.push_back("present." + std::to_string(i) + ".key");
      out_names_s.push_back("present." + std::to_string(i) + ".value");
    }
    std::vector<const char *> m_in, m_out;
    for (const auto &s : in_names_s)
      m_in.push_back(s.c_str());
    for (const auto &s : out_names_s)
      m_out.push_back(s.c_str());

    // ── Chunked prefill ───────────────────────────────────────────────
    int64_t next_id = -1;
    int64_t kv_len = 0; // grows with each chunk

    // Track generated token IDs for repetition penalty.
    // We keep the last 128 tokens — enough to catch phrase loops.
    std::vector<int64_t> generated_ids;
    generated_ids.reserve(128);

    // ── Stop strings ──────────────────────────────────────────────────
    // When the full output ends with any of these, generation is complete.
    // Keeps a rolling buffer of the last N chars of output to match against.
    const std::vector<std::string> STOP_STRINGS = {
        "<end_of_turn>", // Gemma control token (text form)
        "<eos>",         // explicit eos string
        "---END OF REPORT---",
        "--- END OF REPORT ---",
        "End of Report",
        "end of report",
        // Common patterns the model emits before trailing disclaimers:
        "Generated by KintaMed",
        "Disclaimer:",
        "DISCLAIMER:",
        "Note: This AI",
        "Note: This report",
        "NOTE: This",
        "*This report is",
        "This is not medical advice",
        "Confidentiality Notice",
    };
    const size_t STOP_BUF_SIZE =
        64; // keep last 64 chars — enough to match longest stop string
    std::string stop_buf; // rolling window of recent output
    stop_buf.reserve(STOP_BUF_SIZE * 2);
    bool stop_triggered = false;

    // Helper: append text to rolling buffer and check stop strings
    auto check_stop = [&](const char *text) -> bool {
      if (!text)
        return false;
      stop_buf += text;
      // Keep only the last STOP_BUF_SIZE characters
      if (stop_buf.size() > STOP_BUF_SIZE * 2)
        stop_buf.erase(0, stop_buf.size() - STOP_BUF_SIZE);

      // 1. Standard exact match for controlled tokens like <eos>
      for (const auto &ss : STOP_STRINGS) {
        if (stop_buf.size() >= ss.size()) {
          if (stop_buf.find(ss) != std::string::npos) {
            LOGI("Stop string triggered (exact): '%s'", ss.c_str());
            return true;
          }
        }
      }

      // 2. Normalized match for "END OF REPORT" to handle case, spacing, and
      // punctuation variations
      std::string normalized;
      for (char c : stop_buf) {
        if (std::isalnum(c)) {
          normalized += (char)std::tolower(c);
        }
      }

      if (normalized.find("endofreport") != std::string::npos) {
        LOGI("Stop string triggered (normalized): 'endofreport'");
        return true;
      }

      if (normalized.find("generatedbykintamed") != std::string::npos) {
        LOGI("Stop string triggered (normalized): 'generatedbykintamed'");
        return true;
      }

      return false;
    };

    for (int64_t chunk_start = 0; chunk_start < total_prefill;
         chunk_start += PREFILL_CHUNK) {
      int64_t chunk_len =
          std::min((int64_t)PREFILL_CHUNK, total_prefill - chunk_start);

      // Slice this chunk's embeddings from final_embeds
      size_t offset = chunk_start * embed_dim;
      size_t count = chunk_len * embed_dim;
      std::vector<int64_t> c_shape = {1, chunk_len, (int64_t)embed_dim};
      m_inputs[0] = Ort::Value::CreateTensor<float>(
          state->memory_info, final_embeds.data() + offset, count,
          c_shape.data(), c_shape.size());

      // Build attention mask: past KV positions + current chunk
      std::vector<int64_t> chunk_mask(kv_len + chunk_len, 1);
      m_inputs[1] = create_tensor(chunk_mask, {1, kv_len + chunk_len},
                                  state->memory_info);

      LOGD("Prefill chunk [%lld..%lld] kv_len=%lld", chunk_start,
           chunk_start + chunk_len - 1, kv_len);

      auto chunk_res =
          state->m_sess->Run(run_opts, m_in.data(), m_inputs.data(),
                             m_inputs.size(), m_out.data(), m_out.size());

      // Extract next_id from last token of this chunk (only needed for final
      // chunk)
      bool is_last_chunk = (chunk_start + chunk_len >= total_prefill);
      if (is_last_chunk) {
        float *lg = chunk_res[0].GetTensorMutableData<float>();
        size_t vs = chunk_res[0].GetTensorTypeAndShapeInfo().GetShape().back();
        size_t tot = chunk_res[0].GetTensorTypeAndShapeInfo().GetElementCount();
        std::vector<float> last_lg(lg + tot - vs, lg + tot);
        next_id = sample_top_p(last_lg, 0.75f, 0.29f, &generated_ids, 1.30f,
                               state->tokenizer.get());
        LOGI("Prefill complete, first token id=%lld", next_id);
      }

      // Free logits tensor immediately (up to 16×256000×4 = 16 MB per chunk)
      {
        Ort::Value _drop = std::move(chunk_res[0]);
      }

      // Update KV cache
      kv_len += chunk_len;
      for (size_t i = 1; i < chunk_res.size(); ++i)
        m_inputs[i + 1] = std::move(chunk_res[i]);
    }

    // Free the full prefill embeddings now — no longer needed
    {
      std::vector<float> tmp;
      final_embeds.swap(tmp);
    }
    LOGD("final_embeds freed after chunked prefill");

    // Bail if prefill failed
    if (next_id < 0) {
      LOGE("Prefill produced no token");
      if (callback)
        callback("[ERR] Prefill failed");
      return;
    }

    // Emit first token if not EOS
    if (std::find(EOS_IDS.begin(), EOS_IDS.end(), next_id) == EOS_IDS.end()) {
      generated_ids.push_back(next_id);
      if (generated_ids.size() > 128)
        generated_ids.erase(generated_ids.begin());
      int32_t to_dec0 = static_cast<int32_t>(next_id);
      const char *decoded0 = nullptr;
      OgaTokenizerDecode(state->tokenizer.get(), &to_dec0, 1, &decoded0);
      if (decoded0 && callback)
        callback(decoded0);
      stop_triggered = check_stop(decoded0);
    }

    // ── Autoregressive decode loop ────────────────────────────────────
    for (int step = 0; step < (max_tokens - 1) && !stop_triggered; ++step) {
      // Embed next_id and run one decode step (logits = {1,1,256000} = 1 MB
      // only)
      std::vector<int64_t> nid_v = {next_id}, nid_s = {1, 1};
      auto nid_t = create_tensor(nid_v, nid_s, state->memory_info);
      const char *ein[] = {"input_ids"};
      const char *eout[] = {"embeddings"};
      auto n_emb_res =
          state->e_sess->Run(Ort::RunOptions{nullptr}, ein, &nid_t, 1, eout, 1);

      m_inputs[0] = std::move(n_emb_res[0]);

      // Attention mask: kv_len past positions + 1 new token
      // kv_len=174 on first decode step → mask size = 175 ✓
      // Do NOT increment kv_len here — only once after the run
      std::vector<int64_t> dec_mask(kv_len + 1, 1);
      m_inputs[1] = create_tensor(dec_mask, {1, (int64_t)dec_mask.size()},
                                  state->memory_info);

      LOGD("Decode step %d: kv_len=%lld mask_size=%zu", step, kv_len,
           dec_mask.size());

      auto d_res =
          state->m_sess->Run(run_opts, m_in.data(), m_inputs.data(),
                             m_inputs.size(), m_out.data(), m_out.size());

      // Decode logits: always {1,1,256000} = 1 MB — free immediately
      float *dlg = d_res[0].GetTensorMutableData<float>();
      size_t dvs = d_res[0].GetTensorTypeAndShapeInfo().GetShape().back();
      size_t dtot = d_res[0].GetTensorTypeAndShapeInfo().GetElementCount();
      std::vector<float> d_last(dlg + dtot - dvs, dlg + dtot);
      {
        Ort::Value _drop = std::move(d_res[0]);
      } // free logits tensor

      next_id = sample_top_p(d_last, 0.75f, 0.29f, &generated_ids, 1.30f,
                             state->tokenizer.get());
      {
        std::vector<float> tmp;
        d_last.swap(tmp);
      }

      if (std::find(EOS_IDS.begin(), EOS_IDS.end(), next_id) != EOS_IDS.end()) {
        LOGI("EOS at decode step %d", step + 1);
        break;
      }

      generated_ids.push_back(next_id);
      if (generated_ids.size() > 128)
        generated_ids.erase(generated_ids.begin());

      int32_t to_dec = static_cast<int32_t>(next_id);
      const char *decoded = nullptr;
      OgaTokenizerDecode(state->tokenizer.get(), &to_dec, 1, &decoded);
      if (decoded && callback)
        callback(decoded);

      if (check_stop(decoded)) {
        LOGI("Stop string triggered at decode step %d", step + 1);
        stop_triggered = true;
        break;
      }

      // Increment ONCE after the run — kv now includes the token we just
      // processed
      kv_len += 1;

      // Replace KV cache entries (old KV tensors freed by move)
      for (size_t i = 1; i < d_res.size(); ++i)
        m_inputs[i + 1] = std::move(d_res[i]);

#ifdef ANDROID
      if (step % 20 == 0) {
        long ram_kb = 0;
        FILE *mf3 = fopen("/proc/meminfo", "r");
        char ln3[128];
        if (mf3) {
          while (fgets(ln3, sizeof(ln3), mf3))
            if (!strncmp(ln3, "MemAvailable:", 13)) {
              sscanf(ln3 + 13, " %ld", &ram_kb);
              break;
            }
          fclose(mf3);
        }
        LOGI("Decode step %d — RAM: %ld MB", step + 1, ram_kb / 1024);
        if (ram_kb > 0 && ram_kb < 200 * 1024) {
          if (callback)
            callback("[WARN] Low RAM, stopping");
          break;
        }
      }
#endif
    }

    LOGI("Inference complete");

  } catch (const std::exception &e) {
    std::string err = std::string("[EXCEPTION] ") + e.what();
    LOGE("%s", err.c_str());
    if (callback)
      callback(err.c_str());
  }
}

EXPORT void reset_inference_state(void *handle) {
  LOGI("reset_inference_state called");
  auto state = static_cast<MedGemmaState *>(handle);
  if (!state)
    return;
  try {
    auto reload = [&](const std::string &p, Ort::SessionOptions &opts) {
      LOGI("Reloading: %s", p.c_str());
      return std::make_unique<Ort::Session>(*state->env, p.c_str(), opts);
    };
    if (!state->v_sess) {
      state->v_sess = reload(state->model_dir + "/vision_encoder.ort",
                             *state->vision_session_options);
      LOGI("vision_encoder reloaded");
    }
    if (!state->p_sess) {
      state->p_sess = reload(state->model_dir + "/vision_projection.ort",
                             *state->vision_session_options);
      LOGI("vision_projection reloaded");
    }
    LOGI("reset_inference_state complete");
  } catch (const std::exception &e) {
    LOGE("reset_inference_state EXCEPTION: %s", e.what());
  }
}

} // extern "C"