import HostApi

@_expose(wasm, "pose")
@_cdecl("pose")
func pose(id: Int32, alive: Bool) {
}

@MainActor
let pose_buf = UnsafeMutablePointer<Float>.allocate(capacity: 17 * 2)
@MainActor
let transform_buf = UnsafeMutablePointer<Float>.allocate(capacity: 16)

@main
struct wasi_test {
    static func main() {
        simulo_set_buffers(pose_buf, transform_buf)
        if true {

        }
    }
}