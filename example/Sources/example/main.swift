import HostApi
import Foundation

@MainActor
var lastPointer: UnsafeMutableRawPointer?

let WHITE_PIXEL_IMAGE: UInt32 = UInt32.max

struct Matrix4x4 {
    var m00, m01, m02, m03: Float
    var m10, m11, m12, m13: Float
    var m20, m21, m22, m23: Float
    var m30, m31, m32, m33: Float
    
    static let identity = Matrix4x4(
        m00: 1, m01: 0, m02: 0, m03: 0,
        m10: 0, m11: 1, m12: 0, m13: 0,
        m20: 0, m21: 0, m22: 1, m23: 0,
        m30: 0, m31: 0, m32: 0, m33: 1
    )
    
    static func translation(x: Float, y: Float, z: Float) -> Matrix4x4 {
        var matrix = identity
        matrix.m30 = x
        matrix.m31 = y
        matrix.m32 = z
        return matrix
    }
    
    static func rotationZ(angle: Float) -> Matrix4x4 {
        let cos = cosf(angle)
        let sin = sinf(angle)
        
        var matrix = identity
        matrix.m00 = cos
        matrix.m01 = sin
        matrix.m10 = -sin
        matrix.m11 = cos
        return matrix
    }
    
    static func scale(x: Float, y: Float, z: Float) -> Matrix4x4 {
        var matrix = identity
        matrix.m00 = x
        matrix.m11 = y
        matrix.m22 = z
        return matrix
    }
    
    static func * (_ a: Matrix4x4, _ b: Matrix4x4) -> Matrix4x4 {
        var result = Matrix4x4.identity
        
        result.m00 = a.m00 * b.m00 + a.m01 * b.m10 + a.m02 * b.m20 + a.m03 * b.m30
        result.m01 = a.m00 * b.m01 + a.m01 * b.m11 + a.m02 * b.m21 + a.m03 * b.m31
        result.m02 = a.m00 * b.m02 + a.m01 * b.m12 + a.m02 * b.m22 + a.m03 * b.m32
        result.m03 = a.m00 * b.m03 + a.m01 * b.m13 + a.m02 * b.m23 + a.m03 * b.m33
        
        result.m10 = a.m10 * b.m00 + a.m11 * b.m10 + a.m12 * b.m20 + a.m13 * b.m30
        result.m11 = a.m10 * b.m01 + a.m11 * b.m11 + a.m12 * b.m21 + a.m13 * b.m31
        result.m12 = a.m10 * b.m02 + a.m11 * b.m12 + a.m12 * b.m22 + a.m13 * b.m32
        result.m13 = a.m10 * b.m03 + a.m11 * b.m13 + a.m12 * b.m23 + a.m13 * b.m33
        
        result.m20 = a.m20 * b.m00 + a.m21 * b.m10 + a.m22 * b.m20 + a.m23 * b.m30
        result.m21 = a.m20 * b.m01 + a.m21 * b.m11 + a.m22 * b.m21 + a.m23 * b.m31
        result.m22 = a.m20 * b.m02 + a.m21 * b.m12 + a.m22 * b.m22 + a.m23 * b.m32
        result.m23 = a.m20 * b.m03 + a.m21 * b.m13 + a.m22 * b.m23 + a.m23 * b.m33
        
        result.m30 = a.m30 * b.m00 + a.m31 * b.m10 + a.m32 * b.m20 + a.m33 * b.m30
        result.m31 = a.m30 * b.m01 + a.m31 * b.m11 + a.m32 * b.m21 + a.m33 * b.m31
        result.m32 = a.m30 * b.m02 + a.m31 * b.m12 + a.m32 * b.m22 + a.m33 * b.m32
        result.m33 = a.m30 * b.m03 + a.m31 * b.m13 + a.m32 * b.m23 + a.m33 * b.m33
        
        return result
    }
}

@MainActor
var POSE_DATA: [Float] = Array(repeating: 0.0, count: 17 * 2)
@MainActor
var TRANSFORM_DATA: [Float] = Array(repeating: 0.0, count: 16)

class Object {
    var position: SIMD2<Float> = SIMD2<Float>(0, 0)
    var rotation: Float = 0.0
    var scale: SIMD2<Float> = SIMD2<Float>(1, 1)
    let id: UInt32
    
    init(material: Material) {
        self.id = simulo_create_object(material.id)
    }
    
    deinit {
        simulo_drop_object(id)
    }
    
    func recalculateTransform() -> Matrix4x4 {
        let translation = Matrix4x4.translation(x: position.x, y: position.y, z: 0.0)
        let rotation = Matrix4x4.rotationZ(angle: rotation)
        let scale = Matrix4x4.scale(x: scale.x, y: scale.y, z: 1.0)
        return translation * rotation * scale
    }
    
    func addChild(_ child: Object) {
        let childId = child.id
        let this = Unmanaged.passRetained(child as Object).toOpaque()
        
        simulo_set_object_ptrs(childId, this)
        simulo_add_object_child(id, childId)
    }
    
    func children() -> [Object] {
        var children = Array<UnsafeMutableRawPointer?>(repeating: nil, count: 128)
        let nChildren = simulo_get_children(id, &children, UInt32(children.count))
        
        var childrenBuffer: [Object] = []
        for i in 0..<Int(nChildren) {
            if let ptr = children[i] {
                // Use takeRetainedValue to decrement ref count - we now "own" this reference
                // The returned objects will be retained by the array and released when the array is deallocated
                let object = Unmanaged<Object>.fromOpaque(ptr).takeRetainedValue()
                childrenBuffer.append(object)
            }
        }
        return childrenBuffer
    }
    
    func markTransformOutdated() {
        simulo_mark_transform_outdated(id)
    }
    
    func setMaterial(_ material: Material) {
        simulo_set_object_material(id, material.id)
    }
    
    func delete() {
        simulo_remove_object_from_parent(id)
    }
    
    func update(delta: Float) {
    }
}

// Material class
class Material {
    let id: UInt32
    
    init(imageId: UInt32, r: Float, g: Float, b: Float) {
        self.id = simulo_create_material(imageId, r, g, b)
    }
    
    deinit {
        simulo_delete_material(id)
    }
}

// Utility functions
func randomFloat() -> Float {
    return simulo_random()
}

func windowSize() -> SIMD2<Int32> {
    return SIMD2<Int32>(simulo_window_width(), simulo_window_height())
}

// Pose class
class Pose {
    let data: [Float]
    
    init(data: [Float]) {
        self.data = data
    }
    
    func keypoint(_ index: Int) -> SIMD2<Float> {
        return SIMD2<Float>(data[index * 2], data[index * 2 + 1])
    }
    
    var nose: SIMD2<Float> { keypoint(0) }
    var leftEye: SIMD2<Float> { keypoint(1) }
    var rightEye: SIMD2<Float> { keypoint(2) }
    var leftEar: SIMD2<Float> { keypoint(3) }
    var rightEar: SIMD2<Float> { keypoint(4) }
    var leftShoulder: SIMD2<Float> { keypoint(5) }
    var rightShoulder: SIMD2<Float> { keypoint(6) }
    var leftElbow: SIMD2<Float> { keypoint(7) }
    var rightElbow: SIMD2<Float> { keypoint(8) }
    var leftWrist: SIMD2<Float> { keypoint(9) }
    var rightWrist: SIMD2<Float> { keypoint(10) }
    var leftHip: SIMD2<Float> { keypoint(11) }
    var rightHip: SIMD2<Float> { keypoint(12) }
    var leftKnee: SIMD2<Float> { keypoint(13) }
    var rightKnee: SIMD2<Float> { keypoint(14) }
    var leftAnkle: SIMD2<Float> { keypoint(15) }
    var rightAnkle: SIMD2<Float> { keypoint(16) }
}

class Game: Object {
    private var material: Material
    
    override init(material: Material) {
        self.material = material
        super.init(material: material)
        self.scale = SIMD2<Float>(100, 100)
        self.markTransformOutdated()
    }
    
    func onPoseUpdate(id: UInt32, pose: Pose?) {
        if let pose = pose {
            let particle = Particle(material: material)
            particle.position = pose.nose
            addChild(particle)
        }
        
        for child in children() {
            child.position -= SIMD2<Float>(0, 10)
        }
    }
}

// Particle class - inherits from Object
class Particle: Object {
    var lifetime: Float = 1.0
    var velocity: SIMD2<Float> = SIMD2<Float>(50, 50)
    
    override init(material: Material) {
        super.init(material: material)
    }
    
    override func update(delta: Float) {
        position += velocity * delta
        markTransformOutdated()
        lifetime -= delta
        if lifetime <= 0.0 {
            delete()
        }
    }
}

@MainActor
@main
struct __main {
    static func main() {
        let game = Game(material: Material(imageId: WHITE_PIXEL_IMAGE, r: 1.0, g: 1.0, b: 1.0))
        
        print("!!!!!!!test2!!!!!!!")
        let id = game.id
        let this = Unmanaged.passRetained(game as Object).toOpaque()
        
        POSE_DATA.withUnsafeMutableBufferPointer { posePtr in
            TRANSFORM_DATA.withUnsafeMutableBufferPointer { transformPtr in
                simulo_set_buffers(posePtr.baseAddress!, transformPtr.baseAddress!)
            }
        }
        
        lastPointer = this
        simulo_set_root(id, this)
    }
}

@MainActor
@_expose(wasm, "__pose")
@_cdecl("__pose")
func __pose(id: Int32, alive: Bool) {
    if true {
        return
    }
    
    if alive {
        let pose = Pose(data: POSE_DATA)
        //game.onPoseUpdate(id: UInt32(id), pose: pose)
    } else {
        //game.onPoseUpdate(id: UInt32(id), pose: nil)
    }
}

@MainActor
@_expose(wasm, "__update")
@_cdecl("__update")
func __update(ptr: UnsafeMutableRawPointer, delta: Float) {
    let object = Unmanaged<Object>.fromOpaque(ptr).takeRetainedValue()
    object.update(delta: delta)
    _ = Unmanaged.passRetained(object);
}

@MainActor
@_expose(wasm, "__recalculate_transform")
@_cdecl("__recalculate_transform")
func __recalculate_transform(ptr: UnsafeMutableRawPointer) {
    let object = Unmanaged<Object>.fromOpaque(ptr).takeRetainedValue()
    let transform = object.recalculateTransform()
    print("!!!!!!!test!!!!!!!")
    TRANSFORM_DATA[0] = transform.m00
    TRANSFORM_DATA[1] = transform.m01
    TRANSFORM_DATA[2] = transform.m02
    TRANSFORM_DATA[3] = transform.m03
    TRANSFORM_DATA[4] = transform.m10
    TRANSFORM_DATA[5] = transform.m11
    TRANSFORM_DATA[6] = transform.m12
    TRANSFORM_DATA[7] = transform.m13
    TRANSFORM_DATA[8] = transform.m20
    TRANSFORM_DATA[9] = transform.m21
    TRANSFORM_DATA[10] = transform.m22
    TRANSFORM_DATA[11] = transform.m23
    TRANSFORM_DATA[12] = transform.m30
    TRANSFORM_DATA[13] = transform.m31
    TRANSFORM_DATA[14] = transform.m32
    TRANSFORM_DATA[15] = transform.m33
    _ = Unmanaged.passRetained(object);
}

@MainActor
@_expose(wasm, "__drop")
@_cdecl("__drop")
func __drop(ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<Object>.fromOpaque(ptr).takeRetainedValue()
}