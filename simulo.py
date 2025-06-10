"""
    Simulo: the game engine of the real world
    This file contains documentation for scripting in the simulo engine, an engine designed for
    creating projection mapping experiences.

    Simulo runs a subset of Python. The following built-in modules are available, with some
    limitations:
    - datetime: math operators on time/date/timedelta not supported
    - random
    - time

    The rest of this file documents API available in the `simulo` module.

    Coordinate system:
    +X = left
    +Y = up
    +Z = forward

    Behavior system:
    Behaviors may be added to objects which can respond to events, fire events, and manipulate the
    object they are attached to. There is no specific order that behaviors execute in.
"""

from typing import Any, Callable

DetectionHandler = Callable[[int, float, float], None]
"""
    :param id: The ID of the object that was detected. If the object's position is updated later,
    it will have the same ID.
    :param x: The screen x-coordinate of the object that was detected. Actual value may be outside
    this range if the object is off-screen.
    :param y: The screen y-coordinate of the object that was detected. Actual value may be outside
    this range if the object is off-screen.

    If both x and y are exactly -1, the object is no longer visible on the screen and has been
    deleted.
"""

def on(func: DetectionHandler) -> None:
    """
        Registers a detection handler callback to be called every frame when an a person's hand
        comes into view, moves, or leaves the screen.
    """
    ...

class GameObject:
    def __init__(self, x: float, y: float):
        """
            Spawns an object in the scene at the given position. At default (1x1) scale, the object
            displays a 1x1 pixel image.
        """
        ...

    def delete(self):
        """
            Deletes the object from the scene at the end of the current frame. Behaviors will no
            longer be executed after this.
        """
        ...

    @property
    def x(self) -> float:
        """
            The screen x-coordinate of the object.
        """
        ...

    @property
    def y(self) -> float:
        """
            The screen y-coordinate of the object.
        """
        ...

    def set_position(self, x: float, y: float):
        """
            Sets the position of the object to the given coordinates.
        """
        ...

    @property
    def x_scale(self) -> float:
        """
            The scale of the object in screen pixels along the x-axis.
        """
        ...

    @property
    def y_scale(self) -> float:
        """
            The scale of the object in screen pixels along the y-axis.
        """
        ...

    def set_scale(self, x_scale: float, y_scale: float):
        """
            Sets the scale of the object to the given values in screen pixels.
        """
        ...

    def add_behavior(self, behavior: Any):
        """
            Adds a behavior to the object. Only one of each type of behavior can be added to a
            specific object.
        """
        ...

class MovementBehavior:
    """
        Constantly moves an object in a given direction scaled by delta time.
    """

    def __init__(self, object: GameObject, dx: float, dy: float):
        """
            :param object: The object this behavior is being attached to.
            :param dx: The number of pixels to move the object in the x-direction per second.
            :param dy: The number of pixels to move the object in the y-direction per second.
        """
        ...

class LifetimeBehavior:
    """
        Destroys an object after a given amount of time.
    """

    def __init__(self, object: GameObject, lifetime: float):
        """
            :param object: The object this behavior is being attached to.
            :param lifetime: The amount of time in seconds before the object is destroyed.
        """
        ...
