#include "sound.h"
#include "fmod.h"

#include <stdexcept>

using namespace villa;

Sound::Sound(FMOD_SYSTEM *system, const char *path) : sound_system_(system) {
   if (FMOD_System_CreateSound(system, "res/sfx/bass.wav", FMOD_DEFAULT, nullptr, &sound_) !=
       FMOD_OK) {
      throw std::runtime_error("failed to load sound");
   }
}

Sound::~Sound() {
   FMOD_Sound_Release(sound_);
}

void Sound::play() const {
   if (FMOD_System_PlaySound(sound_system_, sound_, nullptr, false, nullptr) != FMOD_OK) {
      throw std::runtime_error("failed to play sound");
   }
}
