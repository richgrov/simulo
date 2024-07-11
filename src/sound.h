#ifndef VILLA_SOUND_H_
#define VILLA_SOUND_H_

#include <fmod.h>

namespace villa {

class Sound {
public:
   Sound(FMOD_SYSTEM *system, const char *path);
   ~Sound();

   void play() const;

private:
   FMOD_SOUND *sound_;
   FMOD_SYSTEM *sound_system_;
};

} // namespace villa

#endif // !VILLA_SOUND_H_
