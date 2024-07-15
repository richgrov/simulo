#ifndef VKAD_SOUND_H_
#define VKAD_SOUND_H_

#include <fmod.h>

namespace vkad {

class Sound {
public:
   Sound(FMOD_SYSTEM *system, const char *path);
   ~Sound();

   void play() const;

private:
   FMOD_SOUND *sound_;
   FMOD_SYSTEM *sound_system_;
};

} // namespace vkad

#endif // !VKAD_SOUND_H_
