// Local eSpeak NG boundary. Upstream GPLv3 notices/source must accompany distribution.
#include <jni.h>
#include <espeak-ng/speak_lib.h>
#include <string>

static bool initialized = false;
static std::string data_path;

static void fail(JNIEnv *env, const char *message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_ureader_prototype_speech_FrenchPhonemizer_nativePhonemes(
        JNIEnv *env, jobject, jstring directory, jbyteArray input) {
    // Calls are serialized by FrenchPhonemizer's process-wide lock.
    const char *path_chars = env->GetStringUTFChars(directory, nullptr);
    if (!path_chars) return nullptr;
    const std::string path(path_chars);
    env->ReleaseStringUTFChars(directory, path_chars);
    if (path.size() + sizeof("/espeak-ng-data") >= 1024) {
        fail(env, "French frontend path exceeds native limit");
        return nullptr;
    }
    if (initialized && data_path != path) {
        fail(env, "Frontend data changed while loaded");
        return nullptr;
    }
    if (!initialized) {
        if (espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, path.c_str(),
                              espeakINITIALIZE_DONT_EXIT) < 0) {
            fail(env, "French frontend initialization failed");
            return nullptr;
        }
        initialized = true;
        data_path = path;
    }
    // Match EspeakWrapper.set_voice('fr-fr'): it resolves the language to the
    // pinned voice identifier before calling SetVoiceByName, not the language tag.
    if (espeak_SetVoiceByName("roa/fr") != EE_OK) {
        fail(env, "French phoneme voice unavailable");
        return nullptr;
    }
    const jsize size = env->GetArrayLength(input);
    if (size <= 0 || size > 16384) {
        fail(env, "Frontend input limit");
        return nullptr;
    }
    std::string text(static_cast<size_t>(size), '\0');
    env->GetByteArrayRegion(input, 0, size, reinterpret_cast<jbyte *>(text.data()));
    if (env->ExceptionCheck()) return nullptr;
    if (text.find('\0') != std::string::npos) {
        fail(env, "Embedded NUL rejected");
        return nullptr;
    }
    const void *cursor = text.c_str();
    std::string result;
    while (cursor) {
        const void *previous = cursor;
        // Same IPA/tie mode as phonemizer-fork 3.3.2 used by the PC reference.
        const char *phones = espeak_TextToPhonemes(&cursor, 1, 0x02 | (1 << 7) | (0x361 << 8));
        if (!phones || (cursor && cursor == previous)) {
            fail(env, "French phonemization failed");
            return nullptr;
        }
        result += phones;
        if (cursor) result += ' ';
        if (result.size() > 65536) {
            fail(env, "Phoneme output limit");
            return nullptr;
        }
    }
    return env->NewStringUTF(result.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_ureader_prototype_speech_FrenchPhonemizer_nativeClose(JNIEnv *, jobject) {
    if (initialized) espeak_Terminate();
    initialized = false;
    data_path.clear();
}
