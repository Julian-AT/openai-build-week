import ARKit
import RealityKit
import SwiftUI

struct CameraSurface: UIViewRepresentable {
  let session: ARSession

  func makeUIView(context: Context) -> ARView {
    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    view.session = session
    view.renderOptions.insert(.disableMotionBlur)
    return view
  }

  func updateUIView(_ view: ARView, context: Context) {
    if view.session !== session {
      view.session = session
    }
  }
}
