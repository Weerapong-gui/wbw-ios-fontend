import SwiftUI
import MapLibre

/// แผนที่สมจริง — ภาพถ่ายดาวเทียม (Esri) + 3D terrain (DEM) จำกัดขอบเขตแค่พื้นที่งาน
/// ฟรี ไม่ต้อง API key · MapLibre Native iOS
struct MapScreen: View {
    var body: some View {
        MapViewRep()
            .ignoresSafeArea()
    }
}

private struct MapViewRep: UIViewRepresentable {
    // กรอบพื้นที่งาน (แพนออกนอกไม่ได้)
    static let west = 99.855, east = 99.910, south = 20.022, north = 20.068
    static let center = CLLocationCoordinate2D(latitude: 20.045, longitude: 99.8825)

    static let styleJSON = """
    {
      "version": 8,
      "sources": {
        "satellite": {
          "type": "raster",
          "tiles": ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
          "tileSize": 256,
          "maxzoom": 19,
          "attribution": "Esri, Maxar, Earthstar Geographics"
        },
        "terrainDem": {
          "type": "raster-dem",
          "tiles": ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
          "tileSize": 256,
          "encoding": "terrarium",
          "maxzoom": 15
        }
      },
      "layers": [
        { "id": "bg", "type": "background", "paint": { "background-color": "#0b1a14" } },
        { "id": "satellite", "type": "raster", "source": "satellite" },
        { "id": "hillshade", "type": "hillshade", "source": "terrainDem", "paint": { "hillshade-exaggeration": 0.45 } }
      ],
      "terrain": { "source": "terrainDem", "exaggeration": 1.4 }
    }
    """

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let url = Self.writeStyle()
        let mv = MLNMapView(frame: .zero, styleURL: url)
        mv.delegate = context.coordinator
        mv.showsUserLocation = false
        mv.minimumZoomLevel = 13
        mv.maximumZoomLevel = 18
        mv.compassView.compassVisibility = .adaptive
        mv.setCenter(Self.center, zoomLevel: 13.6, direction: 15, animated: false)
        return mv
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    /// เขียน style JSON ลงไฟล์ caches แล้วคืน URL (MLNMapView รับ styleURL)
    static func writeStyle() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("wbw_style.json")
        try? styleJSON.data(using: .utf8)?.write(to: url)
        return url
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        // เอียงกล้อง 3D หลัง style โหลด · หน่วงเวลาให้ map view มี frame จริงก่อน (ไม่งั้น pitch ไม่ติด)
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            applyTilt(mapView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak mapView] in
                guard let mapView else { return }
                self.applyTilt(mapView)
            }
        }

        private func applyTilt(_ mapView: MLNMapView) {
            let cam = MLNMapCamera(
                lookingAtCenter: MapViewRep.center,
                acrossDistance: 6500,
                pitch: 55,
                heading: 15
            )
            mapView.setCamera(cam, animated: false)
        }

        // กันแพนออกนอกกรอบพื้นที่งาน
        func mapView(_ mapView: MLNMapView,
                     shouldChangeFrom oldCamera: MLNMapCamera,
                     to newCamera: MLNMapCamera,
                     reason: MLNCameraChangeReason) -> Bool {
            let c = newCamera.centerCoordinate
            return c.latitude >= MapViewRep.south && c.latitude <= MapViewRep.north
                && c.longitude >= MapViewRep.west && c.longitude <= MapViewRep.east
        }
    }
}
