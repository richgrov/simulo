#include "sound.h"

#include <format>
#include <stdexcept>

#include <fmod.h>

using namespace vkad;

Sound::Sound(FMOD_SYSTEM *system, const char *path) : sound_system_(system) {
   if (FMOD_System_CreateSound(system, path, FMOD_DEFAULT, nullptr, &sound_) != FMOD_OK) {
      throw std::runtime_error(std::format("failed to load {}", path));
   }
}

Sound::~Sound() {
   if (sound_ != nullptr) {
      FMOD_Sound_Release(sound_);
   }
}

void Sound::play() const {
   if (FMOD_System_PlaySound(sound_system_, sound_, nullptr, false, nullptr) != FMOD_OK) {
      throw std::runtime_error("failed to play sound");
   }
}
