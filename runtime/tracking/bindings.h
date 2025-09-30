#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
   float x;
   float y;
   float width;
   float height;
   float score;
   int zig_id;
} BtInput;

typedef struct BYTETracker BYTETracker;

BYTETracker *create_byte_tracker(int frame_rate, int track_buffer);
void destroy_byte_tracker(BYTETracker *tracker);
int update_byte_tracker(
    BYTETracker *tracker, BtInput *objects, int count, int *outputs, int output_count
);

#ifdef __cplusplus
}
#endif