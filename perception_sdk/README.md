# Perception SDK

## Installation

- Download the latest [release](https://github.com/richgrov/simulo-engine/releases) from Github

- Extract the extension and place the `bin` folder in the root of your Godot project

## Usage

### Class `Perception2d`

Create a **single** `Perception2d` node in your scene and use the following functions:

`Perception2d.start()`

Enable the connected camera and begin looking for a 10x5 chessboard to calibrate with. Calling this
more than once should be discouraged.

The camera and perception logic runs on a thread independent from the game at a variable speed.

`Perception2d.is_calibrated() -> bool`

Returns true if the camera is enabled and calibrated, false otherwise.

`Perception2d.detect() -> Array<Detection>`

Retrieves a list of the detections from the latest frame processed by the camera.

### Class `Detection`

`Detection.get_keypoint(keypoint_index: int) -> Vector2`

Gets the (X, Y) screen coordinates of the specified keypoint. Valid keypoints are:

| ID  | Name           |
| --- | -------------- |
| 0   | Nose           |
| 1   | Left eye       |
| 2   | Right eye      |
| 3   | Left ear       |
| 4   | Right ear      |
| 5   | Left shoulder  |
| 6   | Right shoulder |
| 7   | Left elbow     |
| 8   | Right elbow    |
| 9   | Left wrist     |
| 10  | Right wrist    |
| 11  | Left hip       |
| 12  | Right hip      |
| 13  | Left knee      |
| 14  | Right knee     |
| 15  | Left ankle     |
| 16  | Right ankle    |
