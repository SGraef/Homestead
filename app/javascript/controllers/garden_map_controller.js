import { Controller } from "@hotwired/stimulus"

// Garden map: official WMS layers (basemap.de base, per-Bundesland DOP20
// aerial imagery + ALKIS cadastral parcels, see Garden::MapSources) used to
// capture ONE geometry -- the household's Grundstück. It is either traced by
// clicking vertices over the imagery or adopted from the official parcel
// (Flurstück) under a clicked point. Beds are not mapped; they live in the
// to-scale planner, which uses this outline as its backdrop.
//
// Leaflet is lazy-imported so only this page downloads it. The live area
// readout mirrors Garden::Geometry (equirectangular + shoelace); the stored
// value is always the server's.
const EARTH_RADIUS_M = 6378137.0

export default class extends Controller {
  static values = {
    config: Object, // { basemap:, dop:, alkis: } url/layer/attribution each
    center: Array,
    zoom: Number,
    property: Array, // saved Grundstück ring [{lat, lng}, ...] (may be empty)
    structures: Array, // buildings [{id, name, boundary: [{lat, lng}, ...]}]
    token: String,
    propertyUrl: String, // PATCH endpoint (blank for non-admin members)
    structuresUrl: String, // POST endpoint for traced buildings (blank for members)
    parcelUrl: String // blank when the Bundesland has no Flurstück source
  }

  static targets = ["map", "readout", "dopToggle", "alkisToggle",
                    "drawControls", "adoptControls", "centerLat", "centerLng", "zoom"]

  async connect() {
    this.L = await import("leaflet")
    if (!this.hasMapTarget) return // page changed while leaflet loaded

    this.drawing = null
    this.parcelPicking = false
    this.parcelLayer = null
    this.pendingParcel = null
    this.propertyLayer = null
    this.structureLayers = []

    this.initMap()
    this.renderProperty(this.propertyValue)
    this.renderStructures()
  }

  disconnect() {
    this.map?.remove()
    this.map = null
  }

  initMap() {
    const L = this.L
    this.map = L.map(this.mapTarget, { zoomControl: true })
    this.map.setView(this.centerValue, this.zoomValue)

    const { basemap, dop, alkis } = this.configValue
    L.tileLayer.wms(basemap.url, {
      layers: basemap.layer, format: "image/png", attribution: basemap.attribution || ""
    }).addTo(this.map)

    this.dopLayer = dop && L.tileLayer.wms(dop.url, {
      layers: dop.layer, format: "image/jpeg", attribution: dop.attribution || ""
    })
    this.alkisLayer = alkis && L.tileLayer.wms(alkis.url, {
      layers: alkis.layer, format: "image/png", transparent: true, attribution: alkis.attribution || ""
    })

    // DOP on by default (the point of the map is the aerial view); parcels
    // opt-in. Toggles for layers the Bundesland has no source for are hidden.
    this.setupToggle(this.dopToggleTarget, this.dopLayer, true)
    this.setupToggle(this.alkisToggleTarget, this.alkisLayer, false)

    this.map.on("click", (e) => this.mapClicked(e))
    this.map.on("moveend zoomend", () => this.viewportChanged())
  }

  setupToggle(input, layer, initiallyOn) {
    if (!layer) {
      input.closest("label").hidden = true
      return
    }
    input.checked = initiallyOn
    if (initiallyOn) layer.addTo(this.map)
  }

  toggleDop() { this.applyToggle(this.dopToggleTarget, this.dopLayer) }
  toggleAlkis() { this.applyToggle(this.alkisToggleTarget, this.alkisLayer) }

  applyToggle(input, layer) {
    if (!layer) return
    if (input.checked) layer.addTo(this.map)
    else layer.remove()
  }

  // Mirror the map viewport into the settings form so an admin's "save"
  // persists where the map was left.
  viewportChanged() {
    if (!this.hasCenterLatTarget) return
    const center = this.map.getCenter()
    this.centerLatTarget.value = center.lat.toFixed(7)
    this.centerLngTarget.value = center.lng.toFixed(7)
    this.zoomTarget.value = this.map.getZoom()
  }

  // -- Grundstück outline ----------------------------------------------------

  renderProperty(ring) {
    this.propertyLayer?.remove()
    this.propertyLayer = null
    if (!ring || ring.length < 3) return

    this.propertyLayer = this.L.polygon(ring.map((p) => [p.lat, p.lng]), {
      color: "#c97455", weight: 3, fillOpacity: 0.08
    }).addTo(this.map)
    if (!this.hasFittedProperty) {
      this.map.fitBounds(this.propertyLayer.getBounds(), { maxZoom: 19 })
      this.hasFittedProperty = true
    }
  }

  mapClicked(e) {
    if (this.parcelPicking) {
      this.fetchParcel(e.latlng)
      return
    }
    if (!this.drawing) return
    const point = { lat: e.latlng.lat, lng: e.latlng.lng }
    this.drawing.points.push(point)
    this.drawing.markers.push(
      this.L.circleMarker(e.latlng, { radius: 5, color: this.drawing.color, fillOpacity: 1 }).addTo(this.map)
    )
    this.updatePreview()
  }

  startDraw() {
    this.beginDrawing("property", "#c97455")
  }

  // Same tracing flow as the Grundstück, but the finished ring becomes a
  // building (shadow caster) instead of the property outline.
  startDrawStructure() {
    this.beginDrawing("structure", "#5b6770")
  }

  beginDrawing(mode, color) {
    this.stopParcelPick()
    this.cancelDraw()
    this.drawing = { mode, color, points: [], markers: [], preview: null }
    this.propertyLayer?.setStyle({ opacity: 0.3, fillOpacity: 0.02 })
    this.mapTarget.classList.add("garden-map-drawing")
    this.drawControlsTarget.hidden = false
    this.setReadout(this.element.dataset.i18nDrawHint)
  }

  updatePreview() {
    const { points } = this.drawing
    this.drawing.preview?.remove()
    this.drawing.preview = this.L.polyline(
      points.concat(points.length > 2 ? [points[0]] : []).map((p) => [p.lat, p.lng]),
      { color: this.drawing.color, dashArray: "6 4", weight: 2 }
    ).addTo(this.map)
    if (points.length >= 3) this.setReadout(this.areaLabel(polygonAreaSqm(points)))
  }

  finishDraw() {
    if (!this.drawing) return
    if (this.drawing.points.length < 3) {
      this.setReadout(this.element.dataset.i18nDrawNeedPoints)
      return
    }
    const save = this.drawing.mode === "structure"
      ? this.createStructure(this.drawing.points)
      : this.saveProperty(this.drawing.points)
    save.then((saved) => {
      if (saved) this.cancelDraw()
    })
  }

  cancelDraw() {
    if (!this.drawing) return
    this.drawing.markers.forEach((m) => m.remove())
    this.drawing.preview?.remove()
    this.propertyLayer?.setStyle({ opacity: 1, fillOpacity: 0.08 })
    this.drawing = null
    this.mapTarget.classList.remove("garden-map-drawing")
    this.drawControlsTarget.hidden = true
    this.setReadout("")
  }

  clearProperty() {
    this.saveProperty([])
  }

  async saveProperty(ring) {
    try {
      const response = await fetch(this.propertyUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.tokenValue,
          "Accept": "application/json"
        },
        body: JSON.stringify({ property_boundary: ring })
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      this.renderProperty(ring)
      this.setReadout(data.property_area_sqm ? this.areaLabel(data.property_area_sqm) : "")
      return true
    } catch {
      this.setReadout(this.element.dataset.i18nSaveFailed)
      return false
    }
  }

  // -- buildings (shadow casters) ---------------------------------------------

  renderStructures() {
    this.structureLayers.forEach((layer) => layer.remove())
    this.structureLayers = (this.structuresValue || []).map((structure) =>
      this.L.polygon(structure.boundary.map((p) => [p.lat, p.lng]), {
        color: "#5b6770", weight: 2, fillOpacity: 0.35, interactive: false
      }).bindTooltip(structure.name).addTo(this.map)
    )
  }

  async createStructure(ring) {
    try {
      const response = await fetch(this.structuresUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.tokenValue,
          "Accept": "application/json"
        },
        body: JSON.stringify({ boundary: ring })
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      // Reload so the new building appears in the editable list below the map.
      window.Turbo ? window.Turbo.visit(window.location, { action: "replace" }) : window.location.reload()
      return true
    } catch {
      this.setReadout(this.element.dataset.i18nSaveFailed)
      return false
    }
  }

  // -- official parcel (Flurstück) lookup + adoption --------------------------

  // Toggle "pick a parcel" mode: the next map click asks the server for the
  // cadastral parcel at that point (proxied ALKIS WFS) and shows its outline
  // with the official surveyed area; "adopt" saves it as the Grundstück.
  toggleParcelPick(event) {
    this.cancelDraw()
    if (this.parcelPicking) {
      this.stopParcelPick()
      return
    }
    this.parcelPicking = true
    event.currentTarget.classList.add("soft")
    this.mapTarget.classList.add("garden-map-drawing")
    this.setReadout(this.element.dataset.i18nParcelHint)
  }

  stopParcelPick() {
    if (!this.parcelPicking) return
    this.parcelPicking = false
    this.element.querySelectorAll(".soft").forEach((el) => el.classList.remove("soft"))
    this.mapTarget.classList.remove("garden-map-drawing")
    this.parcelLayer?.remove()
    this.parcelLayer = null
    this.pendingParcel = null
    if (this.hasAdoptControlsTarget) this.adoptControlsTarget.hidden = true
    this.setReadout("")
  }

  async fetchParcel(latlng) {
    this.setReadout("…")
    try {
      const url = `${this.parcelUrlValue}?lat=${latlng.lat}&lng=${latlng.lng}`
      const response = await fetch(url, { headers: { "Accept": "application/json" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.showParcel(await response.json())
    } catch {
      this.setReadout(this.element.dataset.i18nParcelNotFound)
    }
  }

  showParcel(parcel) {
    this.parcelLayer?.remove()
    this.parcelLayer = this.L.polygon(parcel.boundary.map((p) => [p.lat, p.lng]), {
      color: "#2d6a9f", weight: 2, dashArray: "8 5", fill: false, interactive: false
    }).addTo(this.map)
    this.pendingParcel = parcel
    if (this.hasAdoptControlsTarget) this.adoptControlsTarget.hidden = false
    const official = this.element.dataset.i18nParcelOfficial
      .replace("%{area}", formatArea(parcel.area_sqm))
    this.setReadout(parcel.label ? `${parcel.label} — ${official}` : official)
  }

  adoptParcel() {
    if (!this.pendingParcel) return
    this.saveProperty(this.pendingParcel.boundary).then((saved) => {
      if (saved) this.stopParcelPick()
    })
  }

  // -- helpers --------------------------------------------------------------

  areaLabel(areaSqm) {
    return this.element.dataset.i18nAreaLabel.replace("%{area}", formatArea(areaSqm))
  }

  setReadout(text) {
    if (this.hasReadoutTarget) this.readoutTarget.textContent = text || ""
  }
}

// Shoelace on an equirectangular projection around the ring's mean latitude —
// the JS mirror of Garden::Geometry.polygon_area_sqm.
function polygonAreaSqm(ring) {
  if (ring.length < 3) return 0
  const lat0 = ring.reduce((sum, p) => sum + p.lat, 0) / ring.length
  const cos0 = Math.cos((lat0 * Math.PI) / 180)
  const pts = ring.map((p) => [
    EARTH_RADIUS_M * ((p.lng * Math.PI) / 180) * cos0,
    EARTH_RADIUS_M * ((p.lat * Math.PI) / 180)
  ])
  let sum = 0
  for (let i = 0; i < pts.length; i++) {
    const [x1, y1] = pts[i]
    const [x2, y2] = pts[(i + 1) % pts.length]
    sum += x1 * y2 - x2 * y1
  }
  return Math.abs(sum) / 2
}

function formatArea(areaSqm) {
  return new Intl.NumberFormat(document.documentElement.lang || "de", {
    minimumFractionDigits: 1, maximumFractionDigits: 1
  }).format(areaSqm)
}
